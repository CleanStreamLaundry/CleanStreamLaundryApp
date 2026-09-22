import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CortinaDeps, CortinaQuote, createVendSession, resolveQuote } from "../_shared/cortina.ts";

function fixture() {
  const config = { machine_id: 1, is_enabled: true, review_required: false, product_codes: { "400": 3 } as Record<string, number> | null, pulse_line_number: null as number | null };
  let session: Record<string, unknown> | null = null;
  const admin = {
    from(table: string) {
      let insertion: Record<string, unknown> | undefined;
      const query = {
        select: (_columns: string) => query,
        eq: (_key: string, _value: unknown) => query,
        insert: (value: Record<string, unknown>) => { insertion = value; return query; },
        single: async () => {
          if (table === "cortina_machine_config") return { data: structuredClone(config), error: null };
          if (table === "Machines") return { data: { id: 1, Name: "Washer 1", Machine_type: "washer", Status: "idle", Location_ID: 1, washer_size_rate_id: 1 }, error: null };
          if (table === "washer_size_rates") return { data: { id: 1, size_label: "12 kg", price_cents: 400, is_active: true, review_required: false }, error: null };
          if (insertion && session) return { data: null, error: { code: "23505" } };
          if (insertion) session = { ...insertion, id: "session-id" };
          return { data: structuredClone(session), error: null };
        },
        maybeSingle: async () => query.single(),
      };
      return query;
    },
  } as unknown as CortinaDeps["admin"];
  const quote: CortinaQuote = { machineId: 1, publicMachineToken: "token", machineName: "Washer 1", machineType: "washer", locationId: 1, washerSizeRateId: 1, washerSizeLabel: "12 kg", amountCents: 400, dryer: null };
  const input = { userId: null, amountCents: 400, dryerMinutes: null, pulseLineNumber: null, paymentMethod: "card" as const, channel: "web" as const, clientRequestId: crypto.randomUUID() };
  return { config, admin, quote, input };
}

Deno.test("card and wallet sessions snapshot the product code before payment", async () => {
  for (const method of ["card", "wallet"] as const) {
    const f = fixture();
    const input = { ...f.input, paymentMethod: method };
    const first = await createVendSession(f.admin, f.quote, input);
    assertEquals(first.session.product_code, 3);
    assertEquals(first.session.pulse_line_number, null);
    f.config.product_codes = { "400": 5 };
    const replay = await createVendSession(f.admin, f.quote, input);
    assertEquals(replay.wasCreated, false);
    assertEquals(replay.session.product_code, 3);
  }
});

Deno.test("washer pulse lines are also snapshotted rather than deferred until Start", async () => {
  const f = fixture();
  f.config.product_codes = null;
  f.config.pulse_line_number = 2;
  const result = await createVendSession(f.admin, f.quote, f.input);
  assertEquals(result.session.pulse_line_number, 2);
  assertEquals(result.session.product_code, null);
});

Deno.test("unmapped prices fail both quote and session creation before payment", async () => {
  const f = fixture();
  f.config.product_codes = { "1000": 0 };
  await assertRejects(() => resolveQuote(f.admin, { machineToken: "token" }), Error, "product pricing needs review");
  await assertRejects(() => createVendSession(f.admin, f.quote, f.input), Error, "product pricing needs review");
});
