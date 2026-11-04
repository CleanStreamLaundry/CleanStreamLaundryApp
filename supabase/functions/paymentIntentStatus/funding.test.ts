import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type Stripe from "npm:stripe";
import {
  handlePaymentIntentStatus,
  normalizePaymentIntentStatus,
  type PaymentIntentStatusDeps,
  recordWalletLoadFromIntent,
} from "./logic.ts";

const metadata = { user_id: "user-1", purpose: "wallet_load", amount_cents: "2500" };
function intent(overrides: Record<string, unknown> = {}): Stripe.PaymentIntent {
  return {
    id: "pi_wallet", status: "succeeded", currency: "usd", livemode: false,
    amount: 2500, amount_received: 2500, latest_charge: "ch_wallet", metadata,
    ...overrides,
  } as unknown as Stripe.PaymentIntent;
}
function request() {
  return new Request("https://app.invalid/paymentIntentStatus", {
    method: "POST", headers: { Authorization: "Bearer verified-user-token" },
    body: JSON.stringify({ paymentIntentId: "pi_wallet", livemode: true, amount: 999999 }),
  });
}
function fixture(value = intent()) {
  const calls: { name: string; params: unknown }[] = [];
  const deps: PaymentIntentStatusDeps = {
    stripe: { paymentIntents: { retrieve: (id: string) => {
      assertEquals(id, "pi_wallet");
      return Promise.resolve(value);
    } } } as unknown as PaymentIntentStatusDeps["stripe"],
    supabaseAdmin: {
      auth: { getUser: (token: string) => {
        assertEquals(token, "verified-user-token");
        return Promise.resolve({ data: { user: { id: "user-1" } }, error: null });
      } },
      rpc: (name: string, params: unknown) => {
        calls.push({ name, params });
        return Promise.resolve({ data: "wallet-1", error: null });
      },
    } as unknown as PaymentIntentStatusDeps["supabaseAdmin"],
  };
  return { deps, calls };
}

const invalid: [string, Record<string, unknown>][] = [
  ["foreign currency", { currency: "eur" }],
  ["missing currency", { currency: undefined }],
  ["noncanonical currency", { currency: "USD" }],
  ["zero received with positive requested", { amount_received: 0 }],
  ["missing received with positive requested", { amount_received: undefined }],
  ["negative received", { amount_received: -1 }],
  ["fractional received", { amount_received: 2500.5 }],
  ["NaN received", { amount_received: NaN }],
  ["infinite received", { amount_received: Infinity }],
  ["unsafe integer", { amount: Number.MAX_SAFE_INTEGER + 1, amount_received: Number.MAX_SAFE_INTEGER + 1,
    metadata: { ...metadata, amount_cents: String(Number.MAX_SAFE_INTEGER + 1) } }],
  ["string received", { amount_received: "2500" }],
  ["partially received", { amount_received: 2400 }],
  ["over received", { amount_received: 2600 }],
  ["missing requested", { amount: undefined }],
  ["string requested", { amount: "2500" }],
  ["fractional requested", { amount: 2500.5 }],
  ["missing metadata amount", { metadata: { user_id: "user-1", purpose: "wallet_load" } }],
  ["wrong metadata amount", { metadata: { ...metadata, amount_cents: "2400" } }],
  ["noncanonical metadata amount", { metadata: { ...metadata, amount_cents: "02500" } }],
  ["numeric metadata amount", { metadata: { ...metadata, amount_cents: 2500 } }],
  ["missing mode", { livemode: undefined }],
  ["null mode", { livemode: null }],
  ["string mode", { livemode: "false" }],
  ["direct-machine purpose", { metadata: { ...metadata, purpose: "direct_machine_payment" } }],
  ["missing purpose", { metadata: { user_id: "user-1", amount_cents: "2500" } }],
];
for (const [label, overrides] of invalid) {
  Deno.test(`wallet evidence: ${label} never records while preserving provider status`, async () => {
    const value = intent(overrides);
    const { deps, calls } = fixture(value);
    assertEquals(await recordWalletLoadFromIntent(value, "user-1", deps.supabaseAdmin), false);
    const response = await handlePaymentIntentStatus(request(), deps);
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {
      paymentIntentId: "pi_wallet", status: "succeeded", walletLoadRecorded: false,
    });
    assertEquals(calls, []);
  });
}

for (const status of ["processing", "requires_action", "requires_capture", "canceled", "requires_payment_method", "unknown"]) {
  Deno.test(`wallet evidence: ${status} does not settle even with positive received`, async () => {
    const value = intent({ status });
    const { deps, calls } = fixture(value);
    assertEquals(await recordWalletLoadFromIntent(value, "user-1", deps.supabaseAdmin), false);
    const response = await handlePaymentIntentStatus(request(), deps);
    assertEquals(await response.json(), {
      paymentIntentId: "pi_wallet", status: normalizePaymentIntentStatus(status), walletLoadRecorded: false,
    });
    assertEquals(calls, []);
  });
}

for (const owner of [undefined, "other-user"]) {
  Deno.test(`wallet evidence: helper and handler reject owner ${owner}`, async () => {
    const value = intent({ metadata: { ...metadata, user_id: owner } });
    const { deps, calls } = fixture(value);
    assertEquals(await recordWalletLoadFromIntent(value, "user-1", deps.supabaseAdmin), false);
    assertEquals((await handlePaymentIntentStatus(request(), deps)).status, 403);
    assertEquals(calls, []);
  });
}

for (const id of ["pi_other", "not-an-intent", undefined]) {
  Deno.test(`wallet evidence: retrieval must return exact requested identity ${id}`, async () => {
    const { deps, calls } = fixture(intent({ id }));
    const response = await handlePaymentIntentStatus(request(), deps);
    assertEquals(response.status, 409);
    assertEquals(await response.json(), { error: "PaymentIntent details do not match" });
    assertEquals(calls, []);
  });
}

for (const livemode of [false, true]) {
  Deno.test(`wallet evidence: valid mode ${livemode} uses unchanged RPC and canonical retry identities`, async () => {
    const { deps, calls } = fixture(intent({ livemode, latest_charge: { id: "ch_wallet" } }));
    for (let attempt = 0; attempt < 2; attempt++) {
      const response = await handlePaymentIntentStatus(request(), deps);
      assertEquals(response.status, 200);
      assertEquals(await response.json(), {
        paymentIntentId: "pi_wallet", status: "succeeded", walletLoadRecorded: true,
      });
    }
    const expected = { name: "record_wallet_load_from_stripe", params: {
      target_user_id: "user-1", amount_cents: 2500, stripe_payment_intent_id: "pi_wallet",
      stripe_checkout_session_id: null, stripe_charge_id: "ch_wallet", stripe_event_id: null,
    } };
    assertEquals(calls, [expected, expected]);
  });
}

Deno.test("wallet evidence: Checkout helper preserves its session reference", async () => {
  const { deps, calls } = fixture();
  assertEquals(await recordWalletLoadFromIntent(intent(), "user-1", deps.supabaseAdmin, "cs_wallet"), true);
  assertEquals(calls, [{ name: "record_wallet_load_from_stripe", params: {
    target_user_id: "user-1", amount_cents: 2500, stripe_payment_intent_id: "pi_wallet",
    stripe_checkout_session_id: "cs_wallet", stripe_charge_id: "ch_wallet", stripe_event_id: null,
  } }]);
});

Deno.test("wallet evidence: RPC failure keeps paid status and does not claim wallet readiness", async () => {
  const { deps } = fixture();
  deps.supabaseAdmin.rpc = (() => Promise.resolve({ data: null, error: { message: "ledger unavailable" } })) as unknown as typeof deps.supabaseAdmin.rpc;
  await assertRejects(() => recordWalletLoadFromIntent(intent(), "user-1", deps.supabaseAdmin), Error, "ledger unavailable");
  const response = await handlePaymentIntentStatus(request(), deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    paymentIntentId: "pi_wallet", status: "succeeded", walletLoadRecorded: false,
  });
});

Deno.test("wallet evidence: wallet readiness waits for the existing ledger RPC", async () => {
  const { deps } = fixture();
  let finish!: (result: { data: string; error: null }) => void;
  let entered!: () => void;
  const started = new Promise<void>((resolve) => { entered = resolve; });
  const pending = new Promise<{ data: string; error: null }>((resolve) => { finish = resolve; });
  deps.supabaseAdmin.rpc = (() => { entered(); return pending; }) as unknown as typeof deps.supabaseAdmin.rpc;
  let settled = false;
  const response = handlePaymentIntentStatus(request(), deps).then((value) => { settled = true; return value; });
  await started;
  assertEquals(settled, false);
  finish({ data: "wallet-1", error: null });
  assertEquals((await (await response).json()).walletLoadRecorded, true);
});
