import assert from "node:assert/strict";
import {
  databaseRpc,
  deliverOne,
  Env,
  mailConfig,
  MailError,
  MailJob,
  renderMail,
  Rpc,
  sha256,
  token,
  verifyWebhook,
} from "./mail.ts";
import { newsletterHandler } from "../newsletter/index.ts";
import { deliveryHandler } from "../mail-delivery/index.ts";
import { webhookHandler } from "../mail-webhook/index.ts";

const values: Record<string, string> = {
  CLEANSTREAM_MAIL_ENABLED: "true",
  CLEANSTREAM_RESEND_API_KEY: "re_fake_local_only",
  CLEANSTREAM_MAIL_FROM: "news@updates.cleanstreamlaundry.com",
  CLEANSTREAM_MAIL_VERIFIED_FROM: "news@updates.cleanstreamlaundry.com",
  CLEANSTREAM_MAIL_REPLY_TO: "support@cleanstreamlaundry.com",
  CLEANSTREAM_MAIL_CONTENT_APPROVED: "true",
  CLEANSTREAM_MAIL_POSTAL_ADDRESS: "TEST ONLY - NOT APPROVED POSTAL ADDRESS",
  CLEANSTREAM_NEWSLETTER_URL:
    "https://project.example.test/functions/v1/newsletter",
  CLEANSTREAM_MAIL_PROJECT_URL: "https://project.example.test",
  SUPABASE_URL: "https://project.example.test",
  CLEANSTREAM_MAIL_TOKEN_SECRET: "x".repeat(64),
  CLEANSTREAM_MAIL_WORKER_SECRET: "w".repeat(48),
  CLEANSTREAM_MAIL_CORS_ORIGINS:
    "https://app.example.test,https://www.cleanstreamlaundry.com",
  CLEANSTREAM_NEWSLETTER_PAGE_URL:
    "https://www.cleanstreamlaundry.com/newsletter",
  CLEANSTREAM_MAIL_LINKS_APPROVED: "true",
  CLEANSTREAM_RESEND_WEBHOOK_SECRET: "whsec_plJ3nmyCDGBKInavdOK15jsl",
  SUPABASE_ANON_KEY: "fake-public",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service",
};
const env: Env = (name) => values[name];
const config = mailConfig(env)!;

Deno.test("newsletter frontend must be owned, approved and CORS allowlisted", async () => {
  for (
    const url of [
      "https://gundex.io/newsletter",
      "https://www.cleanstreamlaundry.com.evil.test/newsletter",
      "https://www.cleanstreamlaundry.com/newsletter?redirect=evil",
      "https://www.cleanstreamlaundry.com/newsletter#existing",
      "http://www.cleanstreamlaundry.com/newsletter",
    ]
  ) {
    assert.equal(
      mailConfig((n) => n === "CLEANSTREAM_NEWSLETTER_PAGE_URL" ? url : env(n)),
      null,
    );
  }
  assert.equal(
    mailConfig((n) => n === "CLEANSTREAM_MAIL_CORS_ORIGINS" ? "" : env(n)),
    null,
  );
  const f = fake();
  const response = await newsletterHandler(
    (n) => n === "CLEANSTREAM_MAIL_LINKS_APPROVED" ? "false" : env(n),
    f.rpc,
  )(
    new Request(
      `https://project.example.test/functions/v1/newsletter?action=confirm&token=${
        "e".repeat(64)
      }`,
    ),
  );
  assert.equal(response.status, 503);
  assert.equal(f.calls.length, 0);
});

Deno.test("human links use frontend fragments while one-click uses backend POST", async () => {
  const { payload } = await renderMail(job, config);
  assert.ok(payload.text.includes(`${config.pageUrl}#action=confirm&token=`));
  assert.ok(
    payload.text.includes(`${config.pageUrl}#action=unsubscribe&token=`),
  );
  assert.ok(
    payload.headers["List-Unsubscribe"].startsWith(
      `<${config.publicUrl}?action=unsubscribe&token=`,
    ),
  );
});

Deno.test("settings withdrawal uses caller bearer and refuses subject override", async () => {
  const f = fake({ newsletter_withdraw: { state: "unsubscribed" } });
  const handler = newsletterHandler(env, f.rpc);
  assert.equal(
    (await handler(
      request({ action: "withdraw" }, { Authorization: "Bearer caller" }),
    )).status,
    200,
  );
  assert.equal(f.calls[0].name, "newsletter_withdraw");
  assert.equal(f.calls[0].bearer, "Bearer caller");
  assert.deepEqual(f.calls[0].args, {});
  assert.equal(
    (await handler(
      request({ action: "withdraw", user_id: "other" }, {
        Authorization: "Bearer caller",
      }),
    )).status,
    400,
  );
  assert.equal(f.calls.length, 1);
});

Deno.test("signed malformed event and empty provider id fail closed", async () => {
  const f = fake(), handler = webhookHandler(env, f.rpc);
  for (
    const event of [null, [], {
      type: "email.sent",
      data: { email_id: "", to: [job.email] },
    }]
  ) {
    assert.equal((await handler(await signedRequest(event))).status, 400);
  }
  assert.equal(f.calls.length, 0);
});
const job: MailJob = {
  id: "00000000-0000-4000-8000-000000000001",
  lease_id: "00000000-0000-4000-8000-000000000002",
  kind: "newsletter_confirm",
  email: "recipient@example.test",
  consent_id: "00000000-0000-4000-8000-000000000003",
};
const request = (body: unknown, headers: Record<string, string> = {}) =>
  new Request("https://project.example.test/functions/v1/newsletter", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
const fake = (responses: Record<string, unknown> = {}) => {
  const calls: {
    name: string;
    args: Record<string, unknown>;
    bearer?: string;
  }[] = [];
  const rpc: Rpc = <T>(
    name: string,
    args: Record<string, unknown> = {},
    bearer?: string,
  ) => {
    calls.push({ name, args, bearer });
    return Promise.resolve(responses[name] as T);
  };
  return { rpc, calls };
};
const http = (response: Response | Error) => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const transport: typeof fetch = (input, init) => {
    calls.push({ url: String(input), init });
    return response instanceof Error
      ? Promise.reject(response)
      : Promise.resolve(response);
  };
  return { transport, calls };
};

Deno.test("runtime default disabled without reading shared Resend credentials", () => {
  assert.equal(mailConfig(() => undefined), null);
  assert.equal(
    mailConfig((n) => n === "RESEND_API_KEY" ? "re_do_not_use" : undefined),
    null,
  );
});
for (
  const name of [
    "CLEANSTREAM_MAIL_ENABLED",
    "CLEANSTREAM_RESEND_API_KEY",
    "CLEANSTREAM_MAIL_FROM",
    "CLEANSTREAM_MAIL_VERIFIED_FROM",
    "CLEANSTREAM_MAIL_REPLY_TO",
    "CLEANSTREAM_MAIL_CONTENT_APPROVED",
    "CLEANSTREAM_NEWSLETTER_URL",
    "CLEANSTREAM_NEWSLETTER_PAGE_URL",
    "CLEANSTREAM_MAIL_LINKS_APPROVED",
    "CLEANSTREAM_MAIL_PROJECT_URL",
    "CLEANSTREAM_MAIL_TOKEN_SECRET",
  ]
) {
  Deno.test(`configuration fail closed without ${name}`, () => {
    assert.equal(mailConfig((n) => n === name ? undefined : env(n)), null);
  });
}
for (
  const sender of [
    "hello@gundex.io",
    "hello@cleanstreamlaundry.com.attacker.test",
    "X <news@updates.cleanstreamlaundry.com>",
    "news@resend.dev",
  ]
) {
  Deno.test(`reject unauthorized sender ${sender}`, () => {
    assert.equal(
      mailConfig((n) =>
        ["CLEANSTREAM_MAIL_FROM", "CLEANSTREAM_MAIL_VERIFIED_FROM"].includes(n)
          ? sender
          : env(n)
      ),
      null,
    );
  });
}
Deno.test("capabilities deterministic purpose separated and hashes distinct from raw tokens", async () => {
  const a = await token(config.tokenSecret, "confirm", job.consent_id!);
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.equal(a, await token(config.tokenSecret, "confirm", job.consent_id!));
  assert.notEqual(
    a,
    await token(config.tokenSecret, "unsubscribe", job.consent_id!),
  );
  assert.notEqual(a, await sha256(a));
});
for (
  const kind of [
    "account_welcome",
    "newsletter_confirm",
    "newsletter_welcome",
  ] as const
) {
  Deno.test(`template ${kind}: purpose and headers`, async () => {
    const { payload, confirmHash, unsubscribeHash } = await renderMail({
      ...job,
      kind,
    }, config);
    assert.match(payload.html, /<html lang="en">/);
    assert.match(payload.html, /name="viewport"/);
    assert.match(payload.html, /<table role="presentation"/);
    assert.equal((payload.html.match(/<h1\b/g) || []).length, 1);
    assert.match(payload.html, /max-width:600px/);
    assert.match(payload.html, /overflow-wrap:anywhere/);
    assert.match(payload.html, /background-color:#2073A9;color:#FFFFFF/);
    assert.match(payload.html, /border-top:4px solid #F3C404/);
    assert.match(payload.html, /href="mailto:/);
    assert.doesNotMatch(payload.html, /<script|<img|<link|@import/i);
    assert.ok(payload.text);
    assert.equal(payload.to.length, 1);
    assert.equal(payload.tags[0].value, job.id);
    assert.equal(payload.reply_to, config.replyTo);
    if (kind === "account_welcome") {
      assert.match(payload.text, /does not subscribe/);
      assert.equal(payload.headers["List-Unsubscribe"], undefined);
      assert.equal(confirmHash, null);
      assert.equal(unsubscribeHash, null);
      assert.doesNotMatch(payload.text, /offers|discount|promotion/i);
      assert.doesNotMatch(
        payload.html,
        /Unsubscribe|Confirm newsletter subscription/,
      );
    } else {
      assert.equal(
        payload.headers["List-Unsubscribe-Post"],
        "List-Unsubscribe=One-Click",
      );
      assert.match(payload.text, /Unsubscribe:/);
      assert.ok(payload.text.includes(config.postal));
      assert.match(unsubscribeHash!, /^[0-9a-f]{64}$/);
      assert.equal(Boolean(confirmHash), kind === "newsletter_confirm");
      assert.match(payload.html, />Unsubscribe from the newsletter<\/a>/);
      assert.doesNotMatch(payload.html, />https:\/\//);
      assert.equal(
        payload.html.includes(">Confirm newsletter subscription</a>"),
        kind === "newsletter_confirm",
      );
    }
  });
}
Deno.test("template escapes contact/postal HTML", async () => {
  const { payload } = await renderMail(job, {
    ...config,
    postal: '<script>alert("bad")</script>',
  });
  assert.doesNotMatch(payload.html, /<script>/);
  assert.match(payload.html, /&lt;script&gt;/);
});
for (
  const kind of [
    "account_welcome",
    "newsletter_confirm",
    "newsletter_welcome",
  ] as const
) {
  Deno.test(`template ${kind}: retries keep identical payload and token hashes`, async () => {
    const first = await renderMail({ ...job, kind }, config);
    const retry = await renderMail(
      { ...job, kind, lease_id: "new-lease" },
      config,
    );
    assert.deepEqual(retry, first);
    assert.equal(
      first.payloadHash,
      await sha256(JSON.stringify(first.payload)),
    );
  });
}
Deno.test("template treats URL-like postal content as text, not extra links", async () => {
  const { payload } = await renderMail(job, {
    ...config,
    postal: 'Test address\nhttps://example.test/?x=" onclick="bad',
  });
  assert.doesNotMatch(payload.html, /href="https:\/\/example\.test/);
  assert.match(payload.html, /Test address<br>https:/);
  assert.doesNotMatch(payload.html, / onclick="bad/);
});
for (
  const [status, result] of [
    [200, "accepted"],
    [429, "rate_limited"],
    [500, "uncertain"],
    [503, "uncertain"],
    [409, "uncertain"],
    [400, "failed"],
    [401, "failed"],
    [403, "failed"],
    [422, "failed"],
  ] as const
) {
  Deno.test(`provider HTTP ${status} => ${result}, one dispatch only`, async () => {
    const f = fake({ mail_claim: job, mail_prepare: true }),
      h = http(Response.json({ id: "provider-id" }, { status }));
    assert.equal(await deliverOne(f.rpc, config, h.transport), result);
    assert.equal(h.calls.length, 1);
    assert.equal(h.calls[0].url, "https://api.resend.com/emails");
    assert.equal(
      new Headers(h.calls[0].init?.headers).get("Idempotency-Key"),
      `cleanstream/${job.id}`,
    );
    assert.equal(f.calls[2].args.p_result, result);
    assert.equal(
      f.calls[2].args.p_provider_id,
      result === "accepted" ? "provider-id" : null,
    );
    assert.equal(
      f.calls[1].args.p_confirm_hash,
      (await renderMail(job, config)).confirmHash,
    );
  });
}
for (
  const response of [
    new Error("timeout"),
    Response.json({}),
    new Response("malformed", { status: 200 }),
  ]
) {
  Deno.test("ambiguous provider result quarantined without replay", async () => {
    const f = fake({ mail_claim: job, mail_prepare: true }), h = http(response);
    assert.equal(await deliverOne(f.rpc, config, h.transport), "uncertain");
    assert.equal(h.calls.length, 1);
  });
}
for (
  const [claimed, prepared, result] of [[null, false, "idle"], [
    job,
    false,
    "skipped",
  ]] as const
) {
  Deno.test(`worker ${result} does not send`, async () => {
    const f = fake({ mail_claim: claimed, mail_prepare: prepared }),
      h = http(new Error("must not send"));
    assert.equal(await deliverOne(f.rpc, config, h.transport), result);
    assert.equal(h.calls.length, 0);
  });
}
Deno.test("database ack lost after accepted send never retries provider or business action", async () => {
  const f = fake({ mail_claim: job, mail_prepare: true }),
    h = http(Response.json({ id: "provider-id" }));
  const rpc: Rpc = (name, args, bearer) =>
    name === "mail_finish"
      ? Promise.reject(new Error("lost ack"))
      : f.rpc(name, args, bearer);
  await assert.rejects(() => deliverOne(rpc, config, h.transport));
  assert.equal(h.calls.length, 1);
  assert.deepEqual(f.calls.map((c) => c.name), ["mail_claim", "mail_prepare"]);
});
Deno.test("delivery worker rejects missing/wrong secrets before DB/provider", async () => {
  const f = fake(),
    h = http(new Error("must not send")),
    handler = deliveryHandler(env, f.rpc, h.transport);
  for (const authorization of ["", "Bearer wrong", "Bearer fake-service"]) {
    assert.equal(
      (await handler(request({}, { Authorization: authorization }))).status,
      401,
    );
  }
  assert.equal(f.calls.length, 0);
  assert.equal(h.calls.length, 0);
});
Deno.test("valid worker secret with disabled runtime never claims", async () => {
  const f = fake(), h = http(new Error("must not send"));
  const response = await deliveryHandler(
    (n) => n === "CLEANSTREAM_MAIL_ENABLED" ? "false" : env(n),
    f.rpc,
    h.transport,
  )(request({}, {
    Authorization: `Bearer ${values.CLEANSTREAM_MAIL_WORKER_SECRET}`,
  }));
  assert.equal(response.status, 503);
  assert.equal(f.calls.length, 0);
});
Deno.test("worker endpoint runs actual adapter with fake Resend", async () => {
  const f = fake({ mail_claim: job, mail_prepare: true }),
    h = http(Response.json({ id: "provider-id" }));
  const response = await deliveryHandler(env, f.rpc, h.transport)(
    request({}, {
      Authorization: `Bearer ${values.CLEANSTREAM_MAIL_WORKER_SECRET}`,
    }),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { state: "accepted" });
  assert.equal(h.calls.length, 1);
});
Deno.test("newsletter request binds exact bearer and refuses body subject", async () => {
  const f = fake({ newsletter_request: { state: "pending" } }),
    handler = newsletterHandler(env, f.rpc);
  const body = {
    action: "request",
    opt_in: true,
    version: "newsletter-v1",
    source: "signup",
  };
  assert.equal((await handler(request(body))).status, 401);
  assert.equal(
    (await handler(
      request({ ...body, user_id: "other" }, {
        Authorization: "Bearer caller-A",
      }),
    )).status,
    400,
  );
  assert.equal(
    (await handler(request(body, { Authorization: "Bearer caller-A" }))).status,
    200,
  );
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].bearer, "Bearer caller-A");
  assert.equal(f.calls[0].args.p_opt_in, true);
});
for (
  const bad of [null, [], {}, {
    action: "request",
    opt_in: "true",
    version: "newsletter-v1",
    source: "signup",
  }, {
    action: "request",
    opt_in: true,
    version: "newsletter-v1",
    source: "terms",
  }]
) {
  Deno.test(`reject malformed consent ${JSON.stringify(bad)}`, async () => {
    const f = fake();
    assert.equal(
      (await newsletterHandler(env, f.rpc)(
        request(bad, { Authorization: "Bearer A" }),
      )).status,
      400,
    );
    assert.equal(f.calls.length, 0);
  });
}
Deno.test("unchecked request remains explicit false, works while runtime disabled", async () => {
  const f = fake({ newsletter_request: { state: "not_subscribed" } });
  const response = await newsletterHandler(
    (n) => n === "CLEANSTREAM_MAIL_ENABLED" ? "false" : env(n),
    f.rpc,
  )(request({
    action: "request",
    opt_in: false,
    version: "newsletter-v1",
    source: "signup",
  }, { Authorization: "Bearer A" }));
  assert.equal(response.status, 200);
  assert.equal(f.calls[0].args.p_opt_in, false);
});
Deno.test("status uses caller, no worker privilege", async () => {
  const f = fake({ newsletter_status: { state: "not_subscribed" } });
  assert.equal(
    (await newsletterHandler(env, f.rpc)(
      request({ action: "status" }, { Authorization: "Bearer A" }),
    )).status,
    200,
  );
  assert.equal(f.calls[0].bearer, "Bearer A");
  assert.deepEqual(f.calls[0].args, {});
});
for (const action of ["confirm", "unsubscribe"]) {
  Deno.test(`no-login ${action} only passes token hash to SQL`, async () => {
    const f = fake({
        newsletter_token: {
          state: action === "confirm" ? "subscribed" : "unsubscribed",
        },
      }),
      raw = "e".repeat(64);
    const response = await newsletterHandler(env, f.rpc)(
      request({ action, token: raw }),
    );
    assert.equal(response.status, 200);
    assert.equal(f.calls[0].args.p_hash, await sha256(raw));
    assert.equal(f.calls[0].bearer, undefined);
    assert.ok(!JSON.stringify(f.calls).includes(raw));
    assert.equal(response.headers.get("cache-control"), "no-store");
  });
}
Deno.test("GET redirects scanner safely to approved frontend; one-click works without login", async () => {
  const f = fake({ newsletter_token: { state: "unsubscribed" } }),
    handler = newsletterHandler(env, f.rpc),
    url =
      `https://project.example.test/functions/v1/newsletter?action=unsubscribe&token=${
        "e".repeat(64)
      }`;
  const get = await handler(new Request(url));
  assert.equal(get.status, 303);
  assert.equal(f.calls.length, 0);
  assert.equal(
    get.headers.get("location"),
    `${config.pageUrl}#action=unsubscribe&token=${"e".repeat(64)}`,
  );
  assert.equal(get.headers.get("referrer-policy"), "no-referrer");
  const post = await handler(
    new Request(url, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        Origin: "https://project.example.test",
      },
      body: "List-Unsubscribe=One-Click",
    }),
  );
  assert.equal(post.status, 200);
  assert.equal(f.calls[0].args.p_action, "unsubscribe");
});
for (
  const [action, body] of [
    ["confirm", "List-Unsubscribe=One-Click"],
    ["unsubscribe", "List-Unsubscribe=One-Click&action=confirm"],
    ["confirm", `action=confirm&token=${"e".repeat(64)}`],
    ["unsubscribe", "List-Unsubscribe=invalid"],
  ]
) {
  Deno.test(`one-click form refuses non-withdrawal contract: ${action}, ${body}`, async () => {
    const f = fake();
    const response = await newsletterHandler(env, f.rpc)(
      new Request(
        `https://project.example.test/functions/v1/newsletter?action=${action}&token=${
          "e".repeat(64)
        }`,
        {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body,
        },
      ),
    );
    assert.equal(response.status, 400);
    assert.equal(f.calls.length, 0);
  });
}
Deno.test("one-click unsubscribe remains available with sending disabled", async () => {
  const f = fake({ newsletter_token: { state: "unsubscribed" } });
  const response = await newsletterHandler(
    (n) => n === "CLEANSTREAM_MAIL_ENABLED" ? "false" : env(n),
    f.rpc,
  )(
    new Request(
      `${config.publicUrl}?action=unsubscribe&token=${"e".repeat(64)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "List-Unsubscribe=One-Click",
      },
    ),
  );
  assert.equal(response.status, 200);
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].args.p_action, "unsubscribe");
});
for (const endpoint of ["newsletter", "mail-webhook"]) {
  Deno.test(`${endpoint}: invalid UTF-8 is a client error without a database call`, async () => {
    const f = fake();
    const handler = endpoint === "newsletter"
      ? newsletterHandler(env, f.rpc)
      : webhookHandler(env, f.rpc);
    const response = await handler(
      new Request(`https://project.example.test/functions/v1/${endpoint}`, {
        method: "POST",
        body: new Uint8Array([0xc3, 0x28]),
      }),
    );
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_body" });
    assert.equal(f.calls.length, 0);
  });
}
Deno.test("CORS allowlist and body-size boundary", async () => {
  const f = fake(), handler = newsletterHandler(env, f.rpc);
  assert.equal(
    (await handler(request({}, { Origin: "https://evil.test" }))).status,
    403,
  );
  assert.equal((await handler(request("x".repeat(3000)))).status, 413);
  const pre = await handler(
    new Request("https://project.example.test", {
      method: "OPTIONS",
      headers: { Origin: "https://app.example.test" },
    }),
  );
  assert.equal(pre.status, 200);
  assert.equal(
    pre.headers.get("Access-Control-Allow-Origin"),
    "https://app.example.test",
  );
  assert.equal(f.calls.length, 0);
});
Deno.test("RPC adapter uses caller/public key, service only for internal actions; no retry", async () => {
  const h = http(Response.json({ state: "pending" })),
    rpc = databaseRpc(env, h.transport);
  await rpc("newsletter_request", { p_opt_in: true }, "Bearer exact-user");
  assert.equal(
    new Headers(h.calls[0].init?.headers).get("authorization"),
    "Bearer exact-user",
  );
  assert.equal(
    new Headers(h.calls[0].init?.headers).get("apikey"),
    "fake-public",
  );
  const service = http(Response.json(null));
  await databaseRpc(env, service.transport)("mail_claim");
  assert.equal(
    new Headers(service.calls[0].init?.headers).get("authorization"),
    "Bearer fake-service",
  );
  const bad = http(new Response("sensitive database details", { status: 500 }));
  await assert.rejects(
    () => databaseRpc(env, bad.transport)("newsletter_status", {}, "Bearer A"),
    (error) =>
      error instanceof MailError && error.status === 503 &&
      !error.message.includes("sensitive"),
  );
  assert.equal(bad.calls.length, 1);
});

const vector = {
  raw: '{"event_type":"ping","data":{"success":true}}',
  id: "msg_loFOjxBNrRLzqYUf",
  timestamp: "1731705121",
  signature: "v1,rAvfW3dJ/X/qxhsaXPOyyCGmRKsaKWcsNccKXlIktD0=",
};
const vectorHeaders = () =>
  new Headers({
    "svix-id": vector.id,
    "svix-timestamp": vector.timestamp,
    "svix-signature": vector.signature,
  });
Deno.test("official Svix signature test vector and multi-signature rotation", async () => {
  const headers = vectorHeaders();
  await verifyWebhook(
    vector.raw,
    headers,
    values.CLEANSTREAM_RESEND_WEBHOOK_SECRET,
    Number(vector.timestamp) * 1000,
  );
  headers.set("svix-signature", `v1,invalid v2,ignored ${vector.signature}`);
  await verifyWebhook(
    vector.raw,
    headers,
    values.CLEANSTREAM_RESEND_WEBHOOK_SECRET,
    Number(vector.timestamp) * 1000,
  );
});
for (
  const mutation of ["body", "id", "timestamp", "signature", "old", "future"]
) {
  Deno.test(`signed raw-body rejects ${mutation} tampering/replay`, async () => {
    const headers = vectorHeaders();
    let raw = vector.raw, now = Number(vector.timestamp) * 1000;
    if (mutation === "body") raw += " ";
    if (mutation === "id") headers.set("svix-id", "other");
    if (mutation === "timestamp") {
      headers.set("svix-timestamp", String(Number(vector.timestamp) + 1));
    }
    if (mutation === "signature") headers.set("svix-signature", "v1,bad");
    if (mutation === "old") now += 301000;
    if (mutation === "future") now -= 301000;
    await assert.rejects(() =>
      verifyWebhook(raw, headers, values.CLEANSTREAM_RESEND_WEBHOOK_SECRET, now)
    );
  });
}
async function signedRequest(data: unknown) {
  const raw = JSON.stringify(data),
    timestamp = String(Math.floor(Date.now() / 1000)),
    id = "event-123";
  const bytes = Uint8Array.from(
    atob(values.CLEANSTREAM_RESEND_WEBHOOK_SECRET.slice(6)),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    bytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = btoa(
    String.fromCharCode(
      ...new Uint8Array(
        await crypto.subtle.sign(
          "HMAC",
          key,
          new TextEncoder().encode(`${id}.${timestamp}.${raw}`),
        ),
      ),
    ),
  );
  return new Request("https://project.example.test/functions/v1/mail-webhook", {
    method: "POST",
    body: raw,
    headers: {
      "svix-id": id,
      "svix-timestamp": timestamp,
      "svix-signature": `v1,${signature}`,
    },
  });
}
for (
  const type of [
    "email.sent",
    "email.delivered",
    "email.bounced",
    "email.complained",
    "email.failed",
    "email.suppressed",
  ]
) {
  Deno.test(`actual signed webhook adapter ${type}`, async () => {
    const f = fake(),
      response = await webhookHandler(env, f.rpc)(
        await signedRequest({
          type,
          data: {
            email_id: "provider-id",
            to: [job.email],
            tags: { outbox_id: job.id },
          },
        }),
      );
    assert.equal(response.status, 200);
    assert.equal(f.calls[0].name, "mail_record_webhook");
    assert.equal(f.calls[0].args.p_type, type);
    assert.equal(f.calls[0].args.p_outbox_id, job.id);
  });
}
Deno.test("unsigned webhook never reaches database", async () => {
  const f = fake();
  assert.equal(
    (await webhookHandler(env, f.rpc)(request({ type: "email.bounced" })))
      .status,
    400,
  );
  assert.equal(f.calls.length, 0);
});
Deno.test("signed malformed recipients rejected; non-mail events ignored", async () => {
  const f = fake(), handler = webhookHandler(env, f.rpc);
  assert.equal(
    (await handler(
      await signedRequest({
        type: "email.sent",
        data: { email_id: "id", to: ["a", "b"] },
      }),
    )).status,
    400,
  );
  assert.equal(
    (await handler(await signedRequest({ type: "email.opened", data: {} })))
      .status,
    200,
  );
  assert.equal(f.calls.length, 0);
});
Deno.test("signed webhook rejects non-string outbox tags without UUID coercion", async () => {
  const f = fake(), handler = webhookHandler(env, f.rpc);
  for (const value of [[job.id], {}, 123]) {
    for (const tags of [{ outbox_id: value }, [{ name: "outbox_id", value }]]) {
      const response = await handler(
        await signedRequest({
          type: "email.bounced",
          data: { email_id: "provider-id", to: [job.email], tags },
        }),
      );
      assert.equal(response.status, 400);
    }
  }
  assert.equal(f.calls.length, 0);
});
Deno.test("signed webhook preserves array tags and provider-ID-only reconciliation", async () => {
  const f = fake(), handler = webhookHandler(env, f.rpc);
  for (const tags of [[{ name: "outbox_id", value: job.id }], undefined]) {
    const response = await handler(
      await signedRequest({
        type: "email.complained",
        data: { email_id: "provider-id", to: [job.email], tags },
      }),
    );
    assert.equal(response.status, 200);
  }
  assert.equal(f.calls[0].args.p_outbox_id, job.id);
  assert.equal(f.calls[1].args.p_outbox_id, null);
});
Deno.test("unmatched reconciliation event returns retryable HTTP failure", async () => {
  const rpc: Rpc = () =>
    Promise.reject(new MailError(503, "mail_request_failed"));
  assert.equal(
    (await webhookHandler(env, rpc)(
      await signedRequest({
        type: "email.sent",
        data: { email_id: "id", to: [job.email], tags: { outbox_id: job.id } },
      }),
    )).status,
    503,
  );
});

const postalJobs: MailJob[] = [
  { ...job, kind: "account_welcome", consent_id: null },
  { ...job, kind: "refund_request", consent_id: null, refund_notice: {
    refund_id: "7", transaction_id: "41", user_id: job.id,
    amount: "25.00", description: "<stored> & reason",
  } },
  ...(["account_deletion_scheduled", "account_restored"] as const).map((kind) => ({
    ...job, kind, consent_id: null,
    lifecycle_requested_at: "2026-10-01T12:30:45.123456+00:00",
    lifecycle_restore_until: "2026-10-31T12:30:45.123456+00:00",
    lifecycle_restored_at: kind === "account_restored"
      ? "2026-10-02T10:20:30.654321+00:00" : null,
  })),
  { ...job, kind: "credit_decision", consent_id: null, credit_notice: {
    refund_id: "12", transaction_id: "44", status: "approved",
    amount_cents: 250, note: "<stored> & staff note",
  } },
  job,
  { ...job, kind: "newsletter_welcome" },
];
const postalEnv = (postal: string | undefined): Env => (name) =>
  name === "CLEANSTREAM_MAIL_POSTAL_ADDRESS" ? postal : env(name);

Deno.test("postal split: legacy empty and named RPC argument bodies remain exact", async () => {
  for (const args of [undefined, { p_include_newsletter: true }, { p_include_newsletter: false }, { p_include_newsletter: null }]) {
    const h = http(Response.json(null));
    await databaseRpc(env, h.transport)("mail_claim", args);
    assert.equal(h.calls.length, 1);
    assert.equal(h.calls[0].init?.body, JSON.stringify(args || {}));
  }
});

for (const postal of [undefined, "", " \t\r\n "]) {
  Deno.test(`postal split: absent/blank ${JSON.stringify(postal)} permits only transactional delivery`, async () => {
    const current = mailConfig(postalEnv(postal));
    assert.ok(current);
    assert.equal(current.postal, postal || "");
    for (const item of postalJobs) {
      const f = fake({ mail_claim: item, mail_prepare: true });
      const h = http(Response.json({ id: "synthetic-provider" }));
      if (item.kind.startsWith("newsletter")) {
        await assert.rejects(() => renderMail(item, current),
          (error) => error instanceof MailError && error.status === 503 && error.message === "mail_disabled");
        // A defective RPC must not bypass the renderer's independent guard.
        await assert.rejects(() => deliverOne(f.rpc, current, h.transport));
        assert.deepEqual(f.calls.map((c) => c.name), ["mail_claim"]);
        assert.equal(h.calls.length, 0);
      } else {
        assert.deepEqual(await renderMail(item, current), await renderMail(item, config));
        assert.equal(await deliverOne(f.rpc, current, h.transport), "accepted");
        assert.deepEqual(f.calls.map((c) => c.name), ["mail_claim", "mail_prepare", "mail_finish"]);
        assert.equal(h.calls.length, 1);
      }
      assert.deepEqual(f.calls[0].args, { p_include_newsletter: false });
    }
  });
}
Deno.test("postal split: oversized postal still invalidates config", () => {
  assert.equal(mailConfig(postalEnv("x".repeat(501))), null);
});

for (const postal of [undefined, "", " \n ", " TEST ONLY\n  POSTAL & <address> \n"]) {
  Deno.test(`postal split: real worker + RPC filter ${JSON.stringify(postal)}`, async () => {
    const currentEnv = postalEnv(postal);
    const h = http(Response.json(null));
    const provider = http(Response.json({ id: "must-not-send" }));
    const handler = deliveryHandler(currentEnv, databaseRpc(currentEnv, h.transport), provider.transport);
    const send = (authorization: string) => handler(new Request(
      "https://project.example.test/functions/v1/mail-delivery", {
        method: "POST", headers: { Authorization: authorization },
      }));
    assert.equal((await send("Bearer user-session")).status, 401);
    assert.equal(h.calls.length, 0);
    const response = await send(`Bearer ${values.CLEANSTREAM_MAIL_WORKER_SECRET}`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { state: "idle" });
    assert.equal(h.calls.length, 1);
    assert.equal(h.calls[0].url, `${values.SUPABASE_URL}/rest/v1/rpc/mail_claim`);
    assert.deepEqual(JSON.parse(String(h.calls[0].init?.body)), { p_include_newsletter: Boolean(postal?.trim()) });
    assert.equal(new Headers(h.calls[0].init?.headers).get("apikey"), "fake-service");
    assert.equal(new Headers(h.calls[0].init?.headers).get("authorization"), "Bearer fake-service");
    assert.equal(provider.calls.length, 0);
  });
}

for (const runtime of ["complete", "missing", "blank", "other-guard"] as const) {
  const currentEnv: Env = (name) => runtime === "other-guard" && name === "CLEANSTREAM_RESEND_API_KEY"
    ? undefined : runtime === "missing" ? postalEnv(undefined)(name)
    : runtime === "blank" ? postalEnv(" \n ")(name) : env(name);
  for (const enabled of [false, true]) {
    for (const action of ["status", "withdraw", "false-request", "true-request"]) {
      Deno.test(`postal split: HTTP ${runtime}/${enabled}/${action}`, async () => {
        const rpcName = action.endsWith("request") ? "newsletter_request" : `newsletter_${action}`;
        const status = { enabled, state: "not_subscribed", version: "newsletter-v1" };
        const f = fake({ [rpcName]: status });
        const body = action.endsWith("request")
          ? { action: "request", opt_in: action === "true-request", version: "newsletter-v1", source: "settings" }
          : { action };
        const response = await newsletterHandler(currentEnv, f.rpc)(request(body, { Authorization: "Bearer caller" }));
        if (action === "true-request" && runtime !== "complete") {
          assert.equal(response.status, 503);
          assert.deepEqual(await response.json(), { error: "mail_disabled" });
          assert.deepEqual(f.calls, []);
        } else {
          assert.equal(response.status, 200);
          assert.deepEqual(await response.json(), { ...status, enabled: enabled && runtime === "complete" });
          assert.deepEqual(f.calls, [{ name: rpcName, bearer: "Bearer caller", args: action.endsWith("request")
            ? { p_opt_in: action === "true-request", p_version: "newsletter-v1", p_source: "settings" } : {} }]);
        }
      });
    }
  }
  Deno.test(`postal split: ${runtime} preserves capability, withdrawal and scanner semantics`, async () => {
    const raw = "e".repeat(64);
    for (const action of ["confirm", "unsubscribe"]) {
      const result = { state: action === "confirm" ? "subscribed" : "unsubscribed" };
      const f = fake({ newsletter_token: result });
      const handler = newsletterHandler(currentEnv, f.rpc);
      const url = `${config.publicUrl}?action=${action}&token=${raw}`;
      const get = await handler(new Request(url));
      assert.equal(get.status, 303);
      assert.equal(get.headers.get("location"), `${config.pageUrl}#action=${action}&token=${raw}`);
      assert.equal(get.headers.get("referrer-policy"), "no-referrer");
      assert.deepEqual(f.calls, []);
      const response = await handler(request({ action, token: raw }));
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), result);
      assert.deepEqual(f.calls, [{ name: "newsletter_token", args: { p_action: action, p_hash: await sha256(raw) }, bearer: undefined }]);
      const form = await handler(new Request(url, { method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: "List-Unsubscribe=One-Click" }));
      assert.equal(form.status, action === "unsubscribe" ? 200 : 400);
      assert.equal(f.calls.length, action === "unsubscribe" ? 2 : 1);
      if (action === "unsubscribe") assert.deepEqual(f.calls[1], f.calls[0]);
      assert.equal((await handler(request({ action, token: "invalid" }))).status, 400);
      assert.equal(f.calls.length, action === "unsubscribe" ? 2 : 1);
    }
    const f = fake(), handler = newsletterHandler(currentEnv, f.rpc);
    assert.equal((await handler(request({ action: "withdraw" }))).status, 401);
    assert.equal((await handler(request({ action: "withdraw", user_id: "other" }, { Authorization: "Bearer caller" }))).status, 400);
    assert.deepEqual(f.calls, []);
  });
}
