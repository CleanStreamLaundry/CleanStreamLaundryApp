import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePortal } from "./handler.ts";
import type { PortalConfig } from "./backend.ts";

const requestId = "00000000-0000-4000-8000-000000000001";
const payload = { action: "resolveMachineIssue", id: 7, requestId, resolution: "replacement_vend",
  note: "Customer notified staff at this location", atLocation: true, anotherLoadCompleted: false, replacementMachineId: 2 };
function fixture(role = "Owner", replay = false, dispatchFails = false) {
  const calls: Array<{ bearer: string | null; path: string; body: Record<string, unknown> }> = [];
  let starts = 0;
  const review = { capabilities: { walletRefund: true, replacementVend: true }, receipt: { requestId, resolution: "replacement_vend", state: "pending" } };
  const config: PortalConfig = {
    url: "https://database.invalid", anonKey: "public-key",
    fetch: (async (input, init) => {
      const req = new Request(input, init), body = await req.json();
      calls.push({ bearer: req.headers.get("authorization"), path: new URL(req.url).pathname, body });
      if (body.action === "identity") return Response.json({ id: "owner-from-bearer", role: role === "Owner" ? "Owner" : "Admin", portalRole: role });
      if (body.action === "machineIssueReview") return Response.json(review);
      return Response.json({ success: true, alreadyResolved: replay, review, startSessionId: replay ? null : "replacement-session" });
    }) as typeof fetch,
    startReplacement: async (id, authorize) => {
      assertEquals(id, "replacement-session");
      await authorize(); starts++;
      if (dispatchFails) throw new Error("Unknown provider outcome");
    },
  };
  const call = (body: unknown) => handlePortal(new Request("https://portal.invalid/admin-portal", {
    method: "POST", headers: { authorization: "Bearer captured-owner" }, body: JSON.stringify(body),
  }), config, "https://portal.invalid");
  return { calls, config, call, starts: () => starts };
}

Deno.test("machine issue dispatch uses captured actor, exact allowlist, and fresh reservation once", async () => {
  const f = fixture();
  const response = await f.call({ ...payload, actor: "forged", amountCents: 1, locationId: 99 });
  assertEquals(response.status, 200);
  assertEquals(f.starts(), 1);
  const body = await response.json();
  assertEquals(Object.hasOwn(body, "startSessionId"), false);
  assertEquals(body.review.receipt.state, "pending");
  const mutation = f.calls.find((c) => c.body.action === "resolveMachineIssue")!;
  assertEquals(mutation.path, "/rest/v1/rpc/admin_machine_issue");
  const { action: _action, ...expected } = payload;
  assertEquals(mutation.body.payload, expected);
  assertEquals(f.calls.every((c) => c.bearer === "Bearer captured-owner"), true);
});

for (const role of ["Manager", "Maintenance"]) Deno.test(`${role} cannot read or resolve machine finances`, async () => {
  const f = fixture(role);
  assertEquals((await f.call(payload)).status, 403);
  assertEquals((await f.call({ action: "machineIssueReview", id: 7 })).status, 403);
  assertEquals(f.starts(), 0);
  assertEquals(f.calls.every((c) => c.body.action === "identity"), true);
});

Deno.test("replay never dispatches replacement; status uses caller-bound request receipt", async () => {
  const f = fixture("Owner", true);
  assertEquals((await f.call(payload)).status, 200);
  assertEquals(f.starts(), 0);
  await f.call({ action: "machineIssueReview", id: 7, requestId });
  assertEquals(f.calls.at(-1)?.body, { action: "machineIssueReview", payload: { id: 7, requestId } });
});

Deno.test("uncertain dispatch preserves pending receipt without retry or fictional success", async () => {
  const f = fixture("Owner", false, true);
  const response = await f.call(payload);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).review.receipt.state, "pending");
  assertEquals(f.starts(), 1);
});

Deno.test("unconfigured dispatch capability is false and replacement write is refused", async () => {
  const f = fixture(); delete f.config.startReplacement;
  const review = await (await f.call({ action: "machineIssueReview", id: 7 })).json();
  assertEquals(review.capabilities.replacementVend, false);
  assertEquals((await f.call(payload)).status, 503);
  assertEquals(f.starts(), 0);
});

for (const change of [{ id: "7" }, { requestId: "bad" }, { note: "" }, { atLocation: "true" },
  { anotherLoadCompleted: null }, { replacementMachineId: 0 }, { resolution: "replacement_arranged" }]) {
  Deno.test(`invalid machine issue input rejected: ${JSON.stringify(change)}`, async () => {
    const f = fixture(); assertEquals((await f.call({ ...payload, ...change })).status, 400);
    assertEquals(f.starts(), 0);
  });
}
