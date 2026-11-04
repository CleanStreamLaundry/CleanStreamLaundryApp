import { assertEquals } from "https://deno.land/std@0.182.0/testing/asserts.ts";
import { handler } from "./index.ts";

Deno.test("actual adapter uses anon key + captured bearer, no target RPC params or hard deletion", async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = Deno.env.get;
  const calls: {
    url: string;
    method: string;
    auth: string | null;
    key: string | null;
    body: string;
  }[] = [];
  const values: Record<string, string> = {
    SUPABASE_URL: "https://offline.invalid",
    SUPABASE_ANON_KEY: "synthetic-public-key",
  };
  Deno.env.get = (name) => values[name];
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    calls.push({
      url: req.url,
      method: req.method,
      auth: req.headers.get("Authorization"),
      key: req.headers.get("apikey"),
      body: await req.text(),
    });
    if (req.url.endsWith("/auth/v1/user")) {
      return Response.json({ id: "caller" });
    }
    if (req.url.endsWith("/rest/v1/rpc/request_account_deletion")) {
      return Response.json({
        subject_id: "caller",
        account_access: "restricted",
        next_step: "blocked",
        reason: "explicit_restore_required",
        account_state: "pending_deletion",
        restore_until: "2026-10-30T00:00:00Z",
      });
    }
    throw new Error(`Unexpected offline request: ${req.method} ${req.url}`);
  };
  try {
    const response = await handler(
      new Request("https://offline.invalid/delete-account", {
        method: "POST",
        headers: { Authorization: "Bearer captured-token" },
        body: JSON.stringify({ user_id: "caller" }),
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(calls.map(({ url, method }) => [url, method]), [
      ["https://offline.invalid/auth/v1/user", "GET"],
      ["https://offline.invalid/rest/v1/rpc/request_account_deletion", "POST"],
    ]);
    for (const call of calls) {
      assertEquals(call.auth, "Bearer captured-token");
      assertEquals(call.key, "synthetic-public-key");
    }
    assertEquals(calls[1].body, "{}");
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalEnv;
  }
});
