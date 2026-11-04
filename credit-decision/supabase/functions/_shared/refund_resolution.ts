export type RefundDecision = "approved" | "denied";

export interface RefundResolution {
  success: boolean;
  alreadyResolved: boolean;
  refundId: number;
  transactionId: number;
  customerId: string;
  amount: number;
  status: RefundDecision;
  notificationSent: boolean;
  notificationState?: string;
}

export interface RefundResolutionDependencies {
  authenticate(req: Request): Promise<string>;
  resolve(input: {
    refundId: number;
    decision: RefundDecision;
    note: string;
    actorUserId: string;
  }): Promise<RefundResolution>;
}

export function creditNotificationSummary(credit: { notificationSent?: boolean; notificationState?: unknown }) {
  const state = typeof credit.notificationState === "string" ? credit.notificationState : "not_queued";
  const sent = credit.notificationSent === true && ["accepted", "delivered", "legacy_sent"].includes(state);
  const messages: Record<string, string> = {
    ready: "The credit decision is saved. Customer notice is queued; delivery is not yet confirmed.",
    leased: "The credit decision is saved. Customer notice is queued; delivery is not yet confirmed.",
    sending: "The credit decision is saved. Customer notice delivery is not yet confirmed.",
    uncertain: "The credit decision is saved. Customer notice delivery is unconfirmed and requires reconciliation; do not repeat the credit decision.",
    failed: "The credit decision is saved. Customer notice failed; notification follow-up is separate from the credit decision.",
    suppressed: "The credit decision is saved. Customer notice is suppressed or no longer applicable.",
  };
  return {
    notificationSent: sent,
    ...(sent ? {} : {
      notificationWarning: Object.hasOwn(messages, state) ? messages[state] : "The credit decision is saved, but no customer notice is confirmed. Do not repeat the credit decision to send email.",
    }),
  };
}

export class RefundHttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("CLEAN_STREAM_WEB_ORIGIN") ??
    "https://cleanstreamlaundry.com",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Vary": "Origin",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function requestBody(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error("Invalid body");
    }
    return body as Record<string, unknown>;
  } catch {
    throw new RefundHttpError(400, "Invalid JSON body");
  }
}

export async function handleRefundResolution(
  req: Request,
  decision: RefundDecision,
  deps: RefundResolutionDependencies,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "POST required" }, 405);
  }

  try {
    const body = await requestBody(req);
    const refundId = Number(body.refundId);
    if (!Number.isSafeInteger(refundId) || refundId <= 0) {
      throw new RefundHttpError(400, "A valid refundId is required");
    }

    const note = typeof body.note === "string" ? body.note.trim() : "";
    const actorUserId = await deps.authenticate(req);
    const resolution = await deps.resolve({
      refundId,
      decision,
      note,
      actorUserId,
    });

    return json({
      ...resolution,
      ...creditNotificationSummary(resolution),
    });
  } catch (error) {
    const status = error instanceof RefundHttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Refund failed";
    return json({ error: message }, status);
  }
}
