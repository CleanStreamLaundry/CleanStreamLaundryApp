import Stripe from "npm:stripe";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type NormalizedPaymentIntentStatus =
  | "succeeded"
  | "processing"
  | "canceled"
  | "failed"
  | "unknown";

export interface PaymentIntentStatusDeps {
  stripe: Stripe;
  supabaseAdmin: SupabaseClient;
}

export function normalizePaymentIntentStatus(
  status: string | null | undefined
): NormalizedPaymentIntentStatus {
  switch (status) {
    case "succeeded":
      return "succeeded";
    case "processing":
    case "requires_action":
    case "requires_confirmation":
    case "requires_capture":
      return "processing";
    case "canceled":
      return "canceled";
    case "requires_payment_method":
      return "failed";
    default:
      return "unknown";
  }
}

export async function getAuthenticatedUserId(
  req: Request,
  supabaseAdmin: SupabaseClient
): Promise<string | null> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return null;
  }

  const token = authorization.replace("Bearer ", "");
  if (!token || token === authorization) {
    return null;
  }

  const {
    data: { user },
    error,
  } = await supabaseAdmin.auth.getUser(token);

  if (error || !user) {
    return null;
  }

  return user.id;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function getPaymentIntentChargeId(intent: Stripe.PaymentIntent): string | null {
  const charge = intent.latest_charge;
  if (typeof charge === "string") {
    return charge;
  }
  return charge?.id ?? null;
}

export async function recordWalletLoadFromIntent(
  intent: Stripe.PaymentIntent,
  userId: string,
  supabaseAdmin: SupabaseClient,
  checkoutSessionId: string | null = null
): Promise<boolean> {
  // This writer is shared with Checkout status. Require the same paid USD
  // principal/metadata evidence here, including when called without Checkout.
  const amountCents = intent.amount_received;
  if (
    intent.status !== "succeeded" ||
    typeof intent.id !== "string" || !intent.id.startsWith("pi_") ||
    intent.metadata?.purpose !== "wallet_load" ||
    !userId || intent.metadata.user_id !== userId ||
    intent.currency !== "usd" || typeof intent.livemode !== "boolean" ||
    !Number.isSafeInteger(amountCents) || amountCents <= 0 ||
    intent.amount !== amountCents ||
    intent.metadata.amount_cents !== String(amountCents)
  ) {
    return false;
  }

  const { error } = await supabaseAdmin.rpc("record_wallet_load_from_stripe", {
    target_user_id: userId,
    amount_cents: amountCents,
    stripe_payment_intent_id: intent.id,
    stripe_checkout_session_id: checkoutSessionId,
    stripe_charge_id: getPaymentIntentChargeId(intent),
    stripe_event_id: null,
  });

  if (error) {
    throw new Error(error.message);
  }

  return true;
}

export async function handlePaymentIntentStatus(
  req: Request,
  deps: PaymentIntentStatusDeps
): Promise<Response> {
  const userId = await getAuthenticatedUserId(req, deps.supabaseAdmin);
  if (!userId) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const body = await req.json();
  const paymentIntentId = body?.paymentIntentId;
  if (
    typeof paymentIntentId !== "string" ||
    !paymentIntentId.startsWith("pi_")
  ) {
    return jsonResponse({ error: "Invalid paymentIntentId" }, 400);
  }

  const intent = await deps.stripe.paymentIntents.retrieve(paymentIntentId);
  if (intent.id !== paymentIntentId) {
    return jsonResponse({ error: "PaymentIntent details do not match" }, 409);
  }
  if (intent.metadata?.user_id !== userId) {
    return jsonResponse(
      { error: "PaymentIntent does not belong to user" },
      403
    );
  }

  const status = normalizePaymentIntentStatus(intent.status);
  let walletLoadRecorded = false;

  if (status === "succeeded") {
    try {
      walletLoadRecorded = await recordWalletLoadFromIntent(
        intent,
        userId,
        deps.supabaseAdmin
      );
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      console.error("Unable to record wallet load", error.message);
    }
  }

  return jsonResponse({
    paymentIntentId: intent.id,
    status,
    walletLoadRecorded,
  });
}
