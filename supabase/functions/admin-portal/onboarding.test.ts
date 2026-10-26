import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePortal } from "./handler.ts";
import { type PortalConfig } from "./backend.ts";
import { handler } from "./index.ts";

const owner = "00000000-0000-4000-8000-000000000001";
const target = "00000000-0000-4000-8000-000000000002";
const other = "00000000-0000-4000-8000-000000000003";
const origin = "https://portal.invalid";
const email = "staff@example.invalid";
const invite = { action: "invite", email, locationIds: [20, 10] };
const resend = { action: "resend", userId: target, locationId: 10 };
type Call = { path: string; headers: Headers; body: Record<string, unknown>; url: URL };
function fixture(options: {
  existing?: boolean;
  resend?: boolean;
  unverified?: boolean;
  modern?: boolean;
  portalRole?: "Manager" | "Maintenance";
  override?: (call: Call) => Response | Promise<Response> | undefined;
} = {}) {
  const calls: Call[] = [];
  const existing = options.existing || options.resend;
  const config: PortalConfig = {
    url: "https://synthetic.invalid", anonKey: "sb_publishable_synthetic",
    onboarding: { secretKey: "sb_secret_synthetic", modernSecret: options.modern !== false,
      redirectTo: `${origin}/admin/accept-invite` },
    fetch: (async (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      const call: Call = { path: url.pathname, headers: request.headers, body: await request.json(), url };
      calls.push(call);
      if (call.path !== "/rest/v1/rpc/admin_portal_request") {
        assert(init?.signal instanceof AbortSignal);
        assertEquals(init.signal.aborted, false);
      }
      const changed = options.override?.(call);
      if (changed) return await changed;
      if (call.path === "/rest/v1/rpc/admin_portal_request") return Response.json({ id: owner, role: "Owner" });
      if (call.path === "/rest/v1/rpc/admin_team_onboarding") {
        return Response.json({ request_id: "9007199254740993", actor_id: owner,
          target_user_id: existing || call.body.action === "complete" ? target : null,
          email, location_ids: options.resend ? [10] : [10, 20], portal_role: options.portalRole ?? "Manager",
          email_action: existing && !options.unverified ? "recovery" : "invite" });
      }
      if (call.path === "/auth/v1/invite") return Response.json({ id: target, email,
        aud: "authenticated", role: "authenticated", created_at: "2026-09-30T00:00:00Z" });
      if (call.path === "/auth/v1/recover") return Response.json({});
      if (call.path === "/rest/v1/rpc/admin_team_invitation_delivered") return Response.json(null);
      throw new Error(`Unexpected synthetic request ${call.path}`);
    }) as typeof fetch,
  };
  const request = (body: unknown = options.resend ? resend : invite, token = "original-owner") => new Request(`${origin}/admin-portal`, {
    method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify(body),
  });
  const run = (body?: unknown) => handlePortal(request(body), config, origin);
  return { calls, config, request, run };
}

Deno.test("actual SDK new invite uses original caller, Auth mail, atomic assignment and service-only delivery", async () => {
  const f = fixture();
  const response = await f.run({ ...invite, actor: other, role: "Owner", redirectTo: "https://attacker.invalid" });
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {});
  assertEquals(f.calls.map((c) => c.path), [
    "/rest/v1/rpc/admin_portal_request", "/rest/v1/rpc/admin_team_onboarding",
    "/rest/v1/rpc/admin_team_onboarding", "/auth/v1/invite",
    "/rest/v1/rpc/admin_team_onboarding", "/rest/v1/rpc/admin_team_invitation_delivered",
  ]);
  for (const call of f.calls) {
    const service = call.path.startsWith("/auth/") || call.path.endsWith("_delivered");
    assertEquals(call.headers.get("apikey"), service ? "sb_secret_synthetic" : "sb_publishable_synthetic");
    assertEquals(call.headers.get("authorization"), service ? null : "Bearer original-owner");
  }
  assertEquals(f.calls[1].body, { action: "invite", target_email: email, target_locations: [10, 20], target_portal_role: "Manager" });
  assertEquals(f.calls[2].body, { action: "authorize", request_id: "9007199254740993" });
  assertEquals(f.calls[3].body.email, email);
  assertEquals(f.calls[3].url.searchParams.get("redirect_to"), `${origin}/admin/accept-invite`);
  assertEquals(f.calls[3].body.data, undefined);
  assertEquals(f.calls[4].body, { action: "complete", request_id: "9007199254740993", target_user_id: target });
  assertEquals(f.calls[5].body, { request_id: "9007199254740993", target_user_id: target });
});
Deno.test("Maintenance invitation freezes the requested role through authorization and completion", async () => {
  const f = fixture({ portalRole: "Maintenance" });
  assertEquals((await f.run({ ...invite, portalRole: "Maintenance" })).status, 200);
  assertEquals(f.calls[1].body.target_portal_role, "Maintenance");
});
Deno.test("a substituted invitation role stops before Auth email", async () => {
  const f = fixture({ portalRole: "Manager" });
  assertEquals((await f.run({ ...invite, portalRole: "Maintenance" })).status, 503);
  assertEquals(f.calls.length, 2);
});
for (const resending of [false, true]) {
  Deno.test(`existing confirmed member ${resending ? "resend" : "invite"} sends one Auth recovery email`, async () => {
    const f = fixture({ existing: true, resend: resending });
    assertEquals((await f.run()).status, 200);
    assertEquals(f.calls.filter((c) => c.path.startsWith("/auth/")).map((c) => c.path), ["/auth/v1/recover"]);
    assertEquals(f.calls[3].url.searchParams.get("redirect_to"), `${origin}/admin/accept-invite`);
  });
}
Deno.test("unconfirmed invited member resends through Auth invite, not recovery or an outbox", async () => {
  const f = fixture({ resend: true, unverified: true });
  assertEquals((await f.run()).status, 200);
  assertEquals(f.calls.filter((c) => c.path.startsWith("/auth/")).map((c) => c.path), ["/auth/v1/invite"]);
});
Deno.test("explicit legacy server key retains its legacy bearer while caller stays original", async () => {
  const f = fixture({ modern: false });
  assertEquals((await f.run()).status, 200);
  assertEquals(f.calls[3].headers.get("authorization"), "Bearer sb_secret_synthetic");
  assertEquals(f.calls[4].headers.get("authorization"), "Bearer original-owner");
});
for (const stage of ["invite", "authorize"]) {
  for (const [code, message, status] of [
    ["PT401", "session_invalid", 401], ["PT403", "owner_required", 403],
    ["PT403", "challenge_totp", 403], ["PT403", "account_restricted", 403],
    ["PT403", "location_access_denied", 403], ["PT409", "invitation_conflict", 409],
    ["PT503", "internal secret details", 503],
  ] as const) {
    Deno.test(`${stage} ${message} stops before any Auth or delivery request`, async () => {
      const f = fixture({ override: (c) => c.body.action === stage ? Response.json({ code, message }, { status }) : undefined });
      const response = await f.run();
      assertEquals(response.status, status);
      assertEquals(f.calls.some((c) => c.path.startsWith("/auth/") || c.path.endsWith("_delivered")), false);
      assertEquals((await response.text()).includes("secret details"), false);
    });
  }
}
for (const change of [
  { actor_id: other }, { request_id: 123 }, { request_id: "-1" },
  { email: "other@example.invalid" }, { target_user_id: "invalid" },
  { location_ids: [10] }, { location_ids: [20, 10] }, { email_action: "magiclink" },
]) {
  Deno.test(`malformed or substituted SQL receipt rejects ${Object.keys(change)[0]} before Auth`, async () => {
    const f = fixture({ override: (c) => c.body.action === "invite" ? Response.json({
      request_id: "1", actor_id: owner, target_user_id: null, email,
      location_ids: [10, 20], email_action: "invite", ...change,
    }) : undefined });
    assertEquals((await f.run()).status, 503);
    assertEquals(f.calls.length, 2);
  });
}
Deno.test("changed request identity after canonical wait cannot dispatch", async () => {
  const f = fixture({ override: (c) => c.body.action === "authorize" ? Response.json({
    request_id: "42", actor_id: owner, target_user_id: null, email, location_ids: [10, 20], email_action: "invite",
  }) : undefined });
  assertEquals((await f.run()).status, 503);
  assertEquals(f.calls.length, 3);
});
for (const path of ["/auth/v1/invite", "/rest/v1/rpc/admin_team_onboarding", "/rest/v1/rpc/admin_team_invitation_delivered"]) {
  Deno.test(`unknown ${path} outcome is support/recheck, no retry or Auth deletion`, async () => {
    const f = fixture({ override: (c) => c.path === path && (path !== "/rest/v1/rpc/admin_team_onboarding" || c.body.action === "complete")
      ? Response.json({ code: "PT503", message: "sensitive provider diagnostics" }, { status: 503 }) : undefined });
    const response = await f.run();
    assertEquals(response.status, 503);
    const body = await response.json();
    assertEquals(body.code, "admin_onboarding_unavailable");
    assert(body.error.includes("support"));
    assertEquals(body.error.includes("sensitive"), false);
    assertEquals(f.calls.filter((c) => c.path.startsWith("/auth/")).length, 1);
    assertEquals(f.calls.some((c) => c.path.includes("/users")), false);
  });
}
for (const response of [{ id: other, email: "different@example.invalid" }, { id: "bad", email }, {}]) {
  Deno.test(`invalid Auth acknowledgement never grants access: ${JSON.stringify(response)}`, async () => {
    const f = fixture({ override: (c) => c.path === "/auth/v1/invite" ? Response.json(response) : undefined });
    assertEquals((await f.run()).status, 503);
    assertEquals(f.calls.length, 4);
  });
}
Deno.test("Auth thrown timeout is sanitized once and never compensated", async () => {
  const f = fixture({ override: (c) => {
    if (c.path === "/auth/v1/invite") throw new DOMException("synthetic timeout", "TimeoutError");
    return undefined;
  } });
  const response = await f.run();
  assertEquals(response.status, 503);
  assertEquals(f.calls.length, 4);
});
Deno.test("missing configuration stays disabled without new RPC/Auth; unsafe redirect cannot be supplied", async () => {
  const f = fixture(); f.config.onboarding = undefined;
  assertEquals((await f.run()).status, 503);
  assertEquals(f.calls.length, 1);
  for (const redirectTo of ["http://portal.invalid/admin/accept-invite", "https://portal.invalid/other", "https://portal.invalid/admin/accept-invite?next=evil"]) {
    const g = fixture(); g.config.onboarding!.redirectTo = redirectTo;
    assertEquals((await g.run()).status, 503);
    assertEquals(g.calls.length, 1);
  }
});
Deno.test("A-B-A body wait preserves original caller across invitation and completion", async () => {
  const f = fixture(), request = f.request();
  const original = request.text.bind(request);
  let release!: () => void;
  const waiting = new Promise<void>((resolve) => release = resolve);
  request.text = async () => { await waiting; return original(); };
  const pending = handlePortal(request, f.config, origin);
  request.headers.set("authorization", "Bearer replacement-B");
  request.headers.set("authorization", "Bearer replacement-A");
  release();
  assertEquals((await pending).status, 200);
  for (const c of f.calls.filter((c) => c.path.endsWith("admin_portal_request") || c.path.endsWith("admin_team_onboarding"))) {
    assertEquals(c.headers.get("authorization"), "Bearer original-owner");
  }
});

async function withIndexEnv(vars: Record<string, string>, run: () => Promise<void>) {
  const get = Deno.env.get;
  // Synthetic values only; never inspect real credentials or mutate environment.
  Deno.env.get = (name: string) => vars[name];
  try { await run(); } finally { Deno.env.get = get; }
}
const vars = {
  SUPABASE_URL: "https://synthetic.invalid", SUPABASE_ANON_KEY: "legacy-public",
  SUPABASE_SERVICE_ROLE_KEY: "legacy-server",
  CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME: "web", SUPABASE_PUBLISHABLE_KEYS: '{"web":"sb_publishable_synthetic"}',
  CLEANSTREAM_ADMIN_SECRET_KEY_NAME: "onboarding", SUPABASE_SECRET_KEYS: '{"onboarding":"sb_secret_synthetic","other":"sb_secret_unused"}',
  ADMIN_PORTAL_ORIGIN: origin,
};
Deno.test("actual exported handler selects exact named server key only for onboarding", async () => {
  const f = fixture(), original = globalThis.fetch;
  globalThis.fetch = f.config.fetch!;
  try {
    await withIndexEnv(vars, async () => {
      assertEquals((await handler(f.request())).status, 200);
      assertEquals(f.calls[3].headers.get("apikey"), "sb_secret_synthetic");
      assertEquals(f.calls[3].headers.get("authorization"), null);
      assertEquals(f.calls[4].headers.get("authorization"), "Bearer original-owner");
    });
  } finally { globalThis.fetch = original; }
});
for (const override of [
  { CLEANSTREAM_ADMIN_SECRET_KEY_NAME: "" },
  { CLEANSTREAM_ADMIN_SECRET_KEY_NAME: "missing" },
  { CLEANSTREAM_ADMIN_SECRET_KEY_NAME: " onboarding " },
  { SUPABASE_SECRET_KEYS: "not-json" },
  { SUPABASE_SECRET_KEYS: '{"onboarding":"sb_publishable_wrong"}' },
]) {
  Deno.test(`invalid explicit server selector never falls back: ${JSON.stringify(override)}`, async () => {
    const f = fixture(), original = globalThis.fetch;
    globalThis.fetch = f.config.fetch!;
    try {
      await withIndexEnv({ ...vars, ...override }, async () => {
        assertEquals((await handler(f.request())).status, 503);
        assertEquals(f.calls.map((c) => c.path), ["/rest/v1/rpc/admin_portal_request"]);
      });
    } finally { globalThis.fetch = original; }
  });
}
