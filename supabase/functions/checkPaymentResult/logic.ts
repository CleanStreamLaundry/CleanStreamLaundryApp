import type Stripe from "npm:stripe@^14.0.0";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  getAuthenticatedUserId,
  recordWalletLoadFromIntent,
} from "../paymentIntentStatus/logic.ts";

export interface PaymentDeps {
  retrieveSession: (sessionId: string) => Promise<Stripe.Checkout.Session>;
  supabaseAdmin: SupabaseClient;
}

export type CheckoutPaymentStatus =
  | "succeeded"
  | "processing"
  | "canceled"
  | "unknown";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function getPaymentStatusLogic(
  req: Request,
  deps: PaymentDeps,
): Promise<Response> {
  const userId = await getAuthenticatedUserId(req, deps.supabaseAdmin);
  if (!userId) return json({ error: "Unauthorized" }, 401);

  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  const sessionId = body?.session_id;
  if (typeof sessionId !== "string" || !/^cs_[A-Za-z0-9_]+$/.test(sessionId)) {
    return json({ error: "Invalid session_id" }, 400);
  }

  const session = await deps.retrieveSession(sessionId);
  if (session.metadata?.user_id !== userId) {
    return json({ error: "Forbidden" }, 403);
  }

  const purpose = session.metadata.purpose;
  const amountCents = session.amount_total;
  if (
    session.id !== sessionId || session.mode !== "payment" ||
    session.currency !== "usd" || !Number.isSafeInteger(amountCents) ||
    amountCents === null || amountCents <= 0 ||
    session.metadata.amount_cents !== String(amountCents) ||
    (purpose !== "wallet_load" && purpose !== "direct_machine_payment") ||
    !["paid", "unpaid", "no_payment_required"].includes(session.payment_status)
  ) {
    return json({ error: "Checkout details do not match" }, 409);
  }

  // Retrieve with payment_intent expanded; never accept a client-supplied intent.
  const intent = session.payment_intent;
  if (typeof intent === "string") {
    return json({ error: "Checkout details unavailable" }, 503);
  }
  if (intent && intent.metadata?.user_id !== userId) {
    return json({ error: "Forbidden" }, 403);
  }
  if (
    intent && (
      !intent.id.startsWith("pi_") ||
      intent.metadata.purpose !== purpose ||
      intent.metadata.amount_cents !== String(amountCents) ||
      intent.amount !== amountCents || intent.currency !== session.currency ||
      intent.livemode !== session.livemode
    )
  ) {
    return json({ error: "Checkout details do not match" }, 409);
  }

  let paymentStatus: CheckoutPaymentStatus = "unknown";
  if (
    session.payment_status === "paid" && session.status === "complete" &&
    intent?.status === "succeeded" && intent.amount_received === amountCents
  ) {
    paymentStatus = "succeeded";
  } else if (
    session.payment_status === "unpaid" && intent?.status !== "succeeded"
  ) {
    if (
      session.status === "expired" &&
      (!intent || (intent.amount_received === 0 &&
        (intent.status === "canceled" ||
          intent.status === "requires_payment_method")))
    ) {
      paymentStatus = "canceled";
    } else if (
      (session.status === "open" || session.status === "complete") &&
      intent?.status !== "canceled"
    ) {
      // A declined card can be retried inside an open Checkout Session.
      paymentStatus = "processing";
    }
  }

  let walletLoadRecorded = false;
  if (paymentStatus === "succeeded" && purpose === "wallet_load" && intent) {
    try {
      walletLoadRecorded = await recordWalletLoadFromIntent(
        intent,
        userId,
        deps.supabaseAdmin,
        session.id,
      );
    } catch {
      // Paid but not reconciled: callers must keep this wallet load pending.
    }
  }

  return json({
    session_id: session.id,
    status: session.payment_status,
    paymentStatus,
    paymentIntentId: intent?.id ?? null,
    purpose,
    amountCents,
    currency: session.currency,
    walletLoadRecorded,
  });
}
