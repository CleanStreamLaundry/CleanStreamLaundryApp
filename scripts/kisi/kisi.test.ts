import { test } from "node:test";
import assert from "node:assert/strict";
import { KisiClient, KisiError, KISI_SANDBOX_KEY } from "../../supabase/functions/_shared/kisi.ts";
import type { KisiErrorKind, KisiOptions } from "../../supabase/functions/_shared/kisi.ts";
import { createKisiSandbox, startKisiSandbox } from "./sandbox.ts";

const fails = (kind: KisiErrorKind, status?: number) => (error: unknown) => {
  assert.ok(error instanceof KisiError);
  assert.equal(error.kind, kind);
  if (status !== undefined) assert.equal(error.status, status);
  return true;
};
function fixture() {
  const sandbox = createKisiSandbox();
  const fetcher: typeof fetch = async (url, init) => sandbox.handler(new Request(url, init));
  return { ...sandbox, client: new KisiClient({ environment: "local-sandbox", fetcher }) };
}

test("real loopback HTTP lists doors, simulates success, missing hardware and response loss", async () => {
  const server = await startKisiSandbox(0);
  try {
    const client = new KisiClient({ environment: "local-sandbox", port: server.port });
    assert.equal((await client.listPlaces()).items[0].id, 1);
    assert.equal((await client.listLocks(1)).items.length, 8);
    assert.deepEqual(await client.unlock(101), { outcome: "accepted" });
    assert.equal((await client.listLocks(1)).items[0].unlocked, true);
    await assert.rejects(client.unlock(102), fails("controller_unassigned", 409));
    await assert.rejects(client.unlock(108), fails("outcome_unknown"));
  } finally { await server.close(); }
});

test("pagination preserves all doors and the requested place", async () => {
  const { client } = fixture();
  const first = await client.listLocks(1, 0, 3);
  const second = await client.listLocks(1, first.nextOffset!, 3);
  const last = await client.listLocks(1, second.nextOffset!, 3);
  assert.deepEqual([...first.items, ...second.items, ...last.items].map(row => row.id),
    [101, 102, 103, 104, 105, 106, 107, 108]);
  assert.equal(last.nextOffset, null);
  assert.deepEqual(await client.listLocks(2), { items: [], nextOffset: null });
  assert.deepEqual(await client.listLocks(1, 99), { items: [], nextOffset: null });
});

for (const [id, kind, status] of [
  [102, "controller_unassigned", 409], [103, "outcome_unknown", 503],
  [104, "locked_down", 409], [105, "denied", 403],
  [106, "rate_limited", 429], [107, "outcome_unknown", 500], [999, "not_found", 404],
] as const) {
  test(`simulation ${id}: ${kind}, with no retry`, async () => {
    const { client, accepted, requests } = fixture();
    await assert.rejects(client.unlock(id), fails(kind, status));
    assert.deepEqual(accepted, []);
    assert.equal(requests.length, 1);
  });
}

test("response loss after acceptance stays unknown without replaying the side effect", async () => {
  const { client, accepted, requests } = fixture();
  await assert.rejects(client.unlock(108), fails("outcome_unknown"));
  assert.deepEqual(accepted, [108]);
  assert.equal(requests.length, 1);
});

test("rate limit exposes retry metadata without retrying", async () => {
  await assert.rejects(fixture().client.unlock(106), (error: unknown) => {
    assert.ok(error instanceof KisiError);
    assert.equal(error.retryAfterSeconds, 2);
    return true;
  });
});

test("hosted mode is read-only and uses the exact Kisi auth, URL and redirect policy", async () => {
  const calls: Request[] = [];
  const client = new KisiClient({ environment: "hosted", apiKey: "synthetic-hosted-test-key",
    fetcher: async (url, init) => {
      calls.push(new Request(url, init));
      return Response.json([{ id: 1, name: "Fixture" }]);
    },
  });
  await client.listPlaces();
  assert.equal(calls[0].url, "https://api.kisi.io/places?offset=0&limit=50");
  assert.equal(calls[0].headers.get("authorization"), "KISI-LOGIN synthetic-hosted-test-key");
  assert.equal(calls[0].headers.get("accept"), "application/json");
  assert.equal(calls[0].redirect, "manual");
  await assert.rejects(client.unlock(101), fails("unlock_disabled"));
  assert.equal(calls.length, 1);
  assert.equal(JSON.stringify(client).includes("synthetic-hosted-test-key"), false);
});

test("simulation sends only explicitly supplied location and proximity proof", async () => {
  const requests: Request[] = [];
  const client = new KisiClient({ environment: "local-sandbox", fetcher: async (url, init) => {
    requests.push(new Request(url, init)); return Response.json({ message: "Unlocked!" });
  } });
  await client.unlock(101);
  await client.unlock(101, { location: { latitude: 40.1, longitude: -85.6 }, proximityProof: "fixture-proof" });
  assert.deepEqual(await requests[0].json(), {});
  assert.equal(requests[1].method, "POST");
  assert.deepEqual(await requests[1].json(), {
    context: { location: { latitude: 40.1, longitude: -85.6 } }, lock: { proximity_proof: "fixture-proof" },
  });
});

test("invalid IDs, paging and coordinates never dispatch a request", async () => {
  const { client, requests } = fixture();
  for (const id of [0, -1, 1.2, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(client.unlock(id), fails("invalid_input"));
    await assert.rejects(client.listLocks(id), fails("invalid_input"));
  }
  await assert.rejects(client.listPlaces(20001), fails("invalid_input"));
  await assert.rejects(client.listPlaces(0, 251), fails("invalid_input"));
  await assert.rejects(client.unlock(101, { location: { latitude: 91, longitude: 0 } }), fails("invalid_input"));
  await assert.rejects(client.unlock(101, { proximityProof: " " }), fails("invalid_input"));
  assert.equal(requests.length, 0);
});

test("invalid modes/ports and synthetic hosted credentials are rejected", () => {
  for (const options of [
    { environment: "hosted", apiKey: "" }, { environment: "hosted", apiKey: "a\nb" },
    { environment: "hosted", apiKey: KISI_SANDBOX_KEY },
    { environment: "local-sandbox", port: 0 }, { environment: "local-sandbox", port: 65536 },
    { environment: "typo", apiKey: "key" },
  ]) assert.throws(() => new KisiClient(options as KisiOptions), fails("invalid_input"));
});

test("simulator rejects other credentials and unimplemented mutations; no browser CORS", async () => {
  const { handler } = createKisiSandbox();
  assert.equal((await handler(new Request("http://127.0.0.1/places"))).status, 401);
  assert.equal((await handler(new Request("http://127.0.0.1/places", {
    headers: { authorization: "KISI-LOGIN other-key" },
  }))).status, 401);
  const response = await handler(new Request("http://127.0.0.1/locks/101", {
    method: "DELETE", headers: { authorization: `KISI-LOGIN ${KISI_SANDBOX_KEY}` },
  }));
  assert.equal(response.status, 404);
  assert.equal(response.headers.has("access-control-allow-origin"), false);
});

for (const body of [null, {}, [], "Unlocked!", { message: "Queued" }]) {
  test(`unrecognized HTTP 200 body stays unknown: ${JSON.stringify(body)}`, async () => {
    const client = new KisiClient({ environment: "local-sandbox", fetcher: async () => Response.json(body) });
    await assert.rejects(client.unlock(101), fails("outcome_unknown", 200));
  });
}

test("redirect cannot forward credentials or become a successful unlock", async () => {
  let calls = 0;
  const client = new KisiClient({ environment: "local-sandbox", fetcher: async (_url, init) => {
    calls++;
    assert.equal(init?.redirect, "manual");
    return new Response(null, { status: 307, headers: { location: "https://example.invalid" } });
  } });
  await assert.rejects(client.unlock(101), fails("outcome_unknown", 307));
  assert.equal(calls, 1);
});

test("timeout aborts once; reads fail and unlock outcomes stay unknown", async () => {
  let calls = 0;
  const client = new KisiClient({ environment: "local-sandbox", timeoutMs: 15,
    fetcher: async (_url, init) => new Promise((_resolve, reject) => {
      calls++;
      init!.signal!.addEventListener("abort", () => reject(new Error("private details")), { once: true });
    }),
  });
  await assert.rejects(client.listPlaces(), fails("transport_error"));
  await assert.rejects(client.unlock(101), fails("outcome_unknown"));
  assert.equal(calls, 2);
});

test("bad JSON, invalid flags, cross-place data and truncated pages fail closed", async () => {
  const row = { id: 1, name: "Door", place_id: 1, configured: true, online: null, unlocked: false, locked_down: false };
  for (const [body, headers] of [
    ["not JSON", {}], [JSON.stringify({ locks: [row] }), {}],
    [JSON.stringify([{ ...row, configured: "true" }]), {}],
    [JSON.stringify([{ ...row, place_id: 2 }]), {}],
    [JSON.stringify([row]), { "X-Collection-Range": "0-49/80" }],
    [JSON.stringify([row]), { "X-Collection-Range": "invalid" }],
  ] as Array<[string, Record<string, string>]>) {
    const client = new KisiClient({ environment: "local-sandbox", fetcher: async () => new Response(body, { headers }) });
    await assert.rejects(client.listLocks(1), fails("invalid_response"));
  }
  const client = new KisiClient({ environment: "local-sandbox", fetcher: async () => Response.json([row]) });
  assert.equal((await client.listLocks(1)).items[0].online, null);
});

test("missing-controller text fallback does not misclassify unrelated conflicts", async () => {
  const client = (body: unknown) => new KisiClient({ environment: "local-sandbox",
    fetcher: async () => Response.json(body, { status: 409 }) });
  await assert.rejects(client({ error: "The door has no assigned Kisi controller." }).unlock(1), fails("controller_unassigned"));
  await assert.rejects(client({ error: "Other conflict" }).unlock(1), fails("conflict"));
});

test("errors hide provider bodies and honor HTTP authentication failures", async () => {
  const client = new KisiClient({ environment: "local-sandbox", fetcher: async () => Response.json({
    error: "sensitive-secret-and-email", code: "ff420a",
  }, { status: 401 }) });
  await assert.rejects(client.unlock(1), error => {
    assert.ok(error instanceof KisiError);
    assert.equal(error.kind, "unauthorized");
    assert.equal(`${error}${JSON.stringify(error)}`.includes("sensitive-secret-and-email"), false);
    return true;
  });
});
