import assert from "node:assert/strict";
import { handler } from "./index.ts";

const id = "00000000-0000-4000-8000-000000000123";
for (const terminal of ["failed", "canceled"]) {
  for (
    const scenario of [
      "sole",
      "replacement_on_page_two",
      "page_two_error",
      "missing_boundary",
      "null_boundary",
      "empty_continuation",
      "history_limit",
    ]
  ) {
    Deno.test(`offline release adapter ${terminal}: ${scenario}`, async () => {
      const values = {
        SUPABASE_URL: "https://synthetic.invalid",
        SUPABASE_ANON_KEY: "synthetic-public",
        SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
        STRIPE_SECRET_KEY: "sk_test_synthetic",
      };
      const saved = new Map(
        Object.keys(values).map((key) => [key, Deno.env.get(key)]),
      );
      for (const [key, value] of Object.entries(values)) {
        Deno.env.set(key, value);
      }
      const fetch = globalThis.fetch;
      const pages: string[] = [];
      let reconciled = 0, created = 0;
      const refund = {
        id: "re_bound",
        payment_intent: "pi_release",
        amount: 2000,
        currency: "usd",
        status: terminal,
        metadata: { voluntary_topup_refund_id: id },
      };
      globalThis.fetch = async (input, init) => {
        const request = new Request(input, init), url = new URL(request.url);
        if (url.pathname === "/auth/v1/user") {
          return Response.json({ id });
        }
        if (url.pathname.endsWith("/review_voluntary_topup_refund")) {
          assert.equal(
            request.headers.get("authorization"),
            "Bearer synthetic-owner",
          );
          return Response.json({ id, status: "pending" });
        }
        if (url.pathname.endsWith("/prepare_voluntary_topup_refund")) {
          return Response.json({
            id,
            intent: "pi_release",
            amount: 2000,
            livemode: false,
            refund_id: "re_bound",
            idempotency_key: `voluntary-topup-v1:${id}`,
            may_create: false,
          });
        }
        if (url.pathname === "/v1/payment_intents/pi_release") {
          return Response.json({
            id: "pi_release",
            status: "succeeded",
            amount_received: 2000,
            currency: "usd",
            livemode: false,
          });
        }
        if (url.pathname === "/v1/refunds/re_bound") {
          return Response.json(refund);
        }
        if (url.pathname === "/v1/refunds" && request.method === "GET") {
          assert.equal(url.searchParams.get("payment_intent"), "pi_release");
          assert.equal(url.searchParams.get("limit"), "100");
          const cursor = url.searchParams.get("starting_after") ?? "first";
          pages.push(cursor);
          if (cursor === "first") {
            if (scenario === "missing_boundary") {
              return Response.json({ object: "list", data: [refund] });
            }
            if (scenario === "null_boundary") {
              return Response.json({
                object: "list",
                data: [refund],
                has_more: null,
              });
            }
            if (scenario === "history_limit") {
              return Response.json({
                object: "list",
                data: Array.from(
                  { length: 1001 },
                  (_, i) => ({ ...refund, id: `re_${i}` }),
                ),
                has_more: false,
              });
            }
            return Response.json({
              object: "list",
              data: [refund],
              has_more: scenario !== "sole",
            });
          }
          assert.equal(cursor, "re_bound");
          if (scenario === "page_two_error") {
            return Response.json({
              error: {
                type: "invalid_request_error",
                message: "Synthetic history unavailable",
              },
            }, { status: 400 });
          }
          if (scenario === "empty_continuation") {
            return Response.json({ object: "list", data: [], has_more: true });
          }
          return Response.json({
            object: "list",
            data: [{
              ...refund,
              id: "re_external",
              status: "succeeded",
              metadata: {},
            }],
            has_more: false,
          });
        }
        if (
          url.pathname === "/v1/refunds" && request.method === "POST"
        ) created++;
        if (url.pathname.endsWith("/reconcile_voluntary_topup_refund")) {
          reconciled++;
          assert.equal(
            request.headers.get("apikey"),
            values.SUPABASE_SERVICE_ROLE_KEY,
          );
          const body = await request.json();
          assert.equal(body.p_status, terminal);
          assert.equal(body.p_refund_id, "re_bound");
          return Response.json({ id, status: terminal });
        }
        throw new Error(
          `Unexpected synthetic call: ${request.method} ${url.pathname}`,
        );
      };
      try {
        const response = await handler(
          new Request("https://synthetic.invalid/refund", {
            method: "POST",
            headers: { Authorization: "Bearer synthetic-owner" },
            body: JSON.stringify({ action: "reconcile", id }),
          }),
        );
        assert.equal(response.status, scenario === "sole" ? 200 : 503);
        assert.equal(reconciled, scenario === "sole" ? 1 : 0);
        assert.equal(created, 0);
        assert.deepEqual(
          pages,
          ["sole", "missing_boundary", "null_boundary", "history_limit"]
              .includes(scenario)
            ? ["first"]
            : ["first", "re_bound"],
        );
      } finally {
        globalThis.fetch = fetch;
        for (const [key, value] of saved) {
          if (value === undefined) Deno.env.delete(key);
          else Deno.env.set(key, value);
        }
      }
    });
  }
}
