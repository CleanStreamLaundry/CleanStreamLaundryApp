import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CortinaDeps, DRYER_OPTIONS, startCortinaVend } from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";

type Row = Record<string, any>;

function fixture() {
  Deno.env.set("NAYAX_SANDBOX_START_URL", "https://nayax.invalid/start");
  Deno.env.set("NAYAX_SANDBOX_SECRET_TOKEN", "test-secret");
  Deno.env.delete("NAYAX_CALLBACK_AUTH_TOKEN");
  const session: Row = {
    id: "00000000-0000-4000-8000-000000000001",
    transaction_id: "0123456789abcdef0123456789abcdef",
    machine_id: 1,
    user_id: null,
    amount_cents: 400,
    pulse_line_number: null,
    currency: "USD",
    payment_method: "card",
    stripe_payment_intent_id: "pi_test",
    status: "paid",
  };
  const config: Row = {
    machine_id: 1,
    nayax_terminal_id: "4434331126150568",
    pulse_line_number: 1,
    environment: "sandbox",
    is_enabled: true,
  };
  const events: Row[] = [];
  const requests: Row[] = [];
  const refunds = new Map<string, Row>();
  let beforeApproval: (() => void) | undefined;
  let onStart: (() => Promise<Response>) | undefined;

  // Execute predicates at update time to exercise the production compare-and-set logic.
  const admin = {
    from(table: string) {
      let change: Row | undefined;
      let insertion: Row | undefined;
      const filters: Array<(row: Row) => boolean> = [];
      const execute = () => {
        if (insertion) {
          if (events.some((event) => event.event_key === insertion!.event_key)) {
            return { data: null, error: { code: "23505" } };
          }
          events.push(structuredClone(insertion));
          return { data: null, error: null };
        }
        if (change?.status === "approved") beforeApproval?.();
        const row = table === "cortina_machine_config" ? config : session;
        if (!filters.every((filter) => filter(row))) return { data: null, error: null };
        if (change) Object.assign(row, change);
        return { data: structuredClone(row), error: null };
      };
      const query = {
        select(_columns: string) { return query; },
        eq(key: string, value: unknown) {
          filters.push((row) => row[key] === value);
          return query;
        },
        in(key: string, values: unknown[]) {
          filters.push((row) => values.includes(row[key]));
          return query;
        },
        update(value: Row) { change = value; return query; },
        insert(value: Row) { insertion = value; return query; },
        maybeSingle: async () => execute(),
        single: async () => execute(),
        then(resolve: (value: ReturnType<typeof execute>) => unknown) {
          return Promise.resolve(execute()).then(resolve);
        },
      };
      return query;
    },
  };
  const deps = {
    admin,
    stripe: {
      refunds: {
        create: async (body: Row, options: { idempotencyKey: string }) => {
          if (!refunds.has(options.idempotencyKey)) {
            refunds.set(options.idempotencyKey, { id: "re_test", ...body });
          }
          return refunds.get(options.idempotencyKey)!;
        },
      },
    },
    fetcher: async (url: string, init: RequestInit) => {
      requests.push({ url, method: init.method, headers: init.headers, body: JSON.parse(String(init.body)) });
      return onStart ? await onStart() : Response.json({ Status: { Verdict: "Approved" } });
    },
  } as unknown as CortinaDeps;

  const body = () => ({
    BasicInfo: {
      TransactionId: session.transaction_id,
      NayaxTransactionId: 1234567,
      Amount: 4,
      CurrencyCode: "USD",
    },
    DeviceInfo: { HwSerial: config.nayax_terminal_id },
  });
  const callback = async (value = body(), route = "StaticQR/Sale", environment: "sandbox" | "production" = "sandbox") => {
    const response = await handleNayaxCallback(new Request(
      `https://example.supabase.co/functions/v1/nayax-sale-end-sandbox/Cortina/${route}`,
      { method: "POST", body: JSON.stringify(value) },
    ), environment, deps);
    return await response.json();
  };
  return {
    session, config, events, requests, refunds, deps, body, callback,
    start: () => startCortinaVend(session.id, deps),
    onStart(value: () => Promise<Response>) { onStart = value; },
    beforeApproval(value: () => void) { beforeApproval = value; },
  };
}

Deno.test("Start sends the canonical documented request exactly once", async () => {
  const f = fixture();
  await f.start();
  await f.start();
  assertEquals(f.requests.length, 1);
  assertEquals(f.requests[0], {
    url: "https://nayax.invalid/start",
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: {
      AppUserId: `guest-${f.session.id.slice(0, 30)}`,
      TransactionId: f.session.transaction_id,
      SecretToken: "test-secret",
      TerminalId: "4434331126150568",
      Products: [{ PulseLineNumber: 1, Price: 4 }],
    },
  });
  assertEquals(f.session.status, "awaiting_sale");
  const audit = f.events.find((event) => event.event_type === "nayax_start_request")!;
  assertEquals(audit.payload.request.SecretToken, undefined);
  assertEquals(audit.payload.request.Products, [{ PulseLineNumber: 1, Price: 4 }]);
});

Deno.test("unpaid and closed sessions cannot send Start", async () => {
  for (const status of ["payment_pending", "failed", "refunded", "voided", "started"]) {
    const f = fixture();
    f.session.status = status;
    await f.start();
    assertEquals(f.requests.length, 0);
  }
});

Deno.test("all six dryers send one snapshotted pulse line and decimal price", async () => {
  for (const option of DRYER_OPTIONS) {
    const f = fixture();
    f.session.amount_cents = option.amountCents;
    f.session.pulse_line_number = option.pulseLineNumber;
    await f.start();
    assertEquals(f.requests[0].body.Products, [{
      PulseLineNumber: option.pulseLineNumber,
      Price: option.amountCents / 100,
    }]);
  }
});

Deno.test("UniQR is sent instead of an absent terminal ID", async () => {
  const f = fixture();
  f.config.nayax_terminal_id = null;
  f.config.nayax_uniqr = "https://qr.nayax.com/v1/test";
  await f.start();
  assertEquals(f.requests[0].body.TerminalId, undefined);
  assertEquals(f.requests[0].body.UniQR, f.config.nayax_uniqr);
});

Deno.test("price-array Start uses the snapshotted Code, never PulseLineNumber", async () => {
  for (const code of [0, 3]) {
    const f = fixture();
    f.session.product_code = code;
    f.config.product_codes = { "400": 5 };
    f.config.pulse_line_number = null;
    await f.start();
    await f.start();
    assertEquals(f.requests.length, 1);
    assertEquals(f.requests[0].body.Products, [{ Code: code, Price: 4 }]);
  }
});

Deno.test("all six dryer price-array options preserve their individual codes", async () => {
  for (const [code, option] of DRYER_OPTIONS.entries()) {
    const f = fixture();
    f.session.amount_cents = option.amountCents;
    f.session.product_code = code;
    f.config.pulse_line_number = null;
    await f.start();
    assertEquals(f.requests[0].body.Products, [{ Code: code, Price: option.amountCents / 100 }]);
  }
});

Deno.test("a missing session selector refunds without sending Start", async () => {
  const f = fixture();
  f.config.pulse_line_number = null;
  await f.start();
  assertEquals(f.requests.length, 0);
  assertEquals(f.refunds.size, 1);
});

Deno.test("a declined Start refunds once and preserves Nayax code", async () => {
  const f = fixture();
  f.onStart(async () => Response.json({ Status: { Verdict: "Declined", Code: 13 } }));
  await f.start();
  await f.start();
  assertEquals(f.requests.length, 1);
  assertEquals(f.refunds.size, 1);
  assertEquals(f.session.status, "refunded");
  assertEquals(f.session.failure_code, "13");
});

Deno.test("a paid Sale arriving before Start returns is approved", async () => {
  const f = fixture();
  f.onStart(async () => {
    assertEquals((await f.callback()).Status.Verdict, "Approved");
    return Response.json({ Status: { Verdict: "Approved" } });
  });
  await f.start();
  assertEquals(f.session.status, "approved");
  assertEquals(f.refunds.size, 0);
});

Deno.test("fast Sale and SaleEnd are not overwritten by the Start response", async () => {
  const f = fixture();
  f.onStart(async () => {
    await f.callback();
    await f.callback(f.body(), "SaleEndNotification");
    return Response.json({ Status: { Verdict: "Approved" } });
  });
  await f.start();
  assertEquals(f.session.status, "started");
});

Deno.test("a late Start error cannot refund a callback-confirmed vend", async () => {
  const f = fixture();
  f.onStart(async () => {
    await f.callback();
    await f.callback(f.body(), "SaleEndNotification");
    throw new Error("response connection lost");
  });
  await f.start();
  assertEquals(f.session.status, "started");
  assertEquals(f.refunds.size, 0);
});

Deno.test("duplicate Sale is approved without changing a completed vend", async () => {
  const f = fixture();
  f.session.status = "awaiting_sale";
  await f.callback();
  await f.callback(f.body(), "SaleEndNotification");
  assertEquals((await f.callback()).Status.Verdict, "Approved");
  assertEquals(f.session.status, "started");
  assertEquals(f.events.filter((event) => event.event_type === "sale").length, 1);
});

Deno.test("Sale rejects mismatched amount, currency, serial, and environment", async () => {
  for (const mismatch of ["amount", "currency", "serial", "environment"]) {
    const f = fixture();
    f.session.status = "awaiting_sale";
    const body = f.body();
    if (mismatch === "amount") body.BasicInfo.Amount = 6;
    if (mismatch === "currency") body.BasicInfo.CurrencyCode = "EUR";
    if (mismatch === "serial") body.DeviceInfo.HwSerial = "4434331126150748";
    const result = await f.callback(body, "StaticQR/Sale", mismatch === "environment" ? "production" : "sandbox");
    assertEquals(result.Status.Verdict, "Declined");
    assertEquals(f.session.status, "awaiting_sale");
  }
});

Deno.test("Sale cannot approve a session closed during validation", async () => {
  const f = fixture();
  f.session.status = "awaiting_sale";
  f.beforeApproval(() => { f.session.status = "refunded"; });
  assertEquals((await f.callback()).Status.Verdict, "Declined");
  assertEquals(f.session.status, "refunded");
});

Deno.test("Sale never approves an unpaid or already reversed session", async () => {
  for (const status of ["payment_pending", "paid", "refunded", "voided", "failed", "timed_out"]) {
    const f = fixture();
    f.session.status = status;
    assertEquals((await f.callback()).Status.Verdict, "Declined");
  }
});
