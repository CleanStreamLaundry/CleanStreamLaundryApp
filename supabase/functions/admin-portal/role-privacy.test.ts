import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePortal } from "./handler.ts";
import type { PortalRole } from "./logic.ts";

const actor = "00000000-0000-4000-8000-000000000001";
const target = "00000000-0000-4000-8000-000000000002";
const requestId = "00000000-0000-4000-8000-000000000100";
const origin = "https://portal.invalid";
const change = { action: "setStaffRole", userId: target, portalRole: "Maintenance", expectedPortalRole: "Manager", requestId, note: "Approved maintenance access" };
const request = (body: unknown, token = "captured-A") => new Request(`${origin}/admin-portal`, {
  method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify(body),
});
function fixture(role: PortalRole, reply: (body: Record<string, unknown>) => unknown = () => ({ success: true })) {
  const calls: { path: string; token: string | null; body: Record<string, unknown> }[] = [];
  const config = {
    url: "https://synthetic.invalid", anonKey: "public-key",
    fetch: (async (input, init) => {
      const req = new Request(input, init), body = await req.json();
      calls.push({ path: new URL(req.url).pathname, token: req.headers.get("authorization"), body });
      assertEquals(req.headers.get("apikey"), "public-key");
      if (body.action === "identity") return Response.json({ id: actor, role: role === "Owner" ? "Owner" : "Admin", portalRole: role });
      const result = reply(body);
      return result instanceof Response ? result : Response.json(result);
    }) as typeof fetch,
  };
  return { calls, config, run: (body: unknown) => handlePortal(request(body), config, origin) };
}

for (const role of ["Manager", "Maintenance"] as const) {
  for (const body of [
    { action: "rates", locationId: 100 }, { action: "transactions" }, { action: "credits" }, { action: "audit" },
    { action: "saveRate" }, { action: "saveConfig" }, { action: "createLocation" }, { action: "createMachine" },
    { action: "deleteMachine" }, { action: "removeMember" }, { action: "ownerAccounts" }, change,
    { action: "staffRoleStatus", requestId }, { action: "exportRecords", dataset: "transactions" },
    { action: "exportRecords", dataset: "credits" }, { action: "exportRecords", dataset: "audit" },
    { action: "exportRecords", dataset: "team" }, { action: "resolveCredit", id: 1, decision: "approved" },
    { action: "invite", email: "staff@example.invalid", locationIds: [100] },
    { action: "resend", userId: target, locationId: 100 },
  ]) Deno.test(`${role} rejects ${body.action} ${"dataset" in body ? body.dataset : ""} before data/provider dispatch`, async () => {
    const f = fixture(role);
    const response = await f.run({ ...body, role: "Owner", actor: target });
    assertEquals(response.status, 403); assertEquals((await response.json()).code, "admin_forbidden");
    assertEquals(f.calls.length, 1);
  });
}
for (const body of [{ action: "overview" }, { action: "machines", locationId: 100 }, { action: "team" },
  { action: "setAvailability" }, { action: "exportRecords", dataset: "machines" }]) {
  Deno.test(`Maintenance rejects operational-only ${body.action}`, async () => {
    const f = fixture("Maintenance"); assertEquals((await f.run(body)).status, 403); assertEquals(f.calls.length, 1);
  });
}
for (const role of ["Manager", "Maintenance"] as const) {
  for (const action of ["locations", "maintenance", "history", "assignees", "updateMaintenance", "exportRecords"]) {
    Deno.test(`${role} retains scoped maintenance ${action}`, async () => {
      const f = fixture(role); assertEquals((await f.run({ action, id: "1", dataset: "maintenance" })).status, 200);
      assertEquals(f.calls.length, 2); assertEquals(f.calls[1].path, "/rest/v1/rpc/admin_portal_request");
    });
  }
}
Deno.test("Owner staff role command and status have minimal caller-bound RPC payloads", async () => {
  const receipt = { userId: target, role: "Admin", portalRole: "Maintenance", requestId, changed: true };
  const f = fixture("Owner", () => receipt);
  assertEquals((await f.run({ ...change, actor: target })).status, 200);
  assertEquals(f.calls[1], { path: "/rest/v1/rpc/admin_staff_role_management", token: "Bearer captured-A", body: {
    action: "setStaffRole", payload: { userId: target, portalRole: "Maintenance", expectedPortalRole: "Manager", requestId, note: change.note },
  } });
  assertEquals((await f.run({ action: "staffRoleStatus", requestId, userId: target })).status, 200);
  assertEquals(f.calls[3].body, { action: "staffRoleStatus", payload: { requestId } });
});
for (const body of [{ ...change, portalRole: "Owner" }, { ...change, expectedPortalRole: "Admin" },
  { ...change, note: " " }, { ...change, requestId: "invalid" }, { ...change, userId: "invalid" },
  { action: "invite", email: "staff@example.invalid", locationIds: [100], portalRole: "Owner" }]) {
  Deno.test(`invalid staff role input rejected ${JSON.stringify(body)}`, async () => {
    const f = fixture("Owner"); assertEquals((await f.run(body)).status, 400); assertEquals(f.calls.length, 1);
  });
}
for (const message of ["staff_role_state_changed", "staff_role_request_conflict", "staff_role_target_ineligible"]) {
  Deno.test(`staff conflict ${message} is stable and never retried`, async () => {
    const f = fixture("Owner", () => Response.json({ code: "PT409", message }, { status: 409 }));
    const response = await f.run(change); assertEquals(response.status, 409); assertEquals((await response.json()).code, message);
    assertEquals(f.calls.length, 2);
  });
}
Deno.test("changed SQL authority after identity denies without fallback or replay", async () => {
  const f = fixture("Owner", () => Response.json({ code: "PT403", message: "owner_required" }, { status: 403 }));
  assertEquals((await f.run(change)).status, 403); assertEquals(f.calls.length, 2);
});
Deno.test("role mutation keeps captured account across delayed body and A-B-A header replacement", async () => {
  const f = fixture("Owner"), req = request(change), original = req.text.bind(req);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  req.text = async () => { await gate; return original(); };
  const pending = handlePortal(req, f.config, origin);
  req.headers.set("authorization", "Bearer replacement-B"); req.headers.set("authorization", "Bearer replacement-A");
  release(); assertEquals((await pending).status, 200);
  assert(f.calls.every((c) => c.token === "Bearer captured-A"));
});
