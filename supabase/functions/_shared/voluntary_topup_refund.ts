export type RefundOperation = {
  id: string;
  intent: string;
  amount: number;
  livemode: boolean;
  refund_id: string | null;
  idempotency_key: string;
  may_create: boolean;
};

export type ProviderRefund = {
  id: string;
  payment_intent: string | { id: string } | null;
  amount: number;
  currency: string;
  status: string | null;
  metadata: Record<string, string> | null;
};

export interface TopupRefundDependencies {
  authenticate(req: Request): Promise<void>;
  callerRpc(name: string, args: Record<string, unknown>): Promise<unknown>;
  prepare(id: string): Promise<RefundOperation | null>;
  payment(intent: string): Promise<{
    id: string;
    status: string;
    amount_received: number;
    currency: string;
    livemode: boolean;
  }>;
  refunds(intent: string): Promise<ProviderRefund[]>;
  retrieve(id: string): Promise<ProviderRefund>;
  create(op: RefundOperation): Promise<ProviderRefund>;
  reconcile(op: RefundOperation, refund: ProviderRefund): Promise<unknown>;
}

export class TopupRefundError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

function matches(op: RefundOperation, refund: ProviderRefund): boolean {
  const intent = typeof refund.payment_intent === "string"
    ? refund.payment_intent
    : refund.payment_intent?.id;
  return refund.id.startsWith("re_") && intent === op.intent &&
    refund.amount === op.amount && refund.currency === "usd" &&
    ["pending", "requires_action", "succeeded", "failed", "canceled"].includes(
      refund.status ?? "",
    );
}

export async function executeTopupRefund(
  id: string,
  deps: TopupRefundDependencies,
): Promise<unknown> {
  const op = await deps.prepare(id);
  if (!op) return null;
  if (
    op.id !== id || !Number.isSafeInteger(op.amount) || op.amount <= 0 ||
    !op.intent.startsWith("pi_") || typeof op.livemode !== "boolean" ||
    op.idempotency_key !== `voluntary-topup-v1:${id}` ||
    typeof op.may_create !== "boolean"
  ) {
    throw new Error("Invalid dispatch contract");
  }
  const payment = await deps.payment(op.intent);
  if (
    payment.id !== op.intent || payment.status !== "succeeded" ||
    payment.amount_received !== op.amount || payment.currency !== "usd" ||
    payment.livemode !== op.livemode
  ) throw new Error("Payment mismatch");

  let refund: ProviderRefund;
  if (op.refund_id) {
    // Fetch current provider truth, never apply webhook payload ordering.
    refund = await deps.retrieve(op.refund_id);
    if (refund.id !== op.refund_id) throw new Error("Refund identity mismatch");
    if (["failed", "canceled"].includes(refund.status ?? "")) {
      // A failed bound refund does not rule out a replacement payout. Release
      // only with complete, agreeing history; any other identity needs review.
      const history = await deps.refunds(op.intent);
      if (
        history.length !== 1 || history[0].id !== refund.id ||
        !matches(op, history[0]) || history[0].status !== refund.status
      ) throw new Error("Conflicting or incomplete refund history");
    }
  } else {
    const refunds = await deps.refunds(op.intent);
    const ours = refunds.filter((r) =>
      r.metadata?.voluntary_topup_refund_id === op.id
    );
    const active = refunds.filter((r) =>
      !["failed", "canceled"].includes(r.status ?? "")
    );
    if (ours.length > 1) throw new Error("Multiple matching refunds");
    if (ours.length === 1) {
      refund = await deps.retrieve(ours[0].id);
      if (refund.id !== ours[0].id || active.some((r) => r.id !== refund.id)) {
        throw new Error("Conflicting refunds");
      }
    } else if (active.length === 1 && matches(op, active[0])) {
      // A full original-method external refund can fulfill this operation.
      refund = await deps.retrieve(active[0].id);
      if (refund.id !== active[0].id) {
        throw new Error("Refund identity mismatch");
      }
    } else {
      if (active.length || !op.may_create) {
        throw new Error("Manual reconciliation required");
      }
      // The database caps automatic creation/retry below Stripe's 24h minimum
      // idempotency retention. Unknown older outcomes never issue another POST.
      refund = await deps.create(op);
      if (refund.metadata?.voluntary_topup_refund_id !== op.id) {
        throw new Error("Refund metadata mismatch");
      }
    }
  }
  if (!matches(op, refund)) throw new Error("Refund mismatch");
  return await deps.reconcile(op, refund);
}

export async function handleVoluntaryTopupRefund(
  req: Request,
  deps: TopupRefundDependencies,
): Promise<Response> {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }
  try {
    await deps.authenticate(req);
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      throw new TopupRefundError(400, "invalid_request");
    }
    if (
      !body || Array.isArray(body) || typeof body !== "object" ||
      Object.keys(body).some((k) =>
        !["action", "id", "note", "before", "before_id"].includes(k)
      )
    ) {
      throw new TopupRefundError(400, "invalid_request");
    }
    if (body.action === "list") {
      if (
        body.id !== undefined || body.note !== undefined ||
        (body.before != null &&
          (typeof body.before !== "string" ||
            !Number.isFinite(Date.parse(body.before)))) ||
        (body.before_id != null && (body.before == null ||
          typeof body.before_id !== "string" ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
            .test(body.before_id)))
      ) {
        throw new TopupRefundError(400, "invalid_request");
      }
      const data = await deps.callerRpc("owner_list_voluntary_topup_refunds", {
        p_before: body.before ?? null,
        p_before_id: body.before_id ?? null,
      });
      return Response.json({ data });
    }
    if (
      !["approve", "deny", "reconcile"].includes(String(body.action)) ||
      typeof body.id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        body.id,
      ) ||
      body.before !== undefined || body.before_id !== undefined ||
      (body.note !== undefined &&
        (typeof body.note !== "string" || body.note.length > 2000))
    ) {
      throw new TopupRefundError(400, "invalid_request");
    }
    const refundId = body.id.toLowerCase();
    const reviewed = await deps.callerRpc("review_voluntary_topup_refund", {
      p_id: refundId,
      p_action: body.action,
      p_note: body.note ?? null,
    });
    const data = body.action === "deny"
      ? reviewed
      : await executeTopupRefund(refundId, deps) ?? reviewed;
    const status = (data as { status?: string })?.status;
    // Approval and even a provider POST acknowledgement are not payout success.
    return Response.json({ data }, {
      status: ["unknown", "pending", "approved"].includes(status ?? "")
        ? 202
        : 200,
    });
  } catch (error) {
    if (error instanceof TopupRefundError) {
      return Response.json({ error: error.code }, { status: error.status });
    }
    return Response.json({
      error: "refund_outcome_unknown",
      reconciliation_required: true,
    }, { status: 503 });
  }
}
