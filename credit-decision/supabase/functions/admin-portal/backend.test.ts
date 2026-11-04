import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  capturedBearer,
  createCreditDependencies,
  createPortalDependencies,
} from "./backend.ts";
import { handlePortal } from "./handler.ts";
import { PortalError } from "./logic.ts";
import { handleRefundResolution } from "../_shared/refund_resolution.ts";

const origin = "https://portal.invalid";
const request = (body: unknown, token = "captured-A") =>
  new Request(`${origin}/admin-portal`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
function offline(
  reply: (body: Record<string, unknown>, path: string) => unknown = () => [],
) {
  const calls: {
    token: string | null;
    path: string;
    body: Record<string, unknown>;
  }[] = [];
  const config = {
    url: "https://synthetic.invalid",
    anonKey: "public-anon-key",
    fetch: (async (input, init) => {
      const req = new Request(input, init), path = new URL(req.url).pathname;
      assertEquals(req.headers.get("apikey"), "public-anon-key");
      assertEquals(req.method, "POST");
      const body = await req.json();
      calls.push({ token: req.headers.get("authorization"), path, body });
      const value = body.action === "identity"
        ? { id: "server-A", role: "Owner" }
        : reply(body, path);
      return value instanceof Response ? value : Response.json(value);
    }) as typeof fetch,
  };
  return { config, calls };
}
Deno.test("actual SDK happy path uses captured bearer and caller RPC, never actor credentials/Auth", async () => {
  const { config, calls } = offline(() => [{ id: 1 }]);
  const response = await handlePortal(
    request({ action: "locations", actor: "forged-B" }),
    config,
    origin,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), [{ id: 1 }]);
  assertEquals(calls.length, 2);
  for (const call of calls) {
    assertEquals(call.token, "Bearer captured-A");
    assertEquals(call.path, "/rest/v1/rpc/admin_portal_request");
    assertEquals(Object.keys(call.body).sort(), ["action", "payload"]);
  }
});

Deno.test("bearer is captured before body await; A-B-A and concurrent request cannot replace it", async () => {
  const { config, calls } = offline();
  const req = request({ action: "overview" });
  const original = req.text.bind(req);
  let release!: () => void;
  const waiting = new Promise<void>((resolve) => {
    release = resolve;
  });
  req.text = async () => {
    await waiting;
    return original();
  };
  const first = handlePortal(req, config, origin);
  req.headers.set("authorization", "Bearer replacement-B");
  const second = await handlePortal(
    request({ action: "locations" }, "parallel-B"),
    config,
    origin,
  );
  req.headers.set("authorization", "Bearer replacement-A");
  release();
  assertEquals((await first).status, 200);
  assertEquals(second.status, 200);
  assertEquals(calls.map((call) => call.token), [
    "Bearer parallel-B",
    "Bearer parallel-B",
    "Bearer captured-A",
    "Bearer captured-A",
  ]);
  const deps = createPortalDependencies("original", config);
  await assertRejects(() => deps.authenticate("replacement"), PortalError);
  await assertRejects(
    () => deps.resolve("replacement", 1, "approved", ""),
    PortalError,
  );
  assertEquals(calls.length, 4);
});

for (
  const [code, message, status, expectedCode, step] of [
    ["PT401", "session_invalid", 401, "session_invalid", "sign_in"],
    ["PT403", "verify_email", 403, "verify_email", "verify_email"],
    ["PT403", "enroll_totp", 403, "enroll_totp", "enroll_totp"],
    ["PT403", "challenge_totp", 403, "challenge_totp", "challenge_totp"],
    ["PT403", "account_restricted", 403, "account_restricted", "blocked"],
    ["PT403", "staff_required", 403, "staff_required", "blocked"],
    [
      "PT403",
      "admin_access_changed",
      403,
      "admin_access_changed",
      "revalidate",
    ],
    ["42501", "Location access denied", 403, "admin_forbidden", undefined],
    ["PT503", "admission_unavailable", 503, "admin_unavailable", undefined],
  ] as const
) {
  Deno.test(`SQL ${message} remains authoritative after identity`, async () => {
    const { config, calls } = offline(() =>
      Response.json({ code, message }, { status })
    );
    const response = await handlePortal(
      request({ action: "overview" }),
      config,
      origin,
    );
    assertEquals(response.status, status);
    const body = await response.json();
    assertEquals(body.code, expectedCode);
    assertEquals(body.next_step, step);
    assertEquals(calls.length, 2);
  });
}

Deno.test("missing/malformed bearer and invalid body do not call backend", async () => {
  const { config, calls } = offline();
  for (const authorization of ["", "Basic value", "Bearer two tokens"]) {
    const req = request({ action: "identity" });
    req.headers.set("authorization", authorization);
    assertEquals(capturedBearer(req), "");
    assertEquals((await handlePortal(req, config, origin)).status, 401);
  }
  assertEquals((await handlePortal(request([]), config, origin)).status, 400);
  assertEquals(
    (await handlePortal(
      request({ oversized: "x".repeat(33000) }),
      config,
      origin,
    )).status,
    413,
  );
  assertEquals(calls.length, 0);
});

Deno.test("invite and resend remain disabled without provider, user-list or delivery calls", async () => {
  const { config, calls } = offline();
  for (
    const body of [{
      action: "invite",
      email: "staff@invalid.test",
      locationIds: [1],
    }, {
      action: "resend",
      userId: "00000000-0000-4000-8000-000000000001",
      locationId: 1,
    }]
  ) {
    const response = await handlePortal(request(body), config, origin);
    assertEquals(response.status, 503);
    assertEquals((await response.json()).code, "admin_onboarding_disabled");
  }
  assertEquals(calls.map((call) => call.body.action), ["identity", "identity"]);
});

for (const decision of ["approved", "denied"] as const) {
  Deno.test(`legacy ${decision} uses guarded machine-credit RPC and honest queued notification`, async () => {
    const resolved = {
      success: true,
      alreadyResolved: false,
      refundId: 12,
      transactionId: 44,
      customerId: "customer",
      amount: 4,
      status: decision,
      notificationSent: false,
      notificationState: "ready",
    };
    const { config, calls } = offline(() => resolved);
    const req = request({ refundId: 12, actorUserId: "forged", note: "test" });
    const response = await handleRefundResolution(
      req,
      decision,
      createCreditDependencies(capturedBearer(req), config),
    );
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.status, decision);
    assertEquals(body.notificationSent, false);
    assertEquals(typeof body.notificationWarning, "string");
    assertEquals(calls[1].path, "/rest/v1/rpc/admin_resolve_credit");
    assertEquals(calls[1].body, {
      target_refund_id: 12,
      target_decision: decision,
      resolution_note: "test",
    });
    assertEquals(calls.length, 2);
  });
}

Deno.test("legacy endpoint preserves denied status and does not notify on failed SQL", async () => {
  const { config, calls } = offline(() =>
    Response.json({ code: "PT403", message: "challenge_totp" }, { status: 403 })
  );
  const req = request({ refundId: 12 });
  const response = await handleRefundResolution(
    req,
    "approved",
    createCreditDependencies(capturedBearer(req), config),
  );
  assertEquals(response.status, 403);
  assertEquals(calls.length, 2);
});

Deno.test("portal credit keeps its existing response shape and distinct machine-credit API", async () => {
  const { config, calls } = offline((_body, path) =>
    path.endsWith("admin_resolve_credit")
      ? { success: true, status: "approved", notificationSent: false, notificationState: "ready" }
      : { success: true }
  );
  const response = await handlePortal(
    request({ action: "resolveCredit", id: 12, decision: "approved" }),
    config,
    origin,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    success: true,
    notificationWarning:
      "The credit decision is saved. Customer notice is queued; delivery is not yet confirmed.",
  });
  assertEquals(calls.length, 3);
  assertEquals(calls[2].path, "/rest/v1/rpc/admin_resolve_credit");
});
