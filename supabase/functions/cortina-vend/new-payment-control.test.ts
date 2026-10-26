import assert from "node:assert/strict";
import { handleCortinaVend } from "./logic.ts";
import { createAdminClient, createStripeClient, errorResponse } from "../_shared/cortina.ts";

const subject = "00000000-0000-4000-8000-000000000001";
const sessionId = "00000000-0000-4000-8000-000000000002";
const requestId = "00000000-0000-4000-8000-000000000003";
const secret = "sb_secret_synthetic_vend";
const config: Record<string, string> = {
  SUPABASE_URL: "https://vend.synthetic.invalid",
  SUPABASE_ANON_KEY: "synthetic-public-key",
  CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME: "vend",
  SUPABASE_SECRET_KEYS: JSON.stringify({ vend: secret }),
  STRIPE_SECRET_KEY: "sk_test_synthetic_only",
  NAYAX_SANDBOX_START_URL: "https://nayax.synthetic.invalid/start",
  NAYAX_SANDBOX_SECRET_TOKEN: "synthetic-nayax-only",
};
type Options = {
  method?: "card" | "wallet";
  channel?: "app" | "web";
  guest?: boolean;
  existing?: string;
  control?: unknown;
  failure?: "http" | "timeout";
  debitError?: { code: string; message: string };
};

async function fixture(options: Options, action: (f: {
  calls: Request[];
  state: () => Record<string, unknown> | null;
  request: (route: string) => Promise<Response>;
}) => Promise<void>) {
  const originalFetch = globalThis.fetch, originalEnv = Deno.env.get;
  const calls: Request[] = [];
  const method = options.method ?? "card", channel = options.channel ?? "app";
  const userId = options.guest ? null : subject;
  const control = Object.hasOwn(options, "control") ? options.control : true;
  const machine = { id: 1, Name: "Synthetic washer", Machine_type: "washer", Status: "Idle",
    Location_ID: 1, washer_size_rate_id: 1, is_out_of_service: false };
  const machineConfig = { machine_id: 1, public_machine_token: "synthetic-machine", is_enabled: true,
    review_required: false, product_codes: null, pulse_line_number: 1, environment: "sandbox",
    nayax_terminal_id: "0000000000000001" };
  const base = () => ({ id: sessionId, machine_id: 1, user_id: userId, amount_cents: 400,
    currency: "USD", dryer_minutes: null, product_code: null, pulse_line_number: 1,
    payment_method: method, channel, client_request_id: requestId, transaction_id: "synthetic-transaction",
    nayax_environment: "sandbox", nayax_terminal_id: "0000000000000001", nayax_uniqr: null,
    stripe_livemode: false, stripe_payment_intent_id: method === "card" ? "pi_synthetic" : null,
    stripe_checkout_session_id: method === "card" && channel === "web" ? "cs_synthetic" : null,
    created_at: new Date().toISOString(), status: "payment_pending" });
  let session: Record<string, unknown> | null = options.existing ? { ...base(), status: options.existing } : null;
  const row = (req: Request, value: unknown) => Response.json(
    req.headers.get("accept")?.includes("vnd.pgrst.object") ? value : value === null ? [] : [value],
  );
  try {
    Deno.env.get = (name) => config[name];
    globalThis.fetch = async (input, init) => {
      const req = new Request(input, init), url = new URL(req.url);
      calls.push(req.clone());
      if (url.origin === config.SUPABASE_URL) {
        if (url.pathname === "/auth/v1/user") return Response.json({ id: subject });
        if (url.pathname === "/rest/v1/rpc/consume_cortina_request_capacity") {
          assert.equal(req.method, "POST");
          const body = await req.json();
          assert(["quote", "card", "status"].includes(body.p_bucket));
          assert.deepEqual(body, { p_bucket: body.p_bucket });
          assert.equal(req.headers.get("apikey"), secret);
          assert.equal(req.headers.has("authorization"), false);
          return Response.json({ allowed: true, retry_after_seconds: 0 });
        }
        if (url.pathname === "/rest/v1/rpc/get_admission_status") {
          assert.equal(req.method, "POST");
          assert.deepEqual(await req.json(), {});
          assert.equal(req.headers.get("authorization"), "Bearer original-caller");
          assert.equal(req.headers.get("apikey"), config.SUPABASE_ANON_KEY);
          return Response.json({ subject_id: subject, account_access: "eligible", next_step: "home" });
        }
        if (url.pathname === "/rest/v1/rpc/new_payments_enabled") {
          assert(req.signal instanceof AbortSignal);
          assert.equal(req.signal.aborted, false);
          if (options.failure === "timeout") throw new DOMException("private timeout", "TimeoutError");
          if (options.failure === "http") return Response.json({ message: "private RPC diagnostic" }, { status: 404 });
          return Response.json(control);
        }
        if (url.pathname === "/rest/v1/rpc/redeem_wallet_for_cortina") {
          if (options.debitError) return Response.json(options.debitError, { status: 503 });
          assert(session); session.status = "paid";
          return Response.json({ redemption_id: 1 });
        }
        if (url.pathname === "/rest/v1/rpc/record_cortina_card_payment") {
          assert(session); session.status = "paid";
          return Response.json(true);
        }
        if (url.pathname === "/rest/v1/cortina_machine_config") return row(req, machineConfig);
        if (url.pathname === "/rest/v1/Machines") return row(req, machine);
        if (url.pathname === "/rest/v1/washer_size_rates") {
          return row(req, { id: 1, size_label: "Synthetic", price_cents: 400, is_active: true, review_required: false });
        }
        if (url.pathname === "/rest/v1/cortina_vend_events") {
          return req.method === "GET" ? row(req, null) : Response.json(null);
        }
        if (url.pathname === "/rest/v1/cortina_vend_sessions") {
          if (req.method === "POST") {
            if (session) return Response.json({ code: "23505", message: "Synthetic duplicate" }, { status: 409 });
            session = { ...base(), ...await req.json(), stripe_payment_intent_id: null, stripe_checkout_session_id: null };
            return row(req, session);
          }
          if (req.method === "PATCH") {
            const expected = url.searchParams.get("status");
            if (!session || (expected?.startsWith("eq.") && session.status !== expected.slice(3))) return row(req, null);
            Object.assign(session, await req.json());
          }
          return row(req, session);
        }
      }
      if (url.origin === "https://api.stripe.com") {
        if (req.method === "POST" && url.pathname === "/v1/payment_intents") {
          return Response.json({ id: "pi_synthetic", client_secret: "synthetic-client-secret", livemode: false });
        }
        if (req.method === "POST" && url.pathname === "/v1/checkout/sessions") {
          return Response.json({ id: "cs_synthetic", url: "https://checkout.synthetic.invalid", livemode: false });
        }
        if (req.method === "GET" && url.pathname === "/v1/payment_intents/pi_synthetic") {
          return Response.json({ id: "pi_synthetic", status: "succeeded", amount: 400, amount_received: 400,
            currency: "usd", livemode: false, latest_charge: "ch_synthetic", metadata: {
              purpose: "cortina_vend", cortina_session_id: sessionId, machine_id: "1", amount_cents: "400",
              ...(userId ? { user_id: userId } : {}),
            } });
        }
      }
      if (req.url === config.NAYAX_SANDBOX_START_URL) {
        return Response.json({ Status: { Verdict: "Approved", Code: 0 } });
      }
      throw new Error("Unexpected offline request " + req.method + " " + url.pathname);
    };
    const deps = { admin: createAdminClient("cortina-vend"), stripe: createStripeClient() };
    await action({ calls, state: () => session, request: async (route) => {
      const req = new Request("https://edge.synthetic.invalid/cortina-vend/" + route, {
        method: "POST", headers: options.guest ? {} : { Authorization: "Bearer original-caller" },
        body: JSON.stringify(route === "status" ? { sessionId, accessToken: requestId } :
          { machineToken: "synthetic-machine", amountCents: 400,
          channel, clientRequestId: requestId, sessionId, accessToken: requestId }),
      });
      try { return await handleCortinaVend(req, deps); } catch (error) { return errorResponse(error); }
    } });
  } finally { globalThis.fetch = originalFetch; Deno.env.get = originalEnv; }
}

const path = (r: Request) => new URL(r.url).pathname;
const controls = (calls: Request[]) => calls.filter((r) => path(r).endsWith("/new_payments_enabled"));
const creations = (calls: Request[]) => calls.filter((r) => r.method === "POST" &&
  (new URL(r.url).hostname === "api.stripe.com" || path(r).endsWith("/redeem_wallet_for_cortina") ||
    new URL(r.url).hostname === "nayax.synthetic.invalid"));

for (const channel of ["app", "web"] as const) {
  Deno.test("Cortina enabled guest " + channel + " creates provider object with unchanged binding and metadata", async () => {
    await fixture({ channel, guest: true }, async (f) => {
      const response = await f.request("card"); assert.equal(response.status, 200);
      const result = await response.json(); assert.equal(result.sessionId, sessionId); assert.equal(result.accessToken, requestId);
      assert.equal(controls(f.calls).length, 2); assert.equal(creations(f.calls).length, 1);
      const control = controls(f.calls)[0];
      assert.equal(control.headers.get("apikey"), secret); assert.equal(control.headers.has("authorization"), false);
      assert.equal(await control.text(), "{}");
      const provider = creations(f.calls)[0], form = new URLSearchParams(await provider.text());
      assert.equal(form.get("metadata[cortina_session_id]"), sessionId);
      assert.equal(form.get("metadata[amount_cents]"), "400");
      assert.equal(form.has("metadata[user_id]"), false);
      assert.equal(provider.headers.get("Stripe-Version"), "2023-10-16");
      assert.equal(provider.headers.get("Idempotency-Key"), `cortina-${channel === "app" ? "card" : "checkout"}-${sessionId}`);
      assert.equal(f.state()?.status, "payment_pending");
    });
  });
}
for (const method of ["card", "wallet"] as const) for (const existing of [undefined, "payment_pending"]) {
  Deno.test("Cortina disabled " + method + " " + (existing ?? "new draft") + " creates no money or vend and never marks failed", async () => {
    await fixture({ method, existing, control: false }, async (f) => {
      const response = await f.request(method); assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { error: "new_payments_unavailable", code: "new_payments_unavailable" });
      assert.equal(controls(f.calls).length, 1); assert.equal(creations(f.calls).length, 0);
      assert.equal(f.state()?.status, "payment_pending");
      assert.equal(f.calls.some((r) => r.method === "PATCH"), false);
    });
  });
}
for (const channel of ["app", "web"] as const) Deno.test("Cortina disabled guest " + channel + " is also blocked", async () => {
  await fixture({ channel, guest: true, control: false }, async (f) => {
    assert.equal((await f.request("card")).status, 503);
    assert.equal(creations(f.calls).length, 0); assert.equal(f.calls.some((r) => path(r) === "/auth/v1/user"), false);
  });
});
for (const options of [{ control: null }, { control: "true" }, { control: {} },
  { failure: "http" as const }, { failure: "timeout" as const }]) {
  Deno.test("Cortina creation fails closed without corrupting draft " + JSON.stringify(options), async () => {
    await fixture(options, async (f) => {
      const response = await f.request("card"); assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { error: "new_payments_unavailable", code: "new_payments_unavailable" });
      assert.equal(creations(f.calls).length, 0); assert.equal(f.state()?.status, "payment_pending");
    });
  });
}
Deno.test("Cortina enabled wallet checks before caller-bound debit and preserves paid Start", async () => {
  await fixture({ method: "wallet" }, async (f) => {
    assert.equal((await f.request("wallet")).status, 200);
    const controlIndex = f.calls.findIndex((r) => path(r).endsWith("/new_payments_enabled"));
    const debitIndex = f.calls.findIndex((r) => path(r).endsWith("/redeem_wallet_for_cortina"));
    assert(controlIndex < debitIndex);
    const auth = f.calls.find((r) => path(r) === "/auth/v1/user")!;
    assert.equal(auth.headers.get("authorization"), "Bearer original-caller");
    assert.equal(auth.headers.get("apikey"), secret);
    assert.equal(f.calls[debitIndex].headers.get("authorization"), "Bearer original-caller");
    assert.equal(f.calls[debitIndex].headers.get("apikey"), config.SUPABASE_ANON_KEY);
    assert.equal(f.state()?.status, "awaiting_sale");
    assert.equal(controls(f.calls).length, 1);
  });
});
Deno.test("Cortina reader true then SQL late-disable refusal stays 503 with no failed draft or Start", async () => {
  await fixture({ method: "wallet", control: true,
    debitError: { code: "PT503", message: "new_payments_unavailable" } }, async (f) => {
    const response = await f.request("wallet");
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: "new_payments_unavailable", code: "new_payments_unavailable" });
    assert.equal(controls(f.calls).length, 1);
    assert.equal(f.calls.filter((r) => path(r).endsWith("/redeem_wallet_for_cortina")).length, 1);
    assert.equal(f.state()?.status, "payment_pending");
    assert.equal(f.calls.some((r) => r.method === "PATCH"), false);
    assert.equal(f.calls.some((r) => new URL(r.url).hostname === "nayax.synthetic.invalid"), false);
    assert.equal(f.calls.some((r) => new URL(r.url).hostname === "api.stripe.com"), false);
  });
});
for (const debitError of [{ code: "P0001", message: "Insufficient balance" },
  { code: "PT503", message: "Other existing wallet failure" }]) {
  Deno.test("Cortina unrelated wallet refusal retains existing 402 and failed draft: " + debitError.code, async () => {
    await fixture({ method: "wallet", debitError }, async (f) => {
      const response = await f.request("wallet");
      assert.equal(response.status, 402);
      assert.deepEqual(await response.json(), { error: debitError.message, code: "wallet_failed" });
      assert.equal(f.state()?.status, "failed");
      assert.equal(f.calls.filter((r) => r.method === "PATCH").length, 1);
      assert.equal(f.calls.some((r) => new URL(r.url).hostname === "nayax.synthetic.invalid"), false);
    });
  });
}
for (const existing of ["paid", "awaiting_sale", "started"]) Deno.test("Cortina funded wallet replay " + existing + " bypasses unavailable creation control", async () => {
  await fixture({ method: "wallet", existing, failure: "http" }, async (f) => {
    assert.equal((await f.request("wallet")).status, 200);
    assert.equal(controls(f.calls).length, 0);
    assert.equal(f.calls.some((r) => path(r).endsWith("/redeem_wallet_for_cortina")), false);
    assert.equal(f.state()?.status, existing === "paid" ? "awaiting_sale" : existing);
  });
});
for (const route of ["card", "confirm", "status"]) Deno.test("Cortina funded " + route + " remains available when reader would fail", async () => {
  await fixture({ existing: "paid", failure: "http" }, async (f) => {
    assert.equal((await f.request(route)).status, 200);
    assert.equal(controls(f.calls).length, 0); assert.equal(creations(f.calls).length, 0);
  });
});
Deno.test("Cortina pending card confirmation still verifies settlement and starts when creation is disabled", async () => {
  await fixture({ existing: "payment_pending", control: false }, async (f) => {
    const response = await f.request("confirm"); assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: "paid" });
    assert.equal(controls(f.calls).length, 0);
    assert.equal(f.calls.filter((r) => path(r).endsWith("/record_cortina_card_payment")).length, 1);
    assert.equal(f.calls.filter((r) => new URL(r.url).hostname === "api.stripe.com" && r.method === "POST").length, 0);
    assert.equal(f.state()?.status, "awaiting_sale");
  });
});
Deno.test("Cortina quote remains available with a disabled creation switch", async () => {
  await fixture({ control: false }, async (f) => {
    assert.equal((await f.request("quote")).status, 200);
    assert.equal(controls(f.calls).length, 0); assert.equal(creations(f.calls).length, 0);
  });
});
