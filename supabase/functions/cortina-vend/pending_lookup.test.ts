import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CortinaDeps, HttpError, sha256 } from "../_shared/cortina.ts";
import { handleCortinaVend, handleStatus } from "./logic.ts";

const requestId = "00000000-0000-4000-8000-000000000007";
const sessionId = "00000000-0000-4000-8000-000000000008";
const input = { clientRequestId: requestId, machineId: 7 };
type Row = Record<string, unknown>;

async function fixture() {
  let row: Row | null = {
    id: sessionId, user_id: "owner", machine_id: 7,
    client_request_id: requestId, client_access_token_hash: await sha256(requestId),
    status: "paid", created_at: "2020-01-01T00:00:00Z",
    stripe_payment_intent_id: "pi_private", client_secret: "never-return",
  };
  let user: Row | null = { id: "owner", is_anonymous: false };
  let databaseError = false, databaseThrows = false, authThrows = false;
  let authError: { name: string; status: number; message: string } | null = null;
  let forbidden = 0;
  const verifiedTokens: string[] = [];
  const queries: Array<{ table: string; columns: string; filters: Row }> = [];
  const rejectSideEffect = () => { forbidden++; throw new Error("Forbidden side effect"); };
  const provider = new Proxy({}, { get: rejectSideEffect });
  const admin = {
    auth: { getUser(token: string) {
      verifiedTokens.push(token);
      if (authThrows) throw new Error("Sensitive auth details");
      if (authError) return Promise.resolve({ data: { user: null }, error: authError });
      return Promise.resolve(token === "original-bearer"
        ? { data: { user }, error: null }
        : { data: { user: null }, error: { name: "AuthApiError", status: 401, message: "invalid token" } });
    } },
    rpc: rejectSideEffect,
    from(table: string) {
      if (table !== "cortina_vend_sessions") return rejectSideEffect();
      const query = { table, columns: "", filters: {} as Row };
      queries.push(query);
      const execute = () => {
        if (databaseThrows) throw new Error("Sensitive database details");
        if (databaseError) return { data: null, error: { message: "multiple rows/internal details" } };
        if (!row || !Object.entries(query.filters).every(([key, value]) =>
          row![key] === (key === "client_request_id" ? String(value).toLowerCase() : value))) {
          return { data: null, error: null };
        }
        return { data: Object.fromEntries(query.columns.split(",").map((key) => [key.trim(), row![key.trim()]])), error: null };
      };
      const chain = {
        select(columns: string) { query.columns = columns; return chain; },
        eq(key: string, value: unknown) { query.filters[key] = value; return chain; },
        maybeSingle: async () => execute(), single: async () => execute(),
        update: rejectSideEffect, insert: rejectSideEffect, delete: rejectSideEffect,
        upsert: rejectSideEffect,
      };
      return chain;
    },
  };
  const deps = { admin, stripe: provider, fetcher: rejectSideEffect } as unknown as CortinaDeps;
  const request = (body: unknown = input, authorization: string | null = "Bearer original-bearer") => new Request(
    "https://fixture.invalid/cortina-vend/status", {
      method: "POST", headers: authorization === null ? {} : { authorization },
      body: JSON.stringify(body),
    },
  );
  return {
    deps, queries, verifiedTokens, request,
    run: (body: unknown = input, authorization: string | null = "Bearer original-bearer") =>
      handleCortinaVend(request(body, authorization), deps),
    setRow(value: Row | null) { row = value; },
    patchRow(value: Row) { row = { ...row, ...value }; },
    setUser(value: Row | null) { user = value; },
    failDatabase(throws = false) { databaseError = !throws; databaseThrows = throws; },
    failAuth() { authThrows = true; },
    returnAuthError(name: string, status: number) {
      authError = { name, status, message: "Sensitive auth details" };
    },
    assertNoEffects() { assertEquals(forbidden, 0); },
  };
}

async function denied(f: Awaited<ReturnType<typeof fixture>>, status: number, body: unknown = input,
  authorization: string | null = "Bearer original-bearer") {
  const error = await assertRejects(() => f.run(body, authorization), HttpError) as HttpError;
  assertEquals(error.status, status);
  f.assertNoEffects();
  return error;
}

Deno.test("owned request lookup returns only existing reference with all ownership predicates", async () => {
  const f = await fixture();
  const response = await f.run();
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { sessionId, accessToken: requestId });
  assertEquals(f.verifiedTokens, ["original-bearer"]);
  assertEquals(f.queries, [{
    table: "cortina_vend_sessions",
    columns: "id,user_id,machine_id,client_request_id,client_access_token_hash",
    filters: { user_id: "owner", machine_id: 7, client_request_id: requestId,
      client_access_token_hash: await sha256(requestId) },
  }]);
  f.assertNoEffects();
});

for (const header of [null, "", "Basic credentials", "Bearer", "Bearer sb_publishable_fixture", "Bearer sb_secret_fixture", "Bearer invalid"]) {
  Deno.test(`lookup denies missing or invalid human bearer: ${header}`, async () => {
    const f = await fixture();
    await denied(f, 401, input, header);
    assertEquals(f.queries, []);
  });
}

for (const user of [null, { id: "owner", is_anonymous: true }, { id: "owner" }, { id: "", is_anonymous: false }]) {
  Deno.test(`lookup denies unverified nonanonymous identity: ${JSON.stringify(user)}`, async () => {
    const f = await fixture(); f.setUser(user);
    await denied(f, 401);
    assertEquals(f.queries, []);
  });
}

Deno.test("auth transport failure is sanitized and does not read sessions", async () => {
  const f = await fixture(); f.failAuth();
  const error = await denied(f, 503);
  assertEquals(error.message, "Payment recovery unavailable");
  assertEquals(f.queries, []);
});

for (const [name, status, expected] of [
  ["AuthRetryableFetchError", 0, 503], ["AuthApiError", 0, 503],
  ["AuthApiError", 503, 503], ["AuthApiError", 429, 503], ["AuthApiError", 401, 401],
] as const) {
  Deno.test(`returned ${name}/${status} maps to sanitized ${expected}`, async () => {
    const f = await fixture(); f.returnAuthError(name, status);
    const error = await denied(f, expected);
    assertEquals(error.message, expected === 503 ? "Payment recovery unavailable" : "Sign in to recover this payment");
    assertEquals(f.queries, []);
  });
}

const invalidBodies: Row[] = [
  { clientRequestId: requestId }, { machineId: 7 },
  { ...input, clientRequestId: null }, { ...input, clientRequestId: "" },
  { ...input, clientRequestId: "invalid" }, { ...input, clientRequestId: ` ${requestId}` },
  { ...input, machineId: null }, { ...input, machineId: "7" },
  { ...input, machineId: 0 }, { ...input, machineId: -1 },
  { ...input, machineId: 1.5 }, { ...input, machineId: Number.MAX_SAFE_INTEGER + 1 },
  { ...input, sessionId: "" }, { ...input, sessionId: null },
  { ...input, accessToken: "" }, { ...input, accessToken: null },
  { ...input, sessionId, accessToken: requestId }, { ...input, userId: "another-owner" },
];
for (const [index, body] of invalidBodies.entries()) {
  Deno.test(`lookup rejects mixed/partial/invalid selector ${index + 1}`, async () => {
    const f = await fixture(); await denied(f, 400, body);
    assertEquals(f.queries, []);
    assertEquals(f.verifiedTokens, []);
  });
}

for (const mismatch of [null, { user_id: "other" }, { machine_id: 8 },
  { client_access_token_hash: "wrong" }, { client_request_id: "other" }]) {
  Deno.test(`lookup does not disclose missing or mismatched session: ${JSON.stringify(mismatch)}`, async () => {
    const f = await fixture();
    if (mismatch == null) f.setRow(null); else f.patchRow(mismatch);
    const error = await denied(f, 404);
    assertEquals(error.message, "Vend session not found");
    assertEquals(error.code, "session_not_found");
  });
}

for (const throws of [false, true]) {
  Deno.test(`lookup database error or ambiguity is unavailable: throws=${throws}`, async () => {
    const f = await fixture(); f.failDatabase(throws);
    const error = await denied(f, 503);
    assertEquals(error.message, "Payment recovery unavailable");
  });
}

Deno.test("lookup refuses a malformed saved reference", async () => {
  const f = await fixture(); f.patchRow({ id: null });
  await denied(f, 503);
});

for (const status of ["payment_pending", "paid", "starting", "support_required", "refunded", "started"]) {
  Deno.test(`lookup of old ${status} session never enters timeout or compensation`, async () => {
    const f = await fixture(); f.patchRow({ status });
    assertEquals(await (await f.run()).json(), { sessionId, accessToken: requestId });
    assertEquals(f.queries.length, 1);
    f.assertNoEffects();
  });
}

Deno.test("lookup captures original bearer before asynchronous body consumption", async () => {
  const f = await fixture();
  let send!: ReadableStreamDefaultController<Uint8Array>;
  const request = new Request("https://fixture.invalid/cortina-vend/status", {
    method: "POST", headers: { authorization: "Bearer original-bearer" },
    body: new ReadableStream<Uint8Array>({ start(controller) { send = controller; } }),
  });
  const response = handleStatus(request, f.deps);
  request.headers.set("authorization", "Bearer changed-bearer");
  send.enqueue(new TextEncoder().encode(JSON.stringify(input))); send.close();
  assertEquals(await (await response).json(), { sessionId, accessToken: requestId });
  assertEquals(f.verifiedTokens, ["original-bearer"]);
  f.assertNoEffects();
});

Deno.test("original bound-reference status remains available without owner lookup", async () => {
  const f = await fixture(); f.patchRow({ status: "started" });
  const response = await f.run({ sessionId, accessToken: requestId }, null);
  assertEquals((await response.json()).status, "started");
  assertEquals(f.verifiedTokens, []);
  assertEquals(f.queries.length, 2);
  f.assertNoEffects();
});

Deno.test("UUID lookup normalizes database identity but preserves exact capability hash", async () => {
  const f = await fixture();
  const upper = "ABCDEF00-0000-4000-8000-000000000007";
  f.patchRow({ client_request_id: upper.toLowerCase(), client_access_token_hash: await sha256(upper) });
  assertEquals(await (await f.run({ ...input, clientRequestId: upper })).json(), {
    sessionId, accessToken: upper,
  });
  await denied(f, 404, { ...input, clientRequestId: upper.toLowerCase() });
  f.assertNoEffects();
});
