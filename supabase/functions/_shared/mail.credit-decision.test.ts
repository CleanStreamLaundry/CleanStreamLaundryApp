import assert from "node:assert/strict";
import { deliverOne, type MailConfig, type MailJob, renderMail, type Rpc } from "./mail.ts";
import { creditNotificationSummary } from "./refund_resolution.ts";

const config: MailConfig = {
  key: "re_synthetic", from: "synthetic@cleanstreamlaundry.com",
  replyTo: "support@cleanstreamlaundry.com", postal: "Synthetic postal address",
  publicUrl: "https://synthetic.invalid/functions/v1/newsletter",
  pageUrl: "https://cleanstreamlaundry.com/newsletter", tokenSecret: "x".repeat(43),
};
const job: MailJob = {
  id: "00000000-0000-4000-8000-000000000001", lease_id: "synthetic-lease",
  kind: "credit_decision", email: "customer@example.invalid", consent_id: null,
  credit_notice: { refund_id: "12", transaction_id: "44", status: "approved",
    amount_cents: 250, note: '<script>alert("private")</script> & staff note' },
};
for (const status of ["approved", "denied"] as const) {
  Deno.test(`credit ${status}: server snapshot, promo-not-cash purpose, private-note exclusion and shared accessible brand`, async () => {
    const result = await renderMail({ ...job, credit_notice: { ...job.credit_notice!, status } }, config);
    assert.match(result.payload.subject, new RegExp(status));
    assert.match(result.payload.text, /\$2.50/);
    assert.match(result.payload.text, /Claim #12 for transaction #44/);
    assert.match(result.payload.text, status === "approved" ? /promotional credit was added/ : /was not approved/);
    assert.match(result.payload.text, status === "approved" ? /not a cash refund/ : /did not add a credit or return money/);
    assert(!/script|staff note|private/.test(result.payload.html));
    assert(!/script|staff note|private/.test(result.payload.text));
    assert.match(result.payload.html, /<html lang="en"/); assert.match(result.payload.html, /role="presentation"/);
    assert.match(result.payload.html, /#2073A9/); assert.match(result.payload.html, /<h1/);
    assert.equal(result.payload.reply_to, config.replyTo);
    assert.deepEqual(result.payload.to, [job.email]); assert.deepEqual(result.payload.headers, {});
    assert.equal(result.confirmHash, null); assert.equal(result.unsubscribeHash, null);
    assert(!/approveRefund|denyRefund|action=confirm|action=restore/.test(result.payload.html));
    assert.equal(result.payloadHash, (await renderMail({ ...job, credit_notice: { ...job.credit_notice!, status } }, config)).payloadHash);
  });
}
for (const [label, notice] of [
  ["missing snapshot", undefined], ["bad id", { ...job.credit_notice!, refund_id: "<id>" }],
  ["bad status", { ...job.credit_notice!, status: "pending" }],
  ["fractional cents", { ...job.credit_notice!, amount_cents: 2.5 }],
  ["zero cents", { ...job.credit_notice!, amount_cents: 0 }],
  ["overflow", { ...job.credit_notice!, amount_cents: 2147483648 }],
  ["oversized note", { ...job.credit_notice!, note: "x".repeat(4001) }],
] as const) {
  Deno.test(`credit renderer rejects ${label}`, async () => {
    await assert.rejects(() => renderMail({ ...job, credit_notice: notice as MailJob["credit_notice"] }, config));
  });
}
for (const state of ["ready", "leased", "sending", "uncertain", "failed", "suppressed", "not_queued", "PRIVATE", "__proto__"]) {
  Deno.test(`credit receipt ${state}: committed decision never implies sent or delivery`, () => {
    const summary = creditNotificationSummary({ notificationState: state, notificationSent: true });
    assert.equal(summary.notificationSent, false); assert.match(summary.notificationWarning!, /credit decision is saved/);
    assert(!summary.notificationWarning!.includes("PRIVATE"));
    if (state === "ready" || state === "leased") assert.match(summary.notificationWarning!, /queued; delivery is not yet confirmed/);
    if (state === "uncertain") assert.match(summary.notificationWarning!, /requires reconciliation; do not repeat/);
  });
}
for (const state of ["accepted", "delivered", "legacy_sent"]) {
  Deno.test(`credit receipt ${state}: only server-confirmed acceptance supports sent receipt`, () => {
    assert.deepEqual(creditNotificationSummary({ notificationState: state, notificationSent: true }), { notificationSent: true });
    assert.equal(creditNotificationSummary({ notificationState: state, notificationSent: false }).notificationSent, false);
  });
}
Deno.test("credit receipt missing evidence remains unconfirmed", () => {
  assert.equal(creditNotificationSummary({ notificationSent: true }).notificationSent, false);
});
for (const [status, expected] of [[200, "accepted"], [429, "rate_limited"], [500, "uncertain"]] as const) {
  Deno.test(`credit worker ${expected}: notification attempt never invokes the financial decision`, async () => {
    const calls: { name: string; args?: Record<string, unknown> }[] = [];
    const rpc: Rpc = <T>(name: string, args?: Record<string, unknown>) => {
      assert(["mail_claim", "mail_prepare", "mail_finish"].includes(name)); calls.push({ name, args });
      return Promise.resolve((name === "mail_claim" ? job : name === "mail_prepare" ? true : null) as T);
    };
    let sends = 0;
    assert.equal(await deliverOne(rpc, config, (_input, init) => {
      sends++; assert.equal(new Headers(init?.headers).get("Idempotency-Key"), `cleanstream/${job.id}`);
      return Promise.resolve(Response.json({ id: "synthetic-provider" }, { status }));
    }), expected);
    assert.equal(sends, 1); assert.deepEqual(calls.map((c) => c.name), ["mail_claim", "mail_prepare", "mail_finish"]);
    assert.equal(calls[2].args?.p_result, expected);
  });
}
Deno.test("credit worker does not send a superseded snapshot rejected during prepare", async () => {
  const rpc: Rpc = <T>(name: string) => Promise.resolve((name === "mail_claim" ? job : false) as T);
  assert.equal(await deliverOne(rpc, config, () => { throw new Error("No send expected"); }), "skipped");
});
