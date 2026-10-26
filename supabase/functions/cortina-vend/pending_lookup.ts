import { CortinaDeps, HttpError, jsonResponse, sha256 } from "../_shared/cortina.ts";

const requestIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function requestsPendingLookup(body: Record<string, unknown>): boolean {
  return Object.hasOwn(body, "clientRequestId") || Object.hasOwn(body, "machineId");
}

// Lookup only: never enter the legacy timeout/settlement path or replay creation.
export async function handlePendingLookup(
  authorization: string | null,
  body: Record<string, unknown>,
  deps: CortinaDeps,
): Promise<Response> {
  const requestId = body.clientRequestId;
  const machineId = body.machineId;
  if (
    typeof requestId !== "string" || !requestIdPattern.test(requestId) ||
    typeof machineId !== "number" || !Number.isSafeInteger(machineId) || machineId <= 0 ||
    Object.keys(body).some((key) => key !== "clientRequestId" && key !== "machineId")
  ) {
    throw new HttpError(400, "Invalid recovery request", "invalid_recovery_request");
  }
  const token = /^Bearer\s+(.+)$/i.exec(authorization ?? "")?.[1].trim();
  if (!token || token.startsWith("sb_")) {
    throw new HttpError(401, "Sign in to recover this payment", "authentication_required");
  }

  let user: { id: string; is_anonymous?: boolean } | null | undefined;
  try {
    const verified = await deps.admin.auth.getUser(token);
    if (verified.error) {
      const status = verified.error.status ?? 0;
      if (verified.error.name === "AuthRetryableFetchError" ||
        status === 0 || status === 429 || status >= 500) {
        throw new HttpError(503, "Payment recovery unavailable", "recovery_unavailable");
      }
    }
    if (!verified.error) user = verified.data.user;
  } catch {
    throw new HttpError(503, "Payment recovery unavailable", "recovery_unavailable");
  }
  if (!user?.id || user.is_anonymous !== false) {
    throw new HttpError(401, "Sign in to recover this payment", "authentication_required");
  }

  const hash = await sha256(requestId);
  let result: { data: Record<string, unknown> | null; error: unknown };
  try {
    result = await deps.admin.from("cortina_vend_sessions")
      .select("id,user_id,machine_id,client_request_id,client_access_token_hash")
      .eq("user_id", user.id)
      .eq("machine_id", machineId)
      .eq("client_request_id", requestId)
      .eq("client_access_token_hash", hash)
      .maybeSingle();
  } catch {
    throw new HttpError(503, "Payment recovery unavailable", "recovery_unavailable");
  }
  if (result.error) {
    throw new HttpError(503, "Payment recovery unavailable", "recovery_unavailable");
  }
  const row = result.data;
  if (!row || row.user_id !== user.id || row.machine_id !== machineId ||
    row.client_request_id !== requestId.toLowerCase() || row.client_access_token_hash !== hash) {
    throw new HttpError(404, "Vend session not found", "session_not_found");
  }
  if (typeof row.id !== "string" || !requestIdPattern.test(row.id)) {
    throw new HttpError(503, "Payment recovery unavailable", "recovery_unavailable");
  }
  return jsonResponse({ sessionId: row.id, accessToken: requestId });
}
