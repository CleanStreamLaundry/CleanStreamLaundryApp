import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  DRYER_DEFAULT_CENTS,
  DRYER_OPTIONS,
  functionRoute,
  HttpError,
  nayaxPriceFromCents,
  resolveProductSelector,
  validateVendAmount,
} from "../_shared/cortina.ts";

const washerQuote = {
  machineId: 1,
  publicMachineToken: "00000000-0000-4000-8000-000000000001",
  machineName: "Washer 1",
  machineType: "washer" as const,
  locationId: 1,
  washerSizeRateId: 10,
  washerSizeLabel: "18 kg",
  amountCents: 450,
  dryer: null,
};

const dryerQuote = {
  machineId: 2,
  publicMachineToken: "00000000-0000-4000-8000-000000000002",
  machineName: "Dryer 1",
  machineType: "dryer" as const,
  locationId: 1,
  washerSizeRateId: null,
  washerSizeLabel: null,
  amountCents: DRYER_DEFAULT_CENTS,
  dryer: {
    defaultCents: 150,
    options: DRYER_OPTIONS.map(({ minutes, amountCents }) => ({
      minutes,
      amountCents,
    })),
  },
};

Deno.test("washer accepts only the current server price", () => {
  assertEquals(validateVendAmount(washerQuote, 450), {
    amountCents: 450,
    dryerMinutes: null,
    pulseLineNumber: null,
  });
  const error = assertThrows(() => validateVendAmount(washerQuote, 475));
  assertEquals((error as HttpError).code, "price_changed");
});

Deno.test("dryer options map to fixed minutes and pulse lines", () => {
  assertEquals(validateVendAmount(dryerQuote, 150), {
    amountCents: 150,
    dryerMinutes: 30,
    pulseLineNumber: 3,
  });
  for (const option of DRYER_OPTIONS) {
    assertEquals(validateVendAmount(dryerQuote, option.amountCents), {
      amountCents: option.amountCents,
      dryerMinutes: option.minutes,
      pulseLineNumber: option.pulseLineNumber,
    });
  }
});

Deno.test("dryer rejects amounts outside the six configured products", () => {
  for (const amount of [0, 25, 75, 250, 475]) {
    const error = assertThrows(() => validateVendAmount(dryerQuote, amount));
    assertEquals((error as HttpError).code, "invalid_dryer_amount");
  }
});

Deno.test("functionRoute resolves routed Edge Function paths", () => {
  assertEquals(
    functionRoute("https://example.supabase.co/functions/v1/cortina-vend/quote"),
    "quote",
  );
  assertEquals(
    functionRoute("https://example.supabase.co/functions/v1/cortina-vend/status"),
    "status",
  );
});

Deno.test("converts integer cents to the decimal Nayax product price", () => {
  assertEquals(nayaxPriceFromCents(25), 0.25);
  assertEquals(nayaxPriceFromCents(400), 4);
  assertEquals(nayaxPriceFromCents(450), 4.5);
});

Deno.test("price arrays map cents to explicit codes, including zero", () => {
  const config = { product_codes: { "1000": 0, "800": 1, "600": 2, "400": 3, "200": 4 } };
  assertEquals(resolveProductSelector(config, 400, null), { product_code: 3, pulse_line_number: null });
  assertEquals(resolveProductSelector(config, 1000, null), { product_code: 0, pulse_line_number: null });
  assertEquals(resolveProductSelector(config, 400, 1), { product_code: 3, pulse_line_number: null });
});

Deno.test("missing or invalid price mappings never fall back to a pulse line", () => {
  for (const codes of [{}, { "400": -1 }, { "400": 1.5 }, { "400": "3" }, { "400": 32768 }, [], "bad"]) {
    const error = assertThrows(() => resolveProductSelector({ product_codes: codes, pulse_line_number: 1 }, 400, null));
    assertEquals((error as HttpError).code, "product_mapping_missing");
  }
});

Deno.test("pulse-line machines preserve washer and dryer selectors", () => {
  assertEquals(resolveProductSelector({ pulse_line_number: 2 }, 400, null), { product_code: null, pulse_line_number: 2 });
  for (const option of DRYER_OPTIONS) {
    assertEquals(resolveProductSelector({ pulse_line_number: 1 }, option.amountCents, option.pulseLineNumber), { product_code: null, pulse_line_number: option.pulseLineNumber });
  }
  for (const line of [null, 0, 7, 1.5, "1"]) {
    assertThrows(() => resolveProductSelector({ pulse_line_number: line }, 400, null));
  }
});
