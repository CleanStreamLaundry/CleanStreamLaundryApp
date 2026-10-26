import assert from "node:assert/strict";
import { handler } from "./index.ts";

const selected = "sb_secret_synthetic_cleanup";
const legacy = "synthetic-legacy-service-key";
const worker = "synthetic-cleanup-worker-secret-at-least-32-characters";
const values = (): Record<string, string | undefined> => ({
  ACCOUNT_CLEANUP_ENABLED: "true",
  ACCOUNT_CLEANUP_WORKER_SECRET: worker,
  SUPABASE_URL: "https://cleanup.synthetic.invalid/",
  SUPABASE_SERVICE_ROLE_KEY: legacy,
  CLEANSTREAM_CLEANUP_SECRET_KEY_NAME: "cleanup-only",
  SUPABASE_SECRET_KEYS: JSON.stringify({
    default: "sb_secret_wrong_component",
    "cleanup-only": selected,
  }),
});
const request = (
  body: unknown = { action: "preview", limit: 25, after_user_id: null },
  secret = worker,
) =>
  new Request("https://cleanup.synthetic.invalid/account-cleanup", {
    method: "POST",
    headers: {
      "X-Account-Cleanup-Secret": secret,
      Authorization: "Bearer unrelated-caller",
    },
    body: JSON.stringify(body),
  });

async function fixture(
  config: Record<string, string | undefined>,
  action: (calls: Request[], reads: string[]) => Promise<void>,
) {
  const originalEnv = Deno.env.get, originalFetch = globalThis.fetch;
  const calls: Request[] = [], reads: string[] = [];
  try {
    // Never inspect or modify real process secrets in these offline tests.
    Deno.env.get = (name) => {
      reads.push(name);
      return config[name];
    };
    globalThis.fetch = (input, init) => {
      calls.push(new Request(input, init));
      return Promise.resolve(
        Response.json({
          execution_enabled: false,
          candidates: [],
          next_cursor: null,
        }),
      );
    };
    await action(calls, reads);
  } finally {
    Deno.env.get = originalEnv;
    globalThis.fetch = originalFetch;
  }
}

Deno.test("cleanup selector: exact named key supplies apikey only to preview", () =>
  fixture(values(), async (calls) => {
    const response = await handler(request());
    assert.equal(response.status, 200);
    assert.equal(calls.length, 1);
    assert.equal(
      calls[0].url,
      "https://cleanup.synthetic.invalid/rest/v1/rpc/preview_account_cleanup",
    );
    assert.equal(calls[0].method, "POST");
    assert.equal(calls[0].headers.get("apikey"), selected);
    assert.equal(calls[0].headers.has("Authorization"), false);
    assert.deepEqual(await calls[0].json(), {
      p_limit: 25,
      p_after_user_id: null,
    });
    const body = await response.text();
    for (const secret of [selected, legacy, worker]) {
      assert.equal(body.includes(secret), false);
    }
  }));

Deno.test("cleanup selector: absent name retains legacy service key without selecting default", () => {
  const config = values();
  delete config.CLEANSTREAM_CLEANUP_SECRET_KEY_NAME;
  return fixture(config, async (calls) => {
    assert.equal((await handler(request())).status, 200);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].headers.get("apikey"), legacy);
    assert.equal(calls[0].headers.get("Authorization"), `Bearer ${legacy}`);
  });
});

for (
  const name of ["", " cleanup-only", "cleanup-only ", "missing", "toString"]
) {
  Deno.test(`cleanup selector: explicit ${JSON.stringify(name)} never falls back`, () =>
    fixture({
      ...values(),
      CLEANSTREAM_CLEANUP_SECRET_KEY_NAME: name,
    }, async (calls) => {
      const response = await handler(request());
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: "cleanup_preview_unavailable",
        automatic_retry: false,
      });
      assert.equal(calls.length, 0);
    }));
}
for (
  const ring of [
    undefined,
    "{broken",
    "null",
    "[]",
    '"string"',
    "42",
    '{"cleanup-only":null}',
    '{"cleanup-only":5}',
    '{"cleanup-only":{"key":"sb_secret_wrong"}}',
    '{"cleanup-only":"sb_publishable_wrong"}',
    '{"cleanup-only":""}',
    '{"cleanup-only":" sb_secret_wrong"}',
    '{"default":"sb_secret_wrong"}',
  ]
) {
  Deno.test(`cleanup selector: invalid named secret map ${JSON.stringify(ring)} fails closed`, () =>
    fixture({
      ...values(),
      SUPABASE_SECRET_KEYS: ring,
    }, async (calls) => {
      assert.equal((await handler(request())).status, 503);
      assert.equal(calls.length, 0);
    }));
}
Deno.test("cleanup selector: no name and missing legacy key cannot use a named default", () => {
  const config = values();
  delete config.CLEANSTREAM_CLEANUP_SECRET_KEY_NAME;
  delete config.SUPABASE_SERVICE_ROLE_KEY;
  return fixture(config, async (calls) => {
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
});
Deno.test("cleanup selector: disabled preview never resolves credentials", () =>
  fixture({
    ...values(),
    ACCOUNT_CLEANUP_ENABLED: "false",
  }, async (calls, reads) => {
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
    assert.equal(reads.includes("CLEANSTREAM_CLEANUP_SECRET_KEY_NAME"), false);
    assert.equal(reads.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
  }));
Deno.test("cleanup selector: failed worker authentication never resolves credentials", () =>
  fixture(values(), async (calls, reads) => {
    assert.equal(
      (await handler(request(undefined, "wrong-worker-secret"))).status,
      401,
    );
    assert.equal(calls.length, 0);
    assert.equal(reads.includes("CLEANSTREAM_CLEANUP_SECRET_KEY_NAME"), false);
  }));
for (const name of ["cleanup-only", "missing"]) {
  Deno.test(`cleanup selector: run stays policy-blocked before key selection ${name}`, () =>
    fixture({
      ...values(),
      CLEANSTREAM_CLEANUP_SECRET_KEY_NAME: name,
    }, async (calls, reads) => {
      const response = await handler(request({ action: "run" }));
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: "cleanup_policy_unapproved",
        execution_enabled: false,
      });
      assert.equal(calls.length, 0);
      assert.equal(
        reads.includes("CLEANSTREAM_CLEANUP_SECRET_KEY_NAME"),
        false,
      );
    }));
}
for (const action of ["claim", "retry", "purge"]) {
  Deno.test(`cleanup selector: ${action} remains unsupported without any RPC`, () =>
    fixture(values(), async (calls) => {
      assert.equal((await handler(request({ action }))).status, 400);
      assert.equal(calls.length, 0);
    }));
}
