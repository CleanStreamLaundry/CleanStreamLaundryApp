import {
  databaseRpc,
  type Env,
  json,
  MailError,
  readBounded,
  type Rpc,
} from "../_shared/mail.ts";
import { handleRefundRequest } from "./logic.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

export function refundNoticeHandler(env: Env, rpc: Rpc = databaseRpc(env)) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return json({}, 200, cors);
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405, cors);
    }
    const bearer = request.headers.get("Authorization") || "";
    if (!/^Bearer \S+$/i.test(bearer)) {
      return json({ error: "session_required" }, 401, cors);
    }
    try {
      const raw = await readBounded(request, 8192);
      let body: unknown;
      try {
        body = JSON.parse(raw);
      } catch {
        return json({ error: "invalid_body" }, 400, cors);
      }
      const result = await handleRefundRequest(body, {
        enqueueNotice: (transactionId) =>
          rpc("enqueue_refund_request_notice", {
            target_transaction_id: transactionId,
          }, bearer),
      });
      return json(result.body, result.status, cors);
    } catch (error) {
      return json(
        {
          error: error instanceof MailError
            ? error.message
            : "notification_unavailable",
          notificationWarning:
            "Notification could not be confirmed. Do not submit another claim to retry notification.",
        },
        error instanceof MailError ? error.status : 503,
        cors,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(refundNoticeHandler((name) => Deno.env.get(name)));
}
