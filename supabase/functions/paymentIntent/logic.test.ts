import {
    assertEquals,
    assertRejects,
  } from "https://deno.land/std@0.168.0/testing/asserts.ts";
  import {
    validateAmount,
    createPaymentIntent,
    handleCreatePaymentIntent,
  } from "./logic.ts";
  
  function makeStripeMock(overrides: {
    clientSecret?: string | null;
    throwMessage?: string;
  } = {}) {
    return {
      paymentIntents: {
        create: (_params: unknown) => {
          if (overrides.throwMessage) {
            return Promise.reject(new Error(overrides.throwMessage));
          }
          const clientSecret = "clientSecret" in overrides
            ? overrides.clientSecret
            : "pi_test_secret_abc123";
          return Promise.resolve({ id: "pi_test", client_secret: clientSecret });
        },
      },
    } as any;
  }
  
  function makeRequest(body: unknown) {
    return new Request("http://localhost/create-payment-intent", {
      method: "POST",
      body: JSON.stringify(body),
      headers: { "Content-Type": "application/json", Authorization: "Bearer synthetic-caller" },
    });
  }
  function enabledAdmin() {
    return {
      auth: { getUser: () => Promise.resolve({ data: { user: { id: "test-user" } }, error: null }) },
      rpc: () => ({ abortSignal: () => Promise.resolve({ data: true, error: null }) }),
    } as any;
  }
  
  Deno.test("validateAmount — accepts a valid positive integer", () => {
    assertEquals(validateAmount(2500), 2500);
  });
  
  Deno.test("validateAmount — accepts the minimum valid amount (1 cent)", () => {
    assertEquals(validateAmount(1), 1);
  });
  
  Deno.test("validateAmount — throws on undefined", () => {
    try {
      validateAmount(undefined);
    } catch (e) {
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message, "Missing amount");
    }
  });
  
  Deno.test("validateAmount — throws on null", () => {
    try {
      validateAmount(null);
    } catch (e) {
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message, "Missing amount");
    }
  });
  
  Deno.test("validateAmount — throws on zero", () => {
    try {
      validateAmount(0);
    } catch (e) {
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message.startsWith("Invalid amount"), true);
    }
  });
  
  Deno.test("validateAmount — throws on negative number", () => {
    try {
      validateAmount(-500);
    } catch (e) {
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message.startsWith("Invalid amount"), true);
    }
  });
  
  Deno.test("validateAmount — throws on float (Stripe requires whole cents)", () => {
    try {
      validateAmount(24.99);
    } catch (e) {
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message.startsWith("Invalid amount"), true);
    }
  });
  
  Deno.test("validateAmount — throws on string", () => {
    try {
      validateAmount("2500");
    } catch (e) {
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message.startsWith("Invalid amount"), true);
    }
  });
  
  Deno.test("createPaymentIntent — returns clientSecret on success", async () => {
    const stripe = makeStripeMock();
    const result = await createPaymentIntent(stripe, 2500);
  
    assertEquals(result.clientSecret, "pi_test_secret_abc123");
    assertEquals(result.paymentIntentId, "pi_test");
  });
  
  Deno.test("createPaymentIntent — passes correct amount to Stripe", async () => {
    let capturedParams: any;
    const stripe = {
      paymentIntents: {
        create: (params: unknown) => {
          capturedParams = params;
          return Promise.resolve({ id: "pi_test", client_secret: "pi_test_secret" });
        },
      },
    } as any;
  
    await createPaymentIntent(stripe, 4999);
  
    assertEquals(capturedParams.amount, 4999);
    assertEquals(capturedParams.currency, "usd");
    assertEquals(capturedParams.payment_method_types, ["card"]);
  });
  
  Deno.test("createPaymentIntent — handles null client_secret from Stripe", async () => {
    const stripe = makeStripeMock({ clientSecret: null });
    const result = await createPaymentIntent(stripe, 2500);
  
    assertEquals(result.clientSecret, null);
  });
  
  Deno.test("createPaymentIntent — throws when Stripe rejects", async () => {
    const stripe = makeStripeMock({ throwMessage: "Your card was declined." });
  
    await assertRejects(
      () => createPaymentIntent(stripe, 2500),
      Error,
      "Your card was declined."
    );
  });
  
  
  Deno.test("handleCreatePaymentIntent — returns 200 with clientSecret", async () => {
    const req = makeRequest({ amount: 2500 });
    const res = await handleCreatePaymentIntent(req, { stripe: makeStripeMock(), supabaseAdmin: enabledAdmin() });
    const body = await res.json();
  
    assertEquals(res.status, 200);
    assertEquals(body.clientSecret, "pi_test_secret_abc123");
    assertEquals(body.paymentIntentId, "pi_test");
  });
  
  Deno.test("handleCreatePaymentIntent — throws Missing amount when body has no amount", async () => {
    const req = makeRequest({});
  
    await assertRejects(
      () => handleCreatePaymentIntent(req, { stripe: makeStripeMock() }),
      Error,
      "Missing amount"
    );
  });
  
  Deno.test("handleCreatePaymentIntent — throws Invalid amount for a float", async () => {
    const req = makeRequest({ amount: 19.99 });
  
    await assertRejects(
      () => handleCreatePaymentIntent(req, { stripe: makeStripeMock() }),
      Error,
      "Invalid amount"
    );
  });
  
  Deno.test("handleCreatePaymentIntent — throws when Stripe fails", async () => {
    const req = makeRequest({ amount: 2500 });
  
    await assertRejects(
      () => handleCreatePaymentIntent(req, {
        stripe: makeStripeMock({ throwMessage: "Stripe API unavailable" }),
        supabaseAdmin: enabledAdmin(),
      }),
      Error,
      "Stripe API unavailable"
    );
  });
  
  Deno.test("handleCreatePaymentIntent — response Content-Type is application/json", async () => {
    const req = makeRequest({ amount: 1000 });
    const res = await handleCreatePaymentIntent(req, { stripe: makeStripeMock(), supabaseAdmin: enabledAdmin() });
  
    assertEquals(res.headers.get("Content-Type"), "application/json");
  });
