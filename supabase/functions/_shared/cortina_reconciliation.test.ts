import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { observeCortinaSession, reconcileOneCortinaSession, type ReconcileSession,
  type ReconciliationDeps, type Observation } from "./cortina_reconciliation.ts";

type Row = Record<string, any>;
function fixture(channel: "app" | "web" = "app") {
  const session: ReconcileSession = {
    id: "00000000-0000-4000-8000-000000000001", machine_id: 1, user_id: null,
    amount_cents: 400, currency: "USD", payment_method: "card", channel,
    dryer_minutes: null, product_code: 3, pulse_line_number: null,
    status: "support_required", transaction_id: "synthetic-vend",
    stripe_payment_intent_id: "pi_test", stripe_checkout_session_id: channel === "web" ? "cs_test" : null,
    stripe_charge_id: "ch_test", stripe_refund_id: "re_test", wallet_redemption_id: null,
    nayax_environment: "sandbox", nayax_terminal_id: "4434331126150568", nayax_uniqr: null,
    stripe_livemode: false, reconcile_claim: "00000000-0000-4000-8000-000000000002",
  };
  const metadata = { purpose: "cortina_vend", cortina_session_id: session.id, machine_id: "1", amount_cents: "400" };
  const payment: Row = { id: "pi_test", status: "succeeded", amount: 400, amount_received: 400,
    currency: "usd", livemode: false, latest_charge: "ch_test", metadata: { ...metadata } };
  const checkout: Row = { id: "cs_test", mode: "payment", status: "complete", payment_status: "paid",
    amount_total: 400, currency: "usd", livemode: false, payment_intent: "pi_test", metadata: { ...metadata } };
  const refund: Row = { id: "re_test", payment_intent: "pi_test", charge: "ch_test", amount: 400,
    currency: "usd", status: "succeeded" };
  const calls: string[] = [], finishes: Observation[] = [];
  const deps = {
    claim: async () => { calls.push("claim"); return structuredClone(session); },
    finish: async (_session: ReconcileSession, observation: Observation) => {
      calls.push("finish"); finishes.push(observation); return true;
    },
    payment: async (id: string) => { calls.push(`payment:${id}`); return structuredClone(payment); },
    checkout: async (id: string) => { calls.push(`checkout:${id}`); return structuredClone(checkout); },
    refund: async (id: string) => { calls.push(`refund:${id}`); return structuredClone(refund); },
  } as unknown as ReconciliationDeps;
  return { session, payment, checkout, refund, calls, finishes, deps };
}

Deno.test("closed-app worker retrieves and completes only the already-bound refund", async () => {
  const f = fixture(); const result = await reconcileOneCortinaSession("sandbox", f.deps);
  assertEquals(result, { processed: 1, applied: true, outcome: "refund_succeeded" });
  assertEquals(f.calls, ["claim", "payment:pi_test", "refund:re_test", "finish"]);
  assertEquals(f.finishes[0].evidence.refund, { id: "re_test", payment_intent: "pi_test", charge: "ch_test",
    amount: 400, currency: "usd", status: "succeeded" });
});

for (const status of ["pending", "requires_action", "failed", "canceled", null, "unknown"]) {
  Deno.test(`bound refund ${status} is never replaced or prematurely completed`, async () => {
    const f = fixture(); f.refund.status = status;
    const observation = await observeCortinaSession(f.session, f.deps);
    assertEquals(observation.outcome, ["pending", "requires_action"].includes(status ?? "") ? "refund_pending" : "payment_verified");
    assertEquals(f.calls, ["payment:pi_test", "refund:re_test"]);
    assertEquals(f.session.stripe_refund_id, "re_test");
  });
}

for (const patch of [{ id: "re_other" }, { payment_intent: "pi_other" }, { charge: "ch_other" },
  { amount: 399 }, { currency: "eur" }]) {
  Deno.test(`bound refund mismatch stays support-required ${JSON.stringify(patch)}`, async () => {
    const f = fixture(); Object.assign(f.refund, patch);
    const result = await observeCortinaSession(f.session, f.deps);
    assertEquals(result.outcome, "payment_verified");
    assertEquals(result.reason, "bound_refund_evidence_mismatch");
    assertEquals(result.evidence.refund, undefined);
  });
}

for (const patch of [{ id: "pi_other" }, { amount: 399 }, { amount_received: 399 }, { currency: "eur" },
  { livemode: true }, { latest_charge: "ch_other" }, { latest_charge: null }, { metadata: {} }]) {
  Deno.test(`mismatched payment cannot reconcile money ${JSON.stringify(patch)}`, async () => {
    const f = fixture(); Object.assign(f.payment, patch);
    assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "manual_review");
    assertEquals(f.calls, ["payment:pi_test"]);
  });
}

Deno.test("web reconciliation verifies its stored Checkout before the bound payment/refund", async () => {
  const f = fixture("web"); f.session.stripe_payment_intent_id = null;
  f.checkout.payment_intent = { id: "pi_test" };
  const result = await observeCortinaSession(f.session, f.deps);
  assertEquals(result.outcome, "refund_succeeded");
  assertEquals(f.calls, ["checkout:cs_test", "payment:pi_test", "refund:re_test"]);
});

for (const patch of [{ id: "cs_other" }, { payment_intent: "pi_other" }, { mode: "subscription" },
  { amount_total: 399 }, { currency: "eur" }, { livemode: true }, { metadata: {} }, { status: "open" }]) {
  Deno.test(`Checkout mismatch does not finish a refund ${JSON.stringify(patch)}`, async () => {
    const f = fixture("web"); Object.assign(f.checkout, patch);
    assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "manual_review");
    assertEquals(f.calls.includes("refund:re_test"), false);
  });
}

for (const status of ["payment_pending", "paid", "starting", "awaiting_sale", "approved", "failed", "timed_out", "support_required"] as const) {
  Deno.test(`${status} without a refund binding never invents another Start or refund`, async () => {
    const f = fixture(); f.session.status = status; f.session.stripe_refund_id = null;
    const result = await observeCortinaSession(f.session, f.deps);
    assertEquals(result.outcome, "payment_verified");
    assertEquals(result.reason, "vend_or_refund_outcome_needs_review");
    assertEquals(f.calls, ["payment:pi_test"]);
  });
}

Deno.test("pending payment schedules another observation without declaring a failed vend", async () => {
  const f = fixture(); f.session.status = "payment_pending"; f.session.stripe_refund_id = null;
  f.payment.status = "processing"; f.payment.amount_received = 0;
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "payment_pending");
  assertEquals(f.calls, ["payment:pi_test"]);
});

Deno.test("a transient provider failure does not strand an unsettled payment in support", async () => {
  const f = fixture(); f.session.status = "support_required"; f.session.stripe_refund_id = null;
  f.payment.status = "processing"; f.payment.amount_received = 0;
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "payment_pending");
  f.payment.status = "succeeded"; f.payment.amount_received = 400;
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "payment_verified");
  assertEquals(f.calls, ["payment:pi_test", "payment:pi_test"]);
});

Deno.test("an uncertain prior Start is not treated as an unsettled new payment", async () => {
  const f = fixture(); f.session.stripe_refund_id = null;
  f.session.start_requested_at = "2026-09-30T12:00:00Z"; f.payment.status = "processing";
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "manual_review");
  assertEquals(f.calls, ["payment:pi_test"]);
});

Deno.test("unpaid Checkout can wait without guessing a PaymentIntent", async () => {
  const f = fixture("web"); f.session.status = "payment_pending";
  f.session.stripe_payment_intent_id = null; f.session.stripe_refund_id = null;
  f.checkout.payment_intent = null; f.checkout.status = "open"; f.checkout.payment_status = "unpaid";
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "payment_pending");
  assertEquals(f.calls, ["checkout:cs_test"]);
});

Deno.test("legacy routing and wallet uncertainty stop without any provider lookup", async () => {
  for (const patch of [{ nayax_environment: null }, { stripe_livemode: null }, { product_code: null }, { payment_method: "wallet" }]) {
    const f = fixture(); Object.assign(f.session, patch);
    assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "manual_review");
    assertEquals(f.calls, []);
  }
});

Deno.test("pending-deletion ownership can settle without a human login or account mutation", async () => {
  const f = fixture(); f.session.user_id = "pending-deletion-user";
  f.payment.metadata.user_id = f.session.user_id;
  const before = structuredClone(f.session);
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "refund_succeeded");
  assertEquals(f.session, before);
  f.session.user_id = null;
  assertEquals((await observeCortinaSession(f.session, f.deps)).outcome, "manual_review");
});

Deno.test("a lost provider response is durable support/backoff, not another provider operation", async () => {
  const f = fixture(); f.deps.refund = async () => { f.calls.push("refund-timeout"); throw Error("secret provider details"); };
  const result = await reconcileOneCortinaSession("sandbox", f.deps);
  assertEquals(result.outcome, "provider_unavailable");
  assertEquals(f.finishes[0], { outcome: "provider_unavailable", reason: "provider_observation_unavailable", evidence: {} });
  assertEquals(f.calls, ["claim", "payment:pi_test", "refund-timeout", "finish"]);
});

Deno.test("a stale claim cannot apply its observation and is not reclaimed in-process", async () => {
  const f = fixture(); f.deps.finish = async () => false;
  assertEquals(await reconcileOneCortinaSession("sandbox", f.deps), {
    processed: 1, applied: false, outcome: "refund_succeeded",
  });
  assertEquals(f.calls.filter((call) => call === "claim").length, 1);
});

Deno.test("database completion uncertainty is not retried or reported as success", async () => {
  const f = fixture(); let finishes = 0;
  f.deps.finish = async () => { finishes++; throw Error("database unavailable"); };
  await assertRejects(() => reconcileOneCortinaSession("sandbox", f.deps));
  assertEquals(finishes, 1); assertEquals(f.calls.filter((call) => call === "claim").length, 1);
});

Deno.test("empty queue returns without any provider operation", async () => {
  const f = fixture(); f.deps.claim = async () => null;
  assertEquals(await reconcileOneCortinaSession("sandbox", f.deps), { processed: 0 });
  assertEquals(f.calls, []);
});

Deno.test("a claimed session from another environment cannot reach a provider", async () => {
  const f = fixture(); f.session.nayax_environment = "production"; f.session.stripe_livemode = true;
  assertEquals(await reconcileOneCortinaSession("sandbox", f.deps), {
    processed: 1, applied: true, outcome: "manual_review",
  });
  assertEquals(f.calls, ["claim", "finish"]);
  assertEquals(f.finishes, [{ outcome: "manual_review", reason: "environment_mismatch", evidence: {} }]);
});
