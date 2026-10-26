import { createClient } from "https://esm.sh/@supabase/supabase-js@2.99.3";
import { PortalError } from "./logic.ts";

export type OnboardingConfig = {
  secretKey: string;
  modernSecret: boolean;
  redirectTo: string;
};
type Receipt = {
  request_id: string;
  actor_id: string;
  target_user_id: string | null;
  email: string;
  location_ids: number[];
  email_action: "invite" | "recovery";
  portal_role?: "Manager" | "Maintenance";
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const unavailable = () => new PortalError(
  "The invitation outcome is unavailable. Refresh the team list and contact support before trying again.",
  503, "admin_onboarding_unavailable",
);
function receipt(value: unknown, actor: string, ids: number[], email?: string): Receipt {
  const r = value as Receipt | null;
  if (!r || typeof r.request_id !== "string" || !/^[1-9][0-9]*$/.test(r.request_id) ||
    r.actor_id !== actor || (r.target_user_id !== null &&
      (typeof r.target_user_id !== "string" || !uuid.test(r.target_user_id))) ||
    typeof r.email !== "string" || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(r.email) ||
    (email !== undefined && r.email !== email) ||
    !Array.isArray(r.location_ids) || r.location_ids.length !== ids.length ||
    r.location_ids.some((id, index) => id !== ids[index]) ||
    !["invite", "recovery"].includes(r.email_action) ||
    (r.target_user_id === null && r.email_action !== "invite")) throw unavailable();
  return r;
}

export async function sendTeamInvitation(
  actor: string,
  input: { email: string; locationIds: number[]; portalRole?: "Manager" | "Maintenance" } | { userId: string; locationId: number },
  config: { url: string; onboarding?: OnboardingConfig; fetch?: typeof fetch },
  rpc: (name: string, args: Record<string, unknown>) => Promise<unknown>,
): Promise<{ warning?: string }> {
  const options = config.onboarding;
  if (!options?.secretKey) {
    throw new PortalError("Team invitations are not enabled yet.", 503, "admin_onboarding_disabled");
  }
  const redirect = new URL(options.redirectTo);
  if (redirect.protocol !== "https:" || redirect.username || redirect.password ||
    redirect.pathname !== "/admin/accept-invite" || redirect.search || redirect.hash) throw unavailable();
  const inviting = "email" in input;
  const ids = inviting ? [...input.locationIds].sort((a, b) => a - b) : [input.locationId];
  const expectedEmail = inviting ? input.email : undefined;
  const request = async (args: Record<string, unknown>) => {
    try {
      return receipt(await rpc("admin_team_onboarding", args), actor, ids, expectedEmail);
    } catch (error) {
      if (error instanceof PortalError && error.status < 500) throw error;
      throw unavailable();
    }
  };
  const prepared = await request(inviting
    ? { action: "invite", target_email: input.email, target_locations: ids, target_portal_role: input.portalRole ?? "Manager" }
    : { action: "resend", target_user_id: input.userId, target_locations: ids });
  if (!inviting && prepared.target_user_id !== input.userId.toLowerCase()) throw unavailable();
  if (prepared.portal_role !== undefined && !["Manager", "Maintenance"].includes(prepared.portal_role)) throw unavailable();
  if (inviting && prepared.portal_role !== (input.portalRole ?? "Manager")) throw unavailable();

  const admin = createClient(config.url, options.secretKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, flowType: "implicit" },
    global: { fetch: (url, init) => {
      const headers = new Headers(init?.headers ?? (url instanceof Request ? url.headers : undefined));
      if (options.modernSecret && headers.get("Authorization") === `Bearer ${options.secretKey}`) {
        headers.delete("Authorization");
      }
      return (config.fetch ?? fetch)(url, { ...init, headers, signal: AbortSignal.timeout(8000) });
    } },
  });
  const current = await request({ action: "authorize", request_id: prepared.request_id });
  if (current.request_id !== prepared.request_id || current.target_user_id !== prepared.target_user_id ||
    current.email !== prepared.email || current.email_action !== prepared.email_action || current.portal_role !== prepared.portal_role) throw unavailable();
  // The captured caller reauthorizes immediately before one Auth email call.
  // A timeout cannot undo a dispatched email; never compensate/delete or retry.
  let target = current.target_user_id;
  try {
    if (current.email_action === "invite") {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(current.email, { redirectTo: redirect.href });
      if (error || !data.user || !uuid.test(data.user.id) ||
        data.user.email?.toLowerCase() !== current.email ||
        (target !== null && data.user.id !== target)) throw unavailable();
      target = data.user.id;
    } else {
      const { error } = await admin.auth.resetPasswordForEmail(current.email, { redirectTo: redirect.href });
      if (error) throw unavailable();
    }
    if (!target) throw unavailable();
    const completed = await request({ action: "complete", request_id: current.request_id, target_user_id: target });
    if (completed.request_id !== current.request_id || completed.target_user_id !== target ||
      completed.email !== current.email || completed.portal_role !== current.portal_role) throw unavailable();
    const { error } = await admin.rpc("admin_team_invitation_delivered", {
      request_id: current.request_id, target_user_id: target,
    });
    if (error) throw unavailable();
    return {};
  } catch {
    throw unavailable();
  }
}
