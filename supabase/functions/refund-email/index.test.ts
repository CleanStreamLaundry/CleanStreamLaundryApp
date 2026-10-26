import assert from "node:assert/strict";
import { databaseRpc, type Rpc } from "../_shared/mail.ts";
import { refundNoticeHandler } from "./index.ts";

const project = "https://synthetic.invalid";
const env = (name: string) =>
  ({
    SUPABASE_URL: project,
    CLEANSTREAM_MAIL_PROJECT_URL: project,
    SUPABASE_ANON_KEY: "synthetic-public",
    CLEANSTREAM_MAIL_ENABLED: "false",
  } as Record<string, string>)[name];
const request = (
  body: unknown = { transaction_id: "41" },
  bearer = "Bearer captured-A",
) =>
  new Request(`${project}/refund-email`, {
    method: "POST",
    headers: { Authorization: bearer },
    body: JSON.stringify(body),
  });

function fixture(
  status = 200,
  result: unknown = { refund_id: "7", state: "queued" },
) {
  const calls: { req: Request; args: unknown }[] = [];
  const rpc = databaseRpc((name) => {
    assert(
      ![
        "SUPABASE_SERVICE_ROLE_KEY",
        "SUPABASE_SECRET_KEYS",
        "CLEANSTREAM_RESEND_API_KEY",
        "RESEND_API_KEY",
      ].includes(name),
    );
    return env(name);
  }, async (input, init) => {
    const req = new Request(input, init);
    calls.push({ req, args: await req.json() });
    assert.equal(
      req.url,
      `${project}/rest/v1/rpc/enqueue_refund_request_notice`,
    );
    return Response.json(result, { status });
  });
  return { calls, handler: refundNoticeHandler(env, rpc) };
}

Deno.test("refund adapter: caller-bound RPC only, no provider or privileged credentials", async () => {
  const f = fixture();
  const response = await f.handler(
    request({ transaction_id: "41", user_id: "forged", amount: 999 }),
  );
  assert.equal(response.status, 200);
  assert.equal((await response.json()).notificationSent, false);
  assert.equal(f.calls.length, 1);
  assert.equal(
    f.calls[0].req.headers.get("authorization"),
    "Bearer captured-A",
  );
  assert.equal(f.calls[0].req.headers.get("apikey"), "synthetic-public");
  assert.deepEqual(f.calls[0].args, { target_transaction_id: "41" });
  assert.equal(response.headers.get("cache-control"), "no-store");
});

Deno.test("refund adapter: recipient unset does not fail the saved claim", async () => {
  const f = fixture(200, { refund_id: "7", state: "recipient_unavailable" });
  const response = await f.handler(request());
  const result = await response.json();
  assert.equal(response.status, 200);
  assert.equal(result.claimRecorded, true);
  assert.equal(result.notificationSent, false);
  assert.match(result.notificationWarning, /claim is saved/);
});

Deno.test("refund adapter: captures bearer before reading body", async () => {
  const f = fixture();
  const req = request();
  const stream = req.body!;
  const reader = stream.getReader.bind(stream);
  stream.getReader = (() => {
    req.headers.set("Authorization", "Bearer replacement-B");
    return reader();
  }) as typeof stream.getReader;
  assert.equal((await f.handler(req)).status, 200);
  assert.equal(
    f.calls[0].req.headers.get("authorization"),
    "Bearer captured-A",
  );
});

for (const status of [400, 401, 403, 429, 500]) {
  Deno.test(`refund adapter: HTTP ${status} is sanitized, no automatic retry`, async () => {
    const f = fixture(status, { error: "private provider details" });
    const response = await f.handler(request());
    assert.equal(response.status, status === 500 ? 503 : status);
    assert(!JSON.stringify(await response.json()).includes("private provider"));
    assert.equal(f.calls.length, 1);
  });
}

Deno.test("refund adapter: method, missing bearer, bad JSON and body bounds fail before RPC", async () => {
  const f = fixture();
  assert.equal(
    (await f.handler(new Request(project, { method: "OPTIONS" }))).status,
    200,
  );
  assert.equal((await f.handler(new Request(project))).status, 405);
  assert.equal((await f.handler(request({}, "Basic bad"))).status, 401);
  for (
    const [body, status] of [["{broken", 400], ["x".repeat(8193), 413]] as const
  ) {
    assert.equal(
      (await f.handler(
        new Request(project, {
          method: "POST",
          headers: { Authorization: "Bearer captured-A" },
          body,
        }),
      )).status,
      status,
    );
  }
  assert.equal(f.calls.length, 0);
});

Deno.test("refund adapter: uncertain enqueue never returns a sent/claim acknowledgment", async () => {
  const rpc: Rpc = () => Promise.reject(new Error("private transport details"));
  const response = await refundNoticeHandler(env, rpc)(request());
  assert.equal(response.status, 503);
  const result = await response.json();
  assert.equal(result.error, "notification_unavailable");
  assert(!("claimRecorded" in result));
  assert.match(result.notificationWarning, /Do not submit another claim/);
});
