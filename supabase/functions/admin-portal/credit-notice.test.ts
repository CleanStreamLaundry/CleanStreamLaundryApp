import assert from "node:assert/strict";
import { capturedBearer, createCreditDependencies, type PortalConfig } from "./backend.ts";
import { handlePortal } from "./handler.ts";
import { handleRefundResolution } from "../_shared/refund_resolution.ts";

const request = (body: unknown) => new Request("https://synthetic.invalid/admin-portal", {
  method: "POST", headers: { Authorization: "Bearer original-caller" }, body: JSON.stringify(body),
});
function fixture(state: string, decision = "approved", failure?: string) {
  const calls: { path: string; body: Record<string, unknown> }[] = [];
  const config: PortalConfig = {
    url: "https://synthetic.invalid", anonKey: "synthetic-publishable-key",
    fetch: async (input, init) => {
      const req = new Request(input, init), path = new URL(req.url).pathname;
      assert(["/rest/v1/rpc/admin_portal_request", "/rest/v1/rpc/admin_resolve_credit"].includes(path));
      assert.equal(req.headers.get("authorization"), "Bearer original-caller");
      assert.equal(req.headers.get("apikey"), config.anonKey);
      const body = await req.json(); calls.push({ path, body });
      if (body.action === "identity") return Response.json({ id: "server-actor", role: "Owner" });
      if (body.action === "assertCredit") return Response.json({ success: true });
      if (failure) return Response.json({ code: failure, message: "PRIVATE" }, { status: failure === "PT403" ? 403 : 503 });
      return Response.json({ success: true, alreadyResolved: false, refundId: 12, transactionId: 44,
        customerId: "server-customer", amount: 2.5, status: decision,
        notificationState: state, notificationSent: ["accepted", "delivered"].includes(state) });
    },
  };
  return { config, calls };
}
for (const decision of ["approved", "denied"] as const) {
  for (const endpoint of ["portal", "legacy"] as const) {
    Deno.test(`actual SDK ${endpoint} ${decision}: saved decision plus queued notice, original caller only`, async () => {
      const { config, calls } = fixture("ready", decision);
      const req = request(endpoint === "portal"
        ? { action: "resolveCredit", id: 12, decision, note: "Saved note", actor: "forged" }
        : { refundId: 12, note: "Saved note", actorUserId: "forged" });
      const response = endpoint === "portal" ? await handlePortal(req, config, "https://cleanstreamlaundry.com")
        : await handleRefundResolution(req, decision, createCreditDependencies(capturedBearer(req), config));
      assert.equal(response.status, 200); const body = await response.json();
      assert.equal(body.success, true); assert.match(body.notificationWarning, /queued; delivery is not yet confirmed/);
      if (endpoint === "legacy") assert.equal(body.notificationSent, false);
      assert.equal(calls.length, endpoint === "portal" ? 3 : 2);
      assert.deepEqual(calls.at(-1)?.body, { target_refund_id: 12, target_decision: decision, resolution_note: "Saved note" });
    });
  }
}
for (const state of ["accepted", "delivered", "uncertain", "failed", "suppressed", "not_queued"]) {
  Deno.test(`actual SDK portal maps ${state} without replay or provider request`, async () => {
    const { config, calls } = fixture(state);
    const response = await handlePortal(request({ action: "resolveCredit", id: 12, decision: "approved" }), config, "https://cleanstreamlaundry.com");
    assert.equal(response.status, 200); const body = await response.json(); assert.equal(body.success, true);
    assert.equal(typeof body.notificationWarning, ["accepted", "delivered"].includes(state) ? "undefined" : "string");
    assert.equal(calls.filter((c) => c.path.endsWith("admin_resolve_credit")).length, 1);
  });
}
for (const code of ["PT403", "PT503"]) {
  Deno.test(`actual SDK legacy ${code} cannot claim decision or enqueue success`, async () => {
    const { config, calls } = fixture("ready", "approved", code), req = request({ refundId: 12 });
    const response = await handleRefundResolution(req, "approved", createCreditDependencies(capturedBearer(req), config));
    assert.equal(response.status, code === "PT403" ? 403 : 503);
    const body = await response.json(); assert.equal(body.success, undefined);
    assert.equal(body.notificationSent, undefined); assert(!JSON.stringify(body).includes("PRIVATE"));
    assert.equal(calls.length, 2);
  });
}
Deno.test("actual SDK legacy body await cannot replace the initiating caller", async () => {
  const { config, calls } = fixture("ready", "denied"), req = request({ refundId: 12 });
  let release!: () => void; const wait = new Promise<void>((resolve) => { release = resolve; });
  const original = req.json.bind(req); req.json = async () => { await wait; return original(); };
  const dependencies = createCreditDependencies(capturedBearer(req), config);
  const result = handleRefundResolution(req, "denied", dependencies);
  req.headers.set("authorization", "Bearer replacement-caller"); release();
  assert.equal((await result).status, 200); assert.equal(calls.length, 2);
});
