import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { reconciliationDependencies, reconciliationHandler } from "./index.ts";
import type { ReconciliationDeps } from "../_shared/cortina_reconciliation.ts";

const secret = "synthetic-worker-secret-at-least-thirty-two-characters";
const selector = "CLEANSTREAM_CORTINA_RECONCILIATION_SECRET_KEY_NAME";
const namedKey = "sb_secret_synthetic_reconciliation";
const settings: Record<string, string> = {
  CORTINA_RECONCILIATION_ENABLED: "true",
  CORTINA_RECONCILIATION_WORKER_SECRET: secret,
  CORTINA_RECONCILIATION_ENVIRONMENT: "sandbox",
};
const request = (token = secret, method = "POST") => new Request("https://worker.invalid/cortina-reconcile", {
  method, headers: { Authorization: `Bearer ${token}` },
  ...(method === "POST" ? { body: "intentionally not JSON" } : {}),
});

for (const [name, patch, token, expected] of [
  ["missing secret", { CORTINA_RECONCILIATION_WORKER_SECRET: undefined }, secret, 401],
  ["blank secret", { CORTINA_RECONCILIATION_WORKER_SECRET: " ".repeat(40) }, secret, 401],
  ["short secret", { CORTINA_RECONCILIATION_WORKER_SECRET: "short" }, "short", 401],
  ["wrong secret", {}, "wrong", 401],
  ["disabled by default", { CORTINA_RECONCILIATION_ENABLED: undefined }, secret, 503],
  ["disabled explicitly", { CORTINA_RECONCILIATION_ENABLED: "false" }, secret, 503],
  ["missing environment", { CORTINA_RECONCILIATION_ENVIRONMENT: undefined }, secret, 503],
  ["invalid environment", { CORTINA_RECONCILIATION_ENVIRONMENT: "live" }, secret, 503],
] as const) {
  Deno.test(`worker ${name} denies before body parsing or dependencies`, async () => {
    const env: Record<string, string | undefined> = { ...settings, ...patch };
    const handler = reconciliationHandler((key) => env[key], () => { throw Error("must not construct dependencies"); });
    const req = request(token);
    assertEquals((await handler(req)).status, expected);
    assertEquals(req.bodyUsed, false);
  });
}

Deno.test("worker accepts only authenticated POST with a fixed one-session budget", async () => {
  let claims = 0;
  const handler = reconciliationHandler((key) => settings[key], () => ({
    claim: async (environment: string) => { assertEquals(environment, "sandbox"); claims++; return null; },
  } as ReconciliationDeps));
  assertEquals((await handler(request(secret, "GET"))).status, 405);
  const req = new Request("https://worker.invalid/cortina-reconcile?limit=1000&environment=production", {
    method: "POST", headers: { Authorization: `Bearer ${secret}` },
    body: JSON.stringify({ limit: 1000, sessionId: "attacker-selected", environment: "production" }),
  });
  const response = await handler(req);
  assertEquals(response.status, 200); assertEquals(await response.json(), { processed: 0 });
  assertEquals(claims, 1); assertEquals(req.bodyUsed, false);
  assertEquals(response.headers.get("cache-control"), "no-store");
});

Deno.test("worker sanitizes uncertain database outcomes", async () => {
  const handler = reconciliationHandler((key) => settings[key], () => ({
    claim: async () => { throw Error("sensitive database/provider details"); },
  } as unknown as ReconciliationDeps));
  const response = await handler(request());
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "reconciliation_outcome_unknown" });
});

for (const named of [false, true]) {
Deno.test(`actual SDK adapters use ${named ? "exact named" : "legacy"} key with bounded RPCs and bound Stripe GETs`, async () => {
  const env = { ...settings, SUPABASE_URL: "https://database.invalid", SUPABASE_SERVICE_ROLE_KEY: "fixture-service-key",
    STRIPE_SECRET_KEY: "sk_test_fixture_only", CLEANSTREAM_MAIL_SECRET_KEY_NAME: "other-component",
    SUPABASE_SECRET_KEYS: named ? JSON.stringify({ "reconciliation-component": namedKey,
      "other-component": "sb_secret_synthetic_other", default: "sb_secret_synthetic_default" }) : "{unread-broken-dictionary",
    ...(named ? { [selector]: "reconciliation-component" } : {}),
  } as Record<string, string>;
  const reads: string[] = [];
  const getEnv = (key: string) => { reads.push(key); return env[key]; };
  const id = "00000000-0000-4000-8000-000000000001";
  const session = { id, machine_id: 1, user_id: null, amount_cents: 400, currency: "USD", payment_method: "card",
    channel: "app", status: "support_required", product_code: 3, pulse_line_number: null,
    nayax_environment: "sandbox", nayax_terminal_id: "4434331126150568", nayax_uniqr: null, stripe_livemode: false,
    stripe_payment_intent_id: "pi_fixture", stripe_charge_id: "ch_fixture", stripe_refund_id: "re_fixture",
    stripe_checkout_session_id: null, reconcile_claim: "00000000-0000-4000-8000-000000000002" };
  const calls: Array<{ path: string; method: string }> = [];
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const method = init?.method ?? (input instanceof Request ? input.method : "GET");
      calls.push({ path: url.pathname, method });
      if (url.hostname === "database.invalid") {
        assertEquals(method, "POST"); assertEquals(init?.signal instanceof AbortSignal, true);
        const headers = new Headers(init?.headers);
        assertEquals(headers.get("apikey"), named ? namedKey : "fixture-service-key");
        assertEquals(headers.get("authorization"), named ? null : "Bearer fixture-service-key");
        const body = JSON.parse(String(init?.body));
        if (url.pathname.endsWith("/claim_cortina_reconciliation")) {
          assertEquals(body, { p_environment: "sandbox" }); return Response.json(session);
        }
        assertEquals(url.pathname, "/rest/v1/rpc/finish_cortina_reconciliation");
        assertEquals(body.p_claim, session.reconcile_claim); assertEquals(body.p_session, id);
        assertEquals(body.p_outcome, "refund_succeeded");
        assertEquals(body.p_evidence.refund.id, "re_fixture");
        return Response.json(true);
      }
      assertEquals(url.hostname, "api.stripe.com"); assertEquals(method, "GET");
      if (url.pathname === "/v1/payment_intents/pi_fixture") return Response.json({
        object: "payment_intent", id: "pi_fixture", status: "succeeded", amount: 400, amount_received: 400,
        currency: "usd", livemode: false, latest_charge: "ch_fixture", metadata: {
          purpose: "cortina_vend", cortina_session_id: id, machine_id: "1", amount_cents: "400",
        },
      });
      assertEquals(url.pathname, "/v1/refunds/re_fixture");
      return Response.json({ object: "refund", id: "re_fixture", payment_intent: "pi_fixture", charge: "ch_fixture",
        status: "succeeded", currency: "usd", amount: 400 });
    }) as typeof fetch;
    const handler = reconciliationHandler(getEnv);
    const response = await handler(request());
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { processed: 1, applied: true, outcome: "refund_succeeded" });
    assertEquals(calls, [
      { path: "/rest/v1/rpc/claim_cortina_reconciliation", method: "POST" },
      { path: "/v1/payment_intents/pi_fixture", method: "GET" },
      { path: "/v1/refunds/re_fixture", method: "GET" },
      { path: "/rest/v1/rpc/finish_cortina_reconciliation", method: "POST" },
    ]);
    assertEquals(reads.includes(named ? "SUPABASE_SERVICE_ROLE_KEY" : "SUPABASE_SECRET_KEYS"), false);
    assertEquals(reads.includes("CLEANSTREAM_MAIL_SECRET_KEY_NAME"), false);
    assertEquals(reads.includes("SUPABASE_ANON_KEY"), false);
  } finally { globalThis.fetch = originalFetch; }
});
}

for (const [name, selected, dictionary] of [
  ["empty selector", "", JSON.stringify({ "": namedKey })],
  ["padded selector", " reconciliation-component", JSON.stringify({ " reconciliation-component": namedKey })],
  ["missing dictionary", "reconciliation-component", undefined],
  ["malformed dictionary", "reconciliation-component", "{broken"],
  ["array dictionary", "reconciliation-component", "[]"],
  ["missing selected entry", "reconciliation-component", JSON.stringify({ default: namedKey })],
  ["inherited entry", "toString", "{}"],
  ["publishable instead of secret", "reconciliation-component", JSON.stringify({ "reconciliation-component": "sb_publishable_synthetic" })],
] as const) {
  Deno.test(`worker ${name} returns sanitized 503 without legacy fallback, SDK construction or HTTP`, async () => {
    const env: Record<string, string | undefined> = { ...settings, [selector]: selected,
      SUPABASE_SECRET_KEYS: dictionary, SUPABASE_SERVICE_ROLE_KEY: "fixture-legacy-must-not-be-read",
      SUPABASE_URL: "https://database.invalid", CLEANSTREAM_MAIL_SECRET_KEY_NAME: "default" };
    const reads: string[] = [];
    let sends = 0;
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = (() => { sends++; throw Error("HTTP prohibited"); }) as typeof fetch;
      const handler = reconciliationHandler((key) => { reads.push(key); return env[key]; });
      const req = request();
      const response = await handler(req);
      assertEquals(response.status, 503);
      assertEquals(await response.json(), { error: "reconciliation_outcome_unknown" });
      assertEquals(req.bodyUsed, false); assertEquals(sends, 0);
      assertEquals(reads, ["CORTINA_RECONCILIATION_WORKER_SECRET", "CORTINA_RECONCILIATION_ENABLED",
        "CORTINA_RECONCILIATION_ENVIRONMENT", selector, "SUPABASE_SECRET_KEYS"]);
    } finally { globalThis.fetch = originalFetch; }
  });
}
