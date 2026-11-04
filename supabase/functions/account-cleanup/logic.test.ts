import { strict as assert } from "node:assert";
import { handleAccountCleanup, type CleanupDeps } from "./logic.ts";

const user = "00000000-0000-4000-8000-000000000001";
const requested = "2026-08-01T00:00:00.123456Z";
const secret = "synthetic-worker-secret-for-offline-tests-only";
const preview = { action: "preview", limit: 25, after_user_id: null };
const empty = { execution_enabled: false, candidates: [], next_cursor: null };
const candidate = { user_id: user, deletion_requested_at: requested,
  restore_until: "2026-08-31T00:00:00.123456Z", blocker: null, eligible_to_claim: true };
const request = (body: unknown = preview, auth = secret) =>
  new Request("https://offline.invalid/account-cleanup", {
    method: "POST", headers: { "X-Account-Cleanup-Secret": auth }, body: JSON.stringify(body),
  });
function setup(data: unknown = empty, extra: Partial<CleanupDeps> = {}) {
  const calls: unknown[] = [];
  const deps: CleanupDeps = { enabled: true, workerSecret: secret,
    rpc(name, args) { calls.push({ name, args }); return Promise.resolve(data); }, ...extra };
  return { calls, deps };
}

for (const extra of [{ enabled: false }, { workerSecret: undefined }, { workerSecret: "short" }]) {
  Deno.test(`disabled gate makes zero calls: ${JSON.stringify(extra)}`, async () => {
    const { deps, calls } = setup(empty, extra);
    assert.equal((await handleAccountCleanup(request(), deps)).status, 503);
    assert.equal(calls.length, 0);
  });
}
for (const method of ["GET", "OPTIONS", "DELETE"]) {
  Deno.test(`${method} is closed without CORS or RPC`, async () => {
    const { deps, calls } = setup();
    const response = await handleAccountCleanup(new Request("https://offline.invalid", { method }), deps);
    assert.equal(response.status, 405);
    assert.equal(response.headers.get("Access-Control-Allow-Origin"), null);
    assert.equal(calls.length, 0);
  });
}
for (const auth of ["", "Bearer wrong-secret", "Bearer eyJhbGciOiJIUzI1NiJ9.user.jwt", "Basic secret", `Bearer ${secret} extra`]) {
  Deno.test(`rejects non-worker credential ${auth.slice(0, 20)}`, async () => {
    const { deps, calls } = setup();
    assert.equal((await handleAccountCleanup(request(preview, auth), deps)).status, 401);
    assert.equal(calls.length, 0);
  });
}
for (const body of [null, [], {}, { ...preview, limit: 0 }, { ...preview, limit: 101 },
  { ...preview, limit: 1.5 }, { ...preview, extra: true }, { ...preview, after_user_id: "bad" },
  { action: "claim" }, { action: "retry" }, { action: "purge" }, { action: "complete" },
  { action: "run", policy: "caller-says-approved" }]) {
  Deno.test(`invalid payload ${JSON.stringify(body)}`, async () => {
    const { deps, calls } = setup();
    assert.equal((await handleAccountCleanup(request(body), deps)).status, 400);
    assert.equal(calls.length, 0);
  });
}
Deno.test("bounded raw body, including absent Content-Length", async () => {
  const { deps, calls } = setup();
  const response = await handleAccountCleanup(new Request("https://offline.invalid", {
    method: "POST", headers: { "X-Account-Cleanup-Secret": secret }, body: " ".repeat(2049),
  }), deps);
  assert.equal(response.status, 413);
  assert.equal(calls.length, 0);
});
Deno.test("malformed JSON makes no RPC", async () => {
  const { deps, calls } = setup();
  const response = await handleAccountCleanup(new Request("https://offline.invalid", {
    method: "POST", headers: { "X-Account-Cleanup-Secret": secret }, body: "{",
  }), deps);
  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
});
for (const data of [empty, { ...empty, candidates: [candidate] }]) {
  Deno.test(`preview dispatches once and preserves exact timestamps (${data.candidates.length} candidates)`, async () => {
    const { deps, calls } = setup(data);
    const response = await handleAccountCleanup(request(), deps);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.deepEqual(await response.json(), { execution_enabled: false, data });
    assert.deepEqual(calls, [{ name: "preview_account_cleanup", args: { p_limit: 25, p_after_user_id: null } }]);
  });
}
for (const data of [{}, { execution_enabled: true, candidates: [], next_cursor: null },
  { ...empty, secret: "leak" }, null, []]) {
  Deno.test(`bad RPC response is sanitized: ${JSON.stringify(data)}`, async () => {
    const { deps, calls } = setup(data);
    const response = await handleAccountCleanup(request(), deps);
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: "cleanup_preview_unavailable", automatic_retry: false });
    assert.equal(calls.length, 1);
  });
}
Deno.test("malformed preview candidates do not escape validation", async () => {
  for (const c of [{ ...candidate, user_id: "bad" },
    { ...candidate, deletion_requested_at: "2026-02-30T00:00:00Z" },
    { ...candidate, restore_until: "2026-08-31T00:00:00-04:00" },
    { ...candidate, blocker: "purged" }]) {
    const { deps } = setup({ ...empty, candidates: [c] });
    assert.equal((await handleAccountCleanup(request(), deps)).status, 503);
  }
});
Deno.test("lost preview response is sanitized and never retried", async () => {
  let attempts = 0;
  const { deps } = setup(empty, { rpc() { attempts++; throw new Error("private provider error"); } });
  const response = await handleAccountCleanup(request(), deps);
  assert.equal(response.status, 503);
  assert.equal((await response.text()).includes("private"), false);
  assert.equal(attempts, 1);
});
Deno.test("run rejects unapproved policy in server code even with the environment gate enabled", async () => {
  const { deps, calls } = setup();
  const response = await handleAccountCleanup(request({ action: "run" }), deps);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "cleanup_policy_unapproved", execution_enabled: false });
  assert.deepEqual(calls, []);
});
Deno.test("a user or service Authorization header alone cannot invoke cleanup", async () => {
  const { deps, calls } = setup();
  const response = await handleAccountCleanup(new Request("https://offline.invalid", {
    method: "POST", headers: { Authorization: `Bearer ${secret}` }, body: JSON.stringify(preview),
  }), deps);
  assert.equal(response.status, 401);
  assert.equal(calls.length, 0);
});
