import Stripe from "npm:stripe@14";
import { handleStripeWebhook, selectWebhookSecret } from "./logic.ts";
import {
  createAdminClient,
  errorResponse,
  markCortinaCardPaid,
} from "../_shared/cortina.ts";

export async function handler(req: Request): Promise<Response> {
  let admin;
  try {
    admin = createAdminClient("stripeWebhook");
  } catch (error) {
    return errorResponse(error);
  }
  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
    apiVersion: "2023-10-16",
    httpClient: Stripe.createFetchHttpClient(),
  });
  const signature = req.headers.get("stripe-signature");
  const rawBody = await req.text();

  const result = await handleStripeWebhook(
    { rawBody, signature },
    {
      verifyAndConstructEvent: async (body, sig) => {
        const webhookSecret = selectWebhookSecret(body, {
          live: Deno.env.get("STRIPE_WEBHOOK_SECRET"),
          sandbox: Deno.env.get("STRIPE_SANDBOX_WEBHOOK_SECRET"),
        });
        return await stripe.webhooks.constructEventAsync(
          body,
          sig,
          webhookSecret,
          undefined,
          Stripe.createSubtleCryptoProvider()
        );
      },

      recordWalletLoad: async (payload) => {
        const { error } = await admin.rpc("record_wallet_load_from_stripe", {
          target_user_id: payload.user_id,
          amount_cents: payload.amount_cents,
          stripe_payment_intent_id: payload.stripe_payment_intent_id ?? null,
          stripe_checkout_session_id: payload.stripe_checkout_session_id ?? null,
          stripe_charge_id: payload.stripe_charge_id ?? null,
          stripe_event_id: payload.stripe_event_id ?? null,
        });

        if (error) {
          throw new Error(error.message);
        }
      },

      recordTopupRefundProvenance: async (payload) => {
        const { error } = await admin.rpc("record_topup_refund_provenance", {
          p_intent: payload.intent, p_user: payload.user, p_amount: payload.amount,
          p_succeeded_at: payload.succeededAt, p_event: payload.event,
          p_livemode: payload.livemode,
        });
        // Funding is already idempotently committed. A delivery retry can repair
        // provenance without crediting the wallet twice.
        if (error) throw new Error("Top-up refund provenance unavailable");
      },

      recordCortinaPayment: async (payload) => {
        await markCortinaCardPaid(
          {
            eventId: payload.event_id,
            sessionId: payload.session_id,
            amountCents: payload.amount_cents,
            paymentIntentId: payload.stripe_payment_intent_id,
            checkoutSessionId: payload.stripe_checkout_session_id,
            chargeId: payload.stripe_charge_id,
          },
          { admin, stripe },
        );
      },
    }
  );

  return new Response(result.body, { status: result.status });
}

if (import.meta.main) Deno.serve(handler);
