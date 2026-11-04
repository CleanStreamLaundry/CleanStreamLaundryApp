export interface DeleteUserDeps {
  // Both calls use the exact incoming bearer, never a service-role client.
  getUser(jwt: string): Promise<{ userId: string | null; error: boolean }>;
  requestDeletion(jwt: string): Promise<{
    data: unknown;
    error: { code?: string; message?: string } | null;
  }>;
}

const HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, apikey, x-client-info",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: HEADERS });

function isPendingAcknowledgement(data: unknown, userId: string): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const keys = Object.keys(data);
  const state = data as Record<string, unknown>;
  if (
    keys.length !== 6 || ![
      "subject_id",
      "account_access",
      "next_step",
      "reason",
      "account_state",
      "restore_until",
    ].every((key) => keys.includes(key)) ||
    state.subject_id !== userId || state.account_access !== "restricted" ||
    state.account_state !== "pending_deletion" ||
    typeof state.restore_until !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(
      state.restore_until,
    )
  ) return false;
  const deadline = new Date(state.restore_until);
  // Round-trip calendar fields: Date.parse alone normalizes invalid dates.
  // Do not compare against the Edge clock; expired pending is a valid ack.
  if (
    !Number.isFinite(deadline.getTime()) ||
    deadline.toISOString().slice(0, 19) !== state.restore_until.slice(0, 19)
  ) return false;
  return state.next_step === "blocked"
    ? [
      "explicit_restore_required",
      "restore_expired",
      "profile_missing",
      "role_unavailable",
      "unsupported_factor",
    ].includes(state.reason as string)
    : state.reason === null &&
      ["verify_email", "enroll_totp", "challenge_totp"].includes(
        state.next_step as string,
      );
}

export async function handleDeleteUser(
  req: Request,
  deps: DeleteUserDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: HEADERS });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const jwt = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!jwt) return json(401, { error: "missing_authorization" });

  let userId: string | null;
  try {
    const identity = await deps.getUser(jwt);
    if (identity.error || !identity.userId) {
      return json(401, { error: "invalid_authorization" });
    }
    userId = identity.userId;
  } catch {
    return json(503, { error: "authentication_unavailable" });
  }
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_request" });
  }
  if (
    !body || typeof body !== "object" || !("user_id" in body) ||
    typeof body.user_id !== "string" || !body.user_id.trim()
  ) {
    return json(400, { error: "missing_user_id" });
  }
  // Retain the legacy body, but it is never an RPC argument.
  if (body.user_id !== userId) return json(403, { error: "account_mismatch" });
  try {
    const { data, error } = await deps.requestDeletion(jwt);
    if (error?.code === "PT401") return json(401, { error: "session_invalid" });
    if (error?.code === "PT403") {
      return json(403, { error: "account_restricted" });
    }
    if (error?.code === "PT409" && error.message === "owner_last_required") {
      return json(409, { error: "owner_last_required" });
    }
    if (!error && isPendingAcknowledgement(data, userId)) {
      return json(200, { success: true, data });
    }
  } catch {
    // A lost response can follow a committed request. Do not claim rollback.
  }
  return json(503, {
    error: "deletion_outcome_unknown",
    retryable: true,
    status_rpc: "get_account_lifecycle_status",
  });
}
