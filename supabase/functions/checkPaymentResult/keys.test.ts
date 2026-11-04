import assert from "node:assert/strict";
import "npm:stripe@^14.0.0";
import "https://esm.sh/@supabase/supabase-js@2";

type Handler = (req: Request) => Promise<Response>;
let handler: Handler | undefined;
let registrations = 0;
const serve = Deno.serve;
const get = Deno.env.get;
const transport = globalThis.fetch;
try {
  Deno.serve = ((value: Handler) => {
    handler = value;
    registrations++;
    return {};
  }) as typeof Deno.serve;
  Deno.env.get = () => {
    throw new Error("unexpected import credentials");
  };
  globalThis.fetch = () => {
    throw new Error("unexpected import HTTP");
  };
  await import("./index.ts");
} finally {
  Deno.serve = serve;
  Deno.env.get = get;
  globalThis.fetch = transport;
}

const project = "https://checkout-status.example.invalid";
const selected = "sb_secret_synthetic_checkout_status";
const legacy = "synthetic-legacy-service";
const selector = "CLEANSTREAM_CHECK_PAYMENT_RESULT_SECRET_KEY_NAME";
const request = (token = "caller-A") =>
  new Request(project, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      apikey: "sb_secret_untrusted",
    },
    body: JSON.stringify({ session_id: "cs_synthetic", key_name: "default" }),
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
    state: {
      authStatus: number;
      rpcStatus: number;
      owner: string;
      paid: boolean;
      onAuth?: () => void;
    };
  }) => Promise<void>,
) {
  const get = Deno.env.get;
  const fetch = globalThis.fetch;
  const config: Record<string, string | undefined> = {
    STRIPE_SECRET_KEY: "sk_test_synthetic",
    SUPABASE_URL: project,
    SUPABASE_SERVICE_ROLE_KEY: legacy,
    [selector]: "checkout-status",
    SUPABASE_SECRET_KEYS: JSON.stringify({
      "checkout-status": selected,
      default: "sb_secret_other",
    }),
  };
  const calls: Call[] = [];
  const reads: string[] = [];
  const state: {
    authStatus: number;
    rpcStatus: number;
    owner: string;
    paid: boolean;
    onAuth?: () => void;
  } = {
    authStatus: 200,
    rpcStatus: 200,
    owner: "user-A",
    paid: true,
  };
  Deno.env.get = (name) => {
    reads.push(name);
    assert(!["SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS"].includes(name));
    return config[name];
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    const body = req.method === "POST" ? await req.json() : undefined;
    calls.push({
      path: url.pathname,
      key: req.headers.get("apikey"),
      auth: req.headers.get("authorization"),
      body,
    });
    if (url.origin === project && url.pathname === "/auth/v1/user") {
      state.onAuth?.();
      return Response.json(
        state.authStatus === 200
          ? { id: "user-A" }
          : { message: "synthetic denied" },
        { status: state.authStatus },
      );
    }
    if (
      url.origin === "https://api.stripe.com" &&
      url.pathname === "/v1/checkout/sessions/cs_synthetic"
    ) {
      assert.equal(
        req.headers.get("authorization"),
        "Bearer sk_test_synthetic",
      );
      assert.equal(url.searchParams.get("expand[0]"), "payment_intent");
      const metadata = {
        user_id: state.owner,
        purpose: "wallet_load",
        amount_cents: "2500",
      };
      return Response.json({
        id: "cs_synthetic",
        mode: "payment",
        status: state.paid ? "complete" : "open",
        payment_status: state.paid ? "paid" : "unpaid",
        currency: "usd",
        amount_total: 2500,
        livemode: false,
        metadata,
        payment_intent: {
          id: "pi_synthetic",
          status: state.paid ? "succeeded" : "processing",
          amount: 2500,
          amount_received: state.paid ? 2500 : 0,
          latest_charge: "ch_synthetic",
          currency: "usd",
          livemode: false,
          metadata,
        },
      });
    }
    assert.equal(url.origin, project, "unexpected external HTTP");
    assert.equal(url.pathname, "/rest/v1/rpc/record_wallet_load_from_stripe");
    assert.deepEqual(body, {
      target_user_id: "user-A",
      amount_cents: 2500,
      stripe_payment_intent_id: "pi_synthetic",
      stripe_checkout_session_id: "cs_synthetic",
      stripe_charge_id: "ch_synthetic",
      stripe_event_id: null,
    });
    return Response.json(
      state.rpcStatus === 200 ? null : { message: "synthetic denied" },
      { status: state.rpcStatus },
    );
  };
  try {
    await run({ config, calls, reads, state });
  } finally {
    Deno.env.get = get;
    globalThis.fetch = fetch;
  }
}

Deno.test("checkout status keys: entrypoint registers without credentials or HTTP", () => {
  assert.equal(registrations, 1);
  assert(handler);
});

for (const mode of ["named", "legacy"]) {
  Deno.test(`checkout status keys: actual SDK ${mode} preserves caller and paid outcome`, async () => {
    await offline(async ({ config, calls, reads }) => {
      if (mode === "legacy") delete config[selector];
      const response = await handler!(request());
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        session_id: "cs_synthetic",
        status: "paid",
        paymentStatus: "succeeded",
        paymentIntentId: "pi_synthetic",
        purpose: "wallet_load",
        amountCents: 2500,
        currency: "usd",
        walletLoadRecorded: true,
      });
      assert.deepEqual(calls.map((call) => call.path), [
        "/auth/v1/user",
        "/v1/checkout/sessions/cs_synthetic",
        "/rest/v1/rpc/record_wallet_load_from_stripe",
      ]);
      assert.equal(calls[0].auth, "Bearer caller-A");
      assert.equal(calls[0].key, mode === "named" ? selected : legacy);
      assert.equal(calls[2].key, mode === "named" ? selected : legacy);
      assert.equal(calls[2].auth, mode === "named" ? null : `Bearer ${legacy}`);
      assert(
        !reads.includes(
          mode === "named"
            ? "SUPABASE_SERVICE_ROLE_KEY"
            : "SUPABASE_SECRET_KEYS",
        ),
      );
    });
  });
}

Deno.test("checkout status keys: invalid selector is sanitized503 before HTTP", async () => {
  await offline(async ({ config, calls }) => {
    for (const name of ["", " checkout-status", "missing", "toString"]) {
      config[selector] = name;
      const response = await handler!(request());
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: "Payment status unavailable",
      });
      assert.equal(response.headers.get("cache-control"), "no-store");
    }
    assert.equal(calls.length, 0);
  });
});

Deno.test("checkout status keys: malformed and wrong-kind entries never fall back", async () => {
  await offline(async ({ config, calls, reads }) => {
    for (
      const dictionary of [
        undefined,
        "{broken",
        "[]",
        JSON.stringify({ default: selected }),
        JSON.stringify({ "checkout-status": "sb_publishable_wrong" }),
      ]
    ) {
      config.SUPABASE_SECRET_KEYS = dictionary;
      assert.equal((await handler!(request())).status, 503);
    }
    assert.equal(calls.length, 0);
    assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  });
});

Deno.test("checkout status keys: removal blocks next call; explicit unset permits rollback", async () => {
  await offline(async ({ config, calls, state }) => {
    state.paid = false;
    assert.equal((await handler!(request())).status, 200);
    config.SUPABASE_SECRET_KEYS = "{}";
    assert.equal((await handler!(request())).status, 503);
    assert.equal(calls.length, 2);
    delete config[selector];
    assert.equal((await handler!(request("caller-B"))).status, 200);
    assert.equal(calls.length, 4);
    assert.equal(calls[2].key, legacy);
    assert.equal(calls[2].auth, "Bearer caller-B");
  });
});

Deno.test("checkout status keys: Auth rejection preserves exact bearer and never retrieves payment", async () => {
  await offline(async ({ calls, state }) => {
    state.authStatus = 401;
    for (const token of ["caller-A", selected]) {
      assert.equal((await handler!(request(token))).status, 401);
      assert.equal(calls.at(-1)?.auth, `Bearer ${token}`);
    }
    assert.equal(calls.length, 2);
    assert(
      calls.every((call) =>
        call.path === "/auth/v1/user" && call.key === selected
      ),
    );
  });
});

Deno.test("checkout status keys: ledger rejection retains paid status and pending reconciliation", async () => {
  await offline(async ({ calls, reads, state }) => {
    state.rpcStatus = 401;
    const response = await handler!(request());
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.status, "paid");
    assert.equal(result.paymentStatus, "succeeded");
    assert.equal(result.walletLoadRecorded, false);
    assert.equal(calls.length, 3);
    assert.equal(calls[2].auth, null);
    assert.equal(calls[2].key, selected);
    assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  });
});

Deno.test("checkout status keys: methods bypass invalid key configuration", async () => {
  await offline(async ({ config, calls, reads }) => {
    config[selector] = "";
    for (const method of ["OPTIONS", "GET"]) {
      const response = await handler!(new Request(project, { method }));
      assert.equal(response.status, method === "OPTIONS" ? 200 : 405);
      assert.equal(response.headers.get("access-control-allow-origin"), "*");
    }
    assert.deepEqual(calls, []);
    assert.deepEqual(reads, []);
  });
});

Deno.test("checkout status keys: missing caller stays401 without HTTP", async () => {
  await offline(async ({ calls }) => {
    const req = request();
    req.headers.delete("authorization");
    assert.equal((await handler!(req)).status, 401);
    assert.deepEqual(calls, []);
  });
});

Deno.test("checkout status keys: foreign payment remains403 without ledger write", async () => {
  await offline(async ({ calls, state }) => {
    state.owner = "user-B";
    assert.equal((await handler!(request())).status, 403);
    assert.equal(calls.length, 2);
  });
});

Deno.test("checkout status keys: unpaid processing never records wallet load", async () => {
  await offline(async ({ calls, state }) => {
    state.paid = false;
    const response = await handler!(request());
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.status, "unpaid");
    assert.equal(result.paymentStatus, "processing");
    assert.equal(result.walletLoadRecorded, false);
    assert.equal(calls.length, 2);
  });
});

Deno.test("checkout status keys: later header mutation does not promote caller to DB authority", async () => {
  await offline(async ({ calls, state }) => {
    const req = request();
    state.onAuth = () => req.headers.set("authorization", "Bearer caller-B");
    assert.equal((await handler!(req)).status, 200);
    assert.equal(calls[0].auth, "Bearer caller-A");
    assert.equal(calls[2].auth, null);
  });
});
