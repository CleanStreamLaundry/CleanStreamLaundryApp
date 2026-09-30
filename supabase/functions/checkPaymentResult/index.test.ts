import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { PaymentDeps } from "./logic.ts";

let registered: ((req: Request) => Promise<Response>) | undefined;
let registrations = 0;
const originalServe = Deno.serve;
Deno.serve = ((handler: typeof registered) => {
  registered = handler;
  registrations++;
  return {};
}) as typeof Deno.serve;
let endpoint: typeof import("./index.ts");
try {
  endpoint = await import("./index.ts");
} finally {
  Deno.serve = originalServe;
}

Deno.test("entrypoint registers an actual handler and serves SDK preflight without credentials", async () => {
  assertEquals(registrations, 1);
  assert(registered);
  const response = await registered(
    new Request("http://localhost/status", { method: "OPTIONS" }),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "");
  assertEquals(
    response.headers.get("Access-Control-Allow-Headers"),
    "Content-Type, Authorization, apikey, x-client-info",
  );
  assertEquals(response.headers.get("Cache-Control"), "no-store");
});

Deno.test("registered handler rejects non-POST without dependencies", async () => {
  assert(registered);
  const response = await registered(new Request("http://localhost/status"));
  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "Method Not Allowed" });
});

for (const failAt of ["auth", "stripe"]) {
  Deno.test(`HTTP handler sanitizes thrown ${failAt} errors and never reaches ledger`, async () => {
    const calls: string[] = [];
    const deps = {
      retrieveSession: () => {
        calls.push("stripe");
        throw new Error("private provider detail");
      },
      supabaseAdmin: {
        auth: {
          getUser: () => {
            calls.push("auth");
            if (failAt === "auth") throw new Error("private auth detail");
            return Promise.resolve({
              data: { user: { id: "user-1" } },
              error: null,
            });
          },
        },
        rpc: () => {
          calls.push("rpc");
          throw new Error("should not be reached");
        },
      },
    } as unknown as PaymentDeps;
    const response = await endpoint.getPaymentStatus(
      new Request("http://localhost/status", {
        method: "POST",
        headers: { Authorization: "Bearer synthetic" },
        body: JSON.stringify({ session_id: "cs_test" }),
      }),
      deps,
    );
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {
      error: "Payment status unavailable",
    });
    assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
    assertEquals(calls, failAt === "auth" ? ["auth"] : ["auth", "stripe"]);
  });
}

Deno.test("registered POST handler uses real SDK wiring with synthetic transport only", async () => {
  assert(registered);
  const getEnv = Deno.env.get;
  const fetch = globalThis.fetch;
  const calls: string[] = [];
  Deno.env.get = (name: string) =>
    ({
      STRIPE_SECRET_KEY: "sk_test_synthetic",
      SUPABASE_URL: "https://supabase.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
    })[name];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    calls.push(`${url.host}${url.pathname}`);
    if (url.host === "supabase.invalid" && url.pathname === "/auth/v1/user") {
      return Response.json({ id: "user-1" });
    }
    if (
      url.host === "api.stripe.com" &&
      url.pathname === "/v1/checkout/sessions/cs_test"
    ) {
      assertEquals(url.searchParams.get("expand[0]"), "payment_intent");
      return Response.json({
        id: "cs_test",
        mode: "payment",
        status: "open",
        payment_status: "unpaid",
        currency: "usd",
        amount_total: 2500,
        livemode: false,
        payment_intent: null,
        metadata: {
          user_id: "user-1",
          purpose: "wallet_load",
          amount_cents: "2500",
        },
      });
    }
    throw new Error("Unexpected synthetic request");
  }) as typeof globalThis.fetch;
  try {
    const response = await registered(
      new Request("http://localhost/status", {
        method: "POST",
        headers: { Authorization: "Bearer synthetic-user-token" },
        body: JSON.stringify({ session_id: "cs_test" }),
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {
      session_id: "cs_test",
      status: "unpaid",
      paymentStatus: "processing",
      paymentIntentId: null,
      purpose: "wallet_load",
      amountCents: 2500,
      currency: "usd",
      walletLoadRecorded: false,
    });
    assertEquals(calls, [
      "supabase.invalid/auth/v1/user",
      "api.stripe.com/v1/checkout/sessions/cs_test",
    ]);
  } finally {
    Deno.env.get = getEnv;
    globalThis.fetch = fetch;
  }
});
