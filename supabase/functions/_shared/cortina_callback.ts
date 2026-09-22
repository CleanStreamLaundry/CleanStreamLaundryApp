import {
  centsFromNayaxAmount,
  compensateVend,
  CortinaDeps,
  functionRoute,
  recordVendEvent,
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
  const value = body?.BasicInfo?.TransactionId ?? body?.TransactionId ??
    body?.PaymentInfo?.SrvTranId;
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function nayaxTransactionId(body: JsonObject): string | null {
  const value = body?.BasicInfo?.NayaxTransactionId ?? body?.NayaxTransactionId;
  return value === undefined || value === null ? null : String(value);
}

function rrn(body: JsonObject): string | null {
  const value = body?.BasicInfo?.NayaxRRN ?? body?.PaymentInfo?.RRN;
  return value === undefined || value === null ? null : String(value);
}

function callbackTerminalId(body: JsonObject): string | null {
  const value = body?.MachineInfo?.TerminalId || body?.DeviceInfo?.HwSerial;
  return value === undefined || value === null || String(value).trim() === ""
    ? null
    : String(value).trim();
}

function auditPayload(body: JsonObject): JsonObject {
  return {
    BasicInfo: {
      TransactionId: body?.BasicInfo?.TransactionId,
      NayaxTransactionId: body?.BasicInfo?.NayaxTransactionId,
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
  const amountCents = callbackAmountCents(body);
  const currency = String(body?.BasicInfo?.CurrencyCode ?? "").toUpperCase();
  return amountCents === session.amount_cents &&
    (!currency || currency === session.currency);
}

async function authorizeCallback(req: Request): Promise<boolean> {
  const expected = Deno.env.get("NAYAX_CALLBACK_AUTH_TOKEN");
  if (!expected) return true;
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

async function validateMachine(
  session: VendSession,
  body: JsonObject,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<boolean> {
  const { data: config, error } = await deps.admin.from("cortina_machine_config")
    .select("nayax_terminal_id, environment")
    .eq("machine_id", session.machine_id)
    .maybeSingle();
  if (error || !config || config.environment !== expectedEnvironment) return false;
  const receivedTerminal = callbackTerminalId(body);
  return !receivedTerminal || !config.nayax_terminal_id ||
    String(config.nayax_terminal_id) === receivedTerminal;
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
  if (!await validateMachine(session, body, expectedEnvironment, deps)) {
    return declined(5, "Machine does not match the paid session");
  }

  const eventId = nayaxTransactionId(body) ?? session.transaction_id;
  await recordVendEvent(deps.admin, {
    sessionId: session.id,
    source: "nayax",
    eventType: "sale",
    eventKey: `nayax:sale:${eventId}`,
    payload: auditPayload(body),
  });

  if (!["starting", "awaiting_sale", "approved", "started"].includes(session.status)) {
    return declined(2, "Transaction is not awaiting Sale");
  }
  if (["starting", "awaiting_sale"].includes(session.status)) {
    const { data: updated, error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "approved",
      nayax_transaction_id: nayaxTransactionId(body),
      nayax_rrn: rrn(body),
    }).eq("id", session.id).in("status", ["starting", "awaiting_sale"])
      .select("status").maybeSingle();
    if (error) throw new Error(error.message);
    if (!updated) {
      const { data: current, error: currentError } = await deps.admin
        .from("cortina_vend_sessions").select("status").eq("id", session.id).single();
      if (currentError) throw new Error(currentError.message);
      if (!current || !["approved", "started"].includes(current.status)) {
        return declined(2, "Transaction is no longer awaiting Sale");
      }
    }
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
  if (!await validateMachine(session, body, expectedEnvironment, deps)) {
    return declined(5, "Machine does not match the paid session");
  }
  const reason = String(body?.ReasonText ?? "Nayax voided the vend");
  const eventId = nayaxTransactionId(body) ?? session.transaction_id;
  await recordVendEvent(deps.admin, {
    sessionId: session.id,
    source: "nayax",
    eventType: "void",
    eventKey: `nayax:void:${eventId}`,
    payload: auditPayload(body),
  });

  if (session.status !== "refunded") {
    await deps.admin.from("cortina_vend_sessions").update({
      status: "voided",
      failure_code: String(body?.ReasonCode ?? "nayax_void"),
      failure_message: reason,
    }).eq("id", session.id);
    try {
      await compensateVend({ ...session, status: "voided" }, deps, reason);
    } catch (error) {
      console.error("Cortina compensation requires support", session.id, error);
    }
  }
  return approved(session, session.amount_cents, rrn(body) ?? undefined);
}

async function handleSaleEnd(
  body: JsonObject,
  session: VendSession,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<Response> {
  if (!amountAndCurrencyMatch(session, body)) {
    return declined(7, "Amount or currency does not match the paid session");
  }
  if (!await validateMachine(session, body, expectedEnvironment, deps)) {
    return declined(5, "Machine does not match the paid session");
  }
  const eventId = nayaxTransactionId(body) ?? session.transaction_id;
  await recordVendEvent(deps.admin, {
    sessionId: session.id,
    source: "nayax",
    eventType: "sale_end",
    eventKey: `nayax:sale-end:${eventId}`,
    payload: auditPayload(body),
  });
  if (["approved", "awaiting_sale"].includes(session.status)) {
    const { error } = await deps.admin.from("cortina_vend_sessions").update({
      status: "started",
      nayax_transaction_id: nayaxTransactionId(body),
      nayax_rrn: rrn(body),
      completed_at: new Date().toISOString(),
    }).eq("id", session.id).in("status", ["approved", "awaiting_sale"]);
    if (error) throw new Error(error.message);
  }
  return approved();
}

export async function handleNayaxCallback(
  req: Request,
  expectedEnvironment: "sandbox" | "production",
  deps: CortinaDeps,
): Promise<Response> {
  if (req.method !== "POST") return declined(8, "POST required");
  if (!await authorizeCallback(req)) return declined(5, "Unauthorized callback");
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
