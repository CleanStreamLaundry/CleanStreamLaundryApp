import assert from "node:assert/strict";
import "https://esm.sh/@supabase/supabase-js@2.97.0";

const originalGet = Deno.env.get;
Deno.env.get = () => undefined;
const { handler } = await (async () => {
  try {
    return await import("./index.ts");
  } finally {
    Deno.env.get = originalGet;
  }
})();
const project = "https://topup-refund.example.invalid";
const selected = "sb_publishable_synthetic_refund";
const legacy = "synthetic-public";
const selector = "CLEANSTREAM_TOPUP_REFUND_PUBLISHABLE_KEY_NAME";
const id = "aaaaaaaa-0000-4000-8000-000000000001";
const request = (token = "caller-A", action = "deny") =>
  new Request(project, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      apikey: "sb_secret_untrusted",
      "x-key-name": "default",
    },
    body: JSON.stringify({ action, id }),
  });
type Call = {
  path: string;
  key: string | null;
  auth: string | null;
  body: unknown;
};

async function offline(
  run: (fixture: {
    config: Record<string, string | undefined>;
    calls: Call[];
    reads: string[];
    state: { authDenied: boolean; forbidden: boolean; onAuth?: () => void };
  }) => Promise<void>,
) {
  const get = Deno.env.get;
  const fetch = globalThis.fetch;
  const config: Record<string, string | undefined> = {
    SUPABASE_URL: project,
    SUPABASE_ANON_KEY: legacy,
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
    STRIPE_SECRET_KEY: "sk_test_synthetic",
    [selector]: "refund-public",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      "refund-public": selected,
      default: "sb_publishable_other",
    }),
  };
  const calls: Call[] = [];
  const reads: string[] = [];
  const state: {
    authDenied: boolean;
    forbidden: boolean;
    onAuth?: () => void;
  } = { authDenied: false, forbidden: false };
  Deno.env.get = (name) => {
    reads.push(name);
    return config[name];
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init), url = new URL(req.url);
    assert.equal(url.origin, project, "provider HTTP forbidden");
    const body = req.method === "POST" ? await req.json() : undefined;
    calls.push({
      path: url.pathname,
      key: req.headers.get("apikey"),
      auth: req.headers.get("authorization"),
      body,
    });
    if (url.pathname === "/auth/v1/user") {
      state.onAuth?.();
      return Response.json(state.authDenied ? { message: "denied" } : { id }, {
        status: state.authDenied ? 401 : 200,
      });
    }
    if (url.pathname === "/rest/v1/rpc/review_voluntary_topup_refund") {
      assert.equal(body.p_id, id);
      assert.equal(body.p_note, null);
      assert(["deny", "approve"].includes(body.p_action));
      assert.deepEqual(Object.keys(body).sort(), [
        "p_action",
        "p_id",
        "p_note",
      ]);
      return state.forbidden
        ? Response.json({ code: "PT403", message: "owner_required" }, {
          status: 403,
        })
        : Response.json({
          id,
          status: body.p_action === "deny" ? "denied" : "approved",
        });
    }
    assert.equal(url.pathname, "/rest/v1/rpc/prepare_voluntary_topup_refund");
    assert.deepEqual(body, { p_id: id });
    // No dispatch operation: prove admin/caller separation without provider calls.
    return Response.json(null);
  };
  try {
    await run({ config, calls, reads, state });
  } finally {
    Deno.env.get = get;
    globalThis.fetch = fetch;
  }
}

for (const mode of ["named", "legacy"]) {
  Deno.test(`topup refund caller keys: actual SDK ${mode} retains exact bearer and review contract`, async () => {
    await offline(async ({ config, calls, reads }) => {
      if (mode === "legacy") delete config[selector];
      const result = await handler(request());
      assert.equal(result.status, 200);
      assert.deepEqual(await result.json(), { data: { id, status: "denied" } });
      assert.equal(calls.length, 2);
      assert.deepEqual(calls.map((call) => call.path), [
        "/auth/v1/user",
        "/rest/v1/rpc/review_voluntary_topup_refund",
      ]);
      assert(
        calls.every((call) =>
          call.key === (mode === "named" ? selected : legacy) &&
          call.auth === "Bearer caller-A"
        ),
      );
      assert(
        !reads.includes(
          mode === "named" ? "SUPABASE_ANON_KEY" : "SUPABASE_PUBLISHABLE_KEYS",
        ),
      );
    });
  });
}

Deno.test("topup refund caller keys: invalid explicit name fails503 before HTTP", async () => {
  await offline(async ({ config, calls }) => {
    for (const name of ["", " refund-public", "missing", "toString"]) {
      config[selector] = name;
      const result = await handler(request());
      assert.equal(result.status, 503);
      assert.deepEqual(await result.json(), {
        error: "Public key configuration unavailable",
        code: "key_configuration_unavailable",
      });
    }
    assert.deepEqual(calls, []);
  });
});

Deno.test("topup refund caller keys: wrong-kind/malformed dictionary cannot restore legacy", async () => {
  await offline(async ({ config, calls, reads }) => {
    for (
      const value of [
        undefined,
        "{broken",
        "[]",
        "{}",
        JSON.stringify({ "refund-public": "sb_secret_wrong" }),
      ]
    ) {
      config.SUPABASE_PUBLISHABLE_KEYS = value;
      assert.equal((await handler(request())).status, 503);
    }
    assert.deepEqual(calls, []);
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
});

Deno.test("topup refund caller keys: removal stops next request until explicit unset", async () => {
  await offline(async ({ config, calls }) => {
    assert.equal((await handler(request())).status, 200);
    config.SUPABASE_PUBLISHABLE_KEYS = "{}";
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 2);
    delete config[selector];
    assert.equal((await handler(request("caller-B"))).status, 200);
    assert.equal(calls.length, 4);
    assert(
      calls.slice(2).every((call) =>
        call.key === legacy && call.auth === "Bearer caller-B"
      ),
    );
  });
});

Deno.test("topup refund caller keys: captured bearer survives Auth-time header mutation", async () => {
  await offline(async ({ calls, state }) => {
    const req = request();
    state.onAuth = () => req.headers.set("authorization", "Bearer caller-B");
    assert.equal((await handler(req)).status, 200);
    assert(calls.every((call) => call.auth === "Bearer caller-A"));
  });
});

Deno.test("topup refund caller keys: rejected Auth never reaches review or provider", async () => {
  await offline(async ({ state, calls }) => {
    state.authDenied = true;
    assert.equal((await handler(request())).status, 401);
    assert.equal(calls.length, 1);
  });
});

Deno.test("topup refund caller keys: admission/owner rejection has no retry or privileged promotion", async () => {
  await offline(async ({ state, calls, reads }) => {
    state.forbidden = true;
    const result = await handler(request("caller-A", "approve"));
    assert.equal(result.status, 403);
    assert.deepEqual(await result.json(), {
      error: "owner_or_location_forbidden",
    });
    assert.equal(calls.length, 2);
    assert(calls.every((call) => call.key === selected));
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
});

Deno.test("topup refund caller keys: OPTIONS bypasses all key configuration", async () => {
  await offline(async ({ config, calls, reads }) => {
    config[selector] = "";
    assert.equal(
      (await handler(new Request(project, { method: "OPTIONS" }))).status,
      200,
    );
    assert.deepEqual(reads, []);
    assert.deepEqual(calls, []);
  });
});

Deno.test("topup refund caller keys: missing bearer and method handling retain existing outcomes", async () => {
  await offline(async ({ calls }) => {
    const req = request();
    req.headers.delete("authorization");
    assert.equal((await handler(req)).status, 401);
    assert.equal((await handler(new Request(project))).status, 405);
    assert.deepEqual(calls, []);
  });
});

Deno.test("topup refund caller keys: named public and accepted named admin transport stay distinct", async () => {
  await offline(async ({ config, calls }) => {
    config.CLEANSTREAM_TOPUP_REFUND_SECRET_KEY_NAME = "refund-service";
    config.SUPABASE_SECRET_KEYS = JSON.stringify({
      "refund-service": "sb_secret_synthetic_refund",
    });
    const result = await handler(request("caller-A", "approve"));
    assert.equal(result.status, 202);
    assert.equal(calls.length, 3);
    assert(
      calls.slice(0, 2).every((call) =>
        call.key === selected && call.auth === "Bearer caller-A"
      ),
    );
    assert.equal(calls[2].key, "sb_secret_synthetic_refund");
    assert.equal(calls[2].auth, null);
    assert.deepEqual(await result.json(), { data: { id, status: "approved" } });
  });
});

Deno.test("topup refund caller keys: accepted admin selector still fails closed independently", async () => {
  await offline(async ({ config, calls }) => {
    config.CLEANSTREAM_TOPUP_REFUND_SECRET_KEY_NAME = "";
    const result = await handler(request());
    assert.equal(result.status, 503);
    assert.equal((await result.json()).code, "key_configuration_unavailable");
    assert.deepEqual(calls, []);
  });
});
