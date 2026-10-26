import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { capturedBearer, createCreditDependencies } from "./backend.ts";
import { handlePortal } from "./handler.ts";
import { handleRefundResolution } from "../_shared/refund_resolution.ts";

const origin = "https://portal.invalid";
const request = (body: unknown) =>
  new Request(origin, {
    method: "POST",
    headers: { authorization: "Bearer frozen-A" },
    body: JSON.stringify(body),
  });

function fixture(
  reply: (path: string, body: Record<string, unknown>) => unknown,
) {
  const calls: {
    path: string;
    token: string | null;
    body: Record<string, unknown>;
  }[] = [];
  const config = {
    url: "https://synthetic.invalid",
    anonKey: "public-only",
    fetch: (async (input, init) => {
      const req = new Request(input, init);
      const path = new URL(req.url).pathname;
      assertEquals(req.headers.get("apikey"), "public-only");
      assertEquals(req.method, "POST");
      const body = await req.json();
      calls.push({ path, token: req.headers.get("authorization"), body });
      const result = reply(path, body);
      return result instanceof Response ? result : Response.json(result);
    }) as typeof fetch,
  };
  return { config, calls };
}
const identity = { id: "canonical-A", role: "Owner" };

for (const scenario of ["session revoked", "non-staff identity"]) {
  Deno.test(`independent identity failure stops action: ${scenario}`, async () => {
    const f = fixture(() =>
      scenario === "session revoked"
        ? Response.json({ code: "PT401", message: "session_invalid" }, {
          status: 401,
        })
        : { id: "canonical-A", role: "User" }
    );
    const response = await handlePortal(
      request({ action: "createLocation", actor: "forged" }),
      f.config,
      origin,
    );
    assertEquals(response.status, scenario === "session revoked" ? 401 : 503);
    const body = await response.json();
    assertEquals(
      body.code,
      scenario === "session revoked" ? "session_invalid" : "admin_unavailable",
    );
    assertEquals(
      body.next_step,
      scenario === "session revoked" ? "sign_in" : undefined,
    );
    assertEquals(f.calls.length, 1);
    assertEquals(f.calls[0].body, { action: "identity", payload: {} });
  });
}

Deno.test("independent expired JWT after identity exposes stable code, not backend detail", async () => {
  const f = fixture((_path, body) =>
    body.action === "identity" ? identity : Response.json({
      code: "PGRST301",
      message: "synthetic private diagnostic",
    }, { status: 401 })
  );
  const response = await handlePortal(
    request({ action: "overview" }),
    f.config,
    origin,
  );
  const body = await response.json();
  assertEquals(response.status, 401);
  assertEquals(body.code, "session_invalid");
  assertEquals(body.next_step, "sign_in");
  assertEquals(JSON.stringify(body).includes("private diagnostic"), false);
  assertEquals(f.calls.length, 2);
});

Deno.test("independent credit post-wait denial preserves code and never returns saved success", async () => {
  const f = fixture((path, body) =>
    body.action === "identity"
      ? identity
      : path.endsWith("admin_resolve_credit")
      ? Response.json({ code: "PT403", message: "admin_access_changed" }, {
        status: 403,
      })
      : { success: true }
  );
  const response = await handlePortal(
    request({
      action: "resolveCredit",
      id: 1,
      decision: "approved",
      actor: "forged",
    }),
    f.config,
    origin,
  );
  const body = await response.json();
  assertEquals(response.status, 403);
  assertEquals(body.code, "admin_access_changed");
  assertEquals(body.next_step, "revalidate");
  assertEquals(body.success, undefined);
  assertEquals(f.calls.length, 3);
  assertEquals(f.calls[2].body, {
    target_refund_id: 1,
    target_decision: "approved",
    resolution_note: "",
  });
});

Deno.test("independent uncertain credit transport does not retry the business operation", async () => {
  const f = fixture((path, body) => {
    if (body.action === "identity") return identity;
    if (path.endsWith("admin_resolve_credit")) {
      throw new TypeError("synthetic lost acknowledgement");
    }
    return { success: true };
  });
  const response = await handlePortal(
    request({ action: "resolveCredit", id: 1, decision: "approved" }),
    f.config,
    origin,
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).code, "admin_unavailable");
  assertEquals(
    f.calls.filter((x) => x.path.endsWith("admin_resolve_credit")).length,
    1,
  );
});

Deno.test("independent legacy handler keeps bearer captured before delayed JSON read", async () => {
  const f = fixture((_path, body) =>
    body.action === "identity" ? identity : {
      success: true,
      alreadyResolved: false,
      status: "denied",
      notificationSent: false,
    }
  );
  const req = request({ refundId: 12, actorUserId: "forged-B" });
  const original = req.json.bind(req);
  let release!: () => void;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  req.json = async () => {
    await held;
    return original();
  };
  const deps = createCreditDependencies(capturedBearer(req), f.config);
  const pending = handleRefundResolution(req, "denied", deps);
  req.headers.set("authorization", "Bearer replacement-B");
  release();
  const response = await pending;
  assertEquals(response.status, 200);
  assertEquals(f.calls.map((x) => x.token), [
    "Bearer frozen-A",
    "Bearer frozen-A",
  ]);
  assertEquals(f.calls[1].body, {
    target_refund_id: 12,
    target_decision: "denied",
    resolution_note: "",
  });
  assertEquals((await response.json()).notificationSent, false);
});
