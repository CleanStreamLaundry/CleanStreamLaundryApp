import Stripe from "npm:stripe@14.25.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import {
  CortinaDeps,
  compensateVend,
  createVendSession,
  functionRoute,
  getOptionalUserId,
  HttpError,
  jsonResponse,
  markCortinaCardPaid,
  resolveQuote,
  sha256,
  startCortinaVend,
  validateVendAmount,
  VendSession,
} from "../_shared/cortina.ts";

function objectBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "Request body must be a JSON object", "invalid_body");
  }
  return value as Record<string, unknown>;
}

async function bodyFrom(req: Request): Promise<Record<string, unknown>> {
  try {
    return objectBody(await req.json());
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(400, "Request body must be valid JSON", "invalid_json");
  }
}

function paymentMetadata(
  sessionId: string,
  machineId: number,
  amountCents: number,
  userId: string | null,
): Record<string, string> {
  const metadata: Record<string, string> = {
    purpose: "cortina_vend",
    cortina_session_id: sessionId,
    machine_id: String(machineId),
    amount_cents: String(amountCents),
  };
  if (userId) metadata.user_id = userId;
  return metadata;
}

function clientRequestId(body: Record<string, unknown>): string {
  const value = typeof body.clientRequestId === "string"
    ? body.clientRequestId.trim()
    : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new HttpError(400, "A valid client request ID is required", "invalid_request_id");
  }
  return value;
}

export async function handleQuote(req: Request, deps: CortinaDeps): Promise<Response> {
  const body = await bodyFrom(req);
  return jsonResponse(await resolveQuote(deps.admin, {
    machineToken: body.machineToken,
    terminalId: body.terminalId,
    uniQr: body.uniQr,
  }));
}

export async function handleCard(req: Request, deps: CortinaDeps): Promise<Response> {
  const body = await bodyFrom(req);
  const channel = body.channel === "app" ? "app" : body.channel === "web" ? "web" : null;
  if (!channel) throw new HttpError(400, "Channel must be app or web", "invalid_channel");

  const quote = await resolveQuote(deps.admin, {
    machineToken: body.machineToken,
    terminalId: body.terminalId,
    uniQr: body.uniQr,
  });
  const amount = validateVendAmount(quote, body.amountCents);
  const userId = await getOptionalUserId(req, deps.admin);
  const created = await createVendSession(deps.admin, quote, {
    userId,
    amountCents: amount.amountCents,
    dryerMinutes: amount.dryerMinutes,
    pulseLineNumber: amount.pulseLineNumber,
    paymentMethod: "card",
    channel,
    clientRequestId: clientRequestId(body),
  });
  const metadata = paymentMetadata(
    created.session.id,
    quote.machineId,
    amount.amountCents,
    userId,
  );

  try {
    if (channel === "app") {
      const intent = await deps.stripe.paymentIntents.create({
        amount: amount.amountCents,
        currency: "usd",
        payment_method_types: ["card"],
        metadata,
      }, { idempotencyKey: `cortina-card-${created.session.id}` });
      const { error } = await deps.admin.from("cortina_vend_sessions").update({
        stripe_payment_intent_id: intent.id,
      }).eq("id", created.session.id);
      if (error) throw new Error(error.message);
      return jsonResponse({
        sessionId: created.session.id,
        accessToken: created.accessToken,
        clientSecret: intent.client_secret,
        paymentIntentId: intent.id,
      });
    }

    const payUrl = Deno.env.get("CLEAN_STREAM_PAY_URL") ??
      "https://cleanstreamlaundry.com/pay";
    const cancelSelector = body.machineToken
      ? `machine=${encodeURIComponent(String(body.machineToken))}`
      : body.terminalId
      ? `terminal=${encodeURIComponent(String(body.terminalId))}`
      : `uniqr=${encodeURIComponent(String(body.uniQr ?? ""))}`;
    const checkout = await deps.stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [{
        price_data: {
          currency: "usd",
          unit_amount: amount.amountCents,
          product_data: { name: `${quote.machineName} laundry service` },
        },
        quantity: 1,
      }],
      metadata,
      payment_intent_data: { metadata },
      success_url: `${payUrl}?session=${created.session.id}&access=${created.accessToken}`,
      cancel_url: `${payUrl}?${cancelSelector}`,
    }, { idempotencyKey: `cortina-checkout-${created.session.id}` });
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      stripe_checkout_session_id: checkout.id,
    }).eq("id", created.session.id);
    if (error) throw new Error(error.message);
    return jsonResponse({
      sessionId: created.session.id,
      accessToken: created.accessToken,
      checkoutUrl: checkout.url,
    });
  } catch (error) {
    await deps.admin.from("cortina_vend_sessions").update({
      status: "failed",
      failure_message: error instanceof Error ? error.message : String(error),
    }).eq("id", created.session.id);
    throw error;
  }
}

export async function handleWallet(req: Request, deps: CortinaDeps): Promise<Response> {
  const body = await bodyFrom(req);
  const userId = await getOptionalUserId(req, deps.admin);
  if (!userId) throw new HttpError(401, "Sign in to use your wallet", "unauthorized");

  const quote = await resolveQuote(deps.admin, {
    machineToken: body.machineToken,
    terminalId: body.terminalId,
    uniQr: body.uniQr,
  });
  const amount = validateVendAmount(quote, body.amountCents);
  const created = await createVendSession(deps.admin, quote, {
    userId,
    amountCents: amount.amountCents,
    dryerMinutes: amount.dryerMinutes,
    pulseLineNumber: amount.pulseLineNumber,
    paymentMethod: "wallet",
    channel: body.channel === "web" ? "web" : "app",
    clientRequestId: clientRequestId(body),
  });

  if (!created.wasCreated && created.session.status !== "payment_pending") {
    await startCortinaVend(created.session.id, deps);
    return jsonResponse({
      sessionId: created.session.id,
      accessToken: created.accessToken,
    });
  }

  const authorization = req.headers.get("authorization")!;
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: redemption, error: redemptionError } = await userClient.rpc(
    "redeem_wallet_for_cortina",
    { target_session_id: created.session.id },
  );
  if (redemptionError || !redemption) {
    await deps.admin.from("cortina_vend_sessions").update({
      status: "failed",
      failure_message: redemptionError?.message ?? "Wallet debit failed",
    }).eq("id", created.session.id);
    throw new HttpError(402, redemptionError?.message ?? "Wallet debit failed", "wallet_failed");
  }

  await startCortinaVend(created.session.id, deps);
  return jsonResponse({
    sessionId: created.session.id,
    accessToken: created.accessToken,
  });
}

export async function handleCardConfirm(
  req: Request,
  deps: CortinaDeps,
): Promise<Response> {
  const body = await bodyFrom(req);
  const sessionId = typeof body.sessionId === "string" ? body.sessionId : "";
  const accessToken = typeof body.accessToken === "string" ? body.accessToken : "";
  if (!sessionId || !accessToken) {
    throw new HttpError(400, "Missing session credentials", "missing_session");
  }

  const { data: session, error } = await deps.admin
    .from("cortina_vend_sessions")
    .select("*")
    .eq("id", sessionId)
    .eq("client_access_token_hash", await sha256(accessToken))
    .maybeSingle();
  if (error || !session) {
    throw new HttpError(404, "Vend session not found", "session_not_found");
  }
  if (session.payment_method !== "card" || !session.stripe_payment_intent_id) {
    throw new HttpError(409, "Card payment is unavailable", "payment_unavailable");
  }
  if (session.status !== "payment_pending") {
    return jsonResponse({ status: session.status });
  }

  const intent = await deps.stripe.paymentIntents.retrieve(
    session.stripe_payment_intent_id,
  );
  const amountCents = intent.amount_received || intent.amount;
  if (
    intent.status !== "succeeded" ||
    intent.currency.toLowerCase() !== session.currency.toLowerCase() ||
    amountCents !== session.amount_cents ||
    intent.metadata?.purpose !== "cortina_vend" ||
    intent.metadata?.cortina_session_id !== session.id ||
    intent.metadata?.machine_id !== String(session.machine_id) ||
    intent.metadata?.amount_cents !== String(session.amount_cents)
  ) {
    throw new HttpError(
      409,
      "Stripe has not confirmed this payment",
      "payment_unconfirmed",
    );
  }

  await markCortinaCardPaid(
    {
      eventId: `confirm:${intent.id}`,
      sessionId: session.id,
      amountCents,
      paymentIntentId: intent.id,
      chargeId: typeof intent.latest_charge === "string"
        ? intent.latest_charge
        : intent.latest_charge?.id ?? null,
    },
    deps,
  );
  return jsonResponse({ status: "paid" });
}

export async function handleStatus(req: Request, deps: CortinaDeps): Promise<Response> {
  const body = await bodyFrom(req);
  const sessionId = typeof body.sessionId === "string" ? body.sessionId : "";
  const accessToken = typeof body.accessToken === "string" ? body.accessToken : "";
  if (!sessionId || !accessToken) {
    throw new HttpError(400, "Missing session credentials", "missing_session");
  }

  const { data, error } = await deps.admin.from("cortina_vend_sessions")
    .select("*")
    .eq("id", sessionId)
    .eq("client_access_token_hash", await sha256(accessToken))
    .maybeSingle();
  if (error || !data) {
    throw new HttpError(404, "Vend session not found", "session_not_found");
  }

  const timeoutSeconds = Number(Deno.env.get("CORTINA_VEND_TIMEOUT_SECONDS") ?? 45);
  const timeoutStates = ["paid", "starting", "awaiting_sale", "approved"];
  const startedAt = new Date(data.start_requested_at ?? data.created_at).getTime();
  if (timeoutStates.includes(data.status) && Date.now() - startedAt >= timeoutSeconds * 1000) {
    const { data: claimed, error: claimError } = await deps.admin
      .from("cortina_vend_sessions")
      .update({ status: "timed_out", failure_message: "Nayax did not confirm the vend in time" })
      .eq("id", sessionId)
      .in("status", timeoutStates)
      .select("*")
      .maybeSingle();
    if (claimError) throw new Error(claimError.message);
    if (claimed) {
      try {
        await compensateVend(claimed as VendSession, deps, "Nayax vend timed out");
      } catch (compensationError) {
        console.error("Timed-out Cortina vend requires support", sessionId, compensationError);
      }
    }
  }

  const { data: current, error: currentError } = await deps.admin
    .from("cortina_vend_sessions")
    .select("id, machine_id, amount_cents, dryer_minutes, status, failure_code, failure_message, nayax_rrn, created_at, completed_at")
    .eq("id", sessionId)
    .single();
  if (currentError) throw new Error(currentError.message);
  return jsonResponse(current);
}

export async function handleCortinaVend(req: Request, deps: CortinaDeps): Promise<Response> {
  if (req.method !== "POST") {
    throw new HttpError(405, "Method not allowed", "method_not_allowed");
  }
  switch (functionRoute(req.url)) {
    case "quote":
      return handleQuote(req, deps);
    case "card":
      return handleCard(req, deps);
    case "confirm":
      return handleCardConfirm(req, deps);
    case "wallet":
      return handleWallet(req, deps);
    case "status":
      return handleStatus(req, deps);
    default:
      throw new HttpError(404, "Unknown Cortina route", "route_not_found");
  }
}

export type StripeClient = Stripe;
