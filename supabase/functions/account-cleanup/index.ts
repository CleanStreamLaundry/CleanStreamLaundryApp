import { handleAccountCleanup } from "./logic.ts";
import { selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";

export const handler = (req: Request) =>
  handleAccountCleanup(req, {
    enabled: Deno.env.get("ACCOUNT_CLEANUP_ENABLED") === "true",
    workerSecret: Deno.env.get("ACCOUNT_CLEANUP_WORKER_SECRET"),
    async rpc(name, args) {
      const url = Deno.env.get("SUPABASE_URL");
      const keyName = Deno.env.get("CLEANSTREAM_CLEANUP_SECRET_KEY_NAME");
      const key = keyName === undefined
        ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
        : selectNamedSupabaseKey(
          keyName,
          Deno.env.get("SUPABASE_SECRET_KEYS"),
          "secret",
        );
      if (!url || !key) throw new Error("Missing server configuration");
      const headers = new Headers({
        apikey: key,
        "Content-Type": "application/json",
      });
      // Modern secret keys belong only in apikey, not a JWT bearer header.
      if (keyName === undefined) headers.set("Authorization", `Bearer ${key}`);
      const response = await fetch(
        `${url.replace(/\/$/, "")}/rest/v1/rpc/${name}`,
        {
          method: "POST",
          headers,
          body: JSON.stringify(args),
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!response.ok) throw new Error("Cleanup RPC unavailable");
      return await response.json();
    },
  });

if (import.meta.main) Deno.serve(handler);
