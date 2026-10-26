import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type Stripe from "npm:stripe@^14.0.0";
import { getPaymentStatusLogic, type PaymentDeps } from "./logic.ts";
import { recordWalletLoadFromIntent } from "../paymentIntentStatus/logic.ts";
import { handleStripeWebhook } from "../stripeWebhook/logic.ts";

function intent(
  overrides: Partial<Stripe.PaymentIntent> = {},
): Stripe.PaymentIntent {
  return {
    id: "pi_test",
    status: "succeeded",
    currency: "usd",
    amount: 2500,
    amount_received: 2500,
    livemode: false,
    latest_charge: "ch_test",
    metadata: {
      user_id: "user-1",
      purpose: "wallet_load",
      amount_cents: "2500",
    },
    ...overrides,
  } as Stripe.PaymentIntent;
}

function session(
  overrides: Partial<Stripe.Checkout.Session> = {},
): Stripe.Checkout.Session {
  return {
    id: "cs_test",
    mode: "payment",
    status: "complete",
    payment_status: "paid",
    amount_total: 2500,
    currency: "usd",
    livemode: false,
    metadata: {
      user_id: "user-1",
      purpose: "wallet_load",
      amount_cents: "2500",
    },
    payment_intent: intent(),
    ...overrides,
  } as Stripe.Checkout.Session;
}

function request(body: unknown = { session_id: "cs_test" }, token = "token-1") {
  return new Request("http://localhost/checkPaymentResult", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

function fixture(value = session(), user: string | null = "user-1") {
  const calls: string[] = [];
  const rpcCalls: { name: string; params: Record<string, unknown> }[] = [];
  const deps: PaymentDeps = {
    retrieveSession: async (id) => {
      calls.push(`stripe:${id}`);
      return value;
    },
    supabaseAdmin: {
      auth: {
        getUser: async (token: string) => {
          calls.push(`auth:${token}`);
          return {
            data: { user: user ? { id: user } : null },
            error: user ? null : new Error("private auth detail"),
          };
        },
      },
      rpc: (name: string, params: Record<string, unknown>) => {
        calls.push("rpc");
        rpcCalls.push({ name, params });
        return Promise.resolve({ data: "wallet-1", error: null });
      },
    } as unknown as PaymentDeps["supabaseAdmin"],
  };
  return { deps, calls, rpcCalls };
}

Deno.test("owner receives additive correlated paid wallet contract after authentication", async () => {
  const { deps, calls, rpcCalls } = fixture();
  const response = await getPaymentStatusLogic(
    request({
      session_id: "cs_test",
      user_id: "user-2",
      amountCents: 1,
      purpose: "direct_machine_payment",
      paymentIntentId: "pi_other",
    }),
    deps,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    session_id: "cs_test",
    status: "paid",
    paymentStatus: "succeeded",
    paymentIntentId: "pi_test",
    purpose: "wallet_load",
    amountCents: 2500,
    currency: "usd",
    walletLoadRecorded: true,
  });
  assertEquals(calls, ["auth:token-1", "stripe:cs_test", "rpc"]);
  assertEquals(rpcCalls, [{
    name: "record_wallet_load_from_stripe",
    params: {
      target_user_id: "user-1",
      amount_cents: 2500,
      stripe_payment_intent_id: "pi_test",
      stripe_checkout_session_id: "cs_test",
      stripe_charge_id: "ch_test",
      stripe_event_id: null,
    },
  }]);
});

for (const token of ["", "invalid-token"]) {
  Deno.test(`rejects ${token || "missing token"} before Stripe or ledger`, async () => {
    const { deps, calls } = fixture(session(), null);
    const response = await getPaymentStatusLogic(
      request(undefined, token),
      deps,
    );
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { error: "Unauthorized" });
    assertEquals(calls, token ? [`auth:${token}`] : []);
  });
}

for (
  const body of [null, {}, { session_id: "" }, { session_id: 1 }, {
    session_id: "pi_test",
  }, { session_id: "cs_test?expand=customer" }]
) {
  Deno.test(`invalid session request ${JSON.stringify(body)} never retrieves Stripe`, async () => {
    const { deps, calls } = fixture();
    assertEquals(
      (await getPaymentStatusLogic(request(body), deps)).status,
      400,
    );
    assertEquals(calls, ["auth:token-1"]);
  });
}

Deno.test("malformed JSON is a sanitized client error after authentication", async () => {
  const { deps, calls } = fixture();
  const response = await getPaymentStatusLogic(
    new Request("http://localhost/status", {
      method: "POST",
      headers: { Authorization: "Bearer token-1" },
      body: "private-invalid-json",
    }),
    deps,
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "Invalid request" });
  assertEquals(calls, ["auth:token-1"]);
});

const mismatchCases: [string, Stripe.Checkout.Session, number][] = [
  [
    "session owner",
    session({ metadata: { ...session().metadata, user_id: "user-2" } }),
    403,
  ],
  ["missing session owner", session({ metadata: null }), 403],
  [
    "intent owner",
    session({
      payment_intent: intent({
        metadata: { ...intent().metadata, user_id: "user-2" },
      }),
    }),
    403,
  ],
  [
    "missing intent owner",
    session({ payment_intent: intent({ metadata: {} }) }),
    403,
  ],
  ["session id", session({ id: "cs_other" }), 409],
  ["session mode", session({ mode: "subscription" }), 409],
  ["session currency", session({ currency: "eur" }), 409],
  [
    "intent currency",
    session({ payment_intent: intent({ currency: "eur" }) }),
    409,
  ],
  ["intent amount", session({ payment_intent: intent({ amount: 100 }) }), 409],
  ["zero amount", session({ amount_total: 0 }), 409],
  ["fractional amount", session({ amount_total: 2500.5 }), 409],
  ["null amount", session({ amount_total: null }), 409],
  [
    "session metadata amount",
    session({ metadata: { ...session().metadata, amount_cents: "100" } }),
    409,
  ],
  [
    "intent metadata amount",
    session({
      payment_intent: intent({
        metadata: { ...intent().metadata, amount_cents: "100" },
      }),
    }),
    409,
  ],
  [
    "unsupported purpose",
    session({ metadata: { ...session().metadata, purpose: "cortina_vend" } }),
    409,
  ],
  [
    "missing purpose",
    session({ metadata: { user_id: "user-1", amount_cents: "2500" } }),
    409,
  ],
  [
    "intent purpose",
    session({
      payment_intent: intent({
        metadata: { ...intent().metadata, purpose: "direct_machine_payment" },
      }),
    }),
    409,
  ],
  ["intent mode", session({ payment_intent: intent({ livemode: true }) }), 409],
  ["unexpanded intent", session({ payment_intent: "pi_test" }), 503],
];

for (const [name, value, status] of mismatchCases) {
  Deno.test(`rejects mismatched ${name} without ledger access or financial details`, async () => {
    const { deps, rpcCalls } = fixture(value);
    const response = await getPaymentStatusLogic(
      request({
        session_id: "cs_test",
        user_id: "user-2",
        amount: 100,
        paymentIntentId: "pi_other",
      }),
      deps,
    );
    assertEquals(response.status, status);
    assertEquals(Object.keys(await response.json()), ["error"]);
    assertEquals(rpcCalls, []);
  });
}

const statusCases: [string, Stripe.Checkout.Session, string][] = [
  [
    "expired canceled intent with received funds",
    session({
      status: "expired",
      payment_status: "unpaid",
      payment_intent: intent({ status: "canceled" }),
    }),
    "unknown",
  ],
  [
    "expired unconfirmed intent with received funds",
    session({
      status: "expired",
      payment_status: "unpaid",
      payment_intent: intent({ status: "requires_payment_method" }),
    }),
    "unknown",
  ],
  [
    "open without intent",
    session({ status: "open", payment_status: "unpaid", payment_intent: null }),
    "processing",
  ],
  [
    "open declined card",
    session({
      status: "open",
      payment_status: "unpaid",
      payment_intent: intent({
        status: "requires_payment_method",
        amount_received: 0,
      }),
    }),
    "processing",
  ],
  [
    "open action required",
    session({
      status: "open",
      payment_status: "unpaid",
      payment_intent: intent({ status: "requires_action", amount_received: 0 }),
    }),
    "processing",
  ],
  [
    "complete unpaid",
    session({
      payment_status: "unpaid",
      payment_intent: intent({ status: "processing", amount_received: 0 }),
    }),
    "processing",
  ],
  [
    "expired without intent",
    session({
      status: "expired",
      payment_status: "unpaid",
      payment_intent: null,
    }),
    "canceled",
  ],
  [
    "expired canceled intent",
    session({
      status: "expired",
      payment_status: "unpaid",
      payment_intent: intent({ status: "canceled", amount_received: 0 }),
    }),
    "canceled",
  ],
  [
    "expired unconfirmed intent",
    session({
      status: "expired",
      payment_status: "unpaid",
      payment_intent: intent({
        status: "requires_payment_method",
        amount_received: 0,
      }),
    }),
    "canceled",
  ],
  [
    "expired processing intent",
    session({
      status: "expired",
      payment_status: "unpaid",
      payment_intent: intent({ status: "processing", amount_received: 0 }),
    }),
    "unknown",
  ],
  [
    "expired succeeded intent",
    session({ status: "expired", payment_status: "unpaid" }),
    "unknown",
  ],
  ["paid without intent", session({ payment_intent: null }), "unknown"],
  [
    "paid processing intent",
    session({ payment_intent: intent({ status: "processing" }) }),
    "unknown",
  ],
  [
    "paid wrong received amount",
    session({ payment_intent: intent({ amount_received: 2000 }) }),
    "unknown",
  ],
  ["unpaid succeeded intent", session({ payment_status: "unpaid" }), "unknown"],
  [
    "no payment required",
    session({ payment_status: "no_payment_required" }),
    "unknown",
  ],
  ["missing session status", session({ status: null }), "unknown"],
];

for (const [name, value, expected] of statusCases) {
  Deno.test(`${name} returns ${expected}, never credits wallet`, async () => {
    const { deps, rpcCalls } = fixture(value);
    const response = await getPaymentStatusLogic(request(), deps);
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.status, value.payment_status);
    assertEquals(body.paymentStatus, expected);
    assertEquals(body.walletLoadRecorded, false);
    assertEquals(
      body.paymentIntentId,
      typeof value.payment_intent === "object"
        ? value.payment_intent?.id ?? null
        : value.payment_intent,
    );
    assertEquals(rpcCalls, []);
  });
}

Deno.test("direct-machine payment succeeds without a wallet mutation", async () => {
  const metadata = { ...intent().metadata, purpose: "direct_machine_payment" };
  const { deps, rpcCalls } = fixture(
    session({ metadata, payment_intent: intent({ metadata }) }),
  );
  const body = await (await getPaymentStatusLogic(request(), deps)).json();
  assertEquals(body.paymentStatus, "succeeded");
  assertEquals(body.purpose, "direct_machine_payment");
  assertEquals(body.walletLoadRecorded, false);
  assertEquals(rpcCalls, []);
});

for (const throws of [false, true]) {
  Deno.test(`RPC ${throws ? "throw" : "error"} preserves paid status without leaking error, later retry reconciles`, async () => {
    const { deps } = fixture();
    let calls = 0;
    deps.supabaseAdmin.rpc = (() => {
      calls++;
      if (calls === 1 && throws) throw new Error("private database detail");
      return Promise.resolve({
        data: calls === 1 ? null : "wallet-1",
        error: calls === 1 ? { message: "private database detail" } : null,
      });
    }) as unknown as typeof deps.supabaseAdmin.rpc;
    const first = await getPaymentStatusLogic(request(), deps);
    const firstBody = await first.json();
    assertEquals(first.status, 200);
    assertEquals(firstBody.paymentStatus, "succeeded");
    assertEquals(firstBody.walletLoadRecorded, false);
    assertEquals(JSON.stringify(firstBody).includes("private"), false);
    assertEquals(
      (await (await getPaymentStatusLogic(request(), deps)).json())
        .walletLoadRecorded,
      true,
    );
    assertEquals(calls, 2);
  });
}

Deno.test("does not report wallet ready before delayed ledger confirmation", async () => {
  const { deps } = fixture();
  let finish!: (value: { data: string; error: null }) => void;
  let started!: () => void;
  const entered = new Promise<void>((resolve) => {
    started = resolve;
  });
  const pending = new Promise<{ data: string; error: null }>((resolve) => {
    finish = resolve;
  });
  deps.supabaseAdmin.rpc = (() => {
    started();
    return pending;
  }) as unknown as typeof deps.supabaseAdmin.rpc;
  let settled = false;
  const response = getPaymentStatusLogic(request(), deps).then((value) => {
    settled = true;
    return value;
  });
  await entered;
  assertEquals(settled, false);
  finish({ data: "wallet-1", error: null });
  assertEquals((await (await response).json()).walletLoadRecorded, true);
});

Deno.test("status retries, mobile helper and webhook forward the same canonical idempotency identifiers", async () => {
  const { deps, rpcCalls } = fixture();
  await getPaymentStatusLogic(request(), deps);
  await getPaymentStatusLogic(request(), deps);
  await recordWalletLoadFromIntent(intent(), "user-1", deps.supabaseAdmin);
  let webhookParams: Record<string, unknown> | undefined;
  await handleStripeWebhook({ rawBody: "synthetic", signature: "synthetic" }, {
    verifyAndConstructEvent: async () => ({
      id: "evt_test",
      type: "checkout.session.completed",
      data: { object: session({ payment_intent: "pi_test" }) },
    }),
    recordWalletLoad: async (params) => {
      webhookParams = params;
    },
  });
  assertEquals(rpcCalls[0], rpcCalls[1]);
  assertEquals(rpcCalls.map((call) => call.params.stripe_payment_intent_id), [
    "pi_test",
    "pi_test",
    "pi_test",
  ]);
  assertEquals(rpcCalls[2].params.stripe_checkout_session_id, null);
  assertEquals(webhookParams?.stripe_payment_intent_id, "pi_test");
  assertEquals(webhookParams?.stripe_checkout_session_id, "cs_test");
  // This verifies identifier parity, not PostgreSQL concurrency/locking.
});
