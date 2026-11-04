import assert from "node:assert/strict";
import { databaseRpc, MailError } from "./mail.ts";

const project = "https://mail.example.invalid";
const selected = "sb_publishable_synthetic_mail";
const legacy = "synthetic-legacy-public";
const values = (): Record<string, string | undefined> => ({
  SUPABASE_URL: project,
  CLEANSTREAM_MAIL_PROJECT_URL: project,
  CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME: "mail-component",
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
    "mail-component": selected,
    default: "sb_publishable_synthetic_other",
  }),
  SUPABASE_ANON_KEY: legacy,
  CLEANSTREAM_MAIL_SECRET_KEY_NAME: "mail-service",
  SUPABASE_SECRET_KEYS: JSON.stringify({
    "mail-service": "sb_secret_synthetic_mail",
  }),
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-legacy-service",
});

function unavailable(error: unknown): boolean {
  assert(error instanceof MailError);
  assert.equal(error.status, 503);
  assert.equal(error.message, "mail_unavailable");
  return true;
}

for (
  const name of [
    "newsletter_status",
    "newsletter_request",
    "newsletter_withdraw",
    "enqueue_refund_request_notice",
  ]
) {
  Deno.test(`mail public keys: ${name} retains caller and selects exact public entry`, async () => {
    const config = values();
    let calls = 0;
    const rpc = databaseRpc((key) => {
      assert(
        ![
          "SUPABASE_ANON_KEY",
          "CLEANSTREAM_MAIL_SECRET_KEY_NAME",
          "SUPABASE_SECRET_KEYS",
          "SUPABASE_SERVICE_ROLE_KEY",
        ].includes(key),
      );
      return config[key];
    }, (input, init) => {
      calls++;
      const request = new Request(input, init);
      assert.equal(request.url, `${project}/rest/v1/rpc/${name}`);
      assert.equal(request.method, "POST");
      assert.equal(request.headers.get("apikey"), selected);
      assert.equal(request.headers.get("authorization"), "Bearer caller-A");
      assert.equal(request.headers.get("content-type"), "application/json");
      assert.equal(
        init?.body,
        JSON.stringify({ selector: "untrusted-default" }),
      );
      assert(init?.signal instanceof AbortSignal);
      assert.equal(init.signal.aborted, false);
      return Promise.resolve(Response.json({ state: "synthetic" }));
    });
    assert.deepEqual(
      await rpc(name, { selector: "untrusted-default" }, "Bearer caller-A"),
      { state: "synthetic" },
    );
    assert.equal(calls, 1);
  });
}

for (
  const name of [
    "",
    " ",
    " mail-component",
    "mail-component\n",
    "absent",
    "toString",
  ]
) {
  Deno.test(`mail public keys: explicit selector ${JSON.stringify(name)} fails before HTTP`, async () => {
    const config = values();
    config.CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME = name;
    let calls = 0;
    const rpc = databaseRpc((key) => {
      assert.notEqual(key, "SUPABASE_ANON_KEY");
      return config[key];
    }, () => {
      calls++;
      return Promise.resolve(Response.json(null));
    });
    await assert.rejects(
      () => rpc("newsletter_status", {}, "Bearer A"),
      unavailable,
    );
    assert.equal(calls, 0);
  });
}

for (
  const dictionary of [
    undefined,
    "{broken",
    "null",
    "[]",
    JSON.stringify({ default: selected }),
    JSON.stringify({ "mail-component": null }),
    JSON.stringify({ "mail-component": { key: selected } }),
    JSON.stringify({ "mail-component": "sb_secret_synthetic_mail" }),
    JSON.stringify({ "mail-component": legacy }),
    JSON.stringify({ "mail-component": "sb_publishable_" }),
    JSON.stringify({ "mail-component": `${selected}\n` }),
  ]
) {
  Deno.test("mail public keys: malformed or wrong-kind entry cannot fall back", async () => {
    const config = values();
    config.SUPABASE_PUBLISHABLE_KEYS = dictionary;
    let calls = 0;
    const rpc = databaseRpc((key) => {
      assert.notEqual(key, "SUPABASE_ANON_KEY");
      return config[key];
    }, () => {
      calls++;
      return Promise.resolve(Response.json(null));
    });
    await assert.rejects(
      () => rpc("newsletter_status", {}, "Bearer A"),
      unavailable,
    );
    assert.equal(calls, 0);
  });
}

Deno.test("mail public keys: absent selector preserves legacy without reading dictionaries", async () => {
  const config = values();
  delete config.CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME;
  const rpc = databaseRpc((key) => {
    assert(
      !["SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_SECRET_KEYS"].includes(key),
    );
    return config[key];
  }, (input, init) => {
    const request = new Request(input, init);
    assert.equal(request.headers.get("apikey"), legacy);
    assert.equal(request.headers.get("authorization"), "Bearer caller-A");
    return Promise.resolve(Response.json(null));
  });
  await rpc("newsletter_status", {}, "Bearer caller-A");
});

for (const name of ["mail_claim", "mail_record_webhook", "newsletter_token"]) {
  Deno.test(`mail public keys: ${name} ignores public configuration without a caller`, async () => {
    const config = values();
    config.CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME = "";
    config.SUPABASE_PUBLISHABLE_KEYS = "{broken";
    const requests: Request[] = [];
    const rpc = databaseRpc((key) => {
      assert(
        ![
          "CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME",
          "SUPABASE_PUBLISHABLE_KEYS",
          "SUPABASE_ANON_KEY",
        ].includes(key),
      );
      return config[key];
    }, (input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(Response.json(null));
    });
    await rpc(name);
    delete config.CLEANSTREAM_MAIL_SECRET_KEY_NAME;
    await rpc(name);
    assert.equal(requests.length, 2);
    assert.equal(requests[0].headers.get("apikey"), "sb_secret_synthetic_mail");
    assert.equal(requests[0].headers.get("authorization"), null);
    assert.equal(requests[1].headers.get("apikey"), "synthetic-legacy-service");
    assert.equal(
      requests[1].headers.get("authorization"),
      "Bearer synthetic-legacy-service",
    );
  });
}

Deno.test("mail public keys: overlapping callers retain exact bearer through reversed completion", async () => {
  const config = values();
  const requests: Request[] = [];
  const completions: Array<(value: Response) => void> = [];
  const rpc = databaseRpc((key) => config[key], (input, init) => {
    requests.push(new Request(input, init));
    return new Promise<Response>((resolve) => completions.push(resolve));
  });
  const first = rpc("newsletter_status", {}, "Bearer caller-A");
  const second = rpc("newsletter_withdraw", {}, "Bearer caller-B");
  completions[1](Response.json({ caller: "B" }));
  completions[0](Response.json({ caller: "A" }));
  assert.deepEqual(await first, { caller: "A" });
  assert.deepEqual(await second, { caller: "B" });
  assert.deepEqual(
    requests.map((request) => request.headers.get("authorization")),
    [
      "Bearer caller-A",
      "Bearer caller-B",
    ],
  );
  assert(
    requests.every((request) => request.headers.get("apikey") === selected),
  );
});

Deno.test("mail public keys: removal fails closed on next call; only explicit unset restores legacy", async () => {
  const config = values();
  const requests: Request[] = [];
  const rpc = databaseRpc((key) => config[key], (input, init) => {
    requests.push(new Request(input, init));
    return Promise.resolve(Response.json(null));
  });
  await rpc("newsletter_status", {}, "Bearer A");
  config.SUPABASE_PUBLISHABLE_KEYS = JSON.stringify({ default: selected });
  await assert.rejects(
    () => rpc("newsletter_status", {}, "Bearer A"),
    unavailable,
  );
  assert.equal(requests.length, 1);
  delete config.CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME;
  await rpc("newsletter_status", {}, "Bearer A");
  assert.equal(requests[1].headers.get("apikey"), legacy);
  assert.equal(requests[1].headers.get("authorization"), "Bearer A");
});

for (const status of [401, 403, 500]) {
  Deno.test(`mail public keys: HTTP ${status} never retries with legacy or secret credentials`, async () => {
    const config = values();
    let calls = 0;
    const rpc = databaseRpc((key) => config[key], () => {
      calls++;
      return Promise.resolve(new Response("private details", { status }));
    });
    await assert.rejects(
      () => rpc("newsletter_status", {}, "Bearer A"),
      (error: unknown) => {
        assert(error instanceof MailError);
        assert.equal(error.status, status === 500 ? 503 : status);
        assert.equal(error.message, "mail_request_failed");
        return true;
      },
    );
    assert.equal(calls, 1);
  });
}

for (const mismatch of [undefined, "https://other.example.invalid"]) {
  Deno.test("mail public keys: project binding remains required before HTTP", async () => {
    const config = values();
    config.CLEANSTREAM_MAIL_PROJECT_URL = mismatch;
    let calls = 0;
    const rpc = databaseRpc((key) => config[key], () => {
      calls++;
      return Promise.resolve(Response.json(null));
    });
    await assert.rejects(
      () => rpc("newsletter_status", {}, "Bearer A"),
      unavailable,
    );
    assert.equal(calls, 0);
  });
}
