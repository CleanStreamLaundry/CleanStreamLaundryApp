import assert from "node:assert/strict";
import { handleCreatePaymentIntent } from "../paymentIntent/logic.ts";
import { handleCheckout } from "../createCheckoutSession/logic.ts";
import {
  captureFundingAdmission,
  FUNDING_PUBLIC_KEY_SELECTOR,
  FundingAdmissionError,
} from "./wallet_funding_admission.ts";
import { captureWalletLoadConsent } from "./loyalty_action_consent.ts";

const subject = "00000000-0000-4000-8000-000000000001";
const wallet = "00000000-0000-4000-8000-000000000002";
const contextId = "00000000-0000-4000-8000-000000000003";
const eligible = {
  subject_id: subject,
  account_access: "eligible",
  next_step: "home",
};
const config: Record<string, string> = {
  SUPABASE_URL: "https://synthetic.invalid/",
  SUPABASE_ANON_KEY: "legacy-public-key",
};
const env = (name: string) => {
  assert.notEqual(name, "SUPABASE_SERVICE_ROLE_KEY");
  assert.notEqual(name, "SUPABASE_SECRET_KEYS");
  return config[name];
};
type Endpoint = "intent" | "checkout";
type Options = {
  replies?: unknown[];
  purpose?: string;
  noGate?: boolean;
  authError?: boolean;
  walletError?: boolean;
  beforeWalletReturns?: () => Promise<void>;
  transportFailure?: "throw" | "timeout" | "json" | number;
  failureAt?: number;
};

function scenario(endpoint: Endpoint, options: Options = {}) {
  const events: string[] = [], providerParams: Record<string, unknown>[] = [];
  const signals: (AbortSignal | null | undefined)[] = [];
  const request = new Request("https://functions.synthetic.invalid/funding", {
    method: "POST",
    headers: { Authorization: "Bearer original-token" },
    body: JSON.stringify({
      amount: 2500,
      purpose: options.purpose ?? "walletLoad",
      user_id: "forged-user",
      consent: { context_id: contextId, acknowledged: true },
    }),
  });
  let checks = 0;
  const transport: typeof fetch = (input, init) => {
    events.push("admission");
    signals.push(init?.signal);
    const checkNumber = checks++;
    assert.equal(
      input,
      "https://synthetic.invalid/rest/v1/rpc/get_admission_status",
    );
    assert.equal(init?.method, "POST");
    assert.equal(init?.body, "{}");
    assert.equal(init?.redirect, "error");
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("Authorization"), "Bearer original-token");
    assert.equal(headers.get("apikey"), "legacy-public-key");
    if (checkNumber === (options.failureAt ?? 0)) {
      if (options.transportFailure === "throw") {
        throw new Error("private upstream diagnostic");
      }
      if (options.transportFailure === "timeout") {
        return Promise.reject(
          new DOMException("private upstream timeout", "TimeoutError"),
        );
      }
      if (options.transportFailure === "json") {
        return Promise.resolve(new Response("private invalid json"));
      }
      if (typeof options.transportFailure === "number") {
        return Promise.resolve(
          new Response("private upstream diagnostic", {
            status: options.transportFailure,
          }),
        );
      }
    }
    return Promise.resolve(
      Response.json((options.replies ?? [eligible, eligible, eligible, eligible])[checkNumber]),
    );
  };
  const verifiedUser = { id: subject };
  const auth = {
    getUser: (token?: string) => {
      events.push("auth");
      if (endpoint === "intent") assert.equal(token, "original-token");
      return Promise.resolve({
        data: { user: options.authError ? null : verifiedUser },
        error: options.authError ? { message: "invalid" } : null,
      });
    },
  };
  const admin = {
    auth,
    rpc: (name: string, params: unknown) => {
      if (name === "new_payments_enabled") return {
        abortSignal: () => Promise.resolve({ data: true, error: null }),
      };
      if (name === "bind_wallet_load_consent_provider") {
        events.push("bind");
        assert.deepEqual(params, {
          p_context_id: contextId, p_subject_id: subject, p_amount_cents: 2500,
          p_channel: endpoint === "intent" ? "payment_intent" : "checkout",
          p_provider_reference: endpoint === "intent" ? "pi_synthetic" : "cs_synthetic",
        });
        return Promise.resolve({ data: null, error: null });
      }
      return (async () => {
      events.push("wallet");
      assert.equal(name, "get_or_create_wallet_account");
      assert.deepEqual(params, { target_user_id: subject });
      await options.beforeWalletReturns?.();
      return options.walletError
        ? { data: null, error: { message: "Wallet unavailable" } }
        : { data: wallet, error: null };
      })();
    },
  };
  const stripe = {
    paymentIntents: {
      create: (params: Record<string, unknown>) => {
        events.push("stripe");
        providerParams.push(params);
        return Promise.resolve({
          id: "pi_synthetic",
          client_secret: "synthetic-client-secret",
          amount: 2500, currency: "usd", metadata: params.metadata,
        });
      },
    },
    checkout: {
      sessions: {
        create: (params: Record<string, unknown>) => {
          events.push("stripe");
          providerParams.push(params);
          return Promise.resolve({
            id: "cs_synthetic",
            url: "https://checkout.synthetic.invalid",
            amount_total: 2500, currency: "usd", metadata: params.metadata,
          });
        },
      },
    },
  };
  const deps = {
    stripe,
    supabaseAdmin: admin,
    supabase: { auth },
    fundingAdmission: options.noGate
      ? undefined
      : captureFundingAdmission(request, env, transport),
    walletLoadConsent: captureWalletLoadConsent(request, env, async (input, init) => {
      events.push("consent");
      assert.equal(input, "https://synthetic.invalid/rest/v1/rpc/accept_wallet_load_consent");
      const headers = new Headers(init?.headers);
      assert.equal(headers.get("Authorization"), "Bearer original-token");
      assert.equal(headers.get("apikey"), "legacy-public-key");
      const channel = endpoint === "intent" ? "payment_intent" : "checkout";
      assert.deepEqual(JSON.parse(String(init?.body)), {
        p_context_id: contextId, p_acknowledged: true, p_amount_cents: 2500, p_channel: channel,
      });
      return Response.json({ context_id: contextId, subject_id: subject, wallet_account_id: wallet,
        amount_cents: 2500, channel, accepted_at: "2026-10-05T15:00:00Z",
        policy_version: "synthetic-policy", policy_sha256: "a".repeat(64), provider_reference: null });
    }),
  };
  const run = () =>
    endpoint === "intent"
      ? handleCreatePaymentIntent(
        request,
        deps as unknown as Parameters<typeof handleCreatePaymentIntent>[1],
      )
      : handleCheckout(
        request,
        deps as unknown as Parameters<typeof handleCheckout>[1],
        "https://app.synthetic.invalid",
      );
  return { run, events, providerParams, request, verifiedUser, signals };
}

for (const endpoint of ["intent", "checkout"] as const) {
  Deno.test(`${endpoint}: caller checks surround wallet, consent and provider creation and preserve metadata/receipt`, async () => {
    const s = scenario(endpoint), response = await s.run();
    assert.deepEqual(s.events, [
      "auth",
      "admission",
      "wallet",
      "admission",
      "consent",
      "admission",
      "stripe",
      "bind",
      "admission",
    ]);
    assert.equal(response.status, 200);
    assert.equal(s.providerParams.length, 1);
    const params = s.providerParams[0];
    assert.deepEqual(params.metadata, {
      user_id: subject,
      purpose: "wallet_load",
      amount_cents: "2500",
      wallet_account_id: wallet,
      consent_context_id: contextId,
      consent_policy_version: "synthetic-policy",
      consent_policy_sha256: "a".repeat(64),
    });
    if (endpoint === "intent") {
      assert.equal(params.amount, 2500);
      assert.equal(params.currency, "usd");
      assert.deepEqual(await response.json(), {
        clientSecret: "synthetic-client-secret",
        paymentIntentId: "pi_synthetic",
      });
    } else {
      assert.deepEqual(params.payment_intent_data, {
        metadata: params.metadata,
      });
      assert.equal(
        params.success_url,
        "https://app.synthetic.invalid/homePage",
      );
      assert.equal(params.cancel_url, "https://app.synthetic.invalid/homePage");
      assert.deepEqual(await response.json(), {
        url: "https://checkout.synthetic.invalid",
        session_id: "cs_synthetic",
      });
    }
  });
  const denied: [string, unknown, number][] = [
    ["pending deletion", {
      ...eligible,
      account_access: "restricted",
      next_step: "restore_account",
    }, 403],
    ["MFA", {
      ...eligible,
      account_access: "restricted",
      next_step: "challenge_totp",
    }, 403],
    ["terms", { ...eligible, next_step: "accept_terms" }, 403],
    ["foreign subject", { ...eligible, subject_id: "another-subject" }, 401],
    ["missing subject", { account_access: "eligible", next_step: "home" }, 503],
    ["missing access", { subject_id: subject, next_step: "home" }, 503],
    [
      "missing next step",
      { subject_id: subject, account_access: "eligible" },
      503,
    ],
    ["null", null, 503],
    ["array", [eligible], 503],
  ];
  for (const [name, reply, status] of denied) {
    for (const afterWallet of [false, true]) {
      Deno.test(`${endpoint}: ${name} denied ${afterWallet ? "after wallet await" : "before wallet"}`, async () => {
        const s = scenario(endpoint, {
          replies: afterWallet ? [eligible, reply] : [reply],
        });
        await assert.rejects(
          s.run,
          (e: unknown) =>
            e instanceof FundingAdmissionError && e.status === status,
        );
        assert.deepEqual(
          s.events,
          afterWallet
            ? ["auth", "admission", "wallet", "admission"]
            : ["auth", "admission"],
        );
        assert.equal(s.providerParams.length, 0);
      });
    }
  }
  for (
    const [failure, status] of [
      [401, 401],
      [403, 403],
      [500, 503],
      [404, 503],
      ["throw", 503],
      ["timeout", 503],
      ["json", 503],
    ] as const
  ) {
    for (const failureAt of [0, 1]) {
      Deno.test(`${endpoint}: RPC ${failure} at check ${failureAt} fails closed with sanitized error`, async () => {
        const s = scenario(endpoint, { transportFailure: failure, failureAt });
        await assert.rejects(
          s.run,
          (e: unknown) =>
            e instanceof FundingAdmissionError && e.status === status &&
            (status !== 503 || e.message === "admission_unavailable") &&
            !e.message.includes("private"),
        );
        assert.equal(s.signals.length, failureAt + 1);
        for (const signal of s.signals) {
          assert.ok(signal instanceof AbortSignal);
          assert.equal(signal.aborted, false);
        }
        assert.deepEqual(
          s.events,
          failureAt === 0
            ? ["auth", "admission"]
            : ["auth", "admission", "wallet", "admission"],
        );
        assert.equal(s.providerParams.length, 0);
      });
    }
  }
  Deno.test(`${endpoint}: missing gate dependency never falls back to service identity`, async () => {
    const s = scenario(endpoint, { noGate: true });
    await assert.rejects(
      s.run,
      (e: unknown) => e instanceof FundingAdmissionError && e.status === 503,
    );
    assert.deepEqual(s.events, ["auth"]);
  });
  for (const failureAt of [2, 3]) {
    Deno.test(`${endpoint}: captured admission still fails closed at post-consent check ${failureAt}`, async () => {
      const s = scenario(endpoint, { transportFailure: 403, failureAt });
      await assert.rejects(s.run, (e: unknown) => e instanceof FundingAdmissionError && e.status === 403);
      assert.equal(s.signals.length, failureAt + 1);
      assert.equal(s.providerParams.length, failureAt === 2 ? 0 : 1);
      assert.equal(s.events.includes("bind"), failureAt === 3);
    });
  }
  Deno.test(`${endpoint}: invalid auth never reaches admission, wallet or Stripe`, async () => {
    const s = scenario(endpoint, { authError: true });
    await assert.rejects(s.run, /Unauthorized/);
    assert.deepEqual(s.events, ["auth"]);
  });
  Deno.test(`${endpoint}: wallet failure never proceeds to provider creation`, async () => {
    const s = scenario(endpoint, { walletError: true });
    await assert.rejects(s.run, /Wallet unavailable/);
    assert.deepEqual(s.events, ["auth", "admission", "wallet"]);
  });
  Deno.test(`${endpoint}: unrelated direct-machine behavior does not gain a funding gate`, async () => {
    const s = scenario(endpoint, {
      purpose: "directMachinePayment",
      noGate: true,
    });
    const response = await s.run();
    assert.equal(response.status, 200);
    assert.deepEqual(s.events, ["auth", "stripe"]);
    assert.deepEqual(s.providerParams[0].metadata, {
      user_id: subject,
      purpose: "direct_machine_payment",
      amount_cents: "2500",
    });
  });
  Deno.test(`${endpoint}: original bearer and subject survive a delayed wallet lookup`, async () => {
    let release!: () => void, entered!: () => void;
    const waiting = new Promise<void>((resolve) => {
      release = resolve;
    });
    const ready = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const s = scenario(endpoint, {
      beforeWalletReturns: async () => {
        entered();
        await waiting;
      },
    });
    const work = s.run();
    await ready;
    assert.deepEqual(s.events, ["auth", "admission", "wallet"]);
    s.request.headers.set("Authorization", "Bearer different-account-token");
    s.verifiedUser.id = "different-account";
    release();
    assert.equal((await work).status, 200);
    assert.deepEqual(s.events, [
      "auth",
      "admission",
      "wallet",
      "admission",
      "consent",
      "admission",
      "stripe",
      "bind",
      "admission",
    ]);
  });
}

for (
  const authorization of [
    null,
    "",
    "Basic token",
    "Bearer",
    "Bearer token extra",
  ]
) {
  Deno.test(`funding capture rejects missing/malformed bearer ${authorization}`, async () => {
    let fetched = false;
    const request = new Request("https://synthetic.invalid", {
      headers: authorization === null ? {} : { Authorization: authorization },
    });
    const check = captureFundingAdmission(request, env, () => {
      fetched = true;
      throw new Error("must not fetch");
    });
    await assert.rejects(
      () => check(subject),
      (e: unknown) => e instanceof FundingAdmissionError && e.status === 401,
    );
    assert.equal(fetched, false);
  });
}
Deno.test("funding capture reuses exact named public key selection without changing the bearer", async () => {
  const values = {
    ...config,
    [FUNDING_PUBLIC_KEY_SELECTOR]: "funding",
    SUPABASE_PUBLISHABLE_KEYS:
      '{"funding":"sb_publishable_funding","other":"sb_publishable_other"}',
  };
  let calls = 0;
  const check = captureFundingAdmission(
    new Request("https://synthetic.invalid", {
      headers: { Authorization: "Bearer original-token" },
    }),
    (name) => values[name as keyof typeof values],
    (_input, init) => {
      calls++;
      assert.equal(
        new Headers(init?.headers).get("apikey"),
        "sb_publishable_funding",
      );
      assert.equal(
        new Headers(init?.headers).get("Authorization"),
        "Bearer original-token",
      );
      return Promise.resolve(Response.json(eligible));
    },
  );
  await check(subject);
  await check(subject);
  assert.equal(calls, 2);
});
for (
  const values of [
    {
      ...config,
      [FUNDING_PUBLIC_KEY_SELECTOR]: "missing",
      SUPABASE_PUBLISHABLE_KEYS: '{"other":"sb_publishable_other"}',
    },
    {
      ...config,
      [FUNDING_PUBLIC_KEY_SELECTOR]: "",
      SUPABASE_PUBLISHABLE_KEYS: "{}",
    },
    { ...config, SUPABASE_URL: "" },
  ]
) {
  Deno.test(`funding misconfiguration is closed ${JSON.stringify(values)}`, async () => {
    let fetched = false;
    const check = captureFundingAdmission(
      new Request("https://synthetic.invalid", {
        headers: { Authorization: "Bearer original-token" },
      }),
      (name) => values[name as keyof typeof values],
      () => {
        fetched = true;
        throw new Error("must not fetch");
      },
    );
    await assert.rejects(
      () => check(subject),
      (e: unknown) => e instanceof FundingAdmissionError && e.status === 503,
    );
    assert.equal(fetched, false);
  });
}
