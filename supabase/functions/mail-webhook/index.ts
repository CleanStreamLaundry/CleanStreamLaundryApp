import {
  databaseRpc,
  Env,
  json,
  MailError,
  readBounded,
  Rpc,
  verifyWebhook,
} from "../_shared/mail.ts";

export function webhookHandler(
  env: Env,
  rpc: Rpc = databaseRpc(env),
  now: () => number = Date.now,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const secret = env("CLEANSTREAM_RESEND_WEBHOOK_SECRET");
    if (!secret) return json({ error: "webhook_disabled" }, 503);
    try {
      const raw = await readBounded(request, 32768);
      await verifyWebhook(raw, request.headers, secret, now());
      let event;
      try {
        event = JSON.parse(raw);
      } catch {
        return json({ error: "event_invalid" }, 400);
      }
      if (
        !event || typeof event !== "object" || typeof event.type !== "string"
      ) {
        return json({ error: "event_invalid" }, 400);
      }
      if (
        ![
          "email.sent",
          "email.delivered",
          "email.bounced",
          "email.complained",
          "email.failed",
          "email.suppressed",
        ].includes(event.type)
      ) return json({ received: true });
      const data = event.data;
      const tags = data?.tags;
      const outboxId = Array.isArray(tags)
        ? tags.find((t) => t?.name === "outbox_id")?.value
        : tags?.outbox_id;
      if (
        typeof data?.email_id !== "string" || !data.email_id ||
        data.email_id.length > 200 ||
        !Array.isArray(data.to) ||
        data.to.length !== 1 || typeof data.to[0] !== "string" ||
        !data.to[0] || data.to[0].length > 320 ||
        (outboxId != null &&
          (typeof outboxId !== "string" ||
            !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
              .test(outboxId)))
      ) {
        return json({ error: "event_invalid" }, 400);
      }
      await rpc("mail_record_webhook", {
        p_event_id: request.headers.get("svix-id"),
        p_provider_id: data.email_id,
        p_type: event.type,
        p_outbox_id: outboxId || null,
        p_email: data.to[0],
      });
      return json({ received: true });
    } catch (error) {
      return json({
        error: error instanceof MailError
          ? error.message
          : "webhook_unavailable",
      }, error instanceof MailError ? error.status : 503);
    }
  };
}
if (import.meta.main) Deno.serve(webhookHandler((name) => Deno.env.get(name)));
