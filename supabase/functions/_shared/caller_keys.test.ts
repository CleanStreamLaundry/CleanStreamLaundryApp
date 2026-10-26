import assert from "node:assert/strict";

// Refund CORS reads one env name during import. Never read the host environment.
const originalEnv = Deno.env.get;
Deno.env.get = () => undefined;
const handlers = await (async () => {
  try {
    return {
      "admin-portal": (await import("../admin-portal/index.ts")).handler,
      approveRefund: (await import("../approveRefund/index.ts")).handler,
      denyRefund: (await import("../denyRefund/index.ts")).handler,
      "delete-account": (await import("../delete-account/index.ts")).handler,
    };
  } finally {
    Deno.env.get = originalEnv;
  }
})();

type Component = keyof typeof handlers;
const components = Object.keys(handlers) as Component[];
const project = "https://synthetic.invalid";
const selected = "sb_publishable_synthetic_selected";
const legacy = "synthetic-legacy-public";
const selector = (component: Component) =>
  component === "delete-account"
    ? "CLEANSTREAM_ACCOUNT_PUBLISHABLE_KEY_NAME"
    : "CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME";
const body = (component: Component) =>
  component === "delete-account"
    ? { user_id: "caller" }
    : component === "admin-portal"
    ? { action: "locations" }
    : { refundId: 12, note: "Reviewed" };
const request = (component: Component, token = "captured-A") =>
  new Request(`${project}/${component}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: "sb_secret_untrusted_request",
      "x-key-name": "default",
    },
    body: JSON.stringify({ ...body(component), key_name: "default" }),
  });

async function offline(
  component: Component,
  run: (fixture: {
    config: Record<string, string | undefined>;
    calls: {
      path: string;
      auth: string | null;
      key: string | null;
      body: unknown;
    }[];
    reads: string[];
    fail: () => void;
  }) => Promise<void>,
) {
  const env = Deno.env.get;
  const fetch = globalThis.fetch;
  const config: Record<string, string | undefined> = {
    SUPABASE_URL: project,
    SUPABASE_ANON_KEY: legacy,
    [selector(component)]: "selected",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      selected,
      default: "sb_publishable_synthetic_other",
    }),
  };
  const calls: {
    path: string;
    auth: string | null;
    key: string | null;
    body: unknown;
  }[] = [];
  const reads: string[] = [];
  let rejected = false;
  Deno.env.get = (name) => {
    reads.push(name);
    return config[name];
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    assert.equal(new URL(req.url).origin, project);
    const path = new URL(req.url).pathname;
    const args = req.method === "POST" ? await req.json() : undefined;
    calls.push({
      path,
      auth: req.headers.get("authorization"),
      key: req.headers.get("apikey"),
      body: args,
    });
    if (rejected) {
      return Response.json({ code: "PT401", message: "session_invalid" }, {
        status: 401,
      });
    }
    if (path === "/auth/v1/user") return Response.json({ id: "caller" });
    if (path === "/rest/v1/rpc/admin_portal_request") {
      return Response.json(
        args.action === "identity" ? { id: "caller", role: "Owner" } : [],
      );
    }
    if (path === "/rest/v1/rpc/admin_resolve_credit") {
      return Response.json({
        success: true,
        alreadyResolved: false,
        refundId: 12,
        transactionId: 44,
        customerId: "customer",
        amount: 4,
        status: args.target_decision,
        notificationSent: false,
      });
    }
    assert.equal(path, "/rest/v1/rpc/request_account_deletion");
    return Response.json({
      subject_id: "caller",
      account_access: "restricted",
      next_step: "blocked",
      reason: "explicit_restore_required",
      account_state: "pending_deletion",
      restore_until: "2026-10-30T00:00:00Z",
    });
  };
  try {
    await run({
      config,
      calls,
      reads,
      fail: () => {
        rejected = true;
      },
    });
    assert(!reads.includes("SUPABASE_SECRET_KEYS"));
    assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  } finally {
    Deno.env.get = env;
    globalThis.fetch = fetch;
  }
}

for (const component of components) {
  for (const mode of ["named", "legacy"]) {
    Deno.test(`caller keys: ${component} ${mode} uses captured bearer and existing RPCs`, async () => {
      await offline(component, async ({ config, calls, reads }) => {
        if (mode === "legacy") delete config[selector(component)];
        const response = await handlers[component](request(component));
        assert.equal(response.status, 200);
        const result = await response.json();
        if (component === "approveRefund" || component === "denyRefund") {
          assert.equal(
            result.status,
            component === "approveRefund" ? "approved" : "denied",
          );
          assert.equal(result.notificationSent, false);
          assert.match(result.notificationWarning, /not enabled/);
        }
        assert.equal(calls.length, 2);
        for (const call of calls) {
          assert.equal(call.auth, "Bearer captured-A");
          assert.equal(call.key, mode === "named" ? selected : legacy);
        }
        if (component === "delete-account") {
          assert.deepEqual(calls.map((call) => call.path), [
            "/auth/v1/user",
            "/rest/v1/rpc/request_account_deletion",
          ]);
          assert.deepEqual(calls[1].body, {});
        } else {
          assert.equal(calls[0].path, "/rest/v1/rpc/admin_portal_request");
          assert.deepEqual(calls[0].body, { action: "identity", payload: {} });
          assert.equal(
            calls[1].path,
            component === "admin-portal"
              ? "/rest/v1/rpc/admin_portal_request"
              : "/rest/v1/rpc/admin_resolve_credit",
          );
        }
        assert(
          !reads.includes(
            mode === "named"
              ? "SUPABASE_ANON_KEY"
              : "SUPABASE_PUBLISHABLE_KEYS",
          ),
        );
        assert.equal(
          reads.filter((name) => name === selector(component)).length,
          component === "delete-account" ? 2 : 1,
        );
      });
    });
  }

  Deno.test(`caller keys: ${component} bad explicit config fails closed before HTTP`, async () => {
    await offline(component, async ({ config, calls, reads }) => {
      const dictionary = config.SUPABASE_PUBLISHABLE_KEYS;
      for (const invalid of ["", " selected", "missing", "toString"]) {
        config[selector(component)] = invalid;
        assert.equal(
          (await handlers[component](request(component))).status,
          503,
        );
      }
      config[selector(component)] = "selected";
      for (
        const invalid of [
          undefined,
          "{broken",
          JSON.stringify({ selected: "sb_secret_synthetic_wrong_kind" }),
        ]
      ) {
        config.SUPABASE_PUBLISHABLE_KEYS = invalid;
        const response = await handlers[component](request(component));
        assert.equal(response.status, 503);
        const text = await response.text();
        assert(!text.includes("sb_secret"));
        assert(!text.includes("SUPABASE"));
      }
      assert.equal(calls.length, 0);
      assert(!reads.includes("SUPABASE_ANON_KEY"));
      config.SUPABASE_PUBLISHABLE_KEYS = dictionary;
    });
  });

  Deno.test(`caller keys: ${component} removal stops HTTP until explicit legacy rollback`, async () => {
    await offline(component, async ({ config, calls }) => {
      assert.equal((await handlers[component](request(component))).status, 200);
      config.SUPABASE_PUBLISHABLE_KEYS = JSON.stringify({ default: selected });
      assert.equal((await handlers[component](request(component))).status, 503);
      assert.equal(calls.length, 2);
      delete config[selector(component)];
      assert.equal(
        (await handlers[component](request(component, "captured-B"))).status,
        200,
      );
      assert.equal(calls.length, 4);
      assert(
        calls.slice(2).every((call) =>
          call.key === legacy && call.auth === "Bearer captured-B"
        ),
      );
    });
  });

  Deno.test(`caller keys: ${component} rejected named key never retries legacy`, async () => {
    await offline(component, async ({ calls, reads, fail }) => {
      fail();
      const response = await handlers[component](request(component));
      assert.equal(response.status, 401);
      assert.equal(calls.length, 1);
      assert.equal(calls[0].key, selected);
      assert.equal(calls[0].auth, "Bearer captured-A");
      assert(!reads.includes("SUPABASE_ANON_KEY"));
    });
  });

  Deno.test(`caller keys: ${component} preserves preflight, method and missing-bearer handling`, async () => {
    await offline(component, async ({ config, calls, reads }) => {
      for (const name of ["selected", ""]) {
        config[selector(component)] = name;
        const options = await handlers[component](
          new Request(project, { method: "OPTIONS" }),
        );
        assert.equal(
          options.status,
          component === "approveRefund" || component === "denyRefund"
            ? 204
            : 200,
        );
        assert(
          options.headers.get("access-control-allow-headers")?.toLowerCase()
            .includes("authorization"),
        );
        assert.equal(
          (await handlers[component](new Request(project))).status,
          405,
        );
      }
      assert(!reads.includes(selector(component)));
      config[selector(component)] = "selected";
      const missing = request(component);
      missing.headers.delete("authorization");
      assert.equal((await handlers[component](missing)).status, 401);
      assert.equal(calls.length, 0);
    });
  });
}

for (const component of ["approveRefund", "denyRefund"] as const) {
  Deno.test(`caller keys: ${component} validates body before guarded SDK initialization`, async () => {
    await offline(component, async ({ config, calls, reads }) => {
      config.SUPABASE_URL = "not-a-url";
      config[selector(component)] = "";
      const malformed = new Request(project, {
        method: "POST",
        headers: { Authorization: "Bearer captured-A" },
        body: "{broken",
      });
      assert.equal((await handlers[component](malformed)).status, 400);
      assert(!reads.includes(selector(component)));
      config[selector(component)] = "selected";
      const response = await handlers[component](request(component));
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: "The credit service is temporarily unavailable.",
      });
      assert.equal(
        response.headers.get("access-control-allow-origin"),
        "https://cleanstreamlaundry.com",
      );
      assert.equal(calls.length, 0);
    });
  });
}
