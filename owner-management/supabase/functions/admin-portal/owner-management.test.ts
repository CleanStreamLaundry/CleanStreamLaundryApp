import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePortal } from "./handler.ts";

const actor = "00000000-0000-4000-8000-000000000001";
const target = "00000000-0000-4000-8000-000000000003";
const requestId = "00000000-0000-4000-8000-000000000100";
const origin = "https://portal.invalid";
const change = {
  action: "setOwner", userId: target, owner: true, expectedRole: "User", requestId,
  note: "Approved additional manager",
};
const receipt = { userId: target, role: "Owner", requestId, changed: true };
const request = (body: unknown, token = "captured-A") => new Request(`${origin}/admin-portal`, {
  method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify(body),
});
function offline(reply: (body: Record<string, unknown>) => unknown = () => receipt) {
  const calls: { path: string; token: string | null; body: Record<string, unknown> }[] = [];
  const config = {
    url: "https://synthetic.invalid", anonKey: "public-anon-key",
    fetch: (async (input, init) => {
      const req = new Request(input, init), path = new URL(req.url).pathname;
      assertEquals(req.headers.get("apikey"), "public-anon-key");
      assertEquals(req.method, "POST");
      const body = await req.json();
      calls.push({ path, token: req.headers.get("authorization"), body });
      if (body.action === "identity") return Response.json({ id: actor, role: "Owner" });
      assertEquals(path, "/rest/v1/rpc/admin_owner_management");
      assert(req.signal instanceof AbortSignal);
      assertEquals(req.signal.aborted, false);
      const response = reply(body);
      return response instanceof Response ? response : Response.json(response);
    }) as typeof fetch,
  };
  return { config, calls };
}

Deno.test("Owner management real SDK uses captured bearer, canonical RPC and no Auth/email/provider", async () => {
  const { config, calls } = offline();
  const response = await handlePortal(request({ ...change, actor: "forged", role: "Owner" }), config, origin);
  assertEquals(response.status, 200); assertEquals(await response.json(), receipt);
  assertEquals(calls.length, 2);
  assertEquals(calls.map((c) => c.token), ["Bearer captured-A", "Bearer captured-A"]);
  assertEquals(calls[1].body, { action: "setOwner", payload: {
    userId: target, owner: true, expectedRole: "User", requestId, note: change.note,
  } });
});

for (const [body, payload, result] of [
  [{ action: "ownerAccounts" }, { query: "", page: 1 }, { items: [], page: 1, pageSize: 25, total: 0, activeOwnerCount: 1 }],
  [{ action: "ownerAccounts", query: "  3@example.invalid  ", page: 2 }, { query: "3@example.invalid", page: 2 }, { items: [] }],
  [{ action: "ownerChangeStatus", requestId }, { requestId }, { state: "completed", result: receipt }],
  [{ action: "ownerChangeStatus", requestId }, { requestId }, { state: "not_found" }],
] as const) {
  Deno.test(`Owner ${body.action} forwards minimal payload ${JSON.stringify(result)}`, async () => {
    const { config, calls } = offline(() => result);
    const response = await handlePortal(request(body), config, origin);
    assertEquals(response.status, 200); assertEquals(await response.json(), result);
    assertEquals(calls[1].body, { action: body.action, payload });
    assertEquals(calls.length, 2);
  });
}

for (const desired of [true, false]) {
  Deno.test(`self Owner ${desired ? "grant" : "revoke"} never dispatches mutation`, async () => {
    const { config, calls } = offline();
    const response = await handlePortal(request({ ...change, userId: actor, expectedRole: "Owner", owner: desired }), config, origin);
    assertEquals(response.status, 403); assertEquals((await response.json()).code, "admin_forbidden");
    assertEquals(calls.length, 1);
  });
}

for (const body of [
  { ...change, owner: "true" }, { ...change, expectedRole: "SuperOwner" }, { ...change, userId: "not-uuid" },
  { ...change, requestId: "not-uuid" }, { ...change, note: " " }, { ...change, note: "x".repeat(4001) },
  { action: "ownerAccounts", page: 0 }, { action: "ownerAccounts", page: 1.5 },
  { action: "ownerAccounts", query: "x".repeat(255) }, { action: "ownerChangeStatus" },
]) {
  Deno.test(`invalid Owner payload fails before mutation ${JSON.stringify(body).slice(0, 100)}`, async () => {
    const { config, calls } = offline();
    assertEquals((await handlePortal(request(body), config, origin)).status, 400);
    assertEquals(calls.length, 1);
  });
}

for (const code of ["owner_last_required", "owner_state_changed", "owner_target_ineligible", "owner_request_conflict"]) {
  Deno.test(`Owner conflict ${code} remains explicit and is never retried`, async () => {
    const { config, calls } = offline(() => Response.json({ code: "PT409", message: code }, { status: 409 }));
    const response = await handlePortal(request(change), config, origin);
    assertEquals(response.status, 409); assertEquals((await response.json()).code, code);
    assertEquals(calls.length, 2);
  });
}

for (const [sqlCode, message, status, expected] of [
  ["PT401", "session_invalid", 401, "session_invalid"],
  ["PT403", "owner_required", 403, "admin_forbidden"],
  ["PT403", "enroll_totp", 403, "enroll_totp"],
  ["PT403", "admin_access_changed", 403, "admin_access_changed"],
  ["PT503", "sensitive backend detail", 503, "admin_unavailable"],
] as const) {
  Deno.test(`post-identity SQL ${message} rejects Owner action without authority fallback`, async () => {
    const { config, calls } = offline(() => Response.json({ code: sqlCode, message }, { status }));
    const response = await handlePortal(request(change), config, origin);
    assertEquals(response.status, status); const body = await response.json(); assertEquals(body.code, expected);
    assertEquals(calls.length, 2); assert(!JSON.stringify(body).includes("sensitive backend detail"));
  });
}

Deno.test("unknown transport outcome is sanitized and never automatically resent", async () => {
  const { config, calls } = offline(() => { throw new DOMException("private timeout detail", "TimeoutError"); });
  const response = await handlePortal(request(change), config, origin);
  assertEquals(response.status, 503); const body = await response.json(); assertEquals(body.code, "admin_unavailable");
  assert(!JSON.stringify(body).includes("private timeout detail")); assertEquals(calls.length, 2);
});

Deno.test("captured bearer remains bound across delayed body and concurrent A-B-A requests", async () => {
  const { config, calls } = offline(); const req = request(change), original = req.text.bind(req);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  req.text = async () => { await gate; return original(); };
  const pending = handlePortal(req, config, origin);
  req.headers.set("authorization", "Bearer replacement-B");
  assertEquals((await handlePortal(request(change, "parallel-B"), config, origin)).status, 200);
  req.headers.set("authorization", "Bearer replacement-A"); release();
  assertEquals((await pending).status, 200);
  assertEquals(calls.map((c) => c.token), ["Bearer parallel-B", "Bearer parallel-B", "Bearer captured-A", "Bearer captured-A"]);
});
