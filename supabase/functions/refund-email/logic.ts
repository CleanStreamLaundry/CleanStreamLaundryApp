export interface Dependencies {
  enqueueNotice: (transactionId: string) => Promise<unknown>;
}

const states = new Set([
  "queued",
  "sending",
  "uncertain",
  "accepted",
  "delivered",
  "failed",
  "suppressed",
  "disabled",
  "recipient_unavailable",
]);

function positiveId(value: unknown): string | null {
  const text = typeof value === "number" && Number.isSafeInteger(value)
    ? String(value)
    : typeof value === "string"
    ? value
    : "";
  return text.trim() === text && /^[1-9][0-9]{0,18}$/.test(text) &&
      BigInt(text) <= 9223372036854775807n
    ? text
    : null;
}

export async function handleRefundRequest(body: unknown, deps: Dependencies) {
  const transactionId = body && typeof body === "object" && !Array.isArray(body)
    ? positiveId((body as Record<string, unknown>).transaction_id)
    : null;
  if (!transactionId) {
    return { status: 400, body: { error: "invalid_transaction_id" } };
  }
  // Compatibility fields from the old caller are never content or authority.
  const result = await deps.enqueueNotice(transactionId);
  if (!result || typeof result !== "object" || Array.isArray(result)) {
    throw new Error("Invalid notice result");
  }
  const record = result as Record<string, unknown>;
  const refundId = positiveId(record.refund_id);
  if (
    !refundId || typeof record.state !== "string" || !states.has(record.state)
  ) {
    throw new Error("Invalid notice result");
  }
  const sent = record.state === "accepted" || record.state === "delivered";
  return {
    status: 200,
    body: {
      success: true,
      claimRecorded: true,
      refundId,
      notificationSent: sent,
      notificationState: record.state,
      ...(!sent
        ? {
          notificationWarning: record.state === "queued"
            ? "Your claim is saved. Its notification is queued, not yet sent."
            : "Your claim is saved. Its notification has not been confirmed sent.",
        }
        : {}),
    },
  };
}
