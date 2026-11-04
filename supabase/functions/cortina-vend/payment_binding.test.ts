import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CortinaDeps, HttpError, markCortinaCardPaid, sha256 } from "../_shared/cortina.ts";
import { handleCortinaVend } from "./logic.ts";

type Row = Record<string, any>;

async function fixture(channel = "app") {
  Deno.env.set("NAYAX_SANDBOX_START_URL", "https://nayax.invalid/start");
  Deno.env.set("NAYAX_SANDBOX_SECRET_TOKEN", "test-secret");
  const session: Row = {
    id: "00000000-0000-4000-8000-000000000001", machine_id: 1, user_id: null,
    amount_cents: 400, currency: "USD", payment_method: "card", channel,
    status: "payment_pending", transaction_id: "0123456789abcdef0123456789abcdef",
    client_access_token_hash: await sha256("request-token"),
    stripe_payment_intent_id: channel === "app" ? "pi_test" : null,
    stripe_checkout_session_id: channel === "web" ? "cs_test" : null,
    stripe_charge_id: null, stripe_refund_id: null,
    nayax_environment: "sandbox", nayax_terminal_id: "4434331126150568",
    nayax_uniqr: null, stripe_livemode: false, product_code: 3, pulse_line_number: null,
  };
  const metadata = { purpose: "cortina_vend", cortina_session_id: session.id,
    machine_id: "1", amount_cents: "400" };
  const intent: Row = { id: "pi_test", status: "succeeded", amount: 400,
    amount_received: 400, currency: "usd", livemode: false, metadata: { ...metadata },
    latest_charge: "ch_test" };
  const checkout: Row = { id: "cs_test", payment_intent: "pi_test", mode: "payment",
    status: "complete", payment_status: "paid", amount_total: 400, currency: "usd",
    livemode: false, metadata: { ...metadata } };
  const calls: Row[] = [], starts: Row[] = [], events: Row[] = [];
  let rpcError: string | null = null;
  const admin = {
    rpc(name: string, args: Row) {
      calls.push({ name, args });
      if (name !== "record_cortina_card_payment") throw new Error("Unexpected RPC");
      if (rpcError) return Promise.resolve({ error: { message: rpcError } });
      // The real transactional/role behavior is exercised by the PGlite suite.
      if (session.status === "payment_pending") session.status = "paid";
      session.stripe_payment_intent_id = args.p_intent;
      return Promise.resolve({ error: null });
    },
    from(table: string) {
      let change: Row | undefined, insertion: Row | undefined;
      const filters: Array<(row: Row) => boolean> = [];
      const execute = () => {
        if (insertion) { events.push(insertion); return { data: null, error: null }; }
        const row = table === "Machines" ? { id: 1, is_out_of_service: false }
          : table === "cortina_machine_config" ? { machine_id: 1, is_enabled: true, review_required: false }
          : session;
        if (!filters.every((filter) => filter(row))) return { data: null, error: null };
        if (change) Object.assign(row, change);
        return { data: structuredClone(row), error: null };
      };
      const query = {
        select: (_columns: string) => query,
        eq(key: string, value: unknown) { filters.push((row) => row[key] === value); return query; },
        in(key: string, values: unknown[]) { filters.push((row) => values.includes(row[key])); return query; },
        update(value: Row) { change = value; return query; },
        insert(value: Row) { insertion = value; return query; },
        single: async () => execute(), maybeSingle: async () => execute(),
        then(resolve: (value: ReturnType<typeof execute>) => unknown) { return Promise.resolve(execute()).then(resolve); },
      };
      return query;
    },
  };
  const reads: string[] = [];
  const deps = { admin, stripe: {
    paymentIntents: { retrieve: async (id: string) => { reads.push(id); return structuredClone(intent); } },
    checkout: { sessions: { retrieve: async (id: string) => { reads.push(id); return structuredClone(checkout); } } },
  }, fetcher: async (_url: string, init: RequestInit) => {
    starts.push(JSON.parse(String(init.body)));
    return Response.json({ Status: { Verdict: "Approved" } });
  } } as unknown as CortinaDeps;
  const input = { eventId: "evt_test", sessionId: session.id, amountCents: 400, paymentIntentId: "pi_test" };
  const confirm = (accessToken = "request-token") => handleCortinaVend(new Request(
    "https://local.invalid/cortina-vend/confirm", { method: "POST",
      body: JSON.stringify({ sessionId: session.id, accessToken }) },
  ), deps);
  return { session, intent, checkout, reads, calls, starts, events, deps, input, confirm,
    failRpc(message: string | null) { rpcError = message; } };
}

Deno.test("confirm request verifies exact provider evidence, commits funding, and starts only once", async () => {
  const f = await fixture();
  await Promise.all([f.confirm(), f.confirm(), f.confirm()]);
  assertEquals(f.starts.length, 1);
  assertEquals(f.session.status, "awaiting_sale");
  assertEquals(f.calls[0], { name: "record_cortina_card_payment", args: {
    p_session: f.session.id, p_event: "confirm:pi_test", p_intent: "pi_test",
    p_checkout: null, p_charge: "ch_test", p_amount: 400, p_currency: "usd", p_livemode: false,
  } });
  assertEquals(f.starts[0].Products, [{ Code: 3, Price: 4 }]);
  await f.confirm(); assertEquals(f.starts.length, 1);
});

Deno.test("confirm rejects another access token before reading Stripe", async () => {
  const f = await fixture(); await assertRejects(() => f.confirm("wrong"));
  assertEquals(f.reads, []); assertEquals(f.calls, []); assertEquals(f.starts, []);
});

Deno.test("unconfirmed app payment preserves the retryable HTTP 409 contract", async () => {
  const f = await fixture(); f.intent.status = "processing";
  const error = await assertRejects(() => f.confirm(), HttpError);
  assertEquals(error.status, 409); assertEquals(error.code, "payment_not_confirmed");
  assertEquals(f.calls, []); assertEquals(f.starts, []);
});

for (const patch of [
  { id: "pi_wrong" }, { status: "processing" }, { amount: 401 }, { amount_received: 399 },
  { amount_received: undefined }, { currency: "eur" }, { currency: undefined },
  { livemode: true }, { livemode: undefined }, { latest_charge: null },
]) {
  Deno.test(`confirm rejects intent evidence ${JSON.stringify(patch)}`, async () => {
    const f = await fixture(); Object.assign(f.intent, patch);
    await assertRejects(() => f.confirm());
    assertEquals(f.calls, []); assertEquals(f.starts, []); assertEquals(f.session.status, "payment_pending");
  });
}

for (const field of ["purpose", "cortina_session_id", "machine_id", "amount_cents", "user_id"]) {
  Deno.test(`confirm rejects conflicting ${field} metadata`, async () => {
    const f = await fixture(); f.intent.metadata[field] = "wrong";
    await assertRejects(() => f.confirm()); assertEquals(f.calls, []); assertEquals(f.starts, []);
  });
}

Deno.test("Checkout event and intent event share one bound payment and Start", async () => {
  const f = await fixture("web");
  await Promise.all([
    markCortinaCardPaid({ ...f.input, checkoutSessionId: "cs_test" }, f.deps),
    markCortinaCardPaid({ ...f.input, eventId: "evt_intent" }, f.deps),
  ]);
  assertEquals(f.starts.length, 1);
  assertEquals(f.calls.every((call) => call.args.p_checkout === "cs_test"), true);
  assertEquals(f.reads.filter((id) => id === "cs_test").length, 2);
});

for (const patch of [
  { id: "cs_wrong" }, { payment_intent: "pi_wrong" }, { mode: "subscription" },
  { status: "open" }, { payment_status: "unpaid" }, { amount_total: 399 },
  { currency: "eur" }, { currency: null }, { livemode: true }, { metadata: {} },
]) {
  Deno.test(`Checkout rejects evidence ${JSON.stringify(patch)}`, async () => {
    const f = await fixture("web"); Object.assign(f.checkout, patch);
    await assertRejects(() => markCortinaCardPaid(f.input, f.deps));
    assertEquals(f.calls, []); assertEquals(f.starts, []);
  });
}

for (const patch of [{ paymentIntentId: "pi_other" }, { checkoutSessionId: "cs_other" }, { amountCents: 401 }, { chargeId: "ch_other" }]) {
  Deno.test(`funding rejects conflicting event binding ${JSON.stringify(patch)}`, async () => {
    const f = await fixture();
    await assertRejects(() => markCortinaCardPaid({ ...f.input, ...patch }, f.deps));
    assertEquals(f.calls, []); assertEquals(f.starts, []);
  });
}

Deno.test("audit transaction failure never starts; retry reuses the same payment", async () => {
  const f = await fixture(); f.failRpc("audit unavailable");
  await assertRejects(() => f.confirm(), Error, "audit unavailable");
  assertEquals(f.session.status, "payment_pending"); assertEquals(f.starts, []);
  f.failRpc(null); await f.confirm(); assertEquals(f.starts.length, 1);
});

Deno.test("historical pending payment stays support-required without provider lookup or guessed Start", async () => {
  const f = await fixture(); f.session.nayax_environment = null;
  await assertRejects(() => f.confirm(), Error, "reconciliation");
  assertEquals(f.session.status, "support_required");
  assertEquals(f.reads, []); assertEquals(f.calls, []); assertEquals(f.starts, []);
});

Deno.test("web sessions without their stored Checkout binding cannot be funded by intent alone", async () => {
  const f = await fixture("web"); f.session.stripe_checkout_session_id = null;
  f.session.stripe_payment_intent_id = "pi_test";
  await assertRejects(() => markCortinaCardPaid(f.input, f.deps));
  assertEquals(f.reads, []); assertEquals(f.starts, []);
});

function creationFixture(channel: "app" | "web", providerMode = false, insertError: string | null = null) {
  const config = { machine_id: 1, public_machine_token: "machine-token", is_enabled: true,
    review_required: false, environment: "sandbox", nayax_terminal_id: "4434331126150568",
    product_codes: { "400": 3 }, pulse_line_number: null };
  const machine = { id: 1, Name: "Washer", Machine_type: "washer", Status: "idle",
    Location_ID: 1, washer_size_rate_id: 1, is_out_of_service: false };
  const rate = { id: 1, size_label: "12 kg", price_cents: 400, is_active: true, review_required: false };
  let session: Row = {};
  const creates: Row[] = [];
  const admin = {
    from(table: string) {
      let insertion: Row | undefined, change: Row | undefined;
      const filters: Array<(row: Row) => boolean> = [];
      const execute = () => {
        if (insertion && insertError) return { data: null, error: { code: insertError, message: "Settings changed" } };
        if (insertion) {
          // Models the database INSERT result, whose actual trigger is tested in PGlite.
          session = { ...insertion, id: "00000000-0000-4000-8000-000000000001",
            currency: "USD", status: "payment_pending", nayax_environment: "sandbox",
            nayax_terminal_id: config.nayax_terminal_id, nayax_uniqr: null, stripe_livemode: false };
        }
        const row = table === "Machines" ? machine : table === "washer_size_rates" ? rate
          : table === "cortina_machine_config" ? config : session;
        if (!filters.every((filter) => filter(row))) return { data: null, error: null };
        if (change) Object.assign(row, change);
        return { data: structuredClone(row), error: null };
      };
      const query = {
        select: (_columns: string) => query,
        eq(key: string, value: unknown) { filters.push((row) => row[key] === value); return query; },
        insert(value: Row) { insertion = value; return query; },
        update(value: Row) { change = value; return query; },
        single: async () => execute(), maybeSingle: async () => execute(),
        then(resolve: (value: ReturnType<typeof execute>) => unknown) { return Promise.resolve(execute()).then(resolve); },
      };
      return query;
    },
  };
  const create = async (body: Row, options: Row) => {
    assertEquals(session.product_code, 3); assertEquals(session.nayax_environment, "sandbox");
    assertEquals(session.stripe_livemode, false);
    creates.push({ body, options });
    return channel === "app" ? { id: "pi_test", livemode: providerMode, client_secret: "test-secret" }
      : { id: "cs_test", livemode: providerMode, url: "https://stripe.invalid/test" };
  };
  const deps = { admin, stripe: { paymentIntents: { create }, checkout: { sessions: { create } } } } as unknown as CortinaDeps;
  const request = () => handleCortinaVend(new Request("https://local.invalid/cortina-vend/card", {
    method: "POST", body: JSON.stringify({ channel, machineToken: "machine-token", amountCents: 400,
      clientRequestId: "00000000-0000-4000-8000-000000000002" }),
  }), deps);
  return { request, creates, session: () => session };
}

for (const channel of ["app", "web"] as const) {
  Deno.test(`${channel} creates its provider payment only after the frozen INSERT result`, async () => {
    const f = creationFixture(channel); const response = await f.request();
    assertEquals(response.status, 200); assertEquals(f.creates.length, 1);
    assertEquals(f.creates[0].body.metadata, { purpose: "cortina_vend",
      cortina_session_id: f.session().id, machine_id: "1", amount_cents: "400" });
    assertEquals(f.session()[channel === "app" ? "stripe_payment_intent_id" : "stripe_checkout_session_id"], channel === "app" ? "pi_test" : "cs_test");
  });
  Deno.test(`${channel} withholds payment credentials when Stripe mode conflicts with the snapshot`, async () => {
    const f = creationFixture(channel, true);
    await assertRejects(() => f.request(), Error, "environment");
    assertEquals(f.session().status, "failed");
    assertEquals(f.session().stripe_payment_intent_id, undefined);
    assertEquals(f.session().stripe_checkout_session_id, undefined);
  });
  for (const code of ["40001", "55P03"]) {
    Deno.test(`${channel} refuses a stale or locked snapshot before Stripe with HTTP 409 (${code})`, async () => {
      const f = creationFixture(channel, false, code);
      const error = await assertRejects(() => f.request(), HttpError);
      assertEquals(error.status, 409); assertEquals(f.creates, []);
    });
  }
}
