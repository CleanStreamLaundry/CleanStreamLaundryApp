import assert from "node:assert/strict";
import { deliverOne, type MailConfig, type MailJob, renderMail, type Rpc } from "./mail.ts";

const config: MailConfig = {
  key: "re_synthetic", from: "synthetic@cleanstreamlaundry.com",
  replyTo: "support@cleanstreamlaundry.com", postal: "Synthetic postal address",
  publicUrl: "https://synthetic.invalid/functions/v1/newsletter",
  pageUrl: "https://cleanstreamlaundry.com/newsletter", tokenSecret: "x".repeat(43),
};
const job: MailJob = {
  id: "00000000-0000-4000-8000-000000000001",
  lease_id: "00000000-0000-4000-8000-000000000002",
  kind: "account_deletion_scheduled", email: "customer@example.invalid", consent_id: null,
  lifecycle_requested_at: "2026-10-01T12:30:45.123456+00:00",
  lifecycle_restore_until: "2026-10-31T12:30:45.123456+00:00",
  lifecycle_restored_at: null,
};
const restored: MailJob = { ...job, kind: "account_restored", lifecycle_restored_at: "2026-10-02T10:20:30.654321+00:00" };

Deno.test("90-day deletion confirmation includes the actual acknowledged balances and escaped disclosure", async () => {
  const { payload } = await renderMail({ ...job,
    lifecycle_restore_until: "2026-12-30T12:30:45.123456+00:00",
    lifecycle_consent: {
      policy_version: "synthetic-consent",
      acknowledgement: "I agree to <the recorded terms> & the recovery deadline.",
      purchased_balance_cents: 2050,
      promotional_balance_cents: 500,
    },
  }, config);
  assert.match(payload.text, /2026-12-30 12:30:45.123456 UTC/);
  assert.match(payload.text, /\$20\.50 purchased credit and \$5\.00 promotional credit/);
  assert.match(payload.text, /terms synthetic-consent/);
  assert.match(payload.html, /&lt;the recorded terms&gt; &amp;/);
  assert.match(payload.text, /not a confirmation that credit has been forfeited/);
});

for (const invalid of [-1, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
  Deno.test(`deletion confirmation rejects invalid acknowledged balance ${invalid}`, async () => {
    await assert.rejects(() => renderMail({ ...job, lifecycle_consent: {
      policy_version: "synthetic", acknowledgement: "Acknowledged terms",
      purchased_balance_cents: invalid, promotional_balance_cents: 0,
    } }, config));
  });
}

Deno.test("lifecycle scheduled: exact UTC microsecond deadline and explicit in-app restore, not an auto-restore link", async () => {
  const { payload, confirmHash, unsubscribeHash } = await renderMail(job, config);
  assert.equal(payload.subject, "Your Clean Stream account deletion is scheduled");
  for (const value of [payload.html, payload.text]) {
    assert(value.includes("2026-10-31 12:30:45.123456 UTC"));
    assert.match(value, /open the Clean Stream app, sign in again and verify your identity, then choose Restore account/);
    assert.match(value, /Signing in alone does not restore your account/);
    assert.match(value, /not a confirmation of permanent deletion/);
    assert.match(value, /https:\/\/cleanstreamlaundry.com\/account-deletion/);
    assert.match(value, /Account deletion and restoration information/);
    assert(!/action=restore|\/admin|ConfirmationURL|token=/.test(value));
  }
  assert.equal(confirmHash, null); assert.equal(unsubscribeHash, null);
  assert.deepEqual(payload.headers, {});
});
Deno.test("lifecycle restored: confirms committed restore, not cleanup, resubscription or a new welcome", async () => {
  const { payload } = await renderMail(restored, config);
  assert.equal(payload.subject, "Your Clean Stream account has been restored");
  for (const value of [payload.html, payload.text]) {
    assert.match(value, /restoration completed at 2026-10-02 10:20:30.654321 UTC/);
    assert.match(value, /does not confirm permanent deletion or data cleanup/);
    assert.match(value, /newsletter subscription remains stopped/);
    assert.match(value, /identity verification and account terms still apply/);
    assert(!/Welcome to|List-Unsubscribe|action=confirm/.test(value));
  }
});
for (const notice of [job, restored]) {
  Deno.test(`lifecycle ${notice.kind}: existing accessible brand, configured support reply and stable payload`, async () => {
    const first = await renderMail(notice, config), second = await renderMail(notice, config);
    assert.equal(first.payloadHash, second.payloadHash);
    assert.match(first.payload.html, /<html lang="en"/);
    assert.match(first.payload.html, /role="presentation"/);
    assert.match(first.payload.html, /<h1/);
    assert.match(first.payload.html, /#2073A9/);
    assert.deepEqual(first.payload.to, [notice.email]);
    assert.equal(first.payload.reply_to, config.replyTo);
    assert.equal(first.payload.from, `Clean Stream <${config.from}>`);
  });
}
Deno.test("lifecycle template preserves microseconds while normalizing an explicit server offset to UTC", async () => {
  const { payload } = await renderMail({ ...job,
    lifecycle_requested_at: "2026-10-01T08:30:45.123456-04:00",
    lifecycle_restore_until: "2026-10-31T08:30:45.123456-04:00",
  }, config);
  assert.match(payload.text, /2026-10-31 12:30:45.123456 UTC/);
});
Deno.test("lifecycle template escapes configured footer and reuses existing page origin", async () => {
  const { payload } = await renderMail(job, { ...config, replyTo: "support+<tag>@cleanstreamlaundry.com", pageUrl: "https://www.cleanstreamlaundry.com/newsletter" });
  assert.match(payload.html, /support\+&lt;tag&gt;@cleanstreamlaundry.com/);
  assert(!payload.html.includes("<tag>"));
  assert.match(payload.text, /https:\/\/www.cleanstreamlaundry.com\/account-deletion/);
});
for (const [label, changes] of [
  ["missing requested", { lifecycle_requested_at: undefined }],
  ["missing deadline", { lifecycle_restore_until: null }],
  ["invalid calendar", { lifecycle_restore_until: "2026-02-30T12:30:45Z" }],
  ["injected deadline", { lifecycle_restore_until: '<img src=x onerror="bad">' }],
  ["unbounded fractional precision", { lifecycle_restore_until: "2026-10-31T12:30:45.1234567Z" }],
  ["wrong interval", { lifecycle_restore_until: "2026-11-01T12:30:45.123456Z" }],
  ["wrong microsecond interval", { lifecycle_restore_until: "2026-10-31T12:30:45.123457Z" }],
  ["scheduled with restore", { lifecycle_restored_at: "2026-10-02T00:00:00Z" }],
  ["newsletter consent", { consent_id: job.id }],
] as const) {
  Deno.test(`lifecycle scheduled: rejects ${label}`, async () => {
    await assert.rejects(() => renderMail({ ...job, ...changes }, config));
  });
}
Deno.test("lifecycle restored: valid sub-millisecond restoration is preserved", async () => {
  const { payload } = await renderMail({ ...restored, lifecycle_restored_at: "2026-10-01T12:30:45.123457Z" }, config);
  assert.match(payload.text, /2026-10-01 12:30:45.123457 UTC/);
});
for (const at of [null, "invalid", job.lifecycle_requested_at, job.lifecycle_restore_until]) {
  Deno.test(`lifecycle restored: rejects missing/out-of-window timestamp ${at}`, async () => {
    await assert.rejects(() => renderMail({ ...restored, lifecycle_restored_at: at }, config));
  });
}
for (const [kind, subject] of [
  ["account_welcome", "Welcome to Clean Stream"],
  ["newsletter_confirm", "Confirm your Clean Stream newsletter request"],
  ["newsletter_welcome", "Welcome to the Clean Stream newsletter"],
  ["refund_request", "New loyalty balance credit request"],
] as const) {
  Deno.test(`lifecycle compatibility: unchanged ${kind} renderer contract`, async () => {
    const { payload } = await renderMail({ ...job, kind,
      consent_id: kind.startsWith("newsletter") ? job.id : null,
      refund_notice: { refund_id: "7", transaction_id: "41", user_id: job.id, amount: "25.00", description: "<stored>" },
    }, config);
    assert.equal(payload.subject, subject);
    assert(!payload.text.includes("Restore account"));
    assert.equal("List-Unsubscribe" in payload.headers, kind.startsWith("newsletter"));
    if (kind === "refund_request") {
      assert.match(payload.html, /&lt;stored&gt;/);
      assert.match(payload.text, /https:\/\/cleanstreamlaundry.com\/admin/);
      assert(!/approveRefund|denyRefund/.test(payload.html));
    }
  });
}
for (const [status, expected] of [[200, "accepted"], [429, "rate_limited"], [500, "uncertain"], [403, "failed"]] as const) {
  Deno.test(`lifecycle worker reuses ${expected} classification, one dispatch and permanent idempotency key`, async () => {
    const calls: { name: string; args: Record<string, unknown> | undefined }[] = [];
    const rpc: Rpc = <T>(name: string, args?: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve((name === "mail_claim" ? job : name === "mail_prepare" ? true : null) as T);
    };
    let sends = 0;
    const result = await deliverOne(rpc, config, (_input, init) => {
      sends++;
      assert.equal(new Headers(init?.headers).get("Idempotency-Key"), `cleanstream/${job.id}`);
      return Promise.resolve(Response.json({ id: "synthetic-provider-id" }, { status }));
    });
    assert.equal(result, expected); assert.equal(sends, 1);
    assert.deepEqual(calls.map((c) => c.name), ["mail_claim", "mail_prepare", "mail_finish"]);
    assert.equal(calls[1].args?.p_confirm_hash, null);
    assert.equal(calls[1].args?.p_unsubscribe_hash, null);
    assert.equal(calls[2].args?.p_result, expected);
  });
}
Deno.test("lifecycle worker never sends a stale leased notice rejected at prepare", async () => {
  const rpc: Rpc = <T>(name: string) => Promise.resolve((name === "mail_claim" ? job : false) as T);
  assert.equal(await deliverOne(rpc, config, () => { throw new Error("No send expected"); }), "skipped");
});
Deno.test("lifecycle worker malformed snapshot fails before prepare or transport", async () => {
  const calls: string[] = [];
  const rpc: Rpc = <T>(name: string) => { calls.push(name); return Promise.resolve({ ...job, lifecycle_restore_until: null } as T); };
  await assert.rejects(() => deliverOne(rpc, config, () => { throw new Error("No send expected"); }));
  assert.deepEqual(calls, ["mail_claim"]);
});
