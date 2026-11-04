import assert from "node:assert/strict";
import {
  deliverOne,
  type MailConfig,
  type MailJob,
  renderMail,
  type Rpc,
} from "./mail.ts";

const config: MailConfig = {
  key: "re_synthetic",
  from: "notice@cleanstreamlaundry.com",
  replyTo: "support@cleanstreamlaundry.com",
  postal: "Synthetic postal address",
  publicUrl: "https://synthetic.invalid/functions/v1/newsletter",
  pageUrl: "https://cleanstreamlaundry.com/newsletter",
  tokenSecret: "x".repeat(43),
};
const job: MailJob = {
  id: "00000000-0000-4000-8000-000000000001",
  lease_id: "00000000-0000-4000-8000-000000000002",
  kind: "refund_request",
  email: "owner@example.invalid",
  consent_id: null,
  refund_notice: {
    refund_id: "7",
    transaction_id: "41",
    user_id: "00000000-0000-4000-8000-000000000003",
    amount: "25.00",
    description: '<script>alert("unsafe")</script> & reason',
  },
};

Deno.test("refund template: escaped server snapshot, branded HTML/text and non-action portal link", async () => {
  const rendered = await renderMail(job, config);
  assert.match(rendered.payload.subject, /loyalty balance credit request/);
  assert.match(rendered.payload.text, /Claim #7 for transaction #41/);
  assert.match(rendered.payload.text, /\$25.00/);
  assert.match(rendered.payload.html, /&lt;script&gt;/);
  assert(!rendered.payload.html.includes("<script>"));
  assert.match(rendered.payload.html, /<html lang="en"/);
  assert.match(rendered.payload.html, /role="presentation"/);
  assert.match(rendered.payload.html, /<h1/);
  assert.match(
    rendered.payload.html,
    /https:\/\/cleanstreamlaundry.com\/admin/,
  );
  assert(
    !/approveRefund|denyRefund|List-Unsubscribe|action=confirm/.test(
      JSON.stringify(rendered.payload),
    ),
  );
  assert.deepEqual(rendered.payload.to, [job.email]);
  assert.deepEqual(rendered.payload.headers, {});
  assert.equal(rendered.confirmHash, null);
  assert.equal(rendered.unsubscribeHash, null);
  assert.equal(
    rendered.payloadHash,
    (await renderMail(job, config)).payloadHash,
  );
});

Deno.test("refund template: missing or malformed server snapshot fails closed", async () => {
  for (
    const refund_notice of [
      undefined,
      { ...job.refund_notice!, amount: "NaN" },
      { ...job.refund_notice!, refund_id: "<bad>" },
      { ...job.refund_notice!, user_id: "forged" },
    ]
  ) {
    await assert.rejects(() => renderMail({ ...job, refund_notice }, config));
  }
});

Deno.test("refund template: existing account/newsletter kinds retain purpose and consent behavior", async () => {
  for (
    const [kind, subject] of [
      ["account_welcome", "Welcome to Clean Stream"],
      ["newsletter_confirm", "Confirm your Clean Stream newsletter request"],
      ["newsletter_welcome", "Welcome to the Clean Stream newsletter"],
    ] as const
  ) {
    const result = await renderMail({
      ...job,
      kind,
      consent_id: job.id,
      refund_notice: undefined,
    }, config);
    assert.equal(result.payload.subject, subject);
    assert(!result.payload.html.includes("Claim #"));
    assert.equal(
      "List-Unsubscribe" in result.payload.headers,
      kind !== "account_welcome",
    );
    assert.equal(result.confirmHash !== null, kind === "newsletter_confirm");
  }
});

for (
  const [status, expected] of [[200, "accepted"], [429, "rate_limited"], [
    500,
    "uncertain",
  ], [403, "failed"]] as const
) {
  Deno.test(`refund delivery: reuses existing attempt result ${expected}`, async () => {
    const calls: { name: string; args: unknown }[] = [];
    const rpc: Rpc = <T>(name: string, args?: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve(
        (name === "mail_claim"
          ? job
          : name === "mail_prepare"
          ? true
          : null) as T,
      );
    };
    let sends = 0;
    const result = await deliverOne(rpc, config, (input, init) => {
      sends++;
      const req = new Request(input, init);
      assert.equal(req.headers.get("Idempotency-Key"), `cleanstream/${job.id}`);
      return Promise.resolve(
        Response.json({ id: "synthetic-provider-id" }, { status }),
      );
    });
    assert.equal(result, expected);
    assert.equal(sends, 1);
    assert.deepEqual(calls.map((call) => call.name), [
      "mail_claim",
      "mail_prepare",
      "mail_finish",
    ]);
    assert.equal((calls[2].args as Record<string, unknown>).p_result, expected);
  });
}
