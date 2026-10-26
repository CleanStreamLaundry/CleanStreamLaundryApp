import {
  centsFromNayaxAmount,
  compensateVend,
  CortinaDeps,
  functionRoute,
  hasFrozenVendBinding,
  sha256,
  VendSession,
} from "./cortina.ts";

type JsonObject = Record<string, any>;

function approved(
  session?: VendSession,
  amountCents?: number,
  rrn?: string,
): Response {
  const body: JsonObject = {
    Status: { Verdict: "Approved", StatusMessage: "Approved" },
  };
  if (session) {
    const timestamp = nayaxTimestamp();
    body.PaymentInfo = {
      SrvTranId: session.transaction_id,
      AuthCode: session.id.replaceAll("-", "").slice(0, 12),
      AuthAmount: (amountCents ?? session.amount_cents) / 100,
      SettAmount: (amountCents ?? session.amount_cents) / 100,
      RRN: rrn ?? "",
      Token: "",
      AuthDateTime: timestamp,
      SettDateTime: timestamp,
      TraceNumber: "",
      AuthSource: "CSAPP",
      AdditionalData: JSON.stringify({ cortinaSessionId: session.id }),
      IsGatewayTimeout: false,
    };
  }
  return Response.json(body);
}

function declined(code: number, message: string): Response {
  // These are fixed reasons from this handler, never request bodies or headers.
  console.warn("Cortina callback declined", { code, reason: message });
  return Response.json({
    Status: { Verdict: "Declined", Code: code, StatusMessage: message },
  });
}

function nayaxTimestamp(date = new Date()): string {
  const part = (value: number) => String(value).padStart(2, "0");
  return `${part(date.getUTCDate())}${part(date.getUTCMonth() + 1)}` +
    `${String(date.getUTCFullYear()).slice(-2)}${part(date.getUTCHours())}` +
    `${part(date.getUTCMinutes())}${part(date.getUTCSeconds())}`;
}

function transactionId(body: JsonObject): string | null {
  const value = body?.BasicInfo?.TransactionId;
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function nayaxTransactionId(body: JsonObject): string | null {
  const value = body?.BasicInfo?.NayaxTransactionId ?? body?.NayaxTransactionId;
  if (typeof value === "number") return Number.isSafeInteger(value) && value > 0 ? String(value) : null;
  return typeof value === "string" && /^[1-9][0-9]*$/.test(value) ? value : null;
}

function rrn(body: JsonObject): string | null {
  const value = body?.BasicInfo?.NayaxRRN ?? body?.PaymentInfo?.RRN;
  return value === undefined || value === null ? null : String(value);
}

function callbackTerminalId(body: JsonObject): string | null {
  const value = body?.MachineInfo?.TerminalId;
  return value === undefined || value === null || String(value).trim() === ""
    ? null
    : String(value).trim();
}

function auditPayload(body: JsonObject): JsonObject {
  return {
    BasicInfo: {
      TransactionId: body?.BasicInfo?.TransactionId,
      NayaxTransactionId: body?.BasicInfo?.NayaxTransactionId ?? body?.NayaxTransactionId,
      Amount: body?.BasicInfo?.Amount,
      CurrencyCode: body?.BasicInfo?.CurrencyCode,
      NayaxRRN: body?.BasicInfo?.NayaxRRN,
    },
    MachineInfo: {
      Id: body?.MachineInfo?.Id,
      TerminalId: body?.MachineInfo?.TerminalId,
    },
    DeviceInfo: { HwSerial: body?.DeviceInfo?.HwSerial },
    PaymentInfo: { RRN: body?.PaymentInfo?.RRN },
    ReasonCode: body?.ReasonCode,
    ReasonText: body?.ReasonText,
  };
}

function callbackAmountCents(body: JsonObject): number | null {
  return centsFromNayaxAmount(
    body?.BasicInfo?.Amount ?? body?.PaymentInfo?.SettAmount ??
      body?.PaymentInfo?.AuthAmount,
  );
}

function amountAndCurrencyMatch(session: VendSession, body: JsonObject): boolean {
  const value = body?.BasicInfo?.Amount;
  const amount = typeof value === "number" || (typeof value === "string" && value.trim())
    ? Number(value) : NaN;
  const currency = String(body?.BasicInfo?.CurrencyCode ?? "").toUpperCase();
  return Number.isFinite(amount) && Math.abs(amount * 100 - session.amount_cents) < 1e-8 &&
    currency === session.currency;
}

async function authorizeCallback(
  req: Request,
  environment: "sandbox" | "production",
): Promise<boolean> {
  const prefix = `NAYAX_${environment.toUpperCase()}_CALLBACK`;
  const username = Deno.env.get(`${prefix}_USERNAME`);
  const password = Deno.env.get(`${prefix}_PASSWORD`);
  // Nayax's observed callback uses HTTP Basic. Retain separate-header support,
  // but require the complete configured pair and never fall back to a token.
  if (username !== undefined || password !== undefined) {
    if (!username?.trim() || !password?.trim()) return false;
    let suppliedUsername = req.headers.get("username");
    let suppliedPasswordValue = req.headers.get("password");
    // Explicit headers stay authoritative: an incomplete/wrong pair must not
    // be repaired by a second credential representation on the same request.
    if (suppliedUsername === null && suppliedPasswordValue === null) {
      const basic = /^Basic[ \t]+([A-Za-z0-9+/]+={0,2})$/i.exec(
        req.headers.get("authorization") ?? "",
      );
      if (basic) {
        try {
          const bytes = Uint8Array.from(atob(basic[1]), (char) => char.charCodeAt(0));
          const decoded = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
          const separator = decoded.indexOf(":");
          if (separator > 0 && !/[\u0000-\u001f\u007f]/.test(decoded)) {
            suppliedUsername = decoded.slice(0, separator);
            suppliedPasswordValue = decoded.slice(separator + 1);
          }
        } catch (_) {
          // Malformed Base64/UTF-8 is an authentication failure, not a 500.
        }
      }
    }
    const [expectedUser, suppliedUser, expectedPassword, suppliedPassword] =
      await Promise.all([
        sha256(username),
        sha256(suppliedUsername ?? ""),
        sha256(password),
        sha256(suppliedPasswordValue ?? ""),
      ]);
    const usernameMatches = expectedUser === suppliedUser;
    const passwordMatches = expectedPassword === suppliedPassword;
    if (!usernameMatches || !passwordMatches) {
      // Private diagnostics contain only booleans and a fixed scheme enum.
      // Never log header values, their hashes, or request content.
      const authorization = req.headers.get("authorization");
      console.warn("Cortina callback authentication rejected", {
        environment,
        usernameHeaderPresent: req.headers.has("username"),
        passwordHeaderPresent: req.headers.has("password"),
        usernameMatches,
        passwordMatches,
        authorizationScheme: authorization === null ? "absent"
          : /^Basic\s/i.test(authorization) ? "basic"
          : /^Bearer\s/i.test(authorization) ? "bearer" : "other",
      });
    }
    return usernameMatches && passwordMatches;
  }
  // Preserve previously configured token integrations until their environment
  // is explicitly migrated to the username/password contract.
  const expected = Deno.env.get("NAYAX_CALLBACK_AUTH_TOKEN");
  if (!expected?.trim()) return false;
  const supplied = req.headers.get("x-nayax-auth") ??
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const [expectedHash, suppliedHash] = await Promise.all([
    sha256(expected),
    sha256(supplied),
  ]);
  return expectedHash === suppliedHash;
}

async function readBody(req: Request): Promise<JsonObject | null> {
  try {
    const body = await req.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body : null;
  } catch (_) {
    return null;
  }
}

async function findSession(
  body: JsonObject,
  deps: CortinaDeps,
): Promise<VendSession | null> {
  const id = transactionId(body);
  if (!id) return null;
  const { data, error } = await deps.admin.from("cortina_vend_sessions")
    .select("*")
    .eq("transaction_id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data as VendSession | null;
}

function validateMachine(
  session: VendSession,
  body: JsonObject,
  expectedEnvironment: "sandbox" | "production",
): boolean {
  if (!hasFrozenVendBinding(session) || session.nayax_environment !== expectedEnvironment) return false;
  const receivedTerminal = callbackTerminalId(body);
  // Sale may have an empty terminal, SaleEnd has no device object, and Void
  // may precede Sale. The authenticated transaction is the common binding;
  // HwSerial is audit evidence, never a substitute for TerminalId.
  return !receivedTerminal || session.nayax_terminal_id === receivedTerminal;
}

function transactionMatches(session: VendSession, body: JsonObject, required: boolean): boolean {
  const received = nayaxTransactionId(body);
  if ((required || body?.BasicInfo?.NayaxTransactionId != null || body?.NayaxTransactionId != null) && !received) return false;
  return !session.nayax_transaction_id || !received || session.nayax_transaction_id === received;
}

async function recordCallbackEvent(
  session: VendSession,
  body: JsonObject,
  eventType: string,
  eventKey: string,
  deps: CortinaDeps,
  moneyEvidence?: JsonObject,
): Promise<boolean> {
  // Keep historical audit evidence intact. Only a known different environment
  // can reuse an old unscoped key; unknown historical routing is not inferred.
  const { data: legacy, error: legacyError } = await deps.admin.from("cortina_vend_events")
    .select("session_id, source, event_type, payload").eq("event_key", eventKey).maybeSingle();
  if (legacyError) throw new Error(legacyError.message);
  const matches = (event: JsonObject | null) => event?.session_id === session.id &&
    event.source === "nayax" && event.event_type === eventType &&
    transactionId(event.payload) === session.transaction_id && amountAndCurrencyMatch(session, event.payload) &&
    nayaxTransactionId(event.payload) === nayaxTransactionId(body);
  if (legacy && !matches(legacy)) {
    const { data: owner, error } = await deps.admin.from("cortina_vend_sessions")
      .select("nayax_environment").eq("id", legacy.session_id).maybeSingle();
    if (error) throw new Error(error.message);
    if (!owner?.nayax_environment || owner.nayax_environment === session.nayax_environment) return false;
  }
  const scopedKey = eventKey.replace("nayax:", `nayax:${session.nayax_environment}:`);
  // The database trigger claims provider ownership in this same INSERT. A
  // losing unique claim rolls back its audit, leaving the rightful owner's key free.
  const { error: insertError } = await deps.admin.from("cortina_vend_events").insert({
    session_id: session.id, source: "nayax", event_type: eventType,
    event_key: scopedKey, payload: { ...auditPayload(body), ...(moneyEvidence ? { MoneyValidation: moneyEvidence } : {}) },
  });
  if (!insertError) return true;
  if (insertError.code === "23514") return false;
  if (insertError.code !== "23505") throw new Error(insertError.message);
  const { data: prior, error } = await deps.admin.from("cortina_vend_events")
    .select("session_id, source, event_type, payload").eq("event_key", scopedKey).maybeSingle();
  if (error) throw new Error(error.message);
  return matches(prior);
}

async function handleSale(
  body: JsonObject,
  session: VendSession,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<Response> {
  const amountCents = centsFromNayaxAmount(body?.BasicInfo?.Amount);
  if (!amountAndCurrencyMatch(session, body)) {
    return declined(7, "Amount or currency does not match the paid session");
  }
  if (!validateMachine(session, body, expectedEnvironment) || !transactionMatches(session, body, true)) {
    return declined(5, "Machine does not match the paid session");
  }

  const eventId = nayaxTransactionId(body) ?? session.transaction_id;
  if (!await recordCallbackEvent(session, body, "sale", `nayax:sale:${eventId}`, deps)) {
    return declined(5, "Callback event does not match the paid session");
  }

  if (!["starting", "awaiting_sale", "approved", "started"].includes(session.status)) {
    return declined(2, "Transaction is not awaiting Sale");
  }
  if (["starting", "awaiting_sale"].includes(session.status)) {
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "approved",
      nayax_transaction_id: nayaxTransactionId(body),
      nayax_rrn: rrn(body),
    }).eq("id", session.id).in("status", ["starting", "awaiting_sale"]);
    if (error) throw new Error(error.message);
  }
  // Audit insertion can await a concurrent refund even for an already-approved
  // retry. Every approval must use current state, without reopening a closed vend.
  const { data: current, error: currentError } = await deps.admin
    .from("cortina_vend_sessions").select("*").eq("id", session.id).single();
  if (currentError) throw new Error(currentError.message);
  if (!current || !["approved", "started"].includes(current.status) ||
      !transactionMatches(current as VendSession, body, true)) {
    return declined(2, "Transaction is no longer awaiting Sale");
  }
  if (current.funding_source === "machine_issue") {
    const { data, error } = await deps.admin.rpc("authorize_machine_issue_start", { target_session_id: session.id });
    if (error || data !== true) return declined(2, "Machine issue reservation requires review");
  }
  return approved(session, amountCents ?? undefined, rrn(body) ?? undefined);
}

async function handleVoid(
  body: JsonObject,
  session: VendSession,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<Response> {
  if (!amountAndCurrencyMatch(session, body)) {
    return declined(7, "Amount or currency does not match the paid session");
  }
  if (!validateMachine(session, body, expectedEnvironment) || !transactionMatches(session, body, false)) {
    return declined(5, "Machine does not match the paid session");
  }
  if (["payment_pending", "paid"].includes(session.status)) {
    return declined(2, "Transaction has not requested Start");
  }
  const reason = String(body?.ReasonText ?? "Nayax voided the vend");
  const eventId = nayaxTransactionId(body) ?? session.transaction_id;
  if (!await recordCallbackEvent(session, body, "void", `nayax:void:${eventId}`, deps)) {
    return declined(5, "Callback event does not match the paid session");
  }

  if (session.status !== "refunded") {
    const { data: voided, error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "voided",
      nayax_transaction_id: session.nayax_transaction_id ?? nayaxTransactionId(body),
      failure_code: String(body?.ReasonCode ?? "nayax_void"),
      failure_message: reason,
    }).eq("id", session.id).eq("status", session.status).select("*").maybeSingle();
    if (error) throw new Error(error.message);
    if (!voided) return declined(2, "Transaction changed; retry Void");
    try {
      await compensateVend(voided as VendSession, deps, reason);
    } catch (error) {
      console.error("Cortina compensation requires support", session.id, error);
    }
  }
  return approved(session, session.amount_cents, rrn(body) ?? undefined);
}

// The observed Pulse SaleEnd omits BasicInfo money and reports SettAmount only
// (AuthAmount is zero because this is a Sale, not a preauthorization). Recover
// currency only from this same frozen session's authenticated, validated Sale.
// Never invent a successful Sale or replace a present/conflicting money field.
async function validateSaleEndMoney(
  session: VendSession,
  body: JsonObject,
  environment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<{ body: JsonObject; evidence?: JsonObject } | null> {
  const settlement = body?.PaymentInfo?.SettAmount;
  const settledMatches = (typeof settlement === "number" ||
    (typeof settlement === "string" && /^[0-9]+(?:\.[0-9]+)?$/.test(settlement))) &&
    Number.isFinite(Number(settlement)) &&
    Math.abs(Number(settlement) * 100 - session.amount_cents) < 1e-8;
  if (settlement != null && !settledMatches) return null;
  if (amountAndCurrencyMatch(session, body)) return { body };
  if (body?.BasicInfo?.Amount != null || body?.BasicInfo?.CurrencyCode != null ||
      !settledMatches || !["approved", "started"].includes(session.status) ||
      !session.nayax_transaction_id || session.nayax_transaction_id !== nayaxTransactionId(body)) return null;

  const saleKey = `nayax:${environment}:sale:${session.nayax_transaction_id}`;
  const { data: sale, error } = await deps.admin.from("cortina_vend_events")
    .select("session_id, source, event_type, payload").eq("event_key", saleKey).maybeSingle();
  if (error) throw new Error(error.message);
  if (!sale || sale.session_id !== session.id || sale.source !== "nayax" || sale.event_type !== "sale" ||
      transactionId(sale.payload) !== session.transaction_id ||
      nayaxTransactionId(sale.payload) !== session.nayax_transaction_id ||
      !validateMachine(session, sale.payload, environment) || !amountAndCurrencyMatch(session, sale.payload)) return null;

  return {
    body: { ...body, BasicInfo: { ...body.BasicInfo,
      Amount: Number(settlement), CurrencyCode: sale.payload.BasicInfo.CurrencyCode } },
    // The audit's normalized money still passes the unchanged SQL ownership and
    // money guards; provenance makes clear these fields were not repeated on wire.
    evidence: { source: "settlement_and_validated_sale", saleEventKey: saleKey,
      receivedBasicAmount: null, receivedCurrencyCode: null, settlementAmount: Number(settlement) },
  };
}

async function handleSaleEnd(
  body: JsonObject,
  session: VendSession,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<Response> {
  if (!validateMachine(session, body, expectedEnvironment) || !transactionMatches(session, body, true)) {
    return declined(5, "Machine does not match the paid session");
  }
  const validated = await validateSaleEndMoney(session, body, expectedEnvironment, deps);
  if (!validated) return declined(7, "Amount or currency does not match the paid session");
  body = validated.body;
  if (!["starting", "awaiting_sale", "approved", "started"].includes(session.status)) {
    return declined(2, "Transaction is not awaiting SaleEnd");
  }
  const eventId = nayaxTransactionId(body) ?? session.transaction_id;
  if (!await recordCallbackEvent(session, body, "sale_end", `nayax:sale-end:${eventId}`, deps, validated.evidence)) {
    return declined(5, "Callback event does not match the paid session");
  }
  if (session.funding_source === "machine_issue") {
    const { data, error } = await deps.admin.rpc("authorize_machine_issue_start", { target_session_id: session.id });
    if (error || data !== true) return declined(2, "Machine issue reservation requires review");
  }
  if (["starting", "approved", "awaiting_sale"].includes(session.status)) {
    const { data: updated, error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "started",
      nayax_transaction_id: nayaxTransactionId(body),
      nayax_rrn: rrn(body),
      completed_at: new Date().toISOString(),
    }).eq("id", session.id).in("status", ["starting", "approved", "awaiting_sale"])
      .select("*").maybeSingle();
    if (error) throw new Error(error.message);
    if (!updated) {
      const { data: current, error: currentError } = await deps.admin
        .from("cortina_vend_sessions").select("*").eq("id", session.id).single();
      if (currentError) throw new Error(currentError.message);
      if (!current || current.status !== "started" || !transactionMatches(current as VendSession, body, true)) {
        return declined(2, "Transaction is no longer awaiting SaleEnd");
      }
    }
  }
  return approved();
}
export async function handleNayaxCallback(
  req: Request,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<Response> {
  if (req.method !== "POST") return declined(8, "POST required");
  if (!await authorizeCallback(req, expectedEnvironment)) return declined(5, "Unauthorized callback");
  const body = await readBody(req);
  if (!body) return declined(8, "Invalid JSON body");
  const session = await findSession(body, deps);
  if (!session) return declined(2, "Transaction ID unknown");

  switch (functionRoute(req.url)) {
    case "sale":
      return handleSale(body, session, expectedEnvironment, deps);
    case "void":
      return handleVoid(body, session, expectedEnvironment, deps);
    case "saleendnotification":
      return handleSaleEnd(body, session, expectedEnvironment, deps);
    default:
      return declined(1011, "Callback route is not implemented");
  }
}

export const callbackTestHelpers = {
  auditPayload,
  nayaxTimestamp,
  transactionId,
  callbackTerminalId,
  callbackAmountCents,
};
