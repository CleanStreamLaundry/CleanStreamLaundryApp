import {
    handleStripeWebhook,
    selectWebhookSecret,
    type Dependencies,
    type StripeEvent,
  } from "./logic.ts";
  
  import {
    assertEquals,
    assert,
    assertThrows,
    assertRejects,
    assertStrictEquals,
  } from "https://deno.land/std@0.224.0/testing/asserts.ts";

  Deno.test("selects separate live and sandbox webhook secrets", () => {
    const secrets = { live: "live-secret", sandbox: "sandbox-secret" };
    assertEquals(selectWebhookSecret('{"livemode":true}', secrets), "live-secret");
    assertEquals(selectWebhookSecret('{"livemode":false}', secrets), "sandbox-secret");
  });

  Deno.test("preserves the existing secret before sandbox configuration", () => {
    assertEquals(
      selectWebhookSecret('{"livemode":false}', { live: "existing-secret" }),
      "existing-secret",
    );
  });

  Deno.test("does not use the sandbox secret for live events", () => {
    assertThrows(() => selectWebhookSecret('{"livemode":true}', { sandbox: "test" }));
  });

  Deno.test("rejects missing secrets, invalid JSON, and invalid event modes", () => {
    assertThrows(() => selectWebhookSecret('{"livemode":false}', {}));
    for (const body of ["not JSON", "null", "{}", '{"livemode":"false"}']) {
      assertThrows(() => selectWebhookSecret(body, { live: "test" }));
    }
  });
  
  
  function createDeps(options?: {
    eventType?: string;
    shouldThrow?: boolean;
  }) {
    const walletLoads: unknown[] = [];
    const cortinaPayments: unknown[] = [];
    let verificationCalls = 0;
  
    return {
      deps: {
        verifyAndConstructEvent: async () => {
          verificationCalls++;
          if (options?.shouldThrow) {
            throw new Error("Invalid signature");
          }
  
          return {
            id: "evt_checkout",
            type: options?.eventType ?? "checkout.session.completed",
            data: {
              object: {
                id: "cs_checkout",
                payment_intent: "pi_checkout",
                metadata: { user_id: "user123", purpose: "wallet_load" },
                amount_total: 5000,
              },
            },
          };
        },
  
        recordWalletLoad: async (payload: unknown) => {
          walletLoads.push(payload);
        },
        recordCortinaPayment: async (payload: unknown) => {
          cortinaPayments.push(payload);
        },
      },
      walletLoads,
      cortinaPayments,
      getVerificationCalls: () => verificationCalls,
    };
  }

  
  Deno.test("returns 400 if signature missing", async () => {
    const { deps, walletLoads, cortinaPayments, getVerificationCalls } = createDeps();
  
    const result = await handleStripeWebhook(
      { rawBody: "{}", signature: null },
      deps
    );
  
    assertEquals(result.status, 400);
    assertEquals(result.body, "No signature");
    assertEquals(getVerificationCalls(), 0);
    assertEquals(walletLoads, []);
    assertEquals(cortinaPayments, []);
  });
  
  Deno.test("returns 400 if verification fails", async () => {
    const { deps, walletLoads, cortinaPayments, getVerificationCalls } = createDeps({ shouldThrow: true });
  
    const result = await handleStripeWebhook(
      { rawBody: "{}", signature: "sig" },
      deps
    );
  
    assertEquals(result.status, 400);
    assert(result.body.includes("Invalid signature"));
    assertEquals(getVerificationCalls(), 1);
    assertEquals(walletLoads, []);
    assertEquals(cortinaPayments, []);
  });
  
  Deno.test("records Checkout wallet load without a broadcast dependency", async () => {
    const { deps, walletLoads, cortinaPayments } = createDeps();
  
    const result = await handleStripeWebhook(
      { rawBody: "{}", signature: "sig" },
      deps
    );
  
    assertEquals(result, { status: 200, body: "OK" });
    assertEquals(walletLoads, [{
      user_id: "user123",
      amount_cents: 5000,
      stripe_payment_intent_id: "pi_checkout",
      stripe_checkout_session_id: "cs_checkout",
      stripe_event_id: "evt_checkout",
    }]);
    assertEquals(cortinaPayments, []);
  });
  
  Deno.test("ignores other event types without financial effects", async () => {
    const { deps, walletLoads, cortinaPayments } = createDeps({
      eventType: "payment.failed",
    });
  
    const result = await handleStripeWebhook(
      { rawBody: "{}", signature: "sig" },
      deps
    );
  
    assertEquals(result, { status: 200, body: "OK" });
    assertEquals(walletLoads, []);
    assertEquals(cortinaPayments, []);
  });

  Deno.test("routes Cortina PaymentIntent success to vend orchestration", async () => {
    let captured: any = null;
    const result = await handleStripeWebhook(
      { rawBody: "{}", signature: "sig" },
      {
        verifyAndConstructEvent: async () => ({
          id: "evt_cortina",
          type: "payment_intent.succeeded",
          data: {
            object: {
              id: "pi_cortina",
              amount_received: 450,
              latest_charge: "ch_cortina",
              metadata: {
                purpose: "cortina_vend",
                cortina_session_id: "vend-123",
              },
            },
          },
        }),
        recordCortinaPayment: async (payload) => {
          captured = payload;
        },
      },
    );

    assertEquals(result.status, 200);
    assertEquals(captured, {
      event_id: "evt_cortina",
      session_id: "vend-123",
      amount_cents: 450,
      stripe_payment_intent_id: "pi_cortina",
      stripe_charge_id: "ch_cortina",
    });
  });

const recordingCases: {
  name: string;
  event: StripeEvent;
  recorder: "recordWalletLoad" | "recordCortinaPayment";
  payload: Record<string, unknown>;
}[] = [
  {
    name: "Checkout wallet load",
    event: {
      id: "evt_wallet_checkout",
      type: "checkout.session.completed",
      data: { object: {
        id: "cs_wallet",
        payment_intent: "pi_wallet",
        amount_total: 2500,
        metadata: { purpose: "wallet_load", user_id: "user-wallet" },
      } },
    },
    recorder: "recordWalletLoad",
    payload: {
      user_id: "user-wallet",
      amount_cents: 2500,
      stripe_payment_intent_id: "pi_wallet",
      stripe_checkout_session_id: "cs_wallet",
      stripe_event_id: "evt_wallet_checkout",
    },
  },
  {
    name: "PaymentIntent wallet load",
    event: {
      id: "evt_wallet_intent",
      type: "payment_intent.succeeded",
      data: { object: {
        id: "pi_wallet",
        amount: 9999,
        amount_received: 2500,
        latest_charge: { id: "ch_wallet" },
        metadata: { purpose: "wallet_load", user_id: "user-wallet" },
      } },
    },
    recorder: "recordWalletLoad",
    payload: {
      user_id: "user-wallet",
      amount_cents: 2500,
      stripe_payment_intent_id: "pi_wallet",
      stripe_charge_id: "ch_wallet",
      stripe_event_id: "evt_wallet_intent",
    },
  },
  {
    name: "Checkout Cortina payment",
    event: {
      id: "evt_cortina_checkout",
      type: "checkout.session.completed",
      data: { object: {
        id: "cs_cortina",
        payment_intent: "pi_cortina",
        amount_total: 450,
        metadata: { purpose: "cortina_vend", cortina_session_id: "vend-123" },
      } },
    },
    recorder: "recordCortinaPayment",
    payload: {
      event_id: "evt_cortina_checkout",
      session_id: "vend-123",
      amount_cents: 450,
      stripe_payment_intent_id: "pi_cortina",
      stripe_checkout_session_id: "cs_cortina",
    },
  },
  {
    name: "PaymentIntent Cortina payment",
    event: {
      id: "evt_cortina_intent",
      type: "payment_intent.succeeded",
      data: { object: {
        id: "pi_cortina",
        amount: 9999,
        amount_received: 450,
        latest_charge: "ch_cortina",
        metadata: { purpose: "cortina_vend", cortina_session_id: "vend-123" },
      } },
    },
    recorder: "recordCortinaPayment",
    payload: {
      event_id: "evt_cortina_intent",
      session_id: "vend-123",
      amount_cents: 450,
      stripe_payment_intent_id: "pi_cortina",
      stripe_charge_id: "ch_cortina",
    },
  },
];

for (const scenario of recordingCases) {
  Deno.test(`${scenario.name} awaits unchanged financial recording without broadcasts`, async () => {
    let finish!: () => void;
    let started!: () => void;
    const entered = new Promise<void>((resolve) => { started = resolve; });
    const pending = new Promise<void>((resolve) => { finish = resolve; });
    const calls: unknown[] = [];
    const deps: Dependencies = {
      verifyAndConstructEvent: async (body, signature) => {
        calls.push({ body, signature });
        return scenario.event;
      },
      recordWalletLoad: async (payload) => {
        calls.push({ recorder: "recordWalletLoad", payload });
        started();
        await pending;
      },
      recordCortinaPayment: async (payload) => {
        calls.push({ recorder: "recordCortinaPayment", payload });
        started();
        await pending;
      },
    };
    let settled = false;
    const response = handleStripeWebhook(
      { rawBody: "exact synthetic body", signature: "synthetic-signature" },
      deps,
    ).then((result) => {
      settled = true;
      return result;
    });
    await entered;
    await Promise.resolve();
    assertEquals(settled, false);
    assertEquals(calls, [
      { body: "exact synthetic body", signature: "synthetic-signature" },
      { recorder: scenario.recorder, payload: scenario.payload },
    ]);
    finish();
    assertEquals(await response, { status: 200, body: "OK" });
    assertEquals(calls.length, 2);
  });

  Deno.test(`${scenario.name} propagates recording/provider errors instead of acknowledging success`, async () => {
    const failure = new Error("synthetic recorder/provider failure");
    const calls: unknown[] = [];
    const rejected = await assertRejects(() => handleStripeWebhook(
      { rawBody: "synthetic", signature: "synthetic" },
      {
        verifyAndConstructEvent: async () => scenario.event,
        recordWalletLoad: async (payload) => {
          calls.push({ recorder: "recordWalletLoad", payload });
          throw failure;
        },
        recordCortinaPayment: async (payload) => {
          calls.push({ recorder: "recordCortinaPayment", payload });
          throw failure;
        },
      },
    ), Error, failure.message);
    assertStrictEquals(rejected, failure);
    assertEquals(calls, [{ recorder: scenario.recorder, payload: scenario.payload }]);
  });
}
