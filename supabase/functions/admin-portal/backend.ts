import { createClient } from "https://esm.sh/@supabase/supabase-js@2.99.3";
import { type PortalDependencies, PortalError, type PortalRole, requirePortalAction } from "./logic.ts";
import { geocodeAddress, parseGeocodeAddress } from "./geocoding.ts";
import { type OnboardingConfig, sendTeamInvitation } from "./onboarding.ts";
import {
  RefundHttpError,
  type RefundResolution,
  type RefundResolutionDependencies,
} from "../_shared/refund_resolution.ts";

export interface PortalConfig {
  startReplacement?: (sessionId: string, authorize: () => Promise<void>) => Promise<void>;
  url: string;
  anonKey: string;
  fetch?: typeof fetch;
  geocodeKey?: string;
  onboarding?: OnboardingConfig;
}
export function capturedBearer(request: Request): string {
  return /^Bearer ([^\s]+)$/i.exec(request.headers.get("authorization") ?? "")
    ?.[1] ?? "";
}
const admissionMessages: Record<string, [string, string]> = {
  verify_email: ["Verify your email to continue.", "verify_email"],
  enroll_totp: ["Set up an authenticator to continue.", "enroll_totp"],
  challenge_totp: ["Verify your authenticator to continue.", "challenge_totp"],
  account_restricted: [
    "This account cannot access the staff portal.",
    "blocked",
  ],
  staff_required: ["Staff access is required.", "blocked"],
  admin_access_changed: [
    "Your access changed. Refresh before continuing.",
    "revalidate",
  ],
};
function rpcError(
  error: { code?: string; message: string },
  status: number,
): PortalError {
  if (error.code === "PT409" && error.message.startsWith("machine_issue_")) {
    return new PortalError("This machine issue requires review. Refresh its saved receipt before continuing.", 409, error.message);
  }
  if (error.code === "PT409" && [
    "owner_last_required", "owner_state_changed", "owner_target_ineligible", "owner_request_conflict",
  ].includes(error.message)) {
    return new PortalError("Owner access changed. Recheck the account before continuing.", 409, error.message);
  }
  if (error.code === "PT409" && ["staff_role_state_changed", "staff_role_target_ineligible", "staff_role_request_conflict"].includes(error.message)) {
    return new PortalError("Staff access changed. Recheck the account before continuing.", 409, error.message);
  }
  if (error.code === "PT401" || status === 401 || error.code === "PGRST301") {
    return new PortalError(
      "Your session expired. Sign in again.",
      401,
      "session_invalid",
      "sign_in",
    );
  }
  if (error.code === "PT403" && admissionMessages[error.message]) {
    const [message, step] = admissionMessages[error.message];
    return new PortalError(message, 403, error.message, step);
  }
  if (error.code === "42501" || error.code === "PT403") {
    return new PortalError(
      "You do not have access to this operation or location.",
      403,
      "admin_forbidden",
    );
  }
  if (error.code === "PT503" || status >= 500 || status === 0) {
    return new PortalError(
      "The admin service is temporarily unavailable.",
      503,
      "admin_unavailable",
    );
  }
  return new PortalError(
    "The request could not be completed. Refresh and try again.",
    400,
  );
}
export function createPortalDependencies(
  token: string,
  config: PortalConfig,
): PortalDependencies {
  // No Auth singleton, persisted session, service credential or refresh.
  // Every RPC uses the bearer captured before reading the request body.
  const caller = createClient(config.url, config.anonKey, {
    accessToken: () => Promise.resolve(token),
    global: { fetch: config.fetch },
  });
  const requireCaptured = (supplied: string) => {
    if (!token || supplied !== token) {
      throw new PortalError(
        "Your session expired. Sign in again.",
        401,
        "session_invalid",
        "sign_in",
      );
    }
  };
  let portalRole: PortalRole | undefined;
  const authorize = (action: string, payload: Record<string, unknown> = {}) => requirePortalAction(portalRole, action, payload);
  const rpc = async (name: string, args: Record<string, unknown>) => {
    requireCaptured(token);
    const pending = caller.rpc(name, args);
    const { data, error, status } = await (["admin_team_onboarding", "admin_owner_management"].includes(name)
      ? pending.abortSignal(AbortSignal.timeout(8000)) : pending);
    if (name === "admin_team_onboarding" && error?.code === "PT409") {
      throw new PortalError("Team access changed. Refresh the team list before continuing.", 409, "admin_onboarding_conflict");
    }
    if (error) throw rpcError(error, status);
    return data;
  };
  return {
    machineIssue: async (action, payload) => {
      authorize(action);
      if (action === "resolveMachineIssue" && payload.resolution === "replacement_vend" && !config.startReplacement) {
        throw new PortalError("Replacement starts are not configured.", 503, "machine_issue_replacement_unavailable");
      }
      const result = await rpc("admin_machine_issue", { action, payload });
      if (action === "machineIssueReview") {
        if (!config.startReplacement) {
          result.capabilities.replacementVend = false;
          result.replacementUnavailableReason = "replacement_dispatch_unconfigured";
        }
        return result;
      }
      // Only a fresh durable reservation may dispatch. Replays/status never Start.
      if (result.startSessionId) {
        try { await config.startReplacement!(result.startSessionId, async () => {
          const current = await rpc("admin_portal_request", { action: "identity", payload: {} });
          if (current?.role !== "Owner") throw new PortalError("Owner access is required.", 403, "admin_forbidden");
        }); }
        catch { /* The committed reservation remains pending; never retry Start. */ }
        result.review = await rpc("admin_machine_issue", { action: "machineIssueReview", payload: { id: payload.id, requestId: payload.requestId } });
      }
      delete result.startSessionId;
      return result;
    },
    manageOwners: (action, payload) => { authorize(action); return rpc("admin_owner_management", { action, payload }); },
    manageStaff: (action, payload) => { authorize(action); return rpc("admin_staff_role_management", { action, payload }); },
    geocode: async (actor, address) => {
      const query = parseGeocodeAddress(address);
      // Reuse live session/MFA/lifecycle admission, not client role claims.
      const identity = await rpc("admin_portal_request", {
        action: "identity",
        payload: {},
      });
      if (!identity || identity.id !== actor || identity.role !== "Owner") {
        throw new PortalError("Owner access is required.", 403, "admin_forbidden");
      }
      return { coordinates: await geocodeAddress(query, config.geocodeKey, config.fetch) };
    },
    authenticate: async (supplied) => {
      requireCaptured(supplied);
      const identity = await rpc("admin_portal_request", {
        action: "identity",
        payload: {},
      });
      if (
        !identity || typeof identity.id !== "string" ||
        !["Admin", "Owner"].includes(identity.role) ||
        (identity.portalRole !== undefined && (identity.role === "Owner"
          ? identity.portalRole !== "Owner" : !["Manager", "Maintenance"].includes(identity.portalRole)))
      ) {
        throw new PortalError(
          "Staff identity is unavailable.",
          503,
          "admin_unavailable",
        );
      }
      portalRole = identity.portalRole ?? (identity.role === "Owner" ? "Owner" : "Manager");
      return identity.id;
    },
    rpc: (_actor, action, payload) => {
      authorize(action, payload);
      return rpc("admin_portal_request", { action, payload });
    },
    invite: (actor, email, locationIds, role = "Manager") => {
      authorize("invite"); return sendTeamInvitation(actor, { email, locationIds, portalRole: role }, config, rpc);
    },
    resend: (actor, userId, locationId) => {
      authorize("resend"); return sendTeamInvitation(actor, { userId, locationId }, config, rpc);
    },
    resolve: async (supplied, id, decision, note) => {
      requireCaptured(supplied);
      authorize("resolveCredit");
      return await rpc("admin_resolve_credit", {
        target_refund_id: id,
        target_decision: decision,
        resolution_note: note,
      });
    },
  };
}
export function createCreditDependencies(
  token: string,
  config: PortalConfig,
): RefundResolutionDependencies {
  let portal: PortalDependencies | undefined;
  const getPortal = () => portal ??= createPortalDependencies(token, config);
  const guarded = async <T>(operation: () => Promise<T>): Promise<T> => {
    try {
      return await operation();
    } catch (error) {
      if (error instanceof PortalError) {
        throw new RefundHttpError(error.status, error.message);
      }
      throw new RefundHttpError(
        503,
        "The credit service is temporarily unavailable.",
      );
    }
  };
  return {
    authenticate: () => guarded(() => getPortal().authenticate(token)),
    resolve: ({ refundId, decision, note }) =>
      guarded(async () =>
        await getPortal().resolve(
          token,
          refundId,
          decision,
          note,
        ) as RefundResolution
      ),
  };
}
