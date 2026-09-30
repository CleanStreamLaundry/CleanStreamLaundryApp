import { createClient } from "https://esm.sh/@supabase/supabase-js@2.99.3";
import { type PortalDependencies, PortalError } from "./logic.ts";
import {
  RefundHttpError,
  type RefundResolution,
  type RefundResolutionDependencies,
} from "../_shared/refund_resolution.ts";

export interface PortalConfig {
  url: string;
  anonKey: string;
  fetch?: typeof fetch;
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
  const rpc = async (name: string, args: Record<string, unknown>) => {
    requireCaptured(token);
    const { data, error, status } = await caller.rpc(name, args);
    if (error) throw rpcError(error, status);
    return data;
  };
  const disabled = () => {
    throw new PortalError(
      "Team invitations are not enabled yet.",
      503,
      "admin_onboarding_disabled",
    );
  };
  return {
    authenticate: async (supplied) => {
      requireCaptured(supplied);
      const identity = await rpc("admin_portal_request", {
        action: "identity",
        payload: {},
      });
      if (
        !identity || typeof identity.id !== "string" ||
        !["Admin", "Owner"].includes(identity.role)
      ) {
        throw new PortalError(
          "Staff identity is unavailable.",
          503,
          "admin_unavailable",
        );
      }
      return identity.id;
    },
    rpc: (_actor, action, payload) =>
      rpc("admin_portal_request", { action, payload }),
    invite: disabled,
    resend: disabled,
    resolve: async (supplied, id, decision, note) => {
      requireCaptured(supplied);
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
  const portal = createPortalDependencies(token, config);
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
    authenticate: () => guarded(() => portal.authenticate(token)),
    resolve: ({ refundId, decision, note }) =>
      guarded(async () =>
        await portal.resolve(
          token,
          refundId,
          decision,
          note,
        ) as RefundResolution
      ),
    notify: () =>
      Promise.reject(
        new Error(
          "Customer email is not enabled. The credit decision is saved.",
        ),
      ),
    markNotificationSent: () =>
      Promise.reject(new Error("Customer email is not enabled.")),
  };
}
