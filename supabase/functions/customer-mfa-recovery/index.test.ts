import assert from "node:assert/strict";
import { handler } from "./index.ts";

const target = "00000000-0000-4000-8000-000000000003";
const recovery = "00000000-0000-4000-8000-000000000030";
const factor = "00000000-0000-4000-8000-000000000023";
const other = "00000000-0000-4000-8000-000000000024";
const secret = "sb_secret_recovery_only";
const values = (): Record<string, string | undefined> => ({
  SUPABASE_URL: "https://recovery.synthetic.invalid", SUPABASE_ANON_KEY: "synthetic-public",
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-legacy", CLEANSTREAM_MFA_RECOVERY_SECRET_KEY_NAME: "recovery",
  SUPABASE_SECRET_KEYS: JSON.stringify({ recovery: secret, default: "sb_secret_wrong" }),
});
const body = () => ({ action: "recover", target_user_id: target, support_case: "SUPPORT-123", identity_verified: true });
const request = (payload: unknown = body(), headers: HeadersInit = { Authorization: "Bearer original-owner" }, method = "POST") =>
  new Request("https://edge.synthetic.invalid/customer-mfa-recovery", {
    method, headers, ...(method === "POST" ? { body: JSON.stringify(payload) } : {}),
  });
const result = (ids = [factor]) => ({ target_user_id: target, recovery_id: recovery,
  support_case: "SUPPORT-123", reenrollment_required: true, remaining_factor_ids: ids,
  state: ids.length ? "removal_pending" : "reenrollment_required" });
type Options = {
  env?: Record<string, string | undefined>; replies?: unknown[];
  denyAt?: number; code?: string; message?: string; deleteError?: boolean;
  rpcTimeout?: boolean; deleteTimeout?: boolean;
};
async function fixture(action: (calls: Request[]) => Promise<void>, options: Options = {}) {
  const savedFetch = globalThis.fetch, savedEnv = Deno.env.get;
  const calls: Request[] = []; let rpcCount = 0;
  try {
    const config = options.env ?? values(); Deno.env.get = (key) => config[key];
    globalThis.fetch = (input, init) => {
      const req = new Request(input, init); calls.push(req);
      assert(req.signal instanceof AbortSignal); assert.equal(req.signal.aborted, false);
      const path = new URL(req.url).pathname;
      assert.equal(new URL(req.url).origin, "https://recovery.synthetic.invalid");
      if (path === "/rest/v1/rpc/customer_mfa_recovery_request") {
        assert.equal(req.headers.get("Authorization"), "Bearer original-owner");
        assert.equal(req.headers.get("apikey"), config.SUPABASE_ANON_KEY);
        if (options.rpcTimeout) return Promise.reject(new DOMException("private diagnostic", "TimeoutError"));
        const at = rpcCount++;
        if (at === options.denyAt) return Promise.resolve(Response.json({
          code: options.code ?? "PT403", message: options.message ?? "private diagnostic",
        }, { status: 403 }));
        return Promise.resolve(Response.json((options.replies ?? [result(), result(), result([])])[at]));
      }
      assert.equal(path, `/auth/v1/admin/users/${target}/factors/${factor}`);
      assert.equal(req.method, "DELETE");
      const named = config.CLEANSTREAM_MFA_RECOVERY_SECRET_KEY_NAME !== undefined;
      assert.equal(req.headers.get("apikey"), named ? secret : config.SUPABASE_SERVICE_ROLE_KEY);
      assert.equal(req.headers.get("Authorization"), named ? null : "Bearer synthetic-legacy");
      if (options.deleteTimeout) return Promise.reject(new DOMException("private deletion outcome", "TimeoutError"));
      return Promise.resolve(options.deleteError ? Response.json({ message: "private Auth failure" }, { status: 500 })
        : Response.json({ id: factor }));
    };
    await action(calls);
  } finally { globalThis.fetch = savedFetch; Deno.env.get = savedEnv; }
}

for (const named of [true, false]) Deno.test(`recovery real SDK ${named ? "named" : "legacy"}: original Owner RPC and exact old factor removal`, async () => {
  const env = values(); if (!named) delete env.CLEANSTREAM_MFA_RECOVERY_SECRET_KEY_NAME;
  await fixture(async (calls) => {
    const response = await handler(request()); assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { target_user_id: target, recovery_id: recovery,
      support_case: "SUPPORT-123", state: "reenrollment_required", reenrollment_required: true });
    assert.equal(calls.length, 4);
    assert.deepEqual(await calls[0].json(), { action: "prepare", target_user_id: target,
      support_case: "SUPPORT-123", identity_verified: true, expected_recovery_id: null });
    assert.deepEqual(await calls[1].json(), { action: "authorize", target_user_id: target,
      support_case: null, identity_verified: false, expected_recovery_id: recovery });
  }, { env });
});
Deno.test("recovery inspect needs no server secret and never mutates Auth", async () => {
  const env = values(); delete env.SUPABASE_SERVICE_ROLE_KEY; env.SUPABASE_SECRET_KEYS = "bad";
  await fixture(async (calls) => {
    const response = await handler(request({ action: "inspect", target_user_id: target }));
    assert.equal(response.status, 200); assert.equal(calls.length, 1);
    assert.equal((await calls[0].json()).action, "inspect");
  }, { env });
});
for (const key of ["", "missing", " recovery"]) Deno.test(`recovery invalid explicit named secret ${JSON.stringify(key)} has no fallback`, async () => {
  const env = values(); env.CLEANSTREAM_MFA_RECOVERY_SECRET_KEY_NAME = key;
  await fixture(async (calls) => { assert.equal((await handler(request())).status, 503); assert.equal(calls.length, 0); }, { env });
});
for (const payload of [null, [], {}, { ...body(), target_user_id: "email@example.invalid" },
  { ...body(), identity_verified: false }, { ...body(), identity_verified: "true" },
  { ...body(), support_case: "" }, { ...body(), support_case: " bad " },
  { ...body(), support_case: "a\nb" }, { ...body(), support_case: "x".repeat(121) },
  { ...body(), actor: "Owner" }, { ...body(), action: "delete" }]) {
  Deno.test(`recovery rejects invalid input ${JSON.stringify(payload)}`, async () => fixture(async (calls) => {
    assert.equal((await handler(request(payload))).status, 400); assert.equal(calls.length, 0);
  }));
}
Deno.test("recovery missing original bearer is rejected before RPC", async () => fixture(async (calls) => {
  assert.equal((await handler(request(body(), {}))).status, 401); assert.equal(calls.length, 0);
}));
Deno.test("recovery rejects untrusted browser origin", async () => fixture(async (calls) => {
  assert.equal((await handler(request(body(), { Authorization: "Bearer original-owner", Origin: "https://evil.invalid" }))).status, 403);
  assert.equal(calls.length, 0);
}));
for (const [method, status] of [["OPTIONS", 200], ["GET", 405]] as const) {
  Deno.test(`recovery ${method} performs no backend access`, async () => fixture(async (calls) => {
    assert.equal((await handler(request(null, {}, method))).status, status); assert.equal(calls.length, 0);
  }));
}
Deno.test("recovery malformed JSON performs no backend access", async () => fixture(async (calls) => {
  const req = new Request("https://edge.synthetic.invalid/customer-mfa-recovery", {
    method: "POST", headers: { Authorization: "Bearer original-owner" }, body: "{invalid",
  });
  assert.equal((await handler(req)).status, 400); assert.equal(calls.length, 0);
}));
for (const at of [0, 1]) Deno.test(`recovery canonical denial at RPC ${at} prevents Auth deletion`, async () => fixture(async (calls) => {
  const response = await handler(request()); assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: "recovery_forbidden" });
  assert.equal(calls.length, at + 1);
}, { denyAt: at }));
for (const [code, status, message] of [["PT401", 401, "session_invalid"], ["PT409", 409, "recovery_conflict"],
  ["PT403", 403, "fresh_sign_in_required"], ["PT503", 503, "private diagnostic"]] as const) {
  Deno.test(`recovery canonical ${code}/${message} sanitized`, async () => fixture(async (calls) => {
    const response = await handler(request()); assert.equal(response.status, status);
    assert(!JSON.stringify(await response.json()).includes("private diagnostic")); assert.equal(calls.length, 1);
  }, { denyAt: 0, code, message }));
}
for (const options of [{ rpcTimeout: true }, { deleteTimeout: true }, { deleteError: true }]) {
  Deno.test(`recovery unknown outcome ${JSON.stringify(options)} stops without retry or false completion`, async () => fixture(async (calls) => {
    const response = await handler(request()); assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: "recovery_unavailable" });
    assert.equal(calls.filter((r) => r.method === "DELETE").length, options.rpcTimeout ? 0 : 1);
  }, options));
}
Deno.test("recovery known-complete replay performs no Auth removal", async () => fixture(async (calls) => {
  assert.equal((await handler(request())).status, 200); assert.equal(calls.length, 2);
}, { replies: [result([]), result([])] }));
Deno.test("recovery concurrent removal skips absent old factor, never a new enrollment", async () => fixture(async (calls) => {
  assert.equal((await handler(request())).status, 200); assert.equal(calls.length, 3);
}, { replies: [result(), result([]), result([])] }));
for (const bad of [null, { ...result(), target_user_id: other }, { ...result(), recovery_id: "bad" },
  { ...result(), remaining_factor_ids: [factor, factor] }, { ...result(), remaining_factor_ids: ["bad"] },
  { ...result(), state: "completed" }, { ...result(), reenrollment_required: false }]) {
  Deno.test(`recovery malformed authoritative receipt ${JSON.stringify(bad)}`, async () => fixture(async (calls) => {
    assert.equal((await handler(request())).status, 503); assert.equal(calls.length, 1);
  }, { replies: [bad] }));
}
Deno.test("recovery changed operation or expanded snapshot cannot delete", async () => fixture(async (calls) => {
  assert.equal((await handler(request())).status, 503); assert.equal(calls.length, 2);
}, { replies: [result(), result([factor, other])] }));
Deno.test("recovery remaining captured factor at finish is not success", async () => fixture(async (calls) => {
  assert.equal((await handler(request())).status, 503); assert.equal(calls.length, 4);
}, { replies: [result(), result(), result()] }));
