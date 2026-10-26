import Stripe from "npm:stripe@14.25.0";
import { cortinaRequestCapacity } from "./request_limits.ts";
import { resolveCardCaller } from "./card_admission.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import { handlePendingLookup, requestsPendingLookup } from "./pending_lookup.ts";
import { cortinaCheckoutReturnVersion, cortinaSessionReturnUrls } from "./return_urls.ts";
import { readCortinaBody as bodyFrom, cortinaSessionCredentials } from "./public_controls.ts";
import { callerPublishableKey } from "../_shared/supabase_keys.ts";
import { requireNewPayments } from "../_shared/new_payment_control.ts";
import {
  CortinaDeps,
  compensateVend,
  createVendSession,
  functionRoute,
  getOptionalUserId,
  hasFrozenVendBinding,
  HttpError,
  jsonResponse,
  markCortinaCardPaid,
  resolveQuote,
  sha256,
  startCortinaVend,
  validateVendAmount,
  VendSession,
} from "../_shared/cortina.ts";

async function requireVendCreation(deps: CortinaDeps): Promise<void> {
  try {
    await requireNewPayments(deps.admin);
  } catch {
    throw new HttpError(503, "new_payments_unavailable", "new_payments_unavailable");
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
  const limited = await cortinaRequestCapacity(deps.admin, "quote");
  if (limited) return limited;
  return jsonResponse(await resolveQuote(deps.admin, {
    machineToken: body.machineToken,
    terminalId: body.terminalId,
    uniQr: body.uniQr,
  }));
}

export async function handleCard(req: Request, deps: CortinaDeps): Promise<Response> {
  const authorization = req.headers.get("Authorization");
  const body = await bodyFrom(req);
  const channel = body.channel === "app" ? "app" : body.channel === "web" ? "web" : null;
  if (!channel) throw new HttpError(400, "Channel must be app or web", "invalid_channel");

  const quote = await resolveQuote(deps.admin, {
    machineToken: body.machineToken,
    terminalId: body.terminalId,
    uniQr: body.uniQr,
  });
  const amount = validateVendAmount(quote, body.amountCents);
  const caller = await resolveCardCaller(authorization, deps.admin,
    (name) => Deno.env.get(name), deps.fetcher ?? fetch);
  const userId = caller.userId;
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
    created.session.machine_id,
    created.session.amount_cents,
    created.session.user_id,
  );

  if (!hasFrozenVendBinding(created.session)) {
    throw new HttpError(409, "Payment routing needs reconciliation", "support_required");
  }
  if (created.session.status !== "payment_pending") {
    return jsonResponse({ sessionId: created.session.id, accessToken: created.accessToken,
      status: created.session.status });
  }

  // Outside provider-error compensation: refusal must not fail an existing draft.
  await requireVendCreation(deps);
  const returnVersion = channel === "web"
    ? cortinaCheckoutReturnVersion(created.session.checkout_return_version)
    : null;

  await caller.requireAdmission();
  const limited = await cortinaRequestCapacity(deps.admin, "card");
  if (limited) return limited;
  // Capacity can wait after admission; refuse before dispatching a new charge.
  await caller.requireAdmission();
  await requireVendCreation(deps);
  try {
    if (channel === "app") {
      const intent = await deps.stripe.paymentIntents.create({
        amount: amount.amountCents,
        currency: "usd",
        payment_method_types: ["card"],
        metadata,
      }, { idempotencyKey: `cortina-card-${created.session.id}` });
      if (intent.livemode !== created.session.stripe_livemode) {
        throw new Error("Stripe environment does not match the machine");
      }
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
    const returnUrls = cortinaSessionReturnUrls(returnVersion, payUrl, {
      sessionId: created.session.id, accessToken: created.accessToken,
    }, body);
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
      ...returnUrls,
    }, { idempotencyKey: `cortina-checkout-${created.session.id}` });
    if (checkout.livemode !== created.session.stripe_livemode) {
      throw new Error("Stripe environment does not match the machine");
    }
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
    }).eq("id", created.session.id).eq("status", "payment_pending");
    throw error;
  }
}

export async function handleWallet(req: Request, deps: CortinaDeps): Promise<Response> {
  const body = await bodyFrom(req);
  let publicKey: string;
  try {
    publicKey = callerPublishableKey(
      (name) => Deno.env.get(name),
      "CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME",
    );
  } catch {
    throw new HttpError(503, "Public key configuration unavailable", "key_configuration_unavailable");
  }
  const authorization = req.headers.get("authorization")!;
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

  if (!hasFrozenVendBinding(created.session)) {
    throw new HttpError(409, "Payment routing needs reconciliation", "support_required");
  }
  if (!created.wasCreated && created.session.status !== "payment_pending") {
    await startCortinaVend(created.session.id, deps);
    return jsonResponse({
      sessionId: created.session.id,
      accessToken: created.accessToken,
    });
  }

  await requireVendCreation(deps);
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    publicKey,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: redemption, error: redemptionError } = await userClient.rpc(
    "redeem_wallet_for_cortina",
    { target_session_id: created.session.id },
  );
  if (redemptionError?.code === "PT503" && redemptionError.message === "new_payments_unavailable") {
    throw new HttpError(503, "new_payments_unavailable", "new_payments_unavailable");
  }
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
  const { sessionId, accessToken } = cortinaSessionCredentials(body);

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

  await markCortinaCardPaid(
    {
      eventId: `confirm:${session.stripe_payment_intent_id}`,
      sessionId: session.id,
      amountCents: session.amount_cents,
      paymentIntentId: session.stripe_payment_intent_id,
    },
    deps,
  );
  return jsonResponse({ status: "paid" });
}

export async function handleStatus(req: Request, deps: CortinaDeps): Promise<Response> {
  const recoveryAuthorization = req.headers.get("authorization");
  const body = await bodyFrom(req);
  const limited = await cortinaRequestCapacity(deps.admin, "status");
  if (limited) return limited;
  if (requestsPendingLookup(body)) {
    return handlePendingLookup(recoveryAuthorization, body, deps);
  }
  const { sessionId, accessToken } = cortinaSessionCredentials(body);

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
