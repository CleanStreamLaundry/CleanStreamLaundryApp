import {
  capturedBearer,
  createPortalDependencies,
  type PortalConfig,
} from "./backend.ts";
import { dispatchPortal, PortalError } from "./logic.ts";
import { creditNotificationSummary } from "../_shared/refund_resolution.ts";

export async function handlePortal(
  request: Request,
  config: PortalConfig,
  origin: string,
): Promise<Response> {
  const cors = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
  const response = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") return response({ error: "Use POST." }, 405);
  const token = capturedBearer(request);
  try {
    if (!token) {
      throw new PortalError(
        "Sign in to continue.",
        401,
        "session_invalid",
        "sign_in",
      );
    }
    if (Number(request.headers.get("content-length") || 0) > 32000) {
      throw new PortalError("Request too large.", 413);
    }
    const raw = await request.text();
    if (raw.length > 32000) throw new PortalError("Request too large.", 413);
    const body = JSON.parse(raw);
    if (!body || Array.isArray(body) || typeof body !== "object") {
      throw new PortalError("Invalid request.");
    }
    const result = await dispatchPortal(
      token,
      body,
      createPortalDependencies(token, config),
    );
    if (body.action === "resolveCredit") {
      const credit = result as {
        success?: boolean;
        status?: string;
        notificationSent?: boolean;
        notificationState?: string;
      };
      if (credit?.success !== true || credit.status !== body.decision) {
        throw new PortalError(
          "The credit outcome is unavailable. Refresh before retrying.",
          503,
          "admin_unavailable",
        );
      }
      const { notificationWarning } = creditNotificationSummary(credit);
      return response({
        success: true,
        ...(notificationWarning ? { notificationWarning } : {}),
      });
    }
    return response(result);
  } catch (error) {
    if (error instanceof SyntaxError) {
      return response({
        error: "Invalid request JSON.",
        code: "invalid_request",
      }, 400);
    }
    const failure = error instanceof PortalError ? error : new PortalError(
      "The admin service could not complete this request.",
      503,
      "admin_unavailable",
    );
    return response({
      error: failure.message,
      code: failure.code,
      ...(failure.nextStep ? { next_step: failure.nextStep } : {}),
    }, failure.status);
  }
}
