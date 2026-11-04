import { assertEquals } from "https://deno.land/std@0.182.0/testing/asserts.ts";
import { handler } from "./index.ts";

const id = "00000000-0000-4000-8000-000000000001";
for (
  const [scenario, named] of [
    "success",
    "pending",
    "forbidden",
    "provider_error",
    "db_failure",
  ].flatMap((scenario) => [false, true].map((named) => [scenario, named] as const))
) {
  Deno.test(`actual offline adapter ${named ? "named" : "legacy"}: ${scenario}`, async () => {
    const savedFetch = globalThis.fetch;
    const savedEnvGet = Deno.env.get;
    const env: Record<string, string | undefined> = {
      SUPABASE_URL: "https://offline.invalid",
      SUPABASE_ANON_KEY: "synthetic-public-key",
      SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
      STRIPE_SECRET_KEY: "sk_test_synthetic",
      SUPABASE_SECRET_KEYS: JSON.stringify({ refund: "sb_secret_refund_fixture" }),
      CLEANSTREAM_TOPUP_REFUND_SECRET_KEY_NAME: named ? "refund" : undefined,
      CLEANSTREAM_TOPUP_REFUND_PUBLISHABLE_KEY_NAME: undefined,
      SUPABASE_PUBLISHABLE_KEYS: undefined,
    };
    Deno.env.get = (name) => env[name];
    const adminKey = named ? "sb_secret_refund_fixture" : env.SUPABASE_SERVICE_ROLE_KEY;
    const calls: {
      url: string;
      auth: string | null;
      key: string | null;
      body: string;
    }[] = [];
    globalThis.fetch = async (input, init) => {
      const request = new Request(input, init),
        url = new URL(request.url),
        body = await request.text();
      calls.push({
        url: request.url,
        auth: request.headers.get("authorization"),
        key: request.headers.get("apikey"),
        body,
      });
      if (url.pathname === "/auth/v1/user") return Response.json({ id });
      if (url.pathname.endsWith("/review_voluntary_topup_refund")) {
        assertEquals(
          request.headers.get("authorization"),
          "Bearer captured-token",
        );
        assertEquals(request.headers.get("apikey"), env.SUPABASE_ANON_KEY);
        assertEquals(JSON.parse(body), {
          p_id: id,
          p_action: "approve",
          p_note: null,
        });
        return scenario === "forbidden"
          ? Response.json({ code: "PT403", message: "owner_required" }, {
            status: 403,
          })
          : Response.json({ id, status: "approved" });
      }
      if (url.pathname.endsWith("/prepare_voluntary_topup_refund")) {
        assertEquals(
          request.headers.get("apikey"),
          adminKey,
        );
        assertEquals(request.headers.get("authorization"), named ? null : `Bearer ${adminKey}`);
        return Response.json({
          id,
          intent: "pi_test",
          amount: 2000,
          livemode: false,
          refund_id: null,
          idempotency_key: `voluntary-topup-v1:${id}`,
          may_create: true,
        });
      }
      if (url.pathname === "/v1/payment_intents/pi_test") {
        return Response.json({
          id: "pi_test",
          status: "succeeded",
          amount_received: 2000,
          currency: "usd",
          livemode: false,
        });
      }
      if (url.pathname === "/v1/refunds" && request.method === "GET") {
        assertEquals(url.searchParams.get("payment_intent"), "pi_test");
        return Response.json({ object: "list", data: [], has_more: false });
      }
      if (url.pathname === "/v1/refunds" && request.method === "POST") {
        assertEquals(
          request.headers.get("idempotency-key"),
          `voluntary-topup-v1:${id}`,
        );
        const form = new URLSearchParams(body);
        assertEquals(form.get("amount"), "2000");
        assertEquals(form.get("payment_intent"), "pi_test");
        assertEquals(form.get("reason"), "requested_by_customer");
        assertEquals(form.get("metadata[voluntary_topup_refund_id]"), id);
        assertEquals(
          [...form.keys()].sort(),
          [
            "amount",
            "payment_intent",
            "reason",
            "metadata[voluntary_topup_refund_id]",
            "metadata[policy_version]",
          ].sort(),
        );
        if (scenario === "provider_error") {
          return Response.json({
            error: {
              type: "invalid_request_error",
              message: "synthetic failure",
            },
          }, { status: 400 });
        }
        return Response.json({
          id: "re_test",
          payment_intent: "pi_test",
          amount: 2000,
          currency: "usd",
          status: scenario === "pending" ? "pending" : "succeeded",
          metadata: { voluntary_topup_refund_id: id },
        });
      }
      if (url.pathname.endsWith("/reconcile_voluntary_topup_refund")) {
        assertEquals(
          request.headers.get("apikey"),
          adminKey,
        );
        assertEquals(request.headers.get("authorization"), named ? null : `Bearer ${adminKey}`);
        assertEquals(JSON.parse(body), {
          p_id: id,
          p_refund_id: "re_test",
          p_status: scenario === "pending" ? "pending" : "succeeded",
          p_intent: "pi_test",
          p_amount: 2000,
          p_currency: "usd",
          p_livemode: false,
        });
        if (scenario === "db_failure") {
          return Response.json(
            { code: "PT503", message: "synthetic failure" },
            { status: 503 },
          );
        }
        return Response.json({
          id,
          status: scenario === "pending" ? "pending" : "succeeded",
        });
      }
      throw new Error(
        `Unexpected offline call ${request.method} ${url.pathname}`,
      );
    };
    try {
      const result = await handler(
        new Request("https://offline.invalid/voluntary-topup-refund", {
          method: "POST",
          headers: { Authorization: "Bearer captured-token" },
          body: JSON.stringify({ action: "approve", id }),
        }),
      );
      assertEquals(
        result.status,
        scenario === "success"
          ? 200
          : scenario === "pending"
          ? 202
          : scenario === "forbidden"
          ? 403
          : 503,
      );
      if (scenario === "forbidden") assertEquals(calls.length, 2);
      if (scenario === "provider_error") {
        assertEquals(
          calls.some((c) => c.url.includes("reconcile_voluntary")),
          false,
        );
      }
      assertEquals(calls[0].auth, "Bearer captured-token");
      assertEquals(calls[0].key, env.SUPABASE_ANON_KEY);
    } finally {
      globalThis.fetch = savedFetch;
      Deno.env.get = savedEnvGet;
    }
  });
}
