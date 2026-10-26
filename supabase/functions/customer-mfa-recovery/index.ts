import { createClient } from "https://esm.sh/@supabase/supabase-js@2.99.3";
import { capturedBearer } from "../admin-portal/backend.ts";
import { callerPublishableKey, selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
class RecoveryError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
type Recovery = {
  target_user_id: string;
  recovery_id: string | null;
  support_case: string | null;
  reenrollment_required: boolean;
  remaining_factor_ids: string[];
  state: "not_started" | "removal_pending" | "reenrollment_required";
};
function receipt(value: unknown, target: string): Recovery {
  if (!value || typeof value !== "object") throw new RecoveryError(503, "recovery_unavailable");
  const r = value as Recovery;
  if (r.target_user_id !== target ||
    (r.recovery_id !== null && (typeof r.recovery_id !== "string" || !uuid.test(r.recovery_id))) ||
    (r.support_case !== null && typeof r.support_case !== "string") ||
    typeof r.reenrollment_required !== "boolean" ||
    !["not_started", "removal_pending", "reenrollment_required"].includes(r.state) ||
    !Array.isArray(r.remaining_factor_ids) || r.remaining_factor_ids.length > 10 ||
    r.remaining_factor_ids.some((id) => typeof id !== "string" || !uuid.test(id)) ||
    new Set(r.remaining_factor_ids).size !== r.remaining_factor_ids.length ||
    (r.recovery_id === null) !== (r.state === "not_started") ||
    r.reenrollment_required !== (r.recovery_id !== null) ||
    (r.state === "removal_pending") !== (r.remaining_factor_ids.length > 0)) {
    throw new RecoveryError(503, "recovery_unavailable");
  }
  return r;
}

export async function handler(request: Request): Promise<Response> {
  const env = (name: string) => Deno.env.get(name);
  const origin = env("ADMIN_PORTAL_ORIGIN") || "https://cleanstreamlaundry.com";
  const headers = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
    "Cache-Control": "no-store", "Content-Type": "application/json", "Vary": "Origin",
  };
  const reply = (body: unknown, status = 200) => Response.json(body, { status, headers });
  if (request.headers.has("origin") && request.headers.get("origin") !== origin) {
    return reply({ error: "recovery_forbidden" }, 403);
  }
  if (request.method === "OPTIONS") return new Response(null, { headers });
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  // Capture before the first await; neither body nor service client can supply actor authority.
  const token = capturedBearer(request);
  if (!token) return reply({ error: "session_invalid" }, 401);
  try {
    const text = await request.text();
    if (text.length > 2048) throw new RecoveryError(400, "invalid_request");
    let body;
    try { body = JSON.parse(text); } catch { throw new RecoveryError(400, "invalid_request"); }
    if (!body || typeof body !== "object" || Array.isArray(body) ||
      !["inspect", "recover"].includes(body.action) || typeof body.target_user_id !== "string" ||
      !uuid.test(body.target_user_id) ||
      Object.keys(body).some((key) => !["action", "target_user_id", "support_case", "identity_verified"].includes(key))) {
      throw new RecoveryError(400, "invalid_request");
    }
    const target = body.target_user_id.toLowerCase();
    if (body.action === "recover" && (body.identity_verified !== true ||
      typeof body.support_case !== "string" || body.support_case.trim() !== body.support_case ||
      body.support_case.length < 1 || body.support_case.length > 120 || /[\x00-\x1f\x7f]/.test(body.support_case))) {
      throw new RecoveryError(400, "invalid_request");
    }
    const url = env("SUPABASE_URL");
    const publicKey = callerPublishableKey(env, "CLEANSTREAM_MFA_RECOVERY_PUBLISHABLE_KEY_NAME");
    if (!url) throw new RecoveryError(503, "recovery_unavailable");
    const caller = createClient(url, publicKey, {
      accessToken: () => Promise.resolve(token),
    });
    const rpc = async (action: string, id: string | null = null) => {
      const { data, error } = await caller.rpc("customer_mfa_recovery_request", {
        action, target_user_id: target,
        support_case: action === "prepare" ? body.support_case : null,
        identity_verified: action === "prepare", expected_recovery_id: id,
      }).abortSignal(AbortSignal.timeout(8000));
      if (error) {
        const codes: Record<string, number> = { PT401: 401, PT403: 403, PT409: 409, "22023": 400 };
        const status = codes[error.code] ?? 503;
        const code = status === 401 ? "session_invalid" : status === 409 ? "recovery_conflict"
          : status === 400 ? "invalid_request" : status === 403
          ? (error.message === "fresh_sign_in_required" ? "fresh_sign_in_required" : "recovery_forbidden")
          : "recovery_unavailable";
        throw new RecoveryError(status, code);
      }
      return receipt(data, target);
    };
    const publicReceipt = (r: Recovery) => ({
      target_user_id: r.target_user_id, recovery_id: r.recovery_id,
      support_case: r.support_case, state: r.state, reenrollment_required: r.reenrollment_required,
    });
    if (body.action === "inspect") return reply(publicReceipt(await rpc("inspect")));
    const name = env("CLEANSTREAM_MFA_RECOVERY_SECRET_KEY_NAME");
    const key = name === undefined ? env("SUPABASE_SERVICE_ROLE_KEY")
      : selectNamedSupabaseKey(name, env("SUPABASE_SECRET_KEYS"), "secret");
    if (!key) throw new RecoveryError(503, "recovery_unavailable");
    const admin = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: (input, init) => {
        const outgoing = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
        if (name !== undefined && outgoing.get("Authorization") === `Bearer ${key}`) outgoing.delete("Authorization");
        return fetch(input, { ...init, headers: outgoing, signal: AbortSignal.timeout(8000) });
      } },
    });
    const prepared = await rpc("prepare");
    if (!prepared.recovery_id || prepared.support_case !== body.support_case) {
      throw new RecoveryError(503, "recovery_unavailable");
    }
    // Only the original durable snapshot may be removed. A retry rechecks SQL
    // existence, never snapshots/deletes a customer's newly enrolled factor.
    for (const id of prepared.remaining_factor_ids) {
      const current = await rpc("authorize", prepared.recovery_id);
      if (current.recovery_id !== prepared.recovery_id || current.support_case !== prepared.support_case ||
        current.remaining_factor_ids.some((factor) => !prepared.remaining_factor_ids.includes(factor))) {
        throw new RecoveryError(503, "recovery_unavailable");
      }
      if (!current.remaining_factor_ids.includes(id)) continue;
      const { error } = await admin.auth.admin.mfa.deleteFactor({ userId: target, id });
      // An unknown external outcome cannot clear the durable fence or trigger a blind retry.
      if (error) throw new RecoveryError(503, "recovery_unavailable");
    }
    const finished = await rpc("authorize", prepared.recovery_id);
    if (finished.recovery_id !== prepared.recovery_id || finished.remaining_factor_ids.length !== 0) {
      throw new RecoveryError(503, "recovery_unavailable");
    }
    return reply(publicReceipt(finished));
  } catch (error) {
    return reply({ error: error instanceof RecoveryError ? error.code : "recovery_unavailable" },
      error instanceof RecoveryError ? error.status : 503);
  }
}

if (import.meta.main) Deno.serve(handler);
