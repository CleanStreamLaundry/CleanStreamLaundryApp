import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handlePaymentIntentStatus,
  normalizePaymentIntentStatus,
} from "./logic.ts";

function makeSupabaseMock(
  userId: string | null,
  calls: unknown[] = [],
) {
  return {
    auth: {
      getUser: (_token: string) => Promise.resolve({
        data: { user: userId ? { id: userId } : null },
        error: userId ? null : new Error("Unauthorized"),
      }),
    },
    rpc: (_name: string, params: unknown) => {
      calls.push(params);
      return Promise.resolve({ data: "wallet-1", error: null });
    },
  } as any;
}

function makeStripeMock(intent: {
  id?: string;
  status?: string;
  userId?: string;
  purpose?: string;
  amountReceived?: number;
  amount?: number;
  latestCharge?: string | { id: string } | null;
}) {
  return {
    paymentIntents: {
      retrieve: (paymentIntentId: string) => Promise.resolve({
        id: intent.id ?? paymentIntentId,
        status: intent.status ?? "succeeded",
        currency: "usd",
        livemode: false,
        amount_received: intent.amountReceived ?? intent.amount ?? 100,
        amount: intent.amount ?? intent.amountReceived ?? 100,
        latest_charge: intent.latestCharge ?? "ch_test",
        metadata: {
          user_id: intent.userId ?? "user-1",
          amount_cents: String(intent.amount ?? intent.amountReceived ?? 100),
          ...(intent.purpose ? { purpose: intent.purpose } : {}),
        },
      }),
    },
  } as any;
}

function makeRequest(body: unknown, token = "token-1") {
  return new Request("http://localhost/payment-intent-status", {
    method: "POST",
    body: JSON.stringify(body),
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
}

Deno.test("normalizePaymentIntentStatus — maps Stripe statuses", () => {
  assertEquals(normalizePaymentIntentStatus("succeeded"), "succeeded");
  assertEquals(normalizePaymentIntentStatus("processing"), "processing");
  assertEquals(normalizePaymentIntentStatus("requires_action"), "processing");
  assertEquals(normalizePaymentIntentStatus("canceled"), "canceled");
  assertEquals(
    normalizePaymentIntentStatus("requires_payment_method"),
    "failed"
  );
  assertEquals(normalizePaymentIntentStatus("other"), "unknown");
});

Deno.test("handlePaymentIntentStatus — returns normalized status for the owner", async () => {
  const rpcCalls: unknown[] = [];
  const res = await handlePaymentIntentStatus(
    makeRequest({ paymentIntentId: "pi_test" }),
    {
      stripe: makeStripeMock({ status: "succeeded", userId: "user-1" }),
      supabaseAdmin: makeSupabaseMock("user-1", rpcCalls),
    }
  );
  const body = await res.json();

  assertEquals(res.status, 200);
  assertEquals(body, {
    paymentIntentId: "pi_test",
    status: "succeeded",
    walletLoadRecorded: false,
  });
  assertEquals(rpcCalls.length, 0);
});

Deno.test("handlePaymentIntentStatus — records succeeded wallet loads", async () => {
  const rpcCalls: unknown[] = [];
  const res = await handlePaymentIntentStatus(
    makeRequest({ paymentIntentId: "pi_wallet" }),
    {
      stripe: makeStripeMock({
        status: "succeeded",
        userId: "user-1",
        purpose: "wallet_load",
        amountReceived: 2500,
        latestCharge: "ch_wallet",
      }),
      supabaseAdmin: makeSupabaseMock("user-1", rpcCalls),
    }
  );
  const body = await res.json();

  assertEquals(res.status, 200);
  assertEquals(body.status, "succeeded");
  assertEquals(body.walletLoadRecorded, true);
  assertEquals(rpcCalls, [{
    target_user_id: "user-1",
    amount_cents: 2500,
    stripe_payment_intent_id: "pi_wallet",
    stripe_checkout_session_id: null,
    stripe_charge_id: "ch_wallet",
    stripe_event_id: null,
  }]);
});

Deno.test("handlePaymentIntentStatus — rejects unauthenticated users", async () => {
  const res = await handlePaymentIntentStatus(
    makeRequest({ paymentIntentId: "pi_test" }, ""),
    {
      stripe: makeStripeMock({}),
      supabaseAdmin: makeSupabaseMock(null),
    }
  );

  assertEquals(res.status, 401);
});

Deno.test("handlePaymentIntentStatus — rejects mismatched owners", async () => {
  const res = await handlePaymentIntentStatus(
    makeRequest({ paymentIntentId: "pi_test" }),
    {
      stripe: makeStripeMock({ userId: "other-user" }),
      supabaseAdmin: makeSupabaseMock("user-1"),
    }
  );

  assertEquals(res.status, 403);
});

Deno.test("handlePaymentIntentStatus — rejects invalid PaymentIntent IDs", async () => {
  const res = await handlePaymentIntentStatus(
    makeRequest({ paymentIntentId: "not-an-intent" }),
    {
      stripe: makeStripeMock({}),
      supabaseAdmin: makeSupabaseMock("user-1"),
    }
  );

  assertEquals(res.status, 400);
});
