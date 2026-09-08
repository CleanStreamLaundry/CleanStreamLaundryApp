import Stripe from "npm:stripe@14.25.0";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": Deno.env.get("CLEAN_STREAM_WEB_ORIGIN") ??
    "https://cleanstreamlaundry.com",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, x-nayax-auth",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

export const DRYER_DEFAULT_CENTS = 150;
export const DRYER_OPTIONS = [
  { minutes: 10, amountCents: 50, pulseLineNumber: 1 },
  { minutes: 20, amountCents: 100, pulseLineNumber: 2 },
  { minutes: 30, amountCents: 150, pulseLineNumber: 3 },
  { minutes: 40, amountCents: 200, pulseLineNumber: 4 },
  { minutes: 60, amountCents: 300, pulseLineNumber: 5 },
  { minutes: 90, amountCents: 450, pulseLineNumber: 6 },
] as const;

export type MachineType = "washer" | "dryer";
export type VendStatus =
  | "payment_pending"
  | "paid"
  | "starting"
  | "awaiting_sale"
  | "approved"
  | "started"
  | "voided"
  | "refunded"
  | "failed"
  | "timed_out"
  | "support_required";

export interface CortinaQuote {
  machineId: number;
  publicMachineToken: string;
  machineName: string;
  machineType: MachineType;
  locationId: number;
  washerSizeRateId: number | null;
  washerSizeLabel: string | null;
  amountCents: number;
  dryer: {
    defaultCents: number;
    options: Array<{ minutes: number; amountCents: number }>;
  } | null;
}

export interface VendSession {
  id: string;
  machine_id: number;
  user_id: string | null;
  amount_cents: number;
  dryer_minutes: number | null;
  pulse_line_number: number | null;
  currency: string;
  payment_method: "card" | "wallet";
  channel: "app" | "web";
  status: VendStatus;
  transaction_id: string;
  stripe_payment_intent_id: string | null;
  stripe_checkout_session_id: string | null;
  stripe_refund_id: string | null;
  wallet_redemption_id: number | null;
}

export interface CortinaDeps {
  admin: SupabaseClient;
  stripe: Stripe;
  fetcher?: typeof fetch;
}

export class HttpError extends Error {
  constructor(public status: number, message: string, public code?: string) {
    super(message);
  }
}

function textValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function centsFromNayaxAmount(value: unknown): number | null {
  const amount = numberValue(value);
  return amount === null ? null : Math.round(amount * 100);
}

export function nayaxPriceFromCents(amountCents: number): number {
  return amountCents / 100;
}

export function validateVendAmount(
  quote: CortinaQuote,
  requestedAmount: unknown,
): {
  amountCents: number;
  dryerMinutes: number | null;
  pulseLineNumber: number | null;
} {
  const parsed = numberValue(requestedAmount);
  if (parsed === null || !Number.isInteger(parsed)) {
    throw new HttpError(400, "Amount must be provided in cents", "invalid_amount");
  }

  if (quote.machineType === "washer") {
    if (parsed !== quote.amountCents) {
      throw new HttpError(409, "Washer price has changed", "price_changed");
    }
    return {
      amountCents: parsed,
      dryerMinutes: null,
      pulseLineNumber: null,
    };
  }

  const option = DRYER_OPTIONS.find((candidate) =>
    candidate.amountCents === parsed
  );
  if (!option) {
    throw new HttpError(
      400,
      "Select one of the available dryer times",
      "invalid_dryer_amount",
    );
  }

  return {
    amountCents: option.amountCents,
    dryerMinutes: option.minutes,
    pulseLineNumber: option.pulseLineNumber,
  };
}

export async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function randomTransactionId(): string {
  return crypto.randomUUID().replaceAll("-", "");
}

export function functionRoute(url: string): string {
  const parts = new URL(url).pathname.split("/").filter(Boolean);
  return parts.at(-1)?.toLowerCase() ?? "";
}

export async function getOptionalUserId(
  req: Request,
  admin: SupabaseClient,
): Promise<string | null> {
  const auth = req.headers.get("authorization");
  if (!auth?.toLowerCase().startsWith("bearer ")) return null;
  const token = auth.slice(7).trim();
  if (!token || token.startsWith("sb_publishable_")) return null;

  const { data, error } = await admin.auth.getUser(token);
  return error ? null : data.user?.id ?? null;
}

export async function resolveQuote(
  admin: SupabaseClient,
  selector: { machineToken?: unknown; terminalId?: unknown; uniQr?: unknown },
): Promise<CortinaQuote> {
  const machineToken = textValue(selector.machineToken);
  const terminalId = textValue(selector.terminalId);
  const uniQr = textValue(selector.uniQr);
  if (!machineToken && !terminalId && !uniQr) {
    throw new HttpError(400, "Missing machine token", "missing_machine");
  }
  if (terminalId && !/^\d{16}$/.test(terminalId)) {
    throw new HttpError(400, "Terminal ID is invalid", "invalid_terminal");
  }

  let configQuery = admin.from("cortina_machine_config").select("*");
  configQuery = machineToken
    ? configQuery.eq("public_machine_token", machineToken)
    : terminalId
    ? configQuery.eq("nayax_terminal_id", terminalId)
    : configQuery.eq("nayax_uniqr", uniQr!);
  const { data: config, error: configError } = await configQuery.maybeSingle();

  if (configError || !config) {
    throw new HttpError(404, "Machine QR is not recognized", "machine_not_found");
  }
  if (!config.is_enabled || config.review_required) {
    throw new HttpError(409, "Machine payments are not enabled", "machine_disabled");
  }

  const { data: machine, error: machineError } = await admin
    .from("Machines")
    .select("id, Name, Machine_type, Status, Location_ID, washer_size_rate_id")
    .eq("id", config.machine_id)
    .maybeSingle();
  if (machineError || !machine) {
    throw new HttpError(404, "Machine is not available", "machine_not_found");
  }

  const status = String(machine.Status ?? "").toLowerCase();
  if (status !== "idle" && status !== "available") {
    throw new HttpError(409, "Machine is currently unavailable", "machine_unavailable");
  }

  const machineType = String(machine.Machine_type ?? "").toLowerCase();
  if (machineType !== "washer" && machineType !== "dryer") {
    throw new HttpError(409, "Machine type is not supported", "unsupported_machine");
  }

  let amountCents = DRYER_DEFAULT_CENTS;
  let washerSizeLabel: string | null = null;
  let washerSizeRateId: number | null = null;
  if (machineType === "washer") {
    if (!machine.washer_size_rate_id) {
      throw new HttpError(409, "Washer pricing needs review", "washer_rate_missing");
    }
    const { data: rate, error: rateError } = await admin
      .from("washer_size_rates")
      .select("id, size_label, price_cents, is_active, review_required")
      .eq("id", machine.washer_size_rate_id)
      .maybeSingle();
    if (rateError || !rate || !rate.is_active || rate.review_required) {
      throw new HttpError(409, "Washer pricing needs review", "washer_rate_unavailable");
    }
    amountCents = rate.price_cents;
    washerSizeLabel = rate.size_label;
    washerSizeRateId = rate.id;
  }

  return {
    machineId: machine.id,
    publicMachineToken: String(config.public_machine_token),
    machineName: machine.Name ?? `Machine ${machine.id}`,
    machineType,
    locationId: machine.Location_ID,
    washerSizeRateId,
    washerSizeLabel,
    amountCents,
    dryer: machineType === "dryer"
      ? {
        defaultCents: DRYER_DEFAULT_CENTS,
        options: DRYER_OPTIONS.map(({ minutes, amountCents }) => ({
          minutes,
          amountCents,
        })),
      }
      : null,
  };
}

export async function createVendSession(
  admin: SupabaseClient,
  quote: CortinaQuote,
  input: {
    userId: string | null;
    amountCents: number;
    dryerMinutes: number | null;
    pulseLineNumber: number | null;
    paymentMethod: "card" | "wallet";
    channel: "app" | "web";
    clientRequestId: string;
  },
): Promise<{ session: VendSession; accessToken: string; wasCreated: boolean }> {
  const accessToken = input.clientRequestId;
  const { data, error } = await admin.from("cortina_vend_sessions").insert({
    client_request_id: input.clientRequestId,
    client_access_token_hash: await sha256(accessToken),
    machine_id: quote.machineId,
    user_id: input.userId,
    washer_size_rate_id: quote.washerSizeRateId,
    amount_cents: input.amountCents,
    dryer_minutes: input.dryerMinutes,
    pulse_line_number: input.pulseLineNumber,
    payment_method: input.paymentMethod,
    channel: input.channel,
    transaction_id: randomTransactionId(),
  }).select("*").single();

  if (!error && data) {
    return { session: data as VendSession, accessToken, wasCreated: true };
  }
  if (error?.code !== "23505") {
    throw new HttpError(500, error?.message ?? "Unable to create vend session");
  }

  const { data: existing, error: existingError } = await admin
    .from("cortina_vend_sessions")
    .select("*")
    .eq("client_request_id", input.clientRequestId)
    .maybeSingle();
  if (existingError || !existing) {
    throw new HttpError(500, existingError?.message ?? "Unable to resume vend session");
  }
  if (
    existing.machine_id !== quote.machineId ||
    existing.user_id !== input.userId ||
    existing.amount_cents !== input.amountCents ||
    existing.pulse_line_number !== input.pulseLineNumber ||
    existing.payment_method !== input.paymentMethod ||
    existing.channel !== input.channel
  ) {
    throw new HttpError(409, "Payment request was already used", "idempotency_conflict");
  }
  return {
    session: existing as VendSession,
    accessToken,
    wasCreated: false,
  };
}

export async function recordVendEvent(
  admin: SupabaseClient,
  input: {
    sessionId: string;
    source: "clean_stream" | "stripe" | "nayax";
    eventType: string;
    eventKey: string;
    payload?: unknown;
  },
): Promise<boolean> {
  const { error } = await admin.from("cortina_vend_events").insert({
    session_id: input.sessionId,
    source: input.source,
    event_type: input.eventType,
    event_key: input.eventKey,
    payload: input.payload ?? {},
  });
  if (!error) return true;
  if (error.code === "23505") return false;
  throw new Error(error.message);
}

function nayaxSettings(environment: string) {
  const production = environment === "production";
  const startUrl = Deno.env.get(
    production ? "NAYAX_PRODUCTION_START_URL" : "NAYAX_SANDBOX_START_URL",
  );
  const secretToken = Deno.env.get(
    production ? "NAYAX_PRODUCTION_SECRET_TOKEN" : "NAYAX_SANDBOX_SECRET_TOKEN",
  );
  if (!startUrl || !secretToken) {
    throw new Error(`Nayax ${environment} credentials are not configured`);
  }
  return { startUrl, secretToken };
}

export async function compensateVend(
  session: VendSession,
  deps: CortinaDeps,
  reason: string,
): Promise<void> {
  if (session.status === "refunded") return;
  try {
    if (session.payment_method === "wallet") {
      const { error } = await deps.admin.rpc("reverse_cortina_wallet_redemption", {
        target_session_id: session.id,
      });
      if (error) throw new Error(error.message);
      return;
    }

    if (!session.stripe_payment_intent_id) {
      throw new Error("Paid card session is missing its PaymentIntent");
    }
    const refund = await deps.stripe.refunds.create(
      {
        payment_intent: session.stripe_payment_intent_id,
        reason: "requested_by_customer",
        metadata: { cortina_session_id: session.id, reason },
      },
      { idempotencyKey: `cortina-refund-${session.id}` },
    );
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "refunded",
      stripe_refund_id: refund.id,
      completed_at: new Date().toISOString(),
      failure_message: reason,
    }).eq("id", session.id);
    if (error) throw new Error(error.message);
  } catch (error) {
    await deps.admin.from("cortina_vend_sessions").update({
      status: "support_required",
      failure_message: `${reason}: ${error instanceof Error ? error.message : error}`,
    }).eq("id", session.id);
    throw error;
  }
}

export async function startCortinaVend(
  sessionId: string,
  deps: CortinaDeps,
): Promise<void> {
  const { data: claimed, error: claimError } = await deps.admin
    .from("cortina_vend_sessions")
    .update({ status: "starting", start_requested_at: new Date().toISOString() })
    .eq("id", sessionId)
    .eq("status", "paid")
    .select("*")
    .maybeSingle();

  if (claimError) throw new Error(claimError.message);
  if (!claimed) return;
  const session = claimed as VendSession;

  const { data: config, error: configError } = await deps.admin
    .from("cortina_machine_config")
    .select("*")
    .eq("machine_id", session.machine_id)
    .single();
  if (configError || !config?.is_enabled) {
    await compensateVend(session, deps, "Machine configuration is unavailable");
    return;
  }

  try {
    const settings = nayaxSettings(config.environment);
    const product: Record<string, unknown> = {
      PulseLineNumber: session.pulse_line_number ?? config.pulse_line_number,
      Price: nayaxPriceFromCents(session.amount_cents),
    };
    const payload: Record<string, unknown> = {
      AppUserID: session.user_id ?? `guest-${session.id.slice(0, 30)}`,
      TransactionId: session.transaction_id,
      SecretToken: settings.secretToken,
      Products: [product],
    };
    if (textValue(config.nayax_terminal_id)) {
      payload.TerminalId = config.nayax_terminal_id;
    } else {
      payload.UniQR = config.nayax_uniqr;
    }

    const response = await (deps.fetcher ?? fetch)(settings.startUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(12_000),
    });
    const responseBody = await response.json().catch(() => ({}));
    const verdict = String(responseBody?.Status?.Verdict ?? "").toLowerCase();
    await recordVendEvent(deps.admin, {
      sessionId: session.id,
      source: "clean_stream",
      eventType: "nayax_start_response",
      eventKey: `start:${session.id}`,
      payload: responseBody,
    });

    if (!response.ok || verdict !== "approved") {
      const message = responseBody?.Status?.StatusMessage ??
        `Nayax Start declined with HTTP ${response.status}`;
      await deps.admin.from("cortina_vend_sessions").update({
        status: "failed",
        failure_code: String(responseBody?.Status?.Code ?? response.status),
        failure_message: message,
      }).eq("id", session.id);
      await compensateVend({ ...session, status: "failed" }, deps, message);
      return;
    }

    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "awaiting_sale",
    }).eq("id", session.id).eq("status", "starting");
    if (error) throw new Error(error.message);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await deps.admin.from("cortina_vend_sessions").update({
      status: "failed",
      failure_message: message,
    }).eq("id", session.id);
    await compensateVend({ ...session, status: "failed" }, deps, message);
  }
}

export async function markCortinaCardPaid(
  input: {
    eventId: string;
    sessionId: string;
    amountCents: number;
    paymentIntentId: string;
    checkoutSessionId?: string | null;
    chargeId?: string | null;
  },
  deps: CortinaDeps,
): Promise<void> {
  const { data: session, error } = await deps.admin
    .from("cortina_vend_sessions")
    .select("*")
    .eq("id", input.sessionId)
    .single();
  if (error || !session) throw new Error(error?.message ?? "Vend session not found");
  if (session.amount_cents !== input.amountCents || session.payment_method !== "card") {
    throw new Error("Stripe payment does not match the vend session");
  }

  await recordVendEvent(deps.admin, {
    sessionId: input.sessionId,
    source: "stripe",
    eventType: "payment_succeeded",
    eventKey: `stripe:${input.eventId}`,
    payload: { payment_intent_id: input.paymentIntentId },
  });
  const { error: updateError } = await deps.admin.from("cortina_vend_sessions")
    .update({
      status: "paid",
      stripe_payment_intent_id: input.paymentIntentId,
      stripe_checkout_session_id: input.checkoutSessionId ?? null,
      stripe_charge_id: input.chargeId ?? null,
    })
    .eq("id", input.sessionId)
    .eq("status", "payment_pending");
  if (updateError) throw new Error(updateError.message);
  await startCortinaVend(input.sessionId, deps);
}

export function createAdminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export function createStripeClient(): Stripe {
  return new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
    apiVersion: "2023-10-16",
    httpClient: Stripe.createFetchHttpClient(),
  });
}

export function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: CORS_HEADERS });
}

export function errorResponse(error: unknown): Response {
  const status = error instanceof HttpError ? error.status : 500;
  const code = error instanceof HttpError ? error.code : "internal_error";
  const message = error instanceof Error ? error.message : "Unexpected error";
  return jsonResponse({ error: message, code }, status);
}
