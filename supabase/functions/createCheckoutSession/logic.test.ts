import {
    assertEquals,
    assertRejects,
  } from "https://deno.land/std@0.168.0/testing/asserts.ts";
  import {
    getAuthenticatedUser,
    createCheckoutSession,
    handleCheckout
  } from "./logic.ts";
  
  function makeSupabaseMock(user: object | null, error: object | null = null) {
    return {
      rpc: () => ({ abortSignal: () => Promise.resolve({ data: true, error: null }) }),
      auth: {
        getUser: () => Promise.resolve({ data: { user }, error }),
      },
    } as any;
  }
  
  function makeStripeMock(overrides?: Partial<{ url: string; id: string }>) {
    return {
      checkout: {
        sessions: {
          create: (_params: unknown) =>
            Promise.resolve({
              url: overrides?.url ?? "https://checkout.stripe.com/pay/test_session",
              id: overrides?.id ?? "cs_test_abc123",
            }),
        },
      },
    } as any;
  }

  function makeRequest(body: unknown) {
    return new Request("http://localhost/checkout", {
      method: "POST",
      body: JSON.stringify(body),
      headers: { "Content-Type": "application/json" },
    });
  }
  
  Deno.test("getAuthenticatedUser — returns user when authenticated", async () => {
    const mockUser = { id: "user-123", email: "test@example.com" };
    const supabase = makeSupabaseMock(mockUser);
  
    const user = await getAuthenticatedUser(supabase);
    assertEquals(user.id, "user-123");
  });
  
  Deno.test("getAuthenticatedUser — throws when user is null", async () => {
    const supabase = makeSupabaseMock(null);
  
    await assertRejects(
      () => getAuthenticatedUser(supabase),
      Error,
      "Unauthorized"
    );
  });
  
  Deno.test("getAuthenticatedUser — throws when Supabase returns an error", async () => {
    const supabase = makeSupabaseMock(null, { message: "JWT expired" });
  
    await assertRejects(
      () => getAuthenticatedUser(supabase),
      Error,
      "Unauthorized"
    );
  });
  
  Deno.test("createCheckoutSession — returns url and session_id", async () => {
    const stripe = makeStripeMock();
  
    const result = await createCheckoutSession(stripe, 2500, "user-123");
  
    assertEquals(result.session_id, "cs_test_abc123");
    assertEquals(result.url, "https://checkout.stripe.com/pay/test_session");
  });
  
  Deno.test("createCheckoutSession — passes correct amount to Stripe", async () => {
    let capturedParams: any;
    const stripe = {
      checkout: {
        sessions: {
          create: (params: unknown) => {
            capturedParams = params;
            return Promise.resolve({ url: "https://stripe.com", id: "cs_1" });
          },
        },
      },
    } as any;
  
    await createCheckoutSession(stripe, 4999, "user-456");
  
    assertEquals(capturedParams.line_items[0].price_data.unit_amount, 4999);
    assertEquals(capturedParams.metadata, {
      user_id: "user-456",
      purpose: "direct_machine_payment",
      amount_cents: "4999",
    });
    assertEquals(capturedParams.payment_intent_data.metadata, capturedParams.metadata);
  });
  
  Deno.test("createCheckoutSession — throws on invalid amount (zero)", async () => {
    const stripe = makeStripeMock();
  
    await assertRejects(
      () => createCheckoutSession(stripe, 0, "user-123"),
      Error,
      "Invalid amount"
    );
  });
  
  Deno.test("createCheckoutSession — throws on negative amount", async () => {
    const stripe = makeStripeMock();
  
    await assertRejects(
      () => createCheckoutSession(stripe, -100, "user-123"),
      Error,
      "Invalid amount"
    );
  });
  
  Deno.test("createCheckoutSession — uses custom baseUrl for redirect URLs", async () => {
    let capturedParams: any;
    const stripe = {
      checkout: {
        sessions: {
          create: (params: unknown) => {
            capturedParams = params;
            return Promise.resolve({ url: "https://stripe.com", id: "cs_1" });
          },
        },
      },
    } as any;
  
    await createCheckoutSession(stripe, 1000, "user-123", "https://myapp.com");
  
    assertEquals(capturedParams.success_url, "https://myapp.com/homePage");
    assertEquals(capturedParams.cancel_url, "https://myapp.com/homePage");
  });

  Deno.test("handleCheckout - wallet metadata correlates Session and PaymentIntent", async () => {
    const contextId = "00000000-0000-4000-8000-000000000001";
    let capturedParams: any;
    const calls: unknown[] = [];
    const admissionSubjects: string[] = [];
    const stripe = {
      checkout: { sessions: { create: (params: unknown) => {
        capturedParams = params;
        return Promise.resolve({ url: "https://checkout.stripe.com/test", id: "cs_wallet",
          amount_total: 2500, currency: "usd", metadata: capturedParams.metadata });
      } } },
    } as any;
    const response = await handleCheckout(
      makeRequest({ amount: 2500, purpose: "walletLoad", consent: { context_id: contextId, acknowledged: true } }),
      {
        stripe,
        supabase: makeSupabaseMock({ id: "user-1" }),
        fundingAdmission: (subject) => { admissionSubjects.push(subject); return Promise.resolve(); },
        walletLoadConsent: () => Promise.resolve({context_id:contextId,subject_id:"user-1",wallet_account_id:"wallet-1",
          amount_cents:2500,channel:"checkout",accepted_at:"2026-10-05T15:00:00Z",policy_version:"synthetic-policy",
          policy_sha256:"a".repeat(64),provider_reference:null}),
        supabaseAdmin: { rpc: (name: string, params: unknown) => {
          if (name === "new_payments_enabled") return {
            abortSignal: () => Promise.resolve({ data: true, error: null }),
          };
          calls.push({ name, params });
          return Promise.resolve({ data: "wallet-1", error: null });
        } } as any,
      },
      "https://myapp.com",
    );
    assertEquals(await response.json(), { url: "https://checkout.stripe.com/test", session_id: "cs_wallet" });
    assertEquals(calls, [{ name: "get_or_create_wallet_account", params: { target_user_id: "user-1" } },
      {name:"bind_wallet_load_consent_provider",params:{p_context_id:contextId,p_subject_id:"user-1",
        p_amount_cents:2500,p_channel:"checkout",p_provider_reference:"cs_wallet"}}]);
    assertEquals(admissionSubjects, ["user-1", "user-1", "user-1", "user-1"]);
    assertEquals(capturedParams.metadata, {
      user_id: "user-1", purpose: "wallet_load", amount_cents: "2500", wallet_account_id: "wallet-1",
      consent_context_id:contextId,consent_policy_version:"synthetic-policy",consent_policy_sha256:"a".repeat(64),
    });
    assertEquals(capturedParams.payment_intent_data.metadata, capturedParams.metadata);
    assertEquals(capturedParams.success_url, "https://myapp.com/homePage");
    assertEquals(capturedParams.cancel_url, "https://myapp.com/homePage");
    assertEquals(capturedParams.line_items[0].price_data.currency, "usd");
    assertEquals(capturedParams.line_items[0].price_data.unit_amount, 2500);
  });
  
  Deno.test("handleCheckout — returns 200 with url and session_id on success", async () => {
    const req = makeRequest({ amount: 2500 });
  
    const res = await handleCheckout(req, {
      stripe: makeStripeMock(),
      supabase: makeSupabaseMock({ id: "user-123" }),
    });
    const body = await res.json();
  
    assertEquals(res.status, 200);
    assertEquals(body.session_id, "cs_test_abc123");
    assertEquals(body.url, "https://checkout.stripe.com/pay/test_session");
  });
  
  Deno.test("handleCheckout — response Content-Type is application/json", async () => {
    const req = makeRequest({ amount: 2500 });
  
    const res = await handleCheckout(req, {
      stripe: makeStripeMock(),
      supabase: makeSupabaseMock({ id: "user-123" }),
    });
  
    assertEquals(res.headers.get("Content-Type"), "application/json");
  });
  
  Deno.test("handleCheckout — throws Unauthorized when user is null", async () => {
    const req = makeRequest({ amount: 2500 });
  
    await assertRejects(
      () => handleCheckout(req, {
        stripe: makeStripeMock(),
        supabase: makeSupabaseMock(null),
      }),
      Error,
      "Unauthorized"
    );
  });
  
  Deno.test("handleCheckout — throws Unauthorized when Supabase returns auth error", async () => {
    const req = makeRequest({ amount: 2500 });
  
    await assertRejects(
      () => handleCheckout(req, {
        stripe: makeStripeMock(),
        supabase: makeSupabaseMock(null, { message: "JWT expired" }),
      }),
      Error,
      "Unauthorized"
    );
  });
  
  Deno.test("handleCheckout — throws Invalid amount when amount is zero", async () => {
    const req = makeRequest({ amount: 0 });
  
    await assertRejects(
      () => handleCheckout(req, {
        stripe: makeStripeMock(),
        supabase: makeSupabaseMock({ id: "user-123" }),
      }),
      Error,
      "Invalid amount"
    );
  });
  
  Deno.test("handleCheckout — throws Invalid amount when amount is missing", async () => {
    const req = makeRequest({});
  
    await assertRejects(
      () => handleCheckout(req, {
        stripe: makeStripeMock(),
        supabase: makeSupabaseMock({ id: "user-123" }),
      }),
      Error,
      "Invalid amount"
    );
  });
  
  Deno.test("handleCheckout — forwards user id from auth to Stripe session metadata", async () => {
    let capturedParams: any;
    const stripe = {
      checkout: {
        sessions: {
          create: (params: unknown) => {
            capturedParams = params;
            return Promise.resolve({ url: "https://stripe.com", id: "cs_1" });
          },
        },
      },
    } as any;
  
    const req = makeRequest({ amount: 1500 });
    await handleCheckout(req, {
      stripe,
      supabase: makeSupabaseMock({ id: "user-abc" }),
    });
  
    assertEquals(capturedParams.metadata.user_id, "user-abc");
  });
  
  Deno.test("handleCheckout — uses provided baseUrl for redirect URLs", async () => {
    let capturedParams: any;
    const stripe = {
      checkout: {
        sessions: {
          create: (params: unknown) => {
            capturedParams = params;
            return Promise.resolve({ url: "https://stripe.com", id: "cs_1" });
          },
        },
      },
    } as any;
  
    const req = makeRequest({ amount: 1500 });
    await handleCheckout(
      req,
      { stripe, supabase: makeSupabaseMock({ id: "user-123" }) },
      "https://myapp.com"
    );
  
    assertEquals(capturedParams.success_url, "https://myapp.com/homePage");
    assertEquals(capturedParams.cancel_url, "https://myapp.com/homePage");
  });
