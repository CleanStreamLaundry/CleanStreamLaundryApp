import assert from "node:assert/strict";
import { checkoutHandler } from "./index.ts";

const subject = "00000000-0000-4000-8000-000000000001";
const wallet = "00000000-0000-4000-8000-000000000002";
const consentId = "00000000-0000-4000-8000-000000000003";
const selected = "sb_secret_synthetic_checkout";
const selector = "CLEANSTREAM_CHECKOUT_SECRET_KEY_NAME";
const values = (): Record<string, string | undefined> => ({
  SUPABASE_URL: "https://funding.synthetic.invalid",
  SUPABASE_ANON_KEY: "synthetic-public-key",
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-legacy-service",
  STRIPE_SECRET_KEY: "sk_test_synthetic_only",
  [selector]: "checkout-only",
  CLEANSTREAM_PAYMENT_INTENT_SECRET_KEY_NAME: "wrong-component",
  SUPABASE_SECRET_KEYS: JSON.stringify({
    default: "sb_secret_wrong_default", "checkout-only": selected,
    "wrong-component": "sb_secret_wrong_component",
  }),
});
const request = (purpose = "walletLoad", method = "POST") =>
  new Request("https://edge.synthetic.invalid/createCheckoutSession", {
    method, headers: { Authorization: "Bearer original-caller" },
    ...(method === "POST" ? { body: JSON.stringify({ amount: 2500, purpose,
      consent: { context_id: consentId, acknowledged: true } }) } : {}),
  });

async function fixture(
  config: Record<string, string | undefined>,
  action: (calls: Request[], reads: string[]) => Promise<void>,
  denyAt = -1,
  unauthorized = false,
  control: { replies?: unknown[]; status?: number; timeout?: boolean } = {},
) {
  const originalFetch = globalThis.fetch, originalEnv = Deno.env.get;
  const calls: Request[] = [], reads: string[] = [];
  let admissions = 0, controlReads = 0;
  try {
    // Real SDKs, synthetic HTTP only; no process secrets are inspected or set.
    Deno.env.get = (name) => { reads.push(name); return config[name]; };
    globalThis.fetch = async (input, init) => {
      const req = new Request(input, init), url = new URL(req.url);
      calls.push(req);
      if (url.origin === "https://funding.synthetic.invalid") {
        if (url.pathname === "/auth/v1/user") return Promise.resolve(unauthorized
          ? Response.json({ message: "Invalid caller" }, { status: 401 })
          : Response.json({ id: subject }));
        if (url.pathname === "/rest/v1/rpc/new_payments_enabled") {
          assert(req.signal instanceof AbortSignal);
          assert.equal(req.signal.aborted, false);
          if (control.timeout) return Promise.reject(new DOMException("private timeout detail", "TimeoutError"));
          return Promise.resolve(Response.json((control.replies ?? [true, true])[controlReads++],
            { status: control.status ?? 200 }));
        }
        if (url.pathname === "/rest/v1/rpc/get_admission_status") {
          const denied = admissions++ === denyAt;
          return Promise.resolve(Response.json({
            subject_id: subject, account_access: denied ? "restricted" : "eligible",
            next_step: denied ? "blocked" : "home",
          }));
        }
        if (url.pathname === "/rest/v1/rpc/get_or_create_wallet_account") {
          return Response.json(wallet);
        }
        if (url.pathname === "/rest/v1/rpc/accept_wallet_load_consent") {
          assert.equal(req.headers.get("Authorization"), "Bearer original-caller");
          return Response.json({ context_id: consentId, subject_id: subject, wallet_account_id: wallet,
            amount_cents: 2500, channel: "checkout", accepted_at: "2026-10-05T15:00:00Z",
            policy_version: "synthetic-policy", policy_sha256: "a".repeat(64), provider_reference: null });
        }
        if (url.pathname === "/rest/v1/rpc/bind_wallet_load_consent_provider") {
          return Response.json(null);
        }
      }
      if (url.origin === "https://api.stripe.com" && url.pathname === "/v1/checkout/sessions") {
        const form = new URLSearchParams(await req.clone().text());
        const metadata = Object.fromEntries([...form].filter(([key]) => key.startsWith("metadata["))
          .map(([key,value]) => [key.slice(9,-1),value]));
        return Response.json({ id: "cs_synthetic", url: "https://checkout.synthetic.invalid",
          amount: 2500, amount_total: 2500, currency: "usd", metadata });
      }
      throw new Error("Unexpected offline request");
    };
    await action(calls, reads);
  } finally { globalThis.fetch = originalFetch; Deno.env.get = originalEnv; }
}

for (const named of [true, false]) {
  Deno.test("checkout real SDK " + (named ? "named" : "legacy") + " service transport preserves caller and funding metadata", async () => {
    const config = values();
    if (!named) { delete config[selector]; config.SUPABASE_SECRET_KEYS = "{unused-broken-map"; }
    await fixture(config, async (calls, reads) => {
      const result = await checkoutHandler(request());
      assert.equal(result.status, 200);
      assert.deepEqual(await result.json(), { url: "https://checkout.synthetic.invalid", session_id: "cs_synthetic" });
      assert.deepEqual(calls.map((r) => new URL(r.url).pathname), [
        "/auth/v1/user", "/rest/v1/rpc/get_admission_status", "/rest/v1/rpc/new_payments_enabled",
        "/rest/v1/rpc/get_or_create_wallet_account", "/rest/v1/rpc/get_admission_status",
        "/rest/v1/rpc/accept_wallet_load_consent", "/rest/v1/rpc/get_admission_status",
        "/rest/v1/rpc/new_payments_enabled", "/v1/checkout/sessions",
        "/rest/v1/rpc/bind_wallet_load_consent_provider", "/rest/v1/rpc/get_admission_status",
      ]);
      const serviceKey = named ? selected : config.SUPABASE_SERVICE_ROLE_KEY;
      assert.equal(calls[0].headers.get("apikey"), config.SUPABASE_ANON_KEY);
      assert.equal(calls[0].headers.get("Authorization"), "Bearer original-caller");
      assert.equal(calls[3].headers.get("apikey"), serviceKey);
      assert.equal(calls[3].headers.get("Authorization"), named ? null : "Bearer " + serviceKey);
      assert.deepEqual(await calls[3].json(), { target_user_id: subject });
      for (const i of [1, 4, 6, 10]) {
        assert.equal(calls[i].headers.get("apikey"), config.SUPABASE_ANON_KEY);
        assert.equal(calls[i].headers.get("Authorization"), "Bearer original-caller");
      }
      for (const i of [2, 7]) {
        assert.equal(calls[i].headers.get("apikey"), serviceKey);
        assert.equal(calls[i].headers.get("Authorization"), named ? null : "Bearer " + serviceKey);
        assert.equal(await calls[i].text(), "{}");
      }
      const form = new URLSearchParams(await calls[8].text());
      assert.equal(form.get("metadata[user_id]"), subject);
      assert.equal(form.get("metadata[purpose]"), "wallet_load");
      assert.equal(form.get("metadata[wallet_account_id]"), wallet);
      assert.equal(form.get("line_items[0][price_data][unit_amount]"), "2500");
      assert.equal(form.get("payment_intent_data[metadata][wallet_account_id]"), wallet);
      assert.equal(calls[8].headers.get("Stripe-Version"), "2023-10-16");
      assert.equal(calls[8].headers.get("Idempotency-Key"), `loyalty-load:${consentId}`);
      assert.equal(form.get("metadata[consent_context_id]"), consentId);
      assert.equal(reads.includes(named ? "SUPABASE_SERVICE_ROLE_KEY" : "SUPABASE_SECRET_KEYS"), false);
      assert.equal(reads.includes("CLEANSTREAM_PAYMENT_INTENT_SECRET_KEY_NAME"), false);
    });
  });
}

for (const [label, name, ring] of [
  ["empty selector", "", JSON.stringify({ "": selected })],
  ["leading space", " checkout-only", JSON.stringify({ " checkout-only": selected })],
  ["trailing space", "checkout-only ", JSON.stringify({ "checkout-only ": selected })],
  ["control character", "checkout-only\n", JSON.stringify({ ["checkout-only\n"]: selected })],
  ["missing name", "missing", JSON.stringify({ default: selected })],
  ["inherited name", "toString", "{}"],
  ["missing map", "checkout-only", undefined],
  ["malformed map", "checkout-only", "{broken"],
  ["array map", "checkout-only", "[]"],
  ["null map", "checkout-only", "null"],
  ["non-string key", "checkout-only", JSON.stringify({ "checkout-only": 5 })],
  ["publishable key", "checkout-only", JSON.stringify({ "checkout-only": "sb_publishable_wrong" })],
  ["empty key", "checkout-only", JSON.stringify({ "checkout-only": "" })],
  ["padded key", "checkout-only", JSON.stringify({ "checkout-only": " " + selected })],
] as const) {
  Deno.test("checkout invalid explicit secret " + label + " fails before SDK or provider without fallback", async () => {
    await fixture({ ...values(), [selector]: name, SUPABASE_SECRET_KEYS: ring,
      SUPABASE_URL: "invalid-SDK-url", STRIPE_SECRET_KEY: undefined }, async (calls, reads) => {
      const req = request(), result = await checkoutHandler(req);
      assert.equal(result.status, 503);
      assert.deepEqual(await result.json(), { error: "Server configuration unavailable" });
      assert.equal(result.headers.get("Access-Control-Allow-Origin"), "*");
      assert.equal(req.bodyUsed, false);
      assert.equal(calls.length, 0);
      assert.equal(reads.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
      assert.equal(reads.includes("SUPABASE_URL"), false);
      assert.equal(reads.includes("STRIPE_SECRET_KEY"), false);
    });
  });
}
Deno.test("checkout absent selector cannot fall back to modern default when legacy missing", async () => {
  const config = values(); delete config[selector]; delete config.SUPABASE_SERVICE_ROLE_KEY;
  await fixture(config, async (calls, reads) => {
    const result = await checkoutHandler(request());
    assert.equal(result.status, 503);
    assert.deepEqual(await result.json(), { error: "Server configuration unavailable" });
    assert.equal(calls.length, 0); assert.equal(reads.includes("SUPABASE_SECRET_KEYS"), false);
  });
});
Deno.test("checkout preflight remains credential-free", async () => {
  await fixture({}, async (calls, reads) => {
    const result = await checkoutHandler(request("walletLoad", "OPTIONS"));
    assert.equal(result.status, 200); assert.equal(result.headers.get("Access-Control-Allow-Origin"), "*");
    assert.deepEqual(calls, []); assert.deepEqual(reads, []);
  });
});
Deno.test("checkout exact public selector remains separate from selected service secret", async () => {
  await fixture({ ...values(), CLEANSTREAM_FUNDING_PUBLISHABLE_KEY_NAME: "caller",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ caller: "sb_publishable_synthetic_caller" }),
  }, async (calls) => {
    assert.equal((await checkoutHandler(request())).status, 200);
    for (const i of [0, 1, 4]) {
      assert.equal(calls[i].headers.get("apikey"), "sb_publishable_synthetic_caller");
      assert.equal(calls[i].headers.get("Authorization"), "Bearer original-caller");
    }
    assert.equal(calls[3].headers.get("apikey"), selected);
    assert.equal(calls[3].headers.has("Authorization"), false);
  });
});
Deno.test("checkout invalid caller never reaches admission wallet or Stripe", async () => {
  await fixture(values(), async (calls) => {
    const result = await checkoutHandler(request());
    assert.equal(result.status, 401);
    assert.deepEqual(await result.json(), { error: "Unauthorized" });
    assert.deepEqual(calls.map((r) => new URL(r.url).pathname), ["/auth/v1/user"]);
    assert.equal(calls[0].headers.get("Authorization"), "Bearer original-caller");
  }, -1, true);
});
for (const deniedAt of [0, 1]) {
  Deno.test("checkout named service key does not bypass canonical admission check " + deniedAt, async () => {
    await fixture(values(), async (calls) => {
      const result = await checkoutHandler(request());
      assert.equal(result.status, 403);
      assert.deepEqual(await result.json(), { error: "account_restricted" });
      assert.equal(calls.some((r) => new URL(r.url).hostname === "api.stripe.com"), false);
      assert.equal(calls.length, deniedAt === 0 ? 2 : 5);
    }, deniedAt);
  });
}
Deno.test("checkout named key preserves existing direct-machine branch without wallet RPC", async () => {
  await fixture(values(), async (calls) => {
    const result = await checkoutHandler(request("directMachinePayment"));
    assert.equal(result.status, 200);
    assert.deepEqual(calls.map((r) => new URL(r.url).pathname), ["/auth/v1/user", "/rest/v1/rpc/new_payments_enabled", "/v1/checkout/sessions"]);
    const form = new URLSearchParams(await calls[2].text());
    assert.equal(form.get("metadata[purpose]"), "direct_machine_payment");
    assert.equal(form.has("metadata[wallet_account_id]"), false);
  });
});

for (const [purpose, replies, walletCalls] of [
  ["walletLoad", [false], 0],
  ["walletLoad", [true, false], 1],
  ["directMachinePayment", [false], 0],
] as const) {
  Deno.test("createCheckoutSession creation control rejects " + purpose + " at read " + replies.length + " before provider", async () => {
    await fixture(values(), async (calls) => {
      const response = await checkoutHandler(request(purpose));
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { error: "new_payments_unavailable" });
      assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
      assert.equal(calls.filter((r) => new URL(r.url).pathname.endsWith("/get_or_create_wallet_account")).length, walletCalls);
      assert.equal(calls.filter((r) => new URL(r.url).pathname.endsWith("/new_payments_enabled")).length, replies.length);
      assert.equal(calls.some((r) => new URL(r.url).hostname === "api.stripe.com"), false);
    }, -1, false, { replies: [...replies] });
  });
}
for (const control of [
  { replies: [null] }, { replies: ["true"] }, { replies: [{ enabled: true }] },
  { replies: [[true]] }, { replies: [{ message: "private missing RPC" }], status: 404 },
  { timeout: true },
]) {
  Deno.test("createCheckoutSession malformed or unavailable creation control is sanitized " + JSON.stringify(control), async () => {
    await fixture(values(), async (calls) => {
      const response = await checkoutHandler(request());
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { error: "new_payments_unavailable" });
      assert.equal(calls.some((r) => new URL(r.url).pathname.endsWith("/get_or_create_wallet_account")), false);
      assert.equal(calls.some((r) => new URL(r.url).hostname === "api.stripe.com"), false);
    }, -1, false, control);
  });
}
