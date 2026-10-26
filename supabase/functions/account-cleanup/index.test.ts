import { strict as assert } from "node:assert";
import { handler } from "./index.ts";

const names = ["ACCOUNT_CLEANUP_ENABLED", "ACCOUNT_CLEANUP_WORKER_SECRET", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
const secret = "synthetic-worker-secret-for-offline-tests-only";
const request = () => new Request("https://offline.invalid/account-cleanup", {
  method: "POST", headers: { "X-Account-Cleanup-Secret": secret },
  body: JSON.stringify({ action: "preview", limit: 25, after_user_id: null }),
});
async function fixture(action: (calls: Request[]) => Promise<void>, status = 200) {
  const saved = names.map((name) => Deno.env.get(name));
  const originalFetch = globalThis.fetch;
  const calls: Request[] = [];
  try {
    Deno.env.set(names[0], "true");
    Deno.env.set(names[1], secret);
    Deno.env.set(names[2], "https://offline.invalid");
    Deno.env.set(names[3], "synthetic-server-key");
    globalThis.fetch = (input, init) => {
      calls.push(new Request(input, init));
      return Promise.resolve(Response.json(status === 200
        ? { execution_enabled: false, candidates: [], next_cursor: null }
        : { message: "private failure" }, { status }));
    };
    await action(calls);
  } finally {
    globalThis.fetch = originalFetch;
    names.forEach((name, i) => saved[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, saved[i]!));
  }
}

Deno.test("adapter defaults off and ignores truthy non-exact flags before any fetch", () => fixture(async (calls) => {
  for (const value of [undefined, "1", "TRUE", "false", " true "]) {
    if (value === undefined) Deno.env.delete(names[0]); else Deno.env.set(names[0], value);
    assert.equal((await handler(request())).status, 503);
  }
  assert.equal(calls.length, 0);
}));
Deno.test("adapter makes one bounded RPC call, not Auth or a provider call", () => fixture(async (calls) => {
  assert.equal((await handler(request())).status, 200);
  assert.equal(calls.length, 1);
  const call = calls[0];
  assert.equal(call.url, "https://offline.invalid/rest/v1/rpc/preview_account_cleanup");
  assert.equal(call.method, "POST");
  assert.equal(call.headers.get("apikey"), "synthetic-server-key");
  assert.equal(call.headers.get("Authorization"), "Bearer synthetic-server-key");
  assert.deepEqual(await call.json(), { p_limit: 25, p_after_user_id: null });
}));
Deno.test("server key missing fails closed without fetching", () => fixture(async (calls) => {
  Deno.env.delete(names[3]);
  assert.equal((await handler(request())).status, 503);
  assert.equal(calls.length, 0);
}));
Deno.test("RPC non-success is sanitized and dispatched once", () => fixture(async (calls) => {
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.equal((await response.text()).includes("private failure"), false);
  assert.equal(calls.length, 1);
}, 500));
Deno.test("enabled run is still unsupported and makes no claim/Auth/provider request", () => fixture(async (calls) => {
  const response = await handler(new Request("https://offline.invalid/account-cleanup", {
    method: "POST", headers: { "X-Account-Cleanup-Secret": secret },
    body: JSON.stringify({ action: "run" }),
  }));
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "cleanup_policy_unapproved", execution_enabled: false });
  assert.equal(calls.length, 0);
}));
