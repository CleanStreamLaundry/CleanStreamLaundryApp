import assert from "node:assert/strict";
import { deliverOne, type MailConfig, type MailJob, renderMail, type Rpc } from "./mail.ts";

const config: MailConfig = {
  key: "re_synthetic", from: "notifications@updates.cleanstreamlaundry.com",
  replyTo: "support@cleanstreamlaundry.com", postal: "",
  publicUrl: "https://synthetic.invalid/functions/v1/newsletter",
  pageUrl: "https://cleanstreamlaundry.com/newsletter", tokenSecret: "x".repeat(43),
};
const job: MailJob = {
  id: "00000000-0000-4000-8000-000000000001", lease_id: "synthetic-lease",
  kind: "topup_refund_outcome", email: "customer@example.invalid", consent_id: null,
  followup_notice: {
    refund_id: "00000000-0000-4000-8000-000000000002", load_id: "44",
    status: "succeeded", amount_cents: 2000, provider_refund_id: "re_synthetic",
  },
};
const issue: MailJob = {
  ...job, kind: "maintenance_resolved",
  followup_notice: { report_id: '<report> & "reference"', status: "resolved" },
};
const machine: MailJob = {
  ...job, kind: "machine_issue_outcome", followup_notice: undefined,
  machine_issue_notice: { refund_id: "12", transaction_id: "44", resolution: "wallet_refund",
    amount_cents: 450, paid_amount_cents: 350, promo_amount_cents: 100,
    replacement_machine_id: null, replacement_machine_name: null },
};
for (const status of ["approved", "denied"] as const) {
  Deno.test(`legacy ${status} credit keeps outcome but never exposes internal staff notes`, async () => {
    const { payload } = await renderMail({ ...job, kind: "credit_decision", followup_notice: undefined,
      credit_notice: { refund_id: "12", transaction_id: "44", status, amount_cents: 450,
        note: 'PRIVATE STAFF NOTE <script>alert("internal")</script>' },
    }, config);
    assert.match(payload.text, /Claim #12 for transaction #44/);
    assert.match(payload.text, /\$4.50/);
    assert(!/PRIVATE STAFF NOTE|Staff note|internal|script/.test(payload.text));
    assert(!/PRIVATE STAFF NOTE|Staff note|internal|script/.test(payload.html));
  });
}

for (const status of ["succeeded", "denied", "failed", "canceled"] as const) {
  Deno.test(`topup ${status}: meaningful terminal outcome, existing brand, no marketing`, async () => {
    const input: MailJob = { ...job, followup_notice: {
      ...job.followup_notice as Extract<MailJob["followup_notice"], { refund_id: string }>,
      status, provider_refund_id: status === "denied" ? null : "re_synthetic",
    } };
    const result = await renderMail(input, config);
    assert.match(result.payload.text, /\$20.00/);
    assert.match(result.payload.text, /top-up #44/);
    assert.match(result.payload.text, /support@cleanstreamlaundry.com/);
    if (status === "succeeded") {
      assert.match(result.payload.text, /Stripe has confirmed/);
      assert.match(result.payload.text, /does not confirm that it is visible yet/);
    } else {
      assert(!result.payload.text.includes("Stripe has confirmed"));
      assert.match(result.payload.text, /reserved paid amount has been returned/);
      assert.match(result.payload.text, status === "denied" ? /not approved/ : new RegExp(status));
    }
    assert.match(result.payload.html, /<html lang="en"/);
    assert.match(result.payload.html, /role="presentation"/);
    assert.match(result.payload.html, /#2073A9/);
    assert.equal(result.payload.reply_to, config.replyTo);
    assert.deepEqual(result.payload.headers, {});
    assert.equal(result.confirmHash, null); assert.equal(result.unsubscribeHash, null);
    assert(!/newsletter|Unsubscribe|promotion|discount/i.test(result.payload.text));
    assert.equal(result.payloadHash, (await renderMail(input, config)).payloadHash);
  });
}

Deno.test("issue resolution escapes references and does not promise money or a machine start", async () => {
  const { payload } = await renderMail(issue, config);
  assert.match(payload.text, /staff marked your reported issue as resolved/);
  assert.match(payload.text, /does not confirm a refund, loyalty credit or replacement machine cycle/);
  assert.match(payload.html, /&lt;report&gt; &amp; &quot;reference&quot;/);
  assert(!payload.html.includes("<report>"));
  assert(!payload.text.includes("Staff note"));
  assert.deepEqual(payload.headers, {});
});

Deno.test("machine wallet restoration describes exact purchased/promotional source, never a card refund", async () => {
  const { payload } = await renderMail(machine, config);
  assert.match(payload.text, /\$4.50 was returned/);
  assert.match(payload.text, /\$3.50 in purchased funds and \$1.00 in promotional credit/);
  assert.match(payload.text, /not a refund to a card or other payment method/);
  assert(!payload.text.includes("$4.50 in promotional credit"));
  assert.deepEqual(payload.headers, {});
});
Deno.test("confirmed replacement describes start without promising completion or a payout", async () => {
  const { payload } = await renderMail({ ...machine, machine_issue_notice: {
    ...machine.machine_issue_notice!, resolution: "replacement_vend", replacement_machine_id: "22",
    replacement_machine_name: 'Dryer <A> & "B"',
  } }, config);
  assert.match(payload.text, /machine #22\) was confirmed as started/);
  assert.match(payload.html, /Dryer &lt;A&gt; &amp; &quot;B&quot;/);
  assert.match(payload.text, /without another loyalty balance deduction/);
  assert.match(payload.text, /confirms the start, not completion/);
  assert.match(payload.text, /does not issue a cash refund/);
});
for (const [name, patch] of [
  ["manual review", { resolution: "manual_review" }],
  ["arrangement is not a vend", { resolution: "replacement_arranged" }],
  ["unbalanced source", { paid_amount_cents: 400 }],
  ["negative source", { promo_amount_cents: -100 }],
  ["fractional source", { paid_amount_cents: 350.5 }],
  ["unknown replacement machine", { resolution: "replacement_vend" }],
  ["wallet with replacement", { replacement_machine_id: "22" }],
] as const) {
  Deno.test(`machine outcome rejects ${name}`, async () => {
    await assert.rejects(() => renderMail({ ...machine,
      machine_issue_notice: { ...machine.machine_issue_notice!, ...patch } as MailJob["machine_issue_notice"],
    }, config));
  });
}

const topup = job.followup_notice as Extract<MailJob["followup_notice"], { refund_id: string }>;
for (const [name, patch] of [
  ["pending", { status: "pending" }], ["approved", { status: "approved" }],
  ["unknown", { status: "unknown" }], ["manual review", { status: "manual_review" }],
  ["missing provider confirmation", { provider_refund_id: null }],
  ["invalid provider confirmation", { provider_refund_id: "pending" }],
  ["denial with provider refund", { status: "denied" }],
  ["zero amount", { amount_cents: 0 }], ["fractional cents", { amount_cents: 20.5 }],
  ["overflow", { amount_cents: 2147483648 }], ["wrong load", { load_id: "0" }],
  ["invalid refund reference", { refund_id: "<reference>" }],
] as const) {
  Deno.test(`refund renderer fails closed for ${name}`, async () => {
    await assert.rejects(() => renderMail({ ...job,
      followup_notice: { ...topup, ...patch } as MailJob["followup_notice"],
    }, config));
  });
}
for (const input of [
  { ...job, followup_notice: undefined }, { ...job, consent_id: "newsletter" },
  { ...issue, followup_notice: { report_id: "", status: "resolved" } },
  { ...issue, followup_notice: { report_id: "x".repeat(201), status: "resolved" } },
  { ...issue, followup_notice: { report_id: "12", status: "in_progress" } },
]) {
  Deno.test(`resolution renderer rejects malformed payload ${JSON.stringify(input.followup_notice)}`, async () => {
    await assert.rejects(() => renderMail(input as MailJob, config));
  });
}

for (const input of [job, issue, machine]) {
  for (const [status, expected] of [[200, "accepted"], [429, "rate_limited"], [500, "uncertain"]] as const) {
    Deno.test(`${input.kind} worker ${expected}: one send and mail-only RPCs`, async () => {
      const calls: string[] = [];
      const rpc: Rpc = <T>(name: string, args?: Record<string, unknown>) => {
        calls.push(name);
        if (name === "mail_claim") assert.deepEqual(args, { p_include_newsletter: false });
        if (name === "mail_finish") assert.equal(args?.p_result, expected);
        return Promise.resolve((name === "mail_claim" ? input : name === "mail_prepare" ? true : null) as T);
      };
      let sends = 0;
      assert.equal(await deliverOne(rpc, config, (_url, init) => {
        sends++;
        assert.equal(new Headers(init?.headers).get("Idempotency-Key"), `cleanstream/${input.id}`);
        return Promise.resolve(Response.json({ id: "synthetic-provider" }, { status }));
      }), expected);
      assert.equal(sends, 1);
      assert.deepEqual(calls, ["mail_claim", "mail_prepare", "mail_finish"]);
    });
  }
  Deno.test(`${input.kind} rechecks eligibility before dispatch`, async () => {
    const rpc: Rpc = <T>(name: string) => Promise.resolve((name === "mail_claim" ? input : false) as T);
    assert.equal(await deliverOne(rpc, config, () => { throw new Error("Must not send"); }), "skipped");
  });
}
