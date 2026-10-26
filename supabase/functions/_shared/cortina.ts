import Stripe from "npm:stripe@14.25.0";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import { selectNamedSupabaseKey } from "./supabase_keys.ts";

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
  funding_source?: "payment" | "machine_issue";
  complaint_refund_id?: number | null;
  id: string;
  machine_id: number;
  user_id: string | null;
  amount_cents: number;
  dryer_minutes: number | null;
  pulse_line_number: number | null;
  product_code?: number | null;
  currency: string;
  payment_method: "card" | "wallet";
  channel: "app" | "web";
  status: VendStatus;
  transaction_id: string;
  stripe_payment_intent_id: string | null;
  stripe_checkout_session_id: string | null;
  checkout_return_version?: 1 | 2;
  stripe_refund_id: string | null;
  wallet_redemption_id: number | null;
  nayax_environment: "sandbox" | "production" | null;
  nayax_terminal_id: string | null;
  nayax_uniqr: string | null;
  stripe_livemode: boolean | null;
  nayax_transaction_id?: string | null;
}

export interface CortinaDeps {
  beforeSponsoredStart?: () => Promise<void>;
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

export function hasFrozenVendBinding(session: VendSession): boolean {
  const code = session.product_code;
  const line = session.pulse_line_number;
  const validSelector = code != null
    ? Number.isInteger(code) && code >= 0 && code <= 32767 && line == null
    : typeof line === "number" && Number.isInteger(line) && line >= 1 && line <= 6;
  return ["sandbox", "production"].includes(session.nayax_environment ?? "") &&
    Boolean(textValue(session.nayax_terminal_id) || textValue(session.nayax_uniqr)) &&
    session.currency === "USD" && validSelector &&
    (session.payment_method !== "card" ||
      session.stripe_livemode === (session.nayax_environment === "production"));
}

export function centsFromNayaxAmount(value: unknown): number | null {
  const amount = numberValue(value);
  return amount === null ? null : Math.round(amount * 100);
}

export function nayaxPriceFromCents(amountCents: number): number {
  return amountCents / 100;
}

export function resolveProductSelector(
  config: { product_codes?: unknown; pulse_line_number?: unknown },
  amountCents: number,
  dryerPulseLine: number | null,
): { product_code: number | null; pulse_line_number: number | null } {
  if (config.product_codes != null) {
    const codes = config.product_codes;
    const code = typeof codes === "object" && !Array.isArray(codes)
      ? (codes as Record<string, unknown>)[String(amountCents)]
      : undefined;
    if (typeof code !== "number" || !Number.isInteger(code) || code < 0 || code > 32767) {
      throw new HttpError(409, "Machine product pricing needs review", "product_mapping_missing");
    }
    return { product_code: code, pulse_line_number: null };
  }
  const line = dryerPulseLine ?? config.pulse_line_number;
  if (typeof line !== "number" || !Number.isInteger(line) || line < 1 || line > 6) {
    throw new HttpError(409, "Machine pulse line needs review", "pulse_mapping_missing");
  }
  return { product_code: null, pulse_line_number: line };
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
    .select("id, Name, Machine_type, Status, Location_ID, washer_size_rate_id, is_out_of_service")
    .eq("id", config.machine_id)
    .maybeSingle();
  if (machineError || !machine) {
    throw new HttpError(404, "Machine is not available", "machine_not_found");
  }

  if (machine.is_out_of_service) {
    throw new HttpError(409, "This machine is out of service. Choose another machine.", "machine_unavailable");
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

  // Validate every offered price before a customer can pay.
  if (machineType === "dryer") {
    for (const option of DRYER_OPTIONS) {
      resolveProductSelector(config, option.amountCents, option.pulseLineNumber);
    }
  } else {
    resolveProductSelector(config, amountCents, null);
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
  const { data: config, error: configError } = await admin
    .from("cortina_machine_config").select("*")
    .eq("machine_id", quote.machineId).single();
  if (configError || !config?.is_enabled || config.review_required) {
    throw new HttpError(409, "Machine payments are not enabled", "machine_disabled");
  }
  const selector = resolveProductSelector(config, input.amountCents, input.pulseLineNumber);
  const { data, error } = await admin.from("cortina_vend_sessions").insert({
    client_request_id: input.clientRequestId,
    client_access_token_hash: await sha256(accessToken),
    machine_id: quote.machineId,
    user_id: input.userId,
    washer_size_rate_id: quote.washerSizeRateId,
    amount_cents: input.amountCents,
    dryer_minutes: input.dryerMinutes,
    ...selector,
    payment_method: input.paymentMethod,
    channel: input.channel,
    ...(input.paymentMethod === "card" && input.channel === "web"
      ? { checkout_return_version: 2 } : {}),
    transaction_id: randomTransactionId(),
  }).select("*").single();

  if (!error && data) {
    return { session: data as VendSession, accessToken, wasCreated: true };
  }
  if (error?.code === "55000") {
    throw new HttpError(409, "This machine is out of service. Choose another machine.", "machine_unavailable");
  }
  if (error?.code === "40001" || error?.code === "55P03") {
    throw new HttpError(409, "Machine payment settings changed; request a new quote", "price_changed");
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
    existing.dryer_minutes !== input.dryerMinutes ||
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
  definitiveStartFailure = false,
): Promise<void> {
  if (session.status === "refunded") return;
  if (session.funding_source === "machine_issue") {
    // No money was charged/debited for this session. Keep its one-benefit
    // reservation even on a definitive failure; an Owner must reconcile it.
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "support_required", failure_code: "machine_issue_replacement_review",
      failure_message: reason,
    }).eq("id", session.id).neq("status", "started");
    if (error) throw new Error(error.message);
    return;
  }
  // A client wait limit or historical failure label is not proof of a failed
  // vend. Only this Start attempt's evidence or a validated Void permits creation.
  // An already-bound card refund remains a read-only reconciliation operation.
  if (!(session.payment_method === "card" && session.stripe_refund_id) &&
      session.status !== "voided" && !definitiveStartFailure) {
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "support_required", failure_code: "vend_outcome_unknown",
      failure_message: "Vend outcome is unconfirmed; support review required",
    }).eq("id", session.id).eq("status", session.status);
    if (error) throw new Error(error.message);
    return;
  }
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
    if (!hasFrozenVendBinding(session)) {
      throw new Error("Historical payment routing needs reconciliation");
    }
    const refund = session.stripe_refund_id
      ? await deps.stripe.refunds.retrieve(session.stripe_refund_id)
      : await deps.stripe.refunds.create(
      {
        payment_intent: session.stripe_payment_intent_id,
        reason: "requested_by_customer",
        metadata: { cortina_session_id: session.id, reason },
      },
      { idempotencyKey: `cortina-refund-${session.id}` },
    );
    const paymentIntent = typeof refund.payment_intent === "string"
      ? refund.payment_intent : refund.payment_intent?.id;
    const matches = Boolean(refund.id) &&
      (!session.stripe_refund_id || refund.id === session.stripe_refund_id) &&
      paymentIntent === session.stripe_payment_intent_id &&
      refund.amount === session.amount_cents &&
      refund.currency?.toUpperCase() === session.currency.toUpperCase();
    const succeeded = matches && refund.status === "succeeded";
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: succeeded ? "refunded" : "support_required",
      stripe_refund_id: session.stripe_refund_id ?? refund.id ?? null,
      completed_at: succeeded ? new Date().toISOString() : null,
      failure_message: succeeded ? reason : `${reason}: Refund needs reconciliation`,
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

  if (session.funding_source === "machine_issue") {
    const { data, error } = await deps.admin.rpc("authorize_machine_issue_start", { target_session_id: session.id, for_start: true });
    if (error || data !== true) {
      await failStartingVend(session.id, deps, "Machine issue reservation requires review", "machine_issue_start_blocked");
      return;
    }
  }

  if (!hasFrozenVendBinding(session)) {
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "support_required",
      failure_message: "Historical payment routing needs reconciliation",
    }).eq("id", session.id).eq("status", "starting");
    if (error) throw new Error(error.message);
    return;
  }

  const { data: priorStart, error: priorStartError } = await deps.admin
    .from("cortina_vend_events").select("id")
    .eq("event_key", `start-request:${session.id}`).maybeSingle();
  if (priorStartError || priorStart) {
    await failStartingVend(session.id, deps, "An earlier Start outcome cannot be excluded", "start_outcome_unknown");
    return;
  }

  // A checkout opened before an outage can still settle. Compensate through the
  // existing idempotent refund/reversal path before sending a machine start.
  const { data: machine, error: machineError } = await deps.admin
    .from("Machines")
    .select("id, is_out_of_service")
    .eq("id", session.machine_id)
    .maybeSingle();
  if (machineError || !machine || machine.is_out_of_service) {
    await failStartingVend(session.id, deps, "Machine is out of service or unavailable", "start_not_sent", true);
    return;
  }

  const { data: config, error: configError } = await deps.admin
    .from("cortina_machine_config")
    .select("*")
    .eq("machine_id", session.machine_id)
    .single();
  if (configError || !config?.is_enabled || config.review_required) {
    await failStartingVend(session.id, deps, "Machine configuration is unavailable", "start_not_sent", true);
    return;
  }

  let mayHaveStarted = false;
  try {
    const settings = nayaxSettings(session.nayax_environment!);
    const selector = session.product_code != null
      ? { Code: session.product_code }
      : { PulseLineNumber: session.pulse_line_number };
    const product: Record<string, unknown> = {
      ...selector,
      Price: nayaxPriceFromCents(session.amount_cents),
    };
    const payload: Record<string, unknown> = {
      AppUserId: session.user_id ?? `guest-${session.id.slice(0, 30)}`,
      TransactionId: session.transaction_id,
      SecretToken: settings.secretToken,
      Products: [product],
    };
    if (textValue(session.nayax_terminal_id)) {
      payload.TerminalId = session.nayax_terminal_id;
    } else {
      payload.UniQR = session.nayax_uniqr;
    }

    const { SecretToken: _secret, ...requestSummary } = payload;
    const endpoint = new URL(settings.startUrl);
    const freshRequest = await recordVendEvent(deps.admin, {
      sessionId: session.id,
      source: "clean_stream",
      eventType: "nayax_start_request",
      eventKey: `start-request:${session.id}`,
      payload: { endpoint: `${endpoint.origin}${endpoint.pathname}`, environment: session.nayax_environment, request: requestSummary },
    });
    if (!freshRequest) {
      mayHaveStarted = true;
      await failStartingVend(session.id, deps, "An earlier Start request needs reconciliation", "start_outcome_unknown");
      return;
    }
    if (session.funding_source === "machine_issue") {
      if (!deps.beforeSponsoredStart) throw new Error("Captured Owner authorization is required");
      await deps.beforeSponsoredStart();
      const { data, error } = await deps.admin.rpc("authorize_machine_issue_start", { target_session_id: session.id, for_start: true });
      if (error || data !== true) throw new Error("Machine issue reservation requires review");
    }
    mayHaveStarted = true;
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
      // Documented input/authorization rejections, not timeout (992), system
      // failure (6), general exception (999), or unknown/missing provider codes.
      const code = responseBody?.Status?.Code;
      const definitive = response.ok && verdict === "declined" &&
        Number.isInteger(code) && [1, 5, 7, 8, 997, 998].includes(code);
      const message = responseBody?.Status?.StatusMessage ??
        (definitive ? "Nayax rejected Start" : "Nayax Start outcome is unconfirmed");
      await failStartingVend(
        session.id, deps, message,
        definitive ? String(code) : "start_outcome_unknown", definitive,
      );
      return;
    }

    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "awaiting_sale",
    }).eq("id", session.id).eq("status", "starting");
    if (error) throw new Error(error.message);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await failStartingVend(session.id, deps,
      mayHaveStarted ? "Nayax Start outcome is unconfirmed; support review required" : message,
      mayHaveStarted ? "start_outcome_unknown" : "start_not_sent", !mayHaveStarted);
  }
}

async function failStartingVend(
  sessionId: string,
  deps: CortinaDeps,
  message: string,
  code?: string,
  definitive = false,
): Promise<void> {
  // A callback can finish the vend before the Start HTTP response arrives.
  // Its atomic audit can also bind the provider ID before its status CAS.
  const { data: failed, error } = await deps.admin.from("cortina_vend_sessions")
    .update({ status: definitive ? "failed" : "support_required", failure_code: code ?? null, failure_message: message })
    .eq("id", sessionId)
    .eq("status", "starting")
    .is("nayax_transaction_id", null)
    .select("*")
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (failed && definitive) await compensateVend(failed as VendSession, deps, message, true);
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
  if (!hasFrozenVendBinding(session)) {
    const { error: supportError } = await deps.admin.from("cortina_vend_sessions").update({
      status: "support_required",
      failure_message: "Historical payment routing needs reconciliation",
    }).eq("id", session.id).in("status", ["payment_pending", "paid", "failed"]);
    if (supportError) throw new Error(supportError.message);
    throw new HttpError(409, "Historical payment routing needs reconciliation", "support_required");
  }
  if (session.amount_cents !== input.amountCents || session.payment_method !== "card" ||
      typeof session.stripe_livemode !== "boolean" || !session.nayax_environment ||
      (session.stripe_payment_intent_id && session.stripe_payment_intent_id !== input.paymentIntentId) ||
      (input.checkoutSessionId !== undefined && input.checkoutSessionId !== null &&
        session.stripe_checkout_session_id !== input.checkoutSessionId) ||
      (session.channel === "web" && !session.stripe_checkout_session_id) ||
      (session.channel === "app" && session.stripe_checkout_session_id != null) ||
      (!session.stripe_payment_intent_id && !session.stripe_checkout_session_id)) {
    throw new HttpError(409, "Stripe payment does not match the vend session", "payment_mismatch");
  }

  const metadataMatches = (metadata: Stripe.Metadata | null) =>
    metadata?.purpose === "cortina_vend" && metadata.cortina_session_id === session.id &&
    metadata.machine_id === String(session.machine_id) &&
    metadata.amount_cents === String(session.amount_cents) &&
    (metadata.user_id ?? null) === session.user_id;
  const intent = await deps.stripe.paymentIntents.retrieve(input.paymentIntentId);
  if (intent.id !== input.paymentIntentId || intent.status !== "succeeded" ||
      intent.amount !== session.amount_cents || intent.amount_received !== session.amount_cents ||
      intent.currency?.toUpperCase() !== session.currency ||
      intent.livemode !== session.stripe_livemode || !metadataMatches(intent.metadata)) {
    throw new HttpError(409, "Stripe has not confirmed this exact payment", "payment_not_confirmed");
  }
  if (session.stripe_checkout_session_id) {
    const checkout = await deps.stripe.checkout.sessions.retrieve(session.stripe_checkout_session_id);
    const checkoutIntent = typeof checkout.payment_intent === "string"
      ? checkout.payment_intent : checkout.payment_intent?.id;
    if (checkout.id !== session.stripe_checkout_session_id || checkoutIntent !== intent.id ||
        checkout.mode !== "payment" || checkout.status !== "complete" ||
        checkout.payment_status !== "paid" || checkout.amount_total !== session.amount_cents ||
        checkout.currency?.toUpperCase() !== session.currency ||
        checkout.livemode !== session.stripe_livemode || !metadataMatches(checkout.metadata)) {
      throw new HttpError(409, "Stripe Checkout does not match the vend session", "payment_mismatch");
    }
  }
  const chargeId = typeof intent.latest_charge === "string"
    ? intent.latest_charge : intent.latest_charge?.id ?? null;
  if (!chargeId || (input.chargeId != null && input.chargeId !== chargeId)) {
    throw new HttpError(409, "Stripe charge does not match the vend session", "payment_mismatch");
  }
  const { error: recordError } = await deps.admin.rpc("record_cortina_card_payment", {
    p_session: session.id, p_event: input.eventId, p_intent: intent.id,
    p_checkout: session.stripe_checkout_session_id, p_charge: chargeId,
    p_amount: intent.amount_received, p_currency: intent.currency, p_livemode: intent.livemode,
  });
  if (recordError) throw new Error(recordError.message);
  await startCortinaVend(input.sessionId, deps);
}

const ADMIN_KEY_SELECTORS = {
  "cortina-vend": "CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME",
  "stripeWebhook": "CLEANSTREAM_STRIPE_WEBHOOK_SECRET_KEY_NAME",
  "nayax-production": "CLEANSTREAM_NAYAX_PRODUCTION_SECRET_KEY_NAME",
  "nayax-sandbox": "CLEANSTREAM_NAYAX_SANDBOX_SECRET_KEY_NAME",
  "voluntary-topup-refund": "CLEANSTREAM_TOPUP_REFUND_SECRET_KEY_NAME",
} as const;

export function createAdminClient(
  component: keyof typeof ADMIN_KEY_SELECTORS,
  env: (name: string) => string | undefined = (name) => Deno.env.get(name),
): SupabaseClient {
  const name = env(ADMIN_KEY_SELECTORS[component]);
  const key = name === undefined ? env("SUPABASE_SERVICE_ROLE_KEY")
    : selectNamedSupabaseKey(name, env("SUPABASE_SECRET_KEYS"), "secret");
  if (!key) throw new HttpError(503, "Database key configuration unavailable", "key_configuration_unavailable");
  return createClient(
    env("SUPABASE_URL")!,
    key,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      ...(name === undefined ? {} : { global: { fetch: (input: RequestInfo | URL, init?: RequestInit) => {
        const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
        // Remove only the SDK's secret-as-JWT default, never an explicit getUser bearer.
        if (headers.get("Authorization") === `Bearer ${key}`) headers.delete("Authorization");
        return fetch(input, { ...init, headers });
      } } }),
    },
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
