import assert from "node:assert/strict";
import { CortinaDeps, HttpError, sha256 } from "../_shared/cortina.ts";
import { handleCortinaVend } from "./logic.ts";
import { handler } from "./index.ts";

const sessionId = "00000000-0000-4000-8000-000000000001";
const requestId = "ABCDEF00-0000-4000-8000-000000000002";
const owner = "00000000-0000-4000-8000-000000000003";
const request = (route: string, body: unknown, authorization?: string) => new Request(
  "https://edge.synthetic.invalid/cortina-vend/" + route,
  { method: "POST", body: JSON.stringify(body), headers: authorization ? { Authorization: authorization } : {} },
);

function forbiddenDeps() {
  const effects: string[] = [];
  const deps = new Proxy({}, { get(_target, key) {
    effects.push(String(key));
    throw new Error("Unexpected financial or database dependency");
  } }) as CortinaDeps;
  return { deps, effects };
}

function errorIs(status: number, code: string) {
  return (error: unknown) => {
    assert(error instanceof HttpError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  };
}

for (const route of ["quote", "card", "wallet", "confirm", "status"]) {
  Deno.test("bounded " + route + " refuses oversized public input before any dependency", async () => {
    const f = forbiddenDeps();
    await assert.rejects(() => handleCortinaVend(request(route, { padding: "x".repeat(8192) }), f.deps),
      errorIs(413, "body_too_large"));
    assert.deepEqual(f.effects, []);
  });
}

for (const route of ["confirm", "status"]) {
  Deno.test("bounded " + route + " rejects malformed credentials without hash lookup or provider work", async () => {
    const f = forbiddenDeps();
    for (const body of [{ sessionId, accessToken: "x".repeat(129) },
      { sessionId: "malformed", accessToken: requestId }, { sessionId, accessToken: "a\nb" }]) {
      await assert.rejects(() => handleCortinaVend(request(route, body), f.deps), errorIs(400, "invalid_session_credentials"));
    }
    assert.deepEqual(f.effects, []);
  });
}

function readOnlyDeps(row: Record<string, unknown> | null) {
  const filters: Array<[string, unknown]> = [];
  const auth: string[] = [];
  let reads = 0;
  const query = {
    select: (_columns: string) => query,
    eq: (key: string, value: unknown) => { filters.push([key, value]); return query; },
    maybeSingle: () => Promise.resolve({ data: row, error: null }),
    single: () => Promise.resolve({ data: row, error: null }),
  };
  const deps = {
    admin: {
      from(table: string) { assert.equal(table, "cortina_vend_sessions"); reads++; return query; },
      auth: { getUser(token: string) { auth.push(token); return Promise.resolve({ data: { user: { id: owner, is_anonymous: false } }, error: null }); } },
    },
    get stripe(): never { throw new Error("Provider must not be used"); },
    get fetcher(): never { throw new Error("Start must not be used"); },
  } as unknown as CortinaDeps;
  return { deps, filters, auth, reads: () => reads };
}

Deno.test("confirm retains exact id AND capability hash lookup and generic missing response", async () => {
  const f = readOnlyDeps(null);
  await assert.rejects(() => handleCortinaVend(request("confirm", { sessionId, accessToken: requestId }), f.deps),
    errorIs(404, "session_not_found"));
  assert.deepEqual(f.filters, [["id", sessionId], ["client_access_token_hash", await sha256(requestId)]]);
  assert.equal(f.reads(), 1);
});

Deno.test("existing confirmed card cannot be re-confirmed or re-started", async () => {
  const f = readOnlyDeps({ id: sessionId, status: "started", payment_method: "card", stripe_payment_intent_id: "pi_synthetic" });
  const result = await handleCortinaVend(request("confirm", { sessionId, accessToken: requestId }), f.deps);
  assert.deepEqual(await result.json(), { status: "started" });
  assert.equal(f.reads(), 1);
});

Deno.test("confirmed status remains a read with an opaque historical capability", async () => {
  const row = { id: sessionId, status: "refunded", created_at: "2000-01-01T00:00:00Z" };
  const f = readOnlyDeps(row);
  const result = await handleCortinaVend(request("status", { sessionId, accessToken: "historical-token" }), f.deps);
  assert.deepEqual(await result.json(), row);
  assert.deepEqual(f.filters, [["id", sessionId], ["client_access_token_hash", await sha256("historical-token")], ["id", sessionId]]);
  assert.equal(f.reads(), 2);
});

Deno.test("bounded body preserves authenticated owner recovery before credential or settlement path", async () => {
  const hash = await sha256(requestId);
  const f = readOnlyDeps({ id: sessionId, user_id: owner, machine_id: 7,
    client_request_id: requestId.toLowerCase(), client_access_token_hash: hash });
  const result = await handleCortinaVend(request("status", { clientRequestId: requestId, machineId: 7 }, "Bearer original-owner"), f.deps);
  assert.deepEqual(await result.json(), { sessionId, accessToken: requestId });
  assert.deepEqual(f.auth, ["original-owner"]);
  assert.deepEqual(f.filters, [["user_id", owner], ["machine_id", 7], ["client_request_id", requestId], ["client_access_token_hash", hash]]);
  assert.equal(f.reads(), 1);
});

Deno.test("guest missing-reference recovery still denies access without database or provider effects", async () => {
  const f = forbiddenDeps();
  await assert.rejects(() => handleCortinaVend(request("status", { clientRequestId: requestId, machineId: 7 }), f.deps),
    errorIs(401, "authentication_required"));
  assert.deepEqual(f.effects, []);
});

async function entryFixture(action: (logs: unknown[][]) => Promise<void>, failFactory = false) {
  const env = Deno.env.get, fetcher = globalThis.fetch, log = console.error;
  const values: Record<string, string> = { SUPABASE_URL: "https://supabase.synthetic.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-legacy-key", STRIPE_SECRET_KEY: "sk_test_synthetic_only" };
  const logs: unknown[][] = [];
  try {
    Deno.env.get = (key) => {
      if (failFactory && key === "STRIPE_SECRET_KEY") throw new Error(requestId);
      return values[key];
    };
    globalThis.fetch = () => { throw new Error("Network is forbidden"); };
    console.error = (...args) => { logs.push(args); };
    await action(logs);
  } finally { Deno.env.get = env; globalThis.fetch = fetcher; console.error = log; }
}

Deno.test("entrypoint never logs a capability-bearing server exception or reflects it", async () => {
  await entryFixture(async (logs) => {
    const result = await handler(request("quote", {}));
    assert.equal(result.status, 500);
    assert.deepEqual(await result.json(), { error: "Cortina request unavailable", code: "internal_error" });
    assert.deepEqual(logs, [["cortina-vend request failed", 500]]);
    assert.equal(result.headers.get("cache-control"), "no-store");
  }, true);
});

Deno.test("entrypoint bounded rejection preserves HTTP status and disables caching", async () => {
  await entryFixture(async (logs) => {
    const result = await handler(request("card", { accessToken: requestId, padding: "x".repeat(8192) }));
    assert.equal(result.status, 413);
    assert.deepEqual(await result.json(), { error: "Request body is too large", code: "body_too_large" });
    assert.deepEqual(logs, [["cortina-vend request failed", 413]]);
    assert.equal(result.headers.get("cache-control"), "no-store");
    assert.equal(result.headers.get("referrer-policy"), "no-referrer");
  });
});
