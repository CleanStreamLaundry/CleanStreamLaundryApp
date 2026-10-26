import {
  databaseRpc,
  deliverOne,
  Env,
  equalSecret,
  json,
  mailConfig,
  Rpc,
} from "../_shared/mail.ts";

export function deliveryHandler(
  env: Env,
  rpc: Rpc = databaseRpc(env),
  transport: typeof fetch = fetch,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const secret = env("CLEANSTREAM_MAIL_WORKER_SECRET") || "";
    if (
      secret.length < 32 ||
      !await equalSecret(
        request.headers.get("Authorization") || "",
        `Bearer ${secret}`,
      )
    ) return json({ error: "unauthorized" }, 401);
    const config = mailConfig(env);
    if (!config) return json({ error: "mail_disabled" }, 503);
    try {
      return json({ state: await deliverOne(rpc, config, transport) });
    } catch {
      return json({ error: "delivery_outcome_unknown" }, 503);
    }
  };
}
if (import.meta.main) Deno.serve(deliveryHandler((name) => Deno.env.get(name)));
