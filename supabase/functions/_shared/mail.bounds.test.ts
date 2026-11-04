import assert from "node:assert/strict";
import {
  deliverOne,
  type MailConfig,
  MailError,
  type MailJob,
  readBounded,
  renderMail,
  type Rpc,
  verifyWebhook,
} from "./mail.ts";
import { webhookHandler } from "../mail-webhook/index.ts";
import { newsletterHandler } from "../newsletter/index.ts";

const encoder = new TextEncoder();
const endpoint = "https://fixture.example.invalid/functions/v1/mail-webhook";
const now = 1_800_000_000_000;
const secret = `whsec_${btoa("synthetic-independent-signing-key")}`;

function bodyRequest(body: BodyInit) {
  return new Request(endpoint, { method: "POST", body });
}

Deno.test("raw body preserves leading UTF-8 BOM for byte-for-byte signature input", async () => {
  const wire = new Uint8Array([0xef, 0xbb, 0xbf, 0x7b, 0x7d]);
  const raw = await readBounded(bodyRequest(wire), wire.length);
  assert.equal(raw, "\uFEFF{}");
  assert.deepEqual(encoder.encode(raw), wire);
});

Deno.test("newsletter rejects BOM-prefixed JSON without a database call", async () => {
  let calls = 0;
  const rpc: Rpc = <T>() => {
    calls++;
    return Promise.resolve(null as T);
  };
  const response = await newsletterHandler(() => undefined, rpc)(
    bodyRequest(encoder.encode('\uFEFF{"action":"status"}')),
  );
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_body" });
  assert.equal(calls, 0);
});

Deno.test("independent bounds: exact UTF-8 byte limit succeeds, one byte less rejects", async () => {
  const bytes = encoder.encode("\u00e9\u00e9");
  assert.equal(await readBounded(bodyRequest(bytes), 4), "\u00e9\u00e9");
  await assert.rejects(
    () => readBounded(bodyRequest(bytes), 3),
    (error: unknown) => error instanceof MailError && error.status === 413,
  );
});

Deno.test("independent bounds: streamed overflow cancels the reader", async () => {
  let canceled = false;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array([65, 66]));
      controller.enqueue(new Uint8Array([67, 68]));
    },
    cancel() {
      canceled = true;
    },
  });
  await assert.rejects(
    () => readBounded(bodyRequest(body), 3),
    (error: unknown) => error instanceof MailError && error.status === 413,
  );
  assert.equal(canceled, true);
  assert.equal(body.locked, false);
});

Deno.test("independent bounds: split multibyte UTF-8 survives chunk boundaries", async () => {
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array([0xc3]));
      controller.enqueue(new Uint8Array([0xa9]));
      controller.close();
    },
  });
  assert.equal(await readBounded(bodyRequest(body), 2), "\u00e9");
});

Deno.test("independent bounds: truncated UTF-8 returns a nonretryable client error", async () => {
  await assert.rejects(
    () => readBounded(bodyRequest(new Uint8Array([0xc3])), 2),
    (error: unknown) =>
      error instanceof MailError && error.status === 400 &&
      error.message === "invalid_body",
  );
});

async function signedRequest(raw: string, wire = encoder.encode(raw)) {
  const id = "independent-event", timestamp = String(now / 1000);
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode("synthetic-independent-signing-key"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(`${id}.${timestamp}.${raw}`),
    ),
  );
  return new Request(endpoint, {
    method: "POST",
    body: wire,
    headers: {
      "svix-id": id,
      "svix-timestamp": timestamp,
      "svix-signature": `v1,${btoa(String.fromCharCode(...signature))}`,
    },
  });
}

Deno.test("signed BOM-prefixed body verifies unchanged then fails JSON parsing", async () => {
  const raw = '\uFEFF{"type":"email.sent"}';
  const request = await signedRequest(raw);
  await verifyWebhook(raw, request.headers, secret, now);
  let calls = 0;
  const rpc: Rpc = <T>() => {
    calls++;
    return Promise.resolve(null as T);
  };
  const response = await webhookHandler(
    (name) => name === "CLEANSTREAM_RESEND_WEBHOOK_SECRET" ? secret : undefined,
    rpc,
    () => now,
  )(request);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "event_invalid" });
  assert.equal(calls, 0);
});

for (const prependBom of [false, true]) {
  Deno.test(`independent raw signature: unsigned BOM prefix=${prependBom}`, async () => {
    const raw = JSON.stringify({
      type: "email.delivered",
      data: { email_id: "fixture-provider", to: ["fixture@example.invalid"] },
    });
    const calls: string[] = [];
    const rpc: Rpc = <T>(name: string) => {
      calls.push(name);
      return Promise.resolve(null as T);
    };
    const wire = prependBom
      ? new Uint8Array([0xef, 0xbb, 0xbf, ...encoder.encode(raw)])
      : encoder.encode(raw);
    const response = await webhookHandler(
      (name) =>
        name === "CLEANSTREAM_RESEND_WEBHOOK_SECRET" ? secret : undefined,
      rpc,
      () => now,
    )(await signedRequest(raw, wire));
    assert.equal(response.status, prependBom ? 400 : 200);
    assert.deepEqual(calls, prependBom ? [] : ["mail_record_webhook"]);
  });
}

Deno.test("independent delivery: a refused changed-payload prepare never resets or dispatches", async () => {
  const job: MailJob = {
    id: "00000000-0000-4000-8000-000000000001",
    lease_id: "00000000-0000-4000-8000-000000000002",
    kind: "newsletter_confirm",
    email: "fixture@example.invalid",
    consent_id: "00000000-0000-4000-8000-000000000003",
  };
  const config: MailConfig = {
    key: "re_synthetic",
    from: "news@cleanstreamlaundry.com",
    replyTo: "support@cleanstreamlaundry.com",
    postal: "SYNTHETIC ONLY",
    publicUrl: "https://fixture.example.invalid/functions/v1/newsletter",
    pageUrl: "https://www.cleanstreamlaundry.com/newsletter",
    tokenSecret: "x".repeat(64),
  };
  const original = await renderMail(job, config);
  const changedConfig = { ...config, postal: "CHANGED SYNTHETIC CONTENT" };
  const changed = await renderMail(job, changedConfig);
  assert.notEqual(changed.payloadHash, original.payloadHash);
  const calls: string[] = [];
  const rpc: Rpc = <T>(name: string, args?: Record<string, unknown>) => {
    calls.push(name);
    if (name === "mail_claim") return Promise.resolve(job as T);
    assert.equal(name, "mail_prepare");
    assert.equal(args?.p_payload_hash, changed.payloadHash);
    assert.equal(args?.p_id, job.id);
    return Promise.resolve(false as T);
  };
  let sends = 0;
  const result = await deliverOne(rpc, changedConfig, () => {
    sends++;
    throw new Error("Provider transport must not be called");
  });
  assert.equal(result, "skipped");
  assert.equal(sends, 0);
  assert.deepEqual(calls, ["mail_claim", "mail_prepare"]);
});
