import { handleAccountCleanup } from "./logic.ts";
import { executeAccountCleanup } from "./execution.ts";
import { selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";

// Shared only within this worker: the same named-key contract now serves RPC,
// exact-version Storage deletion and the supported Auth admin DELETE endpoint.
async function request(path: string, body: unknown, method = "POST") {
  const url = Deno.env.get("SUPABASE_URL");
  const keyName = Deno.env.get("CLEANSTREAM_CLEANUP_SECRET_KEY_NAME");
  const key = keyName === undefined ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    : selectNamedSupabaseKey(keyName, Deno.env.get("SUPABASE_SECRET_KEYS"), "secret");
  if (!url || !key) throw new Error("Missing server configuration");
  const headers = new Headers({ apikey: key, "Content-Type": "application/json" });
  if (keyName === undefined) headers.set("Authorization", `Bearer ${key}`);
  const response = await fetch(`${url.replace(/\/$/, "")}${path}`, {
    method, headers, body: JSON.stringify(body), signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error("Cleanup service unavailable");
  }
  return response;
}

const rpc = async (name: string, args: Record<string, unknown>) =>
  await (await request(`/rest/v1/rpc/${name}`, args)).json();

export const handler = (req: Request) => handleAccountCleanup(req, {
  enabled: Deno.env.get("ACCOUNT_CLEANUP_ENABLED") === "true",
  workerSecret: Deno.env.get("ACCOUNT_CLEANUP_WORKER_SECRET"),
  execution: {
    executionEnabled: Deno.env.get("ACCOUNT_CLEANUP_EXECUTION_ENABLED") === "true",
    policyVersion: Deno.env.get("ACCOUNT_CLEANUP_POLICY_VERSION"),
    policySha256: Deno.env.get("ACCOUNT_CLEANUP_POLICY_SHA256"),
  },
  rpc,
  run: () => executeAccountCleanup({
    rpc,
    async removeStorageVersions(objects) {
      // Supported version-addressed transport; do not fall back to path-only
      // deletion or upgrade/cast the older installed storage-js SDK.
      const response = await request("/storage/v1/object/maintenance-images", {
        prefixes: objects.map((o) => ({ path: o.name, versionId: o.version })),
      }, "DELETE");
      await response.body?.cancel();
    },
    async deleteAuthUser(userId) {
      const response = await request(`/auth/v1/admin/users/${encodeURIComponent(userId)}`,
        { should_soft_delete: false }, "DELETE");
      await response.body?.cancel();
    },
  }),
});

if (import.meta.main) Deno.serve(handler);
