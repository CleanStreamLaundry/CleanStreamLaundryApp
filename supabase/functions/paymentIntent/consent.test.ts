import assert from "node:assert/strict";
import { handleCreatePaymentIntent } from "./logic.ts";
import { handleCheckout } from "../createCheckoutSession/logic.ts";
import { ActionConsentError, captureWalletLoadConsent } from "../_shared/loyalty_action_consent.ts";

const subject = "00000000-0000-4000-8000-000000000001";
const wallet = "00000000-0000-4000-8000-000000000002";
const contextId = "00000000-0000-4000-8000-000000000003";
const consent = { context_id: contextId, acknowledged: true };
const env = (name: string) => ({ SUPABASE_URL: "https://consent.synthetic.invalid",
  SUPABASE_ANON_KEY: "synthetic-public" } as Record<string, string>)[name];

for (const channel of ["payment_intent", "checkout"] as const) {
  function fixture(options: {
    admissionFailure?: number; disableAfterConsent?: boolean; bindingFailure?: boolean;
    consentFailure?: string; receiptOverride?: Record<string, unknown>; providerMismatch?: boolean;
  } = {}) {
    const events: string[] = [], keys: unknown[] = [], payloads: Record<string, unknown>[] = [];
    let reference: string | null = null, admissions = 0, accepted = false, creates = 0, retrieves = 0;
    const rpc = (name: string) => {
      if (name === "new_payments_enabled") return { abortSignal: () => Promise.resolve({
        data: !(accepted && options.disableAfterConsent), error: null,
      }) };
      if (name === "get_or_create_wallet_account") return Promise.resolve({ data: wallet, error: null });
      assert.equal(name, "bind_wallet_load_consent_provider");
      events.push("bind");
      if (options.bindingFailure) return Promise.resolve({ error: { message: "synthetic lost receipt" } });
      reference = channel === "payment_intent" ? "pi_consent" : "cs_consent";
      return Promise.resolve({ error: null });
    };
    const supabase = { auth: { getUser: () => Promise.resolve({ data: { user: { id: subject } }, error: null }) }, rpc };
    const transport: typeof fetch = async (input, init) => {
      const request = new Request(input, init);
      assert.equal(request.headers.get("Authorization"), "Bearer captured-original");
      assert.equal(request.headers.get("apikey"), "synthetic-public");
      assert.equal(new URL(request.url).pathname, "/rest/v1/rpc/accept_wallet_load_consent");
      assert.deepEqual(await request.json(), { p_context_id: contextId, p_acknowledged: true,
        p_amount_cents: 2500, p_channel: channel });
      events.push("accept"); accepted = true;
      if (options.consentFailure) return Response.json({ message: options.consentFailure }, { status: 409 });
      return Response.json({ context_id: contextId, subject_id: subject, wallet_account_id: wallet,
        amount_cents: 2500, channel, accepted_at: "2026-10-05T15:00:00Z", policy_version: "synthetic-v1",
        policy_sha256: "a".repeat(64), provider_reference: reference, ...options.receiptOverride });
    };
    let provider: Record<string, unknown>;
    const create = (params: Record<string, unknown>, opts: { idempotencyKey: string }) => {
      creates++; events.push("stripe"); keys.push(opts?.idempotencyKey); payloads.push(params);
      provider = { id: channel === "payment_intent" ? "pi_consent" : "cs_consent",
        client_secret: "synthetic-secret", url: "https://checkout.synthetic.invalid",
        amount: 2500, amount_total: 2500, currency: "usd", metadata: params.metadata };
      if (options.providerMismatch) provider.amount = provider.amount_total = 2600;
      return Promise.resolve(provider);
    };
    const retrieve = (id: string) => {
      retrieves++; events.push("retrieve"); assert.equal(id, reference); return Promise.resolve(provider);
    };
    const stripe = { paymentIntents: { create, retrieve }, checkout: { sessions: { create, retrieve } } };
    const run = (rawConsent: unknown = consent, purpose = "walletLoad", amount = 2500) => {
      const req = new Request("https://edge.synthetic.invalid", { method: "POST",
        headers: { Authorization: "Bearer captured-original" },
        body: JSON.stringify({ amount, purpose, consent: rawConsent }),
      });
      const deps = { stripe, supabase, supabaseAdmin: supabase,
        fundingAdmission: () => {
          events.push("admission");
          if (admissions++ === options.admissionFailure) throw new Error("account_restricted");
          return Promise.resolve();
        },
        walletLoadConsent: captureWalletLoadConsent(req, env, transport),
      };
      return channel === "payment_intent"
        ? handleCreatePaymentIntent(req, deps as unknown as Parameters<typeof handleCreatePaymentIntent>[1])
        : handleCheckout(req, deps as unknown as Parameters<typeof handleCheckout>[1]);
    };
    return { run, events, keys, payloads, counts: () => ({ creates, retrieves }) };
  }

  Deno.test(`${channel}: explicit consent precedes Stripe and immutable provider reference precedes response`, async () => {
    const f = fixture(); assert.equal((await f.run()).status,200);
    assert.deepEqual(f.events,["admission","admission","accept","admission","stripe","bind","admission"]);
    assert.deepEqual(f.keys,[`loyalty-load:${contextId}`]);
    assert.deepEqual(f.payloads[0].metadata,{ user_id:subject,purpose:"wallet_load",amount_cents:"2500",
      wallet_account_id:wallet,consent_context_id:contextId,consent_policy_version:"synthetic-v1",consent_policy_sha256:"a".repeat(64) });
  });
  for (const value of [null, {}, { ...consent, acknowledged:false }, { ...consent, acknowledged:"true" },
    { ...consent, context_id:"bad" }]) {
    Deno.test(`${channel}: missing or unchecked consent cannot reach Stripe ${JSON.stringify(value)}`, async () => {
      const f = fixture(); await assert.rejects(f.run(value), ActionConsentError);
      assert.deepEqual(f.counts(),{creates:0,retrieves:0}); assert(!f.events.includes("accept"));
    });
  }
  for (const message of ["consent_context_invalid","consent_context_stale","consent_replay_mismatch","payment_reconciliation_required"]) {
    Deno.test(`${channel}: database ${message} refuses provider creation`, async () => {
      const f = fixture({consentFailure:message});
      await assert.rejects(f.run(),(e:Error)=>e.message===message);
      assert.deepEqual(f.counts(),{creates:0,retrieves:0});
    });
  }
  for (const receiptOverride of [{subject_id:"different-account"},{wallet_account_id:"invalid"},
    {amount_cents:2600},{channel:"different-channel"},{policy_sha256:"invalid"},{provider_reference:"pi_!"}]) {
    Deno.test(`${channel}: malformed or cross-account receipt fails closed ${JSON.stringify(receiptOverride)}`, async () => {
      const f = fixture({receiptOverride}); await assert.rejects(f.run(),ActionConsentError);
      assert.deepEqual(f.counts(),{creates:0,retrieves:0});
    });
  }
  Deno.test(`${channel}: known provider reference is retrieved on replay, never recreated`, async () => {
    const f = fixture(); const first = await (await f.run()).json();
    assert.deepEqual(await (await f.run()).json(),first);
    assert.deepEqual(f.counts(),{creates:1,retrieves:1});
  });
  Deno.test(`${channel}: failed reference write never exposes payment credentials and retry uses same key`, async () => {
    const f = fixture({bindingFailure:true});
    await assert.rejects(f.run(),(e:Error)=>e.message==="consent_receipt_pending");
    await assert.rejects(f.run(),(e:Error)=>e.message==="consent_receipt_pending");
    assert.deepEqual(f.keys,[`loyalty-load:${contextId}`,`loyalty-load:${contextId}`]);
  });
  Deno.test(`${channel}: admission and creation switch are rechecked after acceptance`, async () => {
    for (const opts of [{admissionFailure:2},{disableAfterConsent:true}]) {
      const f = fixture(opts); await assert.rejects(f.run()); assert.deepEqual(f.counts(),{creates:0,retrieves:0});
    }
  });
  Deno.test(`${channel}: revocation after Stripe still retains provider reference without exposing credentials`, async () => {
    const f = fixture({admissionFailure:3}); await assert.rejects(f.run());
    assert(f.events.includes("stripe")); assert(f.events.includes("bind"));
  });
  Deno.test(`${channel}: mismatched provider amount cannot be attached to acceptance`, async () => {
    const f = fixture({providerMismatch:true}); await assert.rejects(f.run(),ActionConsentError);
    assert(!f.events.includes("bind"));
  });
  Deno.test(`${channel}: fractional or out-of-range wallet cents cannot dispatch`, async () => {
    for (const amount of [1.2,2147483648,Number.MAX_SAFE_INTEGER]) {
      const f = fixture(); await assert.rejects(f.run(consent,"walletLoad",amount));
      assert.deepEqual(f.counts(),{creates:0,retrieves:0});
    }
  });
  Deno.test(`${channel}: direct-machine payment still requires no loyalty context or wallet`, async () => {
    const f = fixture(); assert.equal((await f.run(null,"directMachinePayment")).status,200);
    assert.deepEqual(f.events,["stripe"]); assert.deepEqual(f.keys,[undefined]);
    assert.deepEqual(f.payloads[0].metadata,{user_id:subject,purpose:"direct_machine_payment",amount_cents:"2500"});
  });
}
