import assert from "node:assert/strict";
import "https://esm.sh/@supabase/supabase-js@2.97.0";

const originalGet = Deno.env.get;
Deno.env.get = () => undefined;
const modules = await (async () => {
  try {
    return {
      logic: await import("./logic.ts"),
      shared: await import("../_shared/cortina.ts"),
    };
  } finally {
    Deno.env.get = originalGet;
  }
})();
const project = "https://vend.example.invalid";
const selected = "sb_publishable_synthetic_vend";
const legacy = "synthetic-public";
const service = "synthetic-service";
const selector = "CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME";
const id = "aaaaaaaa-0000-4000-8000-000000000001";
const request = (token = "caller-A") =>
  new Request(`${project}/functions/v1/cortina-vend/wallet`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      apikey: "sb_secret_untrusted",
    },
    body: JSON.stringify({
      machineToken: "public-machine",
      amountCents: 400,
      clientRequestId: id,
    }),
  });
type Call = {
  path: string;
  method: string;
  key: string | null;
  auth: string | null;
  body: unknown;
};

async function offline(
  run: (fixture: {
    config: Record<string, string | undefined>;
    calls: Call[];
    reads: string[];
    send: (req: Request) => Promise<Response>;
    state: {
      authDenied: boolean;
      debitDenied: boolean;
      bound: boolean;
      onAuth?: () => void;
    };
  }) => Promise<void>,
) {
  const get = Deno.env.get;
  const fetch = globalThis.fetch;
  const config: Record<string, string | undefined> = {
    SUPABASE_URL: project,
    SUPABASE_ANON_KEY: legacy,
    SUPABASE_SERVICE_ROLE_KEY: service,
    STRIPE_SECRET_KEY: "sk_test_synthetic",
    [selector]: "vend",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      vend: selected,
      default: "sb_publishable_other",
    }),
  };
  const calls: Call[] = [];
  const reads: string[] = [];
  const state: {
    authDenied: boolean;
    debitDenied: boolean;
    bound: boolean;
    onAuth?: () => void;
  } = {
    authDenied: false,
    debitDenied: false,
    bound: true,
  };
  Deno.env.get = (name) => {
    reads.push(name);
    return config[name];
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init), url = new URL(req.url);
    assert.equal(url.origin, project, "provider HTTP forbidden");
    const body = ["POST", "PATCH"].includes(req.method)
      ? await req.json()
      : undefined;
    calls.push({
      path: url.pathname,
      method: req.method,
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
    if (url.pathname === "/rest/v1/cortina_machine_config") {
      return Response.json({
        machine_id: 1,
        public_machine_token: "public-machine",
        is_enabled: true,
        review_required: false,
        product_codes: { "400": 3 },
        pulse_line_number: null,
      });
    }
    if (url.pathname === "/rest/v1/Machines") {
      return Response.json({
        id: 1,
        Name: "Washer",
        Machine_type: "washer",
        Status: "idle",
        Location_ID: 1,
        washer_size_rate_id: 1,
        is_out_of_service: false,
      });
    }
    if (url.pathname === "/rest/v1/washer_size_rates") {
      return Response.json({
        id: 1,
        price_cents: 400,
        size_label: "12kg",
        is_active: true,
        review_required: false,
      });
    }
    if (
      url.pathname === "/rest/v1/cortina_vend_sessions" && req.method === "POST"
    ) {
      assert.equal(body.user_id, id);
      assert.equal(body.amount_cents, 400);
      assert.equal(body.payment_method, "wallet");
      assert.equal(body.client_request_id, id);
      return Response.json({
        ...body,
        id,
        status: "payment_pending",
        currency: "USD",
        nayax_environment: state.bound ? "sandbox" : null,
        nayax_terminal_id: "1234567890123456",
        nayax_uniqr: null,
        stripe_livemode: false,
      });
    }
    if (url.pathname === "/rest/v1/rpc/redeem_wallet_for_cortina") {
      assert.deepEqual(body, { target_session_id: id });
      return state.debitDenied
        ? Response.json({ code: "PT403", message: "account_restricted" }, {
          status: 403,
        })
        : Response.json({ id: 7 });
    }
    assert.equal(url.pathname, "/rest/v1/cortina_vend_sessions");
    assert.equal(req.method, "PATCH");
    assert.equal(body.status, state.debitDenied ? "failed" : "starting");
    // No Start claim means no provider dispatch; retain the actual claim path.
    return Response.json(null);
  };
  try {
    const deps = {
      admin: modules.shared.createAdminClient("cortina-vend"),
      stripe: modules.shared.createStripeClient(),
    };
    await run({
      config,
      calls,
      reads,
      state,
      send: (req) =>
        modules.logic.handleCortinaVend(req, deps).catch(
          modules.shared.errorResponse,
        ),
    });
  } finally {
    Deno.env.get = get;
    globalThis.fetch = fetch;
  }
}

for (const mode of ["named", "legacy"]) {
  Deno.test(`vend caller keys: actual SDK ${mode} preserves Auth/admin/redemption separation`, async () => {
    await offline(async ({ config, calls, reads, send }) => {
      if (mode === "legacy") delete config[selector];
      const result = await send(request());
      assert.equal(result.status, 200);
      assert.deepEqual(await result.json(), { sessionId: id, accessToken: id });
      const debit = calls.find((call) =>
        call.path.endsWith("/redeem_wallet_for_cortina")
      )!;
      assert.equal(debit.key, mode === "named" ? selected : legacy);
      assert.equal(debit.auth, "Bearer caller-A");
      assert.equal(calls[0].path, "/auth/v1/user");
      assert.equal(calls[0].auth, "Bearer caller-A");
      assert.equal(calls[0].key, service);
      assert(
        calls.filter((call) => call !== debit && call.path !== "/auth/v1/user")
          .every((call) =>
            call.key === service && call.auth === `Bearer ${service}`
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

Deno.test("vend caller keys: explicit invalid name fails503 before Auth/session/debit HTTP", async () => {
  await offline(async ({ config, calls, send }) => {
    for (const name of ["", " vend", "missing", "toString"]) {
      config[selector] = name;
      const result = await send(request());
      assert.equal(result.status, 503);
      assert.deepEqual(await result.json(), {
        error: "Public key configuration unavailable",
        code: "key_configuration_unavailable",
      });
    }
    assert.deepEqual(calls, []);
  });
});

Deno.test("vend caller keys: malformed/wrong-kind dictionary never falls back", async () => {
  await offline(async ({ config, calls, reads, send }) => {
    for (
      const value of [
        undefined,
        "{broken",
        "[]",
        "{}",
        JSON.stringify({ vend: "sb_secret_wrong" }),
      ]
    ) {
      config.SUPABASE_PUBLISHABLE_KEYS = value;
      assert.equal((await send(request())).status, 503);
    }
    assert.deepEqual(calls, []);
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
});

Deno.test("vend caller keys: removal blocks next request until explicit legacy rollback", async () => {
  await offline(async ({ config, calls, send }) => {
    assert.equal((await send(request())).status, 200);
    const count = calls.length;
    config.SUPABASE_PUBLISHABLE_KEYS = "{}";
    assert.equal((await send(request())).status, 503);
    assert.equal(calls.length, count);
    delete config[selector];
    assert.equal((await send(request("caller-B"))).status, 200);
    const debit = calls.filter((call) =>
      call.path.endsWith("/redeem_wallet_for_cortina")
    ).at(-1)!;
    assert.equal(debit.key, legacy);
    assert.equal(debit.auth, "Bearer caller-B");
  });
});

Deno.test("vend caller keys: captured Auth bearer survives later header mutation", async () => {
  await offline(async ({ state, calls, send }) => {
    const req = request();
    state.onAuth = () => req.headers.set("authorization", "Bearer caller-B");
    assert.equal((await send(req)).status, 200);
    assert.equal(
      calls.find((call) => call.path.endsWith("/redeem_wallet_for_cortina"))
        ?.auth,
      "Bearer caller-A",
    );
  });
});

Deno.test("vend caller keys: Auth rejection precedes financial writes", async () => {
  await offline(async ({ state, calls, send }) => {
    state.authDenied = true;
    assert.equal((await send(request())).status, 401);
    assert.equal(calls.length, 1);
  });
});

Deno.test("vend caller keys: admission rejection keeps original debit failure with no fallback", async () => {
  await offline(async ({ state, calls, reads, send }) => {
    state.debitDenied = true;
    const result = await send(request());
    assert.equal(result.status, 402);
    assert.equal((await result.json()).code, "wallet_failed");
    assert.equal(
      calls.filter((call) => call.path.endsWith("/redeem_wallet_for_cortina"))
        .length,
      1,
    );
    assert(
      !calls.some((call) =>
        (call.body as { status?: string })?.status === "starting"
      ),
    );
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
});

Deno.test("vend caller keys: frozen binding guard still prevents redemption", async () => {
  await offline(async ({ state, calls, send }) => {
    state.bound = false;
    const result = await send(request());
    assert.equal(result.status, 409);
    assert.equal((await result.json()).code, "support_required");
    assert(
      !calls.some((call) => call.path.endsWith("/redeem_wallet_for_cortina")),
    );
  });
});

Deno.test("vend caller keys: malformed body still fails before optional configuration", async () => {
  await offline(async ({ config, calls, reads, send }) => {
    config[selector] = "";
    const result = await send(
      new Request(`${project}/functions/v1/cortina-vend/wallet`, {
        method: "POST",
        body: "{bad",
      }),
    );
    assert.equal(result.status, 400);
    assert(!reads.includes(selector));
    assert.deepEqual(calls, []);
  });
});

Deno.test("vend caller keys: missing bearer remains401 without HTTP", async () => {
  await offline(async ({ calls, send }) => {
    const req = request();
    req.headers.delete("authorization");
    assert.equal((await send(req)).status, 401);
    assert.deepEqual(calls, []);
  });
});
