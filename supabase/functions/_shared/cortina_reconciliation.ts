import type Stripe from "npm:stripe@14.25.0";
import { hasFrozenVendBinding, type VendSession } from "./cortina.ts";

export type ReconcileSession = VendSession & {
  stripe_charge_id: string | null;
  reconcile_claim: string;
  start_requested_at?: string | null;
};
export type ReconcileOutcome = "payment_pending" | "payment_verified" | "refund_pending" |
  "refund_succeeded" | "manual_review" | "provider_unavailable";
export type Observation = {
  outcome: ReconcileOutcome;
  reason: string;
  evidence: Record<string, unknown>;
};
export interface ReconciliationDeps {
  claim(environment: "sandbox" | "production"): Promise<ReconcileSession | null>;
  finish(session: ReconcileSession, observation: Observation): Promise<boolean>;
  payment(id: string): Promise<Stripe.PaymentIntent>;
  checkout(id: string): Promise<Stripe.Checkout.Session>;
  refund(id: string): Promise<Stripe.Refund>;
}

function reference(value: string | { id: string } | null): string | null {
  return typeof value === "string" ? value : value?.id ?? null;
}

function metadataMatches(session: ReconcileSession, metadata: Stripe.Metadata | null): boolean {
  return metadata?.purpose === "cortina_vend" && metadata.cortina_session_id === session.id &&
    metadata.machine_id === String(session.machine_id) &&
    metadata.amount_cents === String(session.amount_cents) &&
    (metadata.user_id ?? null) === session.user_id;
}

function outcome(outcome: ReconcileOutcome, reason: string, evidence = {}): Observation {
  return { outcome, reason, evidence };
}

export async function observeCortinaSession(
  session: ReconcileSession,
  deps: Pick<ReconciliationDeps, "payment" | "checkout" | "refund">,
): Promise<Observation> {
  if (session.funding_source === "machine_issue") return outcome("manual_review", "sponsored_replacement_needs_review");
  if (!hasFrozenVendBinding(session)) return outcome("manual_review", "original_routing_unavailable");
  if (session.payment_method !== "card") return outcome("manual_review", "wallet_vend_needs_review");
  const canAwaitPayment = !session.start_requested_at && !session.stripe_refund_id &&
    ["payment_pending", "failed", "support_required"].includes(session.status);
  let intentId = session.stripe_payment_intent_id;
  const evidence: Record<string, unknown> = {};
  let checkout: Stripe.Checkout.Session | undefined;
  if (session.channel === "web") {
    if (!session.stripe_checkout_session_id) return outcome("manual_review", "checkout_binding_missing");
    checkout = await deps.checkout(session.stripe_checkout_session_id);
    if (checkout.id !== session.stripe_checkout_session_id || checkout.mode !== "payment" ||
      checkout.amount_total !== session.amount_cents || checkout.currency?.toUpperCase() !== session.currency ||
      checkout.livemode !== session.stripe_livemode || !metadataMatches(session, checkout.metadata)) {
      return outcome("manual_review", "checkout_evidence_mismatch");
    }
    const checkoutIntent = reference(checkout.payment_intent);
    if (intentId && checkoutIntent !== intentId) return outcome("manual_review", "intent_binding_mismatch");
    if (checkout.status === "expired") return outcome("manual_review", "checkout_expired");
    if (!checkoutIntent) {
      return checkout.status === "open" && checkout.payment_status === "unpaid" && canAwaitPayment
        ? outcome("payment_pending", "checkout_unpaid")
        : outcome("manual_review", "checkout_intent_unknown");
    }
    intentId = checkoutIntent;
    evidence.checkout = {
      id: checkout.id, payment_intent: intentId, mode: checkout.mode, status: checkout.status,
      payment_status: checkout.payment_status, amount_total: checkout.amount_total,
      currency: checkout.currency, livemode: checkout.livemode, metadata: checkout.metadata,
    };
  } else if (session.stripe_checkout_session_id) {
    return outcome("manual_review", "checkout_binding_mismatch");
  }
  if (!intentId) return outcome("manual_review", "intent_binding_missing");
  const payment = await deps.payment(intentId);
  if (payment.id !== intentId || payment.amount !== session.amount_cents ||
    payment.currency?.toUpperCase() !== session.currency || payment.livemode !== session.stripe_livemode ||
    !metadataMatches(session, payment.metadata)) {
    return outcome("manual_review", "payment_evidence_mismatch");
  }
  if (payment.status !== "succeeded") {
    if (payment.status === "canceled" || !canAwaitPayment) {
      return outcome("manual_review", "payment_not_confirmed");
    }
    return outcome("payment_pending", "payment_not_settled");
  }
  const chargeId = reference(payment.latest_charge);
  if (payment.amount_received !== session.amount_cents || !chargeId ||
    (session.stripe_charge_id && session.stripe_charge_id !== chargeId)) {
    return outcome("manual_review", "received_payment_mismatch");
  }
  if (checkout && (checkout.status !== "complete" || checkout.payment_status !== "paid")) {
    return outcome("manual_review", "checkout_settlement_mismatch");
  }
  evidence.payment = {
    id: payment.id, status: payment.status, amount: payment.amount, amount_received: payment.amount_received,
    currency: payment.currency, livemode: payment.livemode, metadata: payment.metadata, charge_id: chargeId,
  };
  if (!session.stripe_refund_id) {
    // Delayed funding is auditable, not permission to start an unattended
    // machine or to guess whether a previous Start/unknown refund succeeded.
    return outcome("payment_verified", "vend_or_refund_outcome_needs_review", evidence);
  }
  const refund = await deps.refund(session.stripe_refund_id);
  if (refund.id !== session.stripe_refund_id || reference(refund.payment_intent) !== payment.id ||
    reference(refund.charge) !== chargeId || refund.amount !== session.amount_cents ||
    refund.currency?.toUpperCase() !== session.currency) {
    return outcome("payment_verified", "bound_refund_evidence_mismatch", evidence);
  }
  evidence.refund = { id: refund.id, payment_intent: payment.id, charge: chargeId,
    amount: refund.amount, currency: refund.currency, status: refund.status };
  if (refund.status === "succeeded") return outcome("refund_succeeded", "bound_refund_succeeded", evidence);
  if (refund.status === "pending" || refund.status === "requires_action") {
    return outcome("refund_pending", "bound_refund_pending", evidence);
  }
  // A failed bound refund does not prove that an external replacement is absent.
  // Never create another refund or release any voluntary-refund reservation here.
  return outcome("payment_verified", "bound_refund_needs_review", evidence);
}

export async function reconcileOneCortinaSession(
  environment: "sandbox" | "production",
  deps: ReconciliationDeps,
): Promise<{ processed: number; applied?: boolean; outcome?: ReconcileOutcome }> {
  const session = await deps.claim(environment);
  if (!session) return { processed: 0 };
  let observation: Observation;
  try {
    observation = session.nayax_environment && session.nayax_environment !== environment
      ? outcome("manual_review", "environment_mismatch")
      : await observeCortinaSession(session, deps);
  } catch {
    observation = outcome("provider_unavailable", "provider_observation_unavailable");
  }
  // Do not retry an uncertain database finish in-process. Its lease and atomic
  // audit permit a later invocation to read fresh provider state safely.
  const applied = await deps.finish(session, observation);
  return { processed: 1, applied, outcome: observation.outcome };
}
