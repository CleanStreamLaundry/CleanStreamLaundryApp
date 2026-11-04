import assert from "node:assert/strict";
import { databaseRpc, MailError } from "./mail.ts";
import { selectNamedSupabaseKey } from "./supabase_keys.ts";

const selected = "sb_secret_synthetic_mail_only";
const other = "sb_secret_synthetic_other";
const project = "https://mail.example.invalid";
const legacy = "synthetic-legacy-service";
const values = () => ({
  SUPABASE_URL: project,
  CLEANSTREAM_MAIL_PROJECT_URL: project,
  CLEANSTREAM_MAIL_SECRET_KEY_NAME: "mail-component",
  SUPABASE_SECRET_KEYS: JSON.stringify({
    "mail-component": selected,
    default: other,
  }),
  SUPABASE_SERVICE_ROLE_KEY: legacy,
  SUPABASE_ANON_KEY: "synthetic-public",
});

Deno.test("mail keys: exact named selection does not prefer default", () => {
  assert.equal(
    selectNamedSupabaseKey(
      "mail-component",
      values().SUPABASE_SECRET_KEYS,
      "secret",
    ),
    selected,
  );
  assert.equal(
    selectNamedSupabaseKey("default", values().SUPABASE_SECRET_KEYS, "secret"),
    other,
  );
  for (const name of ["mail\u0000component", "mail\u007fcomponent"]) {
    assert.equal(
      selectNamedSupabaseKey(
        name,
        JSON.stringify({ [name]: selected }),
        "secret",
      ),
      null,
    );
  }
});

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
  Deno.test(`mail keys: invalid or missing selector ${JSON.stringify(name)} fails closed`, () => {
    assert.equal(
      selectNamedSupabaseKey(name, values().SUPABASE_SECRET_KEYS, "secret"),
      null,
    );
  });
}

for (
  const serialized of [
    undefined,
    "{broken",
    "null",
    "[]",
    '"string"',
    "42",
    JSON.stringify({ default: selected }),
    JSON.stringify({ "mail-component": null }),
    JSON.stringify({ "mail-component": 123 }),
    JSON.stringify({ "mail-component": { key: selected } }),
    JSON.stringify({ "mail-component": "sb_publishable_synthetic" }),
    JSON.stringify({ "mail-component": legacy }),
    JSON.stringify({ "mail-component": "sb_secret_" }),
    JSON.stringify({ "mail-component": `${selected}\n` }),
    JSON.stringify({ "mail-component": ` ${selected}` }),
  ]
) {
  Deno.test("mail keys: malformed dictionary or wrong key shape fails closed before HTTP", async () => {
    const config: Record<string, string | undefined> = {
      ...values(),
      SUPABASE_SECRET_KEYS: serialized,
    };
    let calls = 0;
    const rpc = databaseRpc((name) => config[name], () => {
      calls++;
      return Promise.resolve(Response.json(null));
    });
    await assert.rejects(() => rpc("mail_claim"), (error: unknown) => {
      assert(error instanceof MailError);
      assert.equal(error.status, 503);
      assert.equal(error.message, "mail_unavailable");
      return true;
    });
    assert.equal(calls, 0);
  });
}

for (
  const rpcName of ["mail_claim", "mail_record_webhook", "newsletter_token"]
) {
  Deno.test(`mail keys: ${rpcName} uses named apikey without secret bearer`, async () => {
    const config: Record<string, string> = values();
    const reads: string[] = [];
    const requests: Request[] = [];
    const rpc = databaseRpc((name) => {
      reads.push(name);
      return config[name];
    }, (input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(Response.json({ state: "synthetic" }));
    });
    assert.deepEqual(await rpc(rpcName, { p_id: "synthetic-id" }), {
      state: "synthetic",
    });
    assert.equal(requests.length, 1);
    assert.equal(requests[0].url, `${project}/rest/v1/rpc/${rpcName}`);
    assert.equal(requests[0].headers.get("apikey"), selected);
    assert.equal(requests[0].headers.get("authorization"), null);
    assert.equal(requests[0].headers.get("content-type"), "application/json");
    assert.deepEqual(await requests[0].json(), { p_id: "synthetic-id" });
    assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
}

Deno.test("mail keys: absent selector preserves legacy key and bearer without reading dictionary", async () => {
  const config: Record<string, string> = values();
  delete config.CLEANSTREAM_MAIL_SECRET_KEY_NAME;
  const rpc = databaseRpc((name) => {
    assert.notEqual(name, "SUPABASE_SECRET_KEYS");
    return config[name];
  }, (input, init) => {
    const request = new Request(input, init);
    assert.equal(request.headers.get("apikey"), legacy);
    assert.equal(request.headers.get("authorization"), `Bearer ${legacy}`);
    return Promise.resolve(Response.json(null));
  });
  await rpc("mail_claim");
});

Deno.test("mail keys: explicitly empty selector cannot silently restore legacy mode", async () => {
  const config: Record<string, string> = {
    ...values(),
    CLEANSTREAM_MAIL_SECRET_KEY_NAME: "",
  };
  let sends = 0;
  const rpc = databaseRpc((name) => config[name], () => {
    sends++;
    return Promise.resolve(Response.json(null));
  });
  await assert.rejects(() => rpc("mail_claim"), MailError);
  assert.equal(sends, 0);
});

Deno.test("mail keys: user RPC keeps exact bearer/public key despite unavailable named secret", async () => {
  const config: Record<string, string> = {
    ...values(),
    SUPABASE_SECRET_KEYS: "{broken",
  };
  const headers: Headers[] = [];
  const rpc = databaseRpc((name) => {
    assert(
      ![
        "SUPABASE_SECRET_KEYS",
        "SUPABASE_SERVICE_ROLE_KEY",
        "CLEANSTREAM_MAIL_SECRET_KEY_NAME",
      ].includes(name),
    );
    return config[name];
  }, (input, init) => {
    headers.push(new Request(input, init).headers);
    return Promise.resolve(Response.json(null));
  });
  await rpc("newsletter_status", {}, "Bearer caller-A");
  await rpc("newsletter_withdraw", {}, "Bearer caller-B");
  assert.deepEqual(headers.map((h) => h.get("authorization")), [
    "Bearer caller-A",
    "Bearer caller-B",
  ]);
  assert(headers.every((h) => h.get("apikey") === "synthetic-public"));
});

Deno.test("mail keys: dictionary removal fails closed on the next call, explicit unset allows rollback", async () => {
  const config: Record<string, string> = values();
  const headers: Headers[] = [];
  const rpc = databaseRpc((name) => config[name], (input, init) => {
    headers.push(new Request(input, init).headers);
    return Promise.resolve(Response.json(null));
  });
  await rpc("mail_claim");
  config.SUPABASE_SECRET_KEYS = JSON.stringify({ default: other });
  await assert.rejects(() => rpc("mail_claim"), MailError);
  assert.equal(headers.length, 1);
  delete config.CLEANSTREAM_MAIL_SECRET_KEY_NAME;
  await rpc("mail_claim");
  assert.equal(headers[1].get("apikey"), legacy);
  assert.equal(headers[1].get("authorization"), `Bearer ${legacy}`);
});

for (const status of [401, 403, 500]) {
  Deno.test(`mail keys: named HTTP ${status} never retries with legacy credentials`, async () => {
    const config: Record<string, string> = values();
    let sends = 0;
    const rpc = databaseRpc((name) => config[name], (input, init) => {
      sends++;
      assert.equal(new Request(input, init).headers.get("apikey"), selected);
      return Promise.resolve(
        new Response("provider details must not leak", { status }),
      );
    });
    await assert.rejects(() => rpc("mail_claim"), (error: unknown) => {
      assert(error instanceof MailError);
      assert.equal(error.status, status === 500 ? 503 : status);
      assert.equal(error.message, "mail_request_failed");
      return true;
    });
    assert.equal(sends, 1);
  });
}

Deno.test("mail keys: project mismatch blocks named credentials before transport", async () => {
  const config: Record<string, string> = {
    ...values(),
    CLEANSTREAM_MAIL_PROJECT_URL: "https://other.example.invalid",
  };
  let sends = 0;
  const rpc = databaseRpc((name) => config[name], () => {
    sends++;
    return Promise.resolve(Response.json(null));
  });
  await assert.rejects(() => rpc("mail_claim"), MailError);
  assert.equal(sends, 0);
});
