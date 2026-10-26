export function selectWebhookSecret(
  rawBody: string,
  secrets: { live?: string; sandbox?: string },
): string {
  const { livemode } = JSON.parse(rawBody);
  if (typeof livemode !== "boolean") throw new Error("Invalid Stripe event mode");
  // This untrusted field only selects a key; the raw body must still pass verification.
  const secret = livemode ? secrets.live : secrets.sandbox ?? secrets.live;
  if (!secret) throw new Error("Stripe webhook signing secret is not configured");
  return secret;
}

export interface StripeEvent {
    id?: string;
    created?: number;
    livemode?: boolean;
    type: string;
    data: {
      object: any;
    };
  }
  
  export interface Dependencies {
    verifyAndConstructEvent: (rawBody: string, signature: string) => Promise<StripeEvent>;
    recordTopupRefundProvenance?: (payload: {
      intent: string; user: string; amount: number; succeededAt: string;
      event: string; livemode: boolean;
    }) => Promise<void>;
    recordWalletLoad?: (payload: {
      user_id: string;
      amount_cents: number;
      stripe_payment_intent_id?: string | null;
      stripe_checkout_session_id?: string | null;
      stripe_charge_id?: string | null;
      stripe_event_id?: string | null;
    }) => Promise<void>;
    recordCortinaPayment?: (payload: {
      event_id: string;
      session_id: string;
      amount_cents: number;
      stripe_payment_intent_id: string;
      stripe_checkout_session_id?: string | null;
      stripe_charge_id?: string | null;
    }) => Promise<void>;
  }
  
  export async function handleStripeWebhook(
    params: {
      rawBody: string;
      signature: string | null;
    },
    deps: Dependencies
  ) {
    const { rawBody, signature } = params;
    const {
      verifyAndConstructEvent,
      recordWalletLoad,
      recordCortinaPayment,
    } = deps;
  
    if (!signature) {
      return { status: 400, body: "No signature" };
    }
  
    let event: StripeEvent;
  
    try {
      event = await verifyAndConstructEvent(rawBody, signature);
    } catch (err: any) {
      return {
        status: 400,
        body: `Webhook Error: ${err.message}`,
      };
    }
  
    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const purpose = session.metadata?.purpose;
      const userId = session.metadata?.user_id;
      const amount = session.amount_total;

      if (purpose === "wallet_load" && userId && amount) {
        await recordWalletLoad?.({
          user_id: userId,
          amount_cents: amount,
          stripe_payment_intent_id: session.payment_intent,
          stripe_checkout_session_id: session.id,
          stripe_event_id: event.id ?? null,
        });
      }

      if (
        purpose === "cortina_vend" && session.metadata?.cortina_session_id &&
        amount && typeof session.payment_intent === "string"
      ) {
        await recordCortinaPayment?.({
          event_id: event.id ?? `checkout:${session.id}`,
          session_id: session.metadata.cortina_session_id,
          amount_cents: amount,
          stripe_payment_intent_id: session.payment_intent,
          stripe_checkout_session_id: session.id,
        });
      }
    }

    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object;
      const purpose = paymentIntent.metadata?.purpose;
      const userId = paymentIntent.metadata?.user_id;
      const amount = paymentIntent.amount_received ?? paymentIntent.amount;

      if (purpose === "wallet_load" && userId && amount) {
        await recordWalletLoad?.({
          user_id: userId,
          amount_cents: amount,
          stripe_payment_intent_id: paymentIntent.id,
          stripe_charge_id:
            typeof paymentIntent.latest_charge === "string"
              ? paymentIntent.latest_charge
              : paymentIntent.latest_charge?.id ?? null,
          stripe_event_id: event.id ?? null,
        });
        if (deps.recordTopupRefundProvenance && event.id &&
          Number.isSafeInteger(event.created) && (event.created ?? 0) > 0 &&
          typeof event.livemode === "boolean" && paymentIntent.status === "succeeded" &&
          paymentIntent.currency === "usd" && Number.isSafeInteger(amount) && amount > 0) {
          await deps.recordTopupRefundProvenance({
            intent: paymentIntent.id, user: userId, amount,
            succeededAt: new Date(event.created! * 1000).toISOString(),
            event: event.id, livemode: event.livemode,
          });
        }
      }


      if (purpose === "cortina_vend" && paymentIntent.metadata?.cortina_session_id) {
        await recordCortinaPayment?.({
          event_id: event.id ?? `payment-intent:${paymentIntent.id}`,
          session_id: paymentIntent.metadata.cortina_session_id,
          amount_cents: amount,
          stripe_payment_intent_id: paymentIntent.id,
          stripe_charge_id:
            typeof paymentIntent.latest_charge === "string"
              ? paymentIntent.latest_charge
              : paymentIntent.latest_charge?.id ?? null,
        });
      }
    }
  
    return { status: 200, body: "OK" };
  }
