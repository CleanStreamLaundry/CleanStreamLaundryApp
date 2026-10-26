import {
  databaseRpc,
  Env,
  json,
  mailConfig,
  MailError,
  newsletterAvailable,
  newsletterPage,
  NewsletterStatus,
  readBounded,
  Rpc,
  sha256,
} from "../_shared/mail.ts";

export function newsletterHandler(env: Env, rpc: Rpc = databaseRpc(env)) {
  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get("Origin");
    const allowed = (env("CLEANSTREAM_MAIL_CORS_ORIGINS") || "").split(",")
      .filter(Boolean);
    if (
      origin && origin !== new URL(request.url).origin &&
      !allowed.includes(origin)
    ) return json({ error: "origin_denied" }, 403);
    const cors: Record<string, string> = origin
      ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" }
      : {};
    if (request.method === "OPTIONS") {
      return json({}, 200, {
        ...cors,
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers":
          "authorization, apikey, content-type, x-client-info",
      });
    }
    try {
      const statusResponse = (status: NewsletterStatus) =>
        json({
          ...status,
          enabled: status.enabled === true &&
            newsletterAvailable(mailConfig(env)),
        }, 200, cors);
      const url = new URL(request.url);
      if (request.method === "GET") {
        const action = url.searchParams.get("action"),
          token = url.searchParams.get("token");
        if (
          !["confirm", "unsubscribe"].includes(action || "") ||
          !/^[0-9a-f]{64}$/.test(token || "")
        ) return json({ error: "token_invalid" }, 400, cors);
        const page = newsletterPage(env);
        if (!page) {
          return json({ error: "newsletter_page_unavailable" }, 503, cors);
        }
        // GET never consumes tokens: mail scanners cannot subscribe a recipient.
        return new Response(null, {
          status: 303,
          headers: {
            Location: `${page}#action=${action}&token=${token}`,
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
          },
        });
      }
      if (request.method !== "POST") {
        return json({ error: "method_not_allowed" }, 405, cors);
      }
      const raw = await readBounded(request, 2048);
      let body: Record<string, unknown>;
      const form = request.headers.get("content-type")?.startsWith(
        "application/x-www-form-urlencoded",
      );
      try {
        body = form
          ? Object.fromEntries(new URLSearchParams(raw))
          : JSON.parse(raw);
      } catch {
        return json({ error: "invalid_body" }, 400, cors);
      }
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        return json({ error: "invalid_body" }, 400, cors);
      }
      // Mailbox-provider forms can withdraw only, never grant consent.
      if (
        form && (body["List-Unsubscribe"] !== "One-Click" ||
          url.searchParams.get("action") !== "unsubscribe" ||
          Object.keys(body).length !== 1)
      ) return json({ error: "invalid_body" }, 400, cors);
      const action = form && body["List-Unsubscribe"] === "One-Click"
        ? url.searchParams.get("action")
        : body.action;
      const capability = form && body["List-Unsubscribe"] === "One-Click"
        ? url.searchParams.get("token")
        : body.token;
      if (action === "confirm" || action === "unsubscribe") {
        if (
          typeof capability !== "string" || !/^[0-9a-f]{64}$/.test(capability)
        ) return json({ error: "token_invalid" }, 400, cors);
        const result = await rpc("newsletter_token", {
          p_action: action,
          p_hash: await sha256(capability),
        });
        return json(result, 200, cors);
      }
      const bearer = request.headers.get("Authorization") || "";
      if (!/^Bearer \S+$/i.test(bearer)) {
        return json({ error: "session_required" }, 401, cors);
      }
      if (action === "status") {
        return statusResponse(
          await rpc<NewsletterStatus>("newsletter_status", {}, bearer),
        );
      }
      if (action === "withdraw" && Object.keys(body).length === 1) {
        return statusResponse(
          await rpc<NewsletterStatus>("newsletter_withdraw", {}, bearer),
        );
      }
      if (
        action !== "request" || typeof body.opt_in !== "boolean" ||
        typeof body.version !== "string" ||
        !["signup", "settings"].includes(String(body.source)) ||
        Object.keys(body).some((k) =>
          !["action", "opt_in", "version", "source"].includes(k)
        )
      ) {
        return json({ error: "consent_invalid" }, 400, cors);
      }
      if (body.opt_in && !newsletterAvailable(mailConfig(env))) {
        return json({ error: "mail_disabled" }, 503, cors);
      }
      return statusResponse(
        await rpc<NewsletterStatus>("newsletter_request", {
          p_opt_in: body.opt_in,
          p_version: body.version,
          p_source: body.source,
        }, bearer),
      );
    } catch (error) {
      return json(
        {
          error: error instanceof MailError
            ? error.message
            : "mail_unavailable",
        },
        error instanceof MailError ? error.status : 503,
        cors,
      );
    }
  };
}
if (import.meta.main) {
  Deno.serve(newsletterHandler((name) => Deno.env.get(name)));
}
