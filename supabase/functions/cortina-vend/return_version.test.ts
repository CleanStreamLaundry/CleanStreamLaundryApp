import assert from "node:assert/strict";
import { CortinaDeps, HttpError } from "../_shared/cortina.ts";
import { handleCard } from "./logic.ts";
import { cortinaCheckoutReturnVersion, cortinaReturnUrls, cortinaSessionReturnUrls } from "./return_urls.ts";

const sessionId = "00000000-0000-4000-8000-000000000001";
const requestId = "00000000-0000-4000-8000-000000000002";
const reference = { sessionId, accessToken: requestId };
const payUrl = "https://web.synthetic.invalid/pay";
const legacyCases: Array<[string, Record<string, unknown>, string]> = [
  [payUrl, { machineToken: "a b/+?", terminalId: "ignored" }, "machine=a%20b%2F%2B%3F"],
  [payUrl, { machineToken: "", terminalId: "4434331126150568" }, "terminal=4434331126150568"],
  [payUrl, { machineToken: false, terminalId: 0, uniQr: "qr +/" }, "uniqr=qr%20%2B%2F"],
  [payUrl, {}, "uniqr="],
  [payUrl, { machineToken: 42 }, "machine=42"],
  [payUrl, { machineToken: "\u00e9!*'()" }, "machine=%C3%A9!*'()"],
  [payUrl + "?old=yes#previous", { uniQr: "token" }, "uniqr=token"],
  ["relative legacy value ", { uniQr: null }, "uniqr="],
];
for (const [index, [base, selector, cancel]] of legacyCases.entries()) {
  Deno.test(`legacy1 retains exact original parameter bytes, edge ${index + 1}`, () => {
    assert.deepEqual(cortinaSessionReturnUrls(1, base, reference, selector), {
      success_url: `${base}?session=${sessionId}&access=${requestId}`,
      cancel_url: `${base}?${cancel}`,
    });
  });
}

function reconciliation(error: unknown) {
  assert(error instanceof HttpError);
  assert.equal(error.status, 409);
  assert.equal(error.code, "support_required");
  return true;
}

Deno.test("missing or unsupported stored versions never guess a return format", () => {
  for (const version of [undefined, null, "1", "2", 0, 3, NaN]) {
    assert.throws(() => cortinaCheckoutReturnVersion(version), reconciliation);
  }
});

Deno.test("version2 delegates to the frozen fragment builder without changing its parameters", () => {
  const base = payUrl + "?campaign=abc&access=stale#old";
  const selector = { machineToken: "a b/+?" };
  assert.deepEqual(cortinaSessionReturnUrls(2, base, reference, selector),
    cortinaReturnUrls(base, reference, selector));
});

type Row = Record<string, unknown>;
function fixture(existing?: Row) {
  let row: Row | undefined = existing && structuredClone(existing);
  const inserts: Row[] = [], updates: Row[] = [];
  const calls: Array<{ params: Row; options: Row }> = [];
  const intents: Array<{ params: Row; options: Row }> = [];
  const checkouts = new Map<string, { params: Row; id: string; url: string; livemode: boolean }>();
  const config = { machine_id: 1, public_machine_token: "public-qr", is_enabled: true,
    review_required: false, product_codes: null, pulse_line_number: 1 };
  const machine = { id: 1, Name: "Washer", Machine_type: "washer", Status: "Idle",
    Location_ID: 1, washer_size_rate_id: 1, is_out_of_service: false };
  const rate = { id: 1, size_label: "12kg", price_cents: 400, is_active: true, review_required: false };
  const admin = {
    from(table: string) {
      let insertion: Row | undefined, update: Row | undefined;
      const filters: Array<[string, unknown]> = [];
      const run = () => {
        if (table === "cortina_machine_config") return { data: config, error: null };
        if (table === "Machines") return { data: machine, error: null };
        if (table === "washer_size_rates") return { data: rate, error: null };
        assert.equal(table, "cortina_vend_sessions");
        if (insertion) {
          inserts.push(structuredClone(insertion));
          if (row) return { data: null, error: { code: "23505" } };
          // SQL default/snapshot behavior is independently exercised by the paired PGlite runner.
          row = { ...baseRow(), checkout_return_version: 1, ...insertion };
        } else if (update) {
          assert(row);
          assert(filters.every(([key, value]) => row?.[key] === value));
          updates.push(structuredClone(update));
          Object.assign(row, update);
        } else {
          assert(filters.every(([key, value]) => row?.[key] === value));
        }
        return { data: row && structuredClone(row), error: null };
      };
      const query = {
        select: (_value: string) => query,
        eq: (key: string, value: unknown) => { filters.push([key, value]); return query; },
        insert: (value: Row) => { insertion = value; return query; },
        update: (value: Row) => { update = value; return query; },
        single: () => Promise.resolve(run()),
        maybeSingle: () => Promise.resolve(run()),
        then: <T, U>(resolve?: ((value: ReturnType<typeof run>) => T | PromiseLike<T>) | null,
          reject?: ((reason: unknown) => U | PromiseLike<U>) | null) => Promise.resolve(run()).then(resolve, reject),
      };
      return query;
    },
    rpc(name: string, args?: Row) {
      if (name === "consume_cortina_request_capacity") {
        assert.deepEqual(args, { p_bucket: "card" });
        return { abortSignal: (_signal: AbortSignal) => Promise.resolve({
          data: { allowed: true, retry_after_seconds: 0 }, error: null,
        }) };
      }
      assert.equal(name, "new_payments_enabled");
      return { abortSignal: (_signal: AbortSignal) => Promise.resolve({ data: true, error: null }) };
    },
    auth: { getUser(): never { throw new Error("Guest must not use Auth lookup"); } },
  };
  const deps = { admin, stripe: {
    checkout: { sessions: { create(params: Row, options: Row) {
      calls.push(structuredClone({ params, options }));
      const key = String(options.idempotencyKey);
      const previous = checkouts.get(key);
      if (previous) {
        assert.deepEqual(params, previous.params, "same Stripe key requires identical full create parameters");
        return Promise.resolve(previous);
      }
      const checkout = { params: structuredClone(params), id: "cs_synthetic", url: "https://checkout.synthetic.invalid/session", livemode: false };
      checkouts.set(key, checkout);
      return Promise.resolve(checkout);
    } } },
    paymentIntents: { create(params: Row, options: Row) {
      intents.push(structuredClone({ params, options }));
      return Promise.resolve({ id: "pi_synthetic", client_secret: "synthetic-only", livemode: false });
    } },
  }, fetcher: () => { throw new Error("No provider Start or refund is allowed"); } } as unknown as CortinaDeps;
  return { deps, inserts, updates, calls, intents, checkouts, row: () => row };
}

function baseRow(): Row {
  return { id: sessionId, client_request_id: requestId, machine_id: 1, user_id: null,
    amount_cents: 400, dryer_minutes: null, pulse_line_number: 1, product_code: null,
    payment_method: "card", channel: "web", status: "payment_pending", currency: "USD",
    nayax_environment: "sandbox", nayax_terminal_id: "4434331126150568", stripe_livemode: false,
    stripe_checkout_session_id: null, stripe_payment_intent_id: null };
}
const request = (channel = "web") => new Request("https://edge.synthetic.invalid/cortina-vend/card", {
  method: "POST", body: JSON.stringify({ channel, machineToken: "public-qr", amountCents: 400, clientRequestId: requestId }),
});
async function withUrl(action: () => Promise<void>) {
  const get = Deno.env.get;
  Deno.env.get = (key) => key === "CLEAN_STREAM_PAY_URL" ? payUrl : undefined;
  try { await action(); } finally { Deno.env.get = get; }
}
function expectedParams(version: 1 | 2): Row {
  const metadata = { purpose: "cortina_vend", cortina_session_id: sessionId, machine_id: "1", amount_cents: "400" };
  return { mode: "payment", payment_method_types: ["card"], line_items: [{ price_data: {
    currency: "usd", unit_amount: 400, product_data: { name: "Washer laundry service" },
  }, quantity: 1 }], metadata, payment_intent_data: { metadata },
  success_url: version === 1 ? `${payUrl}?session=${sessionId}&access=${requestId}`
    : `${payUrl}?cortina_return=1#session=${sessionId}&access=${requestId}`,
  cancel_url: `${payUrl}?machine=public-qr` };
}

Deno.test("fresh web-card explicitly stores2 and retry reuses identical parameters, key and Checkout", async () => {
  await withUrl(async () => {
    const f = fixture();
    const first = await (await handleCard(request(), f.deps)).json();
    const retry = await (await handleCard(request(), f.deps)).json();
    assert.deepEqual(retry, first);
    assert.equal(f.inserts[0].checkout_return_version, 2);
    assert.equal(f.row()?.checkout_return_version, 2);
    assert.equal(f.calls.length, 2);
    assert.deepEqual(f.calls[0], { params: expectedParams(2), options: { idempotencyKey: `cortina-checkout-${sessionId}` } });
    assert.deepEqual(f.calls[1], f.calls[0]);
    assert.equal(f.checkouts.size, 1);
    assert.equal(f.intents.length, 0);
  });
});

for (const version of [1, 2] as const) {
  Deno.test(`stored${version} lost-response replay retains full parameters and key across new-writer retries`, async () => {
    await withUrl(async () => {
      const f = fixture({ ...baseRow(), checkout_return_version: version });
      // Model an already-created Checkout whose response/binding was lost.
      f.checkouts.set(`cortina-checkout-${sessionId}`, { params: expectedParams(version),
        id: "cs_synthetic", url: "https://checkout.synthetic.invalid/session", livemode: false });
      await handleCard(request(), f.deps);
      await handleCard(request(), f.deps);
      assert.equal(f.calls.length, 2);
      assert.deepEqual(f.calls[0], { params: expectedParams(version), options: { idempotencyKey: `cortina-checkout-${sessionId}` } });
      assert.deepEqual(f.calls[1], f.calls[0]);
      assert(f.inserts.every((insert) => insert.checkout_return_version === 2));
      assert.equal(f.row()?.checkout_return_version, version);
      assert.equal(f.checkouts.size, 1);
      assert(f.updates.every((update) => Object.keys(update).join() === "stripe_checkout_session_id"));
    });
  });
}

Deno.test("unknown web version refuses before Stripe and does not mark the draft failed", async () => {
  for (const version of [undefined, null, "1", 3]) {
    const f = fixture({ ...baseRow(), checkout_return_version: version });
    await assert.rejects(() => handleCard(request(), f.deps), reconciliation);
    assert.deepEqual(f.calls, []);
    assert.deepEqual(f.updates, []);
    assert.equal(f.row()?.status, "payment_pending");
  }
});

Deno.test("funded replay remains read-only even if old row has no redirect version", async () => {
  const f = fixture({ ...baseRow(), status: "started" });
  const response = await handleCard(request(), f.deps);
  assert.deepEqual(await response.json(), { ...reference, status: "started" });
  assert.deepEqual(f.calls, []);
  assert.deepEqual(f.intents, []);
  assert.deepEqual(f.updates, []);
});

Deno.test("app-card creation omits redirect version and retains the original intent contract", async () => {
  const f = fixture();
  await handleCard(request("app"), f.deps);
  assert.equal(Object.hasOwn(f.inserts[0], "checkout_return_version"), false);
  assert.equal(f.row()?.checkout_return_version, 1);
  assert.equal(f.intents.length, 1);
  assert.equal(f.intents[0].options.idempotencyKey, `cortina-card-${sessionId}`);
  assert.equal(f.intents[0].params.amount, 400);
  assert.equal(f.intents[0].params.currency, "usd");
  assert.deepEqual(f.calls, []);
});
