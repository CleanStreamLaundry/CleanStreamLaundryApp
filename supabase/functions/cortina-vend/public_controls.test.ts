import assert from "node:assert/strict";
import { HttpError } from "../_shared/cortina.ts";
import {
  CORTINA_BODY_TIMEOUT_MS,
  cortinaPublicError,
  cortinaPublicResponse,
  cortinaSessionCredentials,
  MAX_CORTINA_BODY_BYTES,
  readCortinaBody,
} from "./public_controls.ts";

const sessionId = "00000000-0000-4000-8000-000000000001";
const accessToken = "ABCDEF00-0000-4000-8000-000000000002";
const request = (body: BodyInit | null, headers?: HeadersInit, signal?: AbortSignal) =>
  new Request("https://edge.synthetic.invalid/cortina-vend/status", { method: "POST", body, headers, signal });
const expectError = (status: number, code: string) => (error: unknown) => {
  assert(error instanceof HttpError);
  assert.equal(error.status, status);
  assert.equal(error.code, code);
  assert(!error.message.includes(accessToken));
  return true;
};
const encode = (text: string) => new TextEncoder().encode(text);

Deno.test("public body preserves exact capability and owned recovery fields", async () => {
  const body = { clientRequestId: accessToken, machineId: 7 };
  assert.deepEqual(await readCortinaBody(request(JSON.stringify(body))), body);
});

Deno.test("public body allows exactly 8 KiB without requiring a JSON content type", async () => {
  const value = "x".repeat(MAX_CORTINA_BODY_BYTES - 8);
  const body = JSON.stringify({ x: value });
  assert.equal(encode(body).length, MAX_CORTINA_BODY_BYTES);
  assert.deepEqual(await readCortinaBody(request(body)), { x: value });
});

Deno.test("oversized content length cancels without consuming a chunk", async () => {
  let pulls = 0, cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull() { pulls++; }, cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  await assert.rejects(() => readCortinaBody(request(stream, { "content-length": "8193" })), expectError(413, "body_too_large"));
  assert.equal(pulls, 0);
  assert(cancelled);
  assert(!stream.locked);
});

Deno.test("body limit measures actual bytes despite absent or false length", async () => {
  for (const headers of [undefined, { "content-length": "1" }, { "content-length": "not-a-number" }]) {
    await assert.rejects(() => readCortinaBody(request("x".repeat(8193), headers)), expectError(413, "body_too_large"));
  }
});

Deno.test("chunked body is bounded cumulatively and releases its reader", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({ start(controller) {
    controller.enqueue(new Uint8Array(4096));
    controller.enqueue(new Uint8Array(4097));
  }, cancel() { cancelled = true; } });
  await assert.rejects(() => readCortinaBody(request(stream)), expectError(413, "body_too_large"));
  assert(cancelled);
  assert(!stream.locked);
});

Deno.test("multibyte payload cannot bypass the byte limit", async () => {
  const body = JSON.stringify({ value: "\u00e9".repeat(4100) });
  assert(body.length < MAX_CORTINA_BODY_BYTES);
  await assert.rejects(() => readCortinaBody(request(body)), expectError(413, "body_too_large"));
});

Deno.test("malformed empty missing and invalid UTF-8 bodies have sanitized JSON errors", async () => {
  for (const body of [null, "", "{", accessToken, new Uint8Array([0xff])]) {
    await assert.rejects(() => readCortinaBody(request(body)), expectError(400, "invalid_json"));
  }
});

Deno.test("JSON arrays null and primitives preserve invalid-body errors", async () => {
  for (const body of ["[]", "null", "true", "1", JSON.stringify(accessToken)]) {
    await assert.rejects(() => readCortinaBody(request(body)), expectError(400, "invalid_body"));
  }
});

Deno.test("stream failure is sanitized and unlocks the reader", async () => {
  const stream = new ReadableStream<Uint8Array>({ start(controller) { controller.error(new Error(accessToken)); } });
  await assert.rejects(() => readCortinaBody(request(stream)), expectError(400, "invalid_json"));
  assert(!stream.locked);
});

Deno.test("stalled body hits one total deadline even when cancellation never resolves", async () => {
  const originalSet = globalThis.setTimeout, originalClear = globalThis.clearTimeout;
  let fire: (() => void) | undefined, cleared = false, cancelled = false;
  globalThis.setTimeout = ((callback: () => void, ms: number) => {
    assert.equal(ms, CORTINA_BODY_TIMEOUT_MS);
    assert.equal(fire, undefined);
    fire = callback;
    return 123;
  }) as typeof setTimeout;
  globalThis.clearTimeout = ((id: number | undefined) => { assert.equal(id, 123); cleared = true; }) as typeof clearTimeout;
  const stream = new ReadableStream<Uint8Array>({ cancel() { cancelled = true; return new Promise(() => {}); } });
  try {
    const result = readCortinaBody(request(stream));
    assert(fire);
    fire();
    await assert.rejects(() => result, expectError(408, "request_timeout"));
    assert(cancelled);
    assert(cleared);
    assert(!stream.locked);
  } finally { globalThis.setTimeout = originalSet; globalThis.clearTimeout = originalClear; }
});

Deno.test("abort before or during body receive fails closed and cancels", async () => {
  for (const before of [true, false]) {
    let cancelled = false;
    const controller = new AbortController();
    const stream = new ReadableStream<Uint8Array>({ cancel() { cancelled = true; } });
    if (before) controller.abort();
    const result = readCortinaBody(request(stream, undefined, controller.signal));
    if (!before) controller.abort();
    await assert.rejects(() => result, expectError(400, "invalid_json"));
    assert(cancelled);
    assert(!stream.locked);
  }
});

Deno.test("UTF-8 split across chunks decodes once without altering fields", async () => {
  const body = { name: "\u00e9", sessionId, accessToken };
  const stream = new ReadableStream<Uint8Array>({ start(controller) {
    for (const byte of encode(JSON.stringify(body))) controller.enqueue(new Uint8Array([byte]));
    controller.close();
  } });
  assert.deepEqual(await readCortinaBody(request(stream)), body);
  assert(!stream.locked);
});

Deno.test("session capability remains exact including case and historical opaque form", () => {
  for (const token of [accessToken, "0123456789abcdef0123456789abcdef", "request-token", " token ", "x".repeat(128)]) {
    assert.deepEqual(cortinaSessionCredentials({ sessionId, accessToken: token }), { sessionId, accessToken: token });
  }
});

Deno.test("missing or nonstring credentials preserve the missing-session contract", () => {
  for (const body of [{}, { sessionId }, { accessToken }, { sessionId: 1, accessToken },
    { sessionId, accessToken: [] }, { sessionId, accessToken: "" }]) {
    assert.throws(() => cortinaSessionCredentials(body), expectError(400, "missing_session"));
  }
});

Deno.test("invalid session UUID and oversized or control-bearing capabilities are rejected", () => {
  for (const body of [{ sessionId: "not-a-uuid", accessToken }, { sessionId: `${sessionId} `, accessToken },
    { sessionId, accessToken: "x".repeat(129) }, { sessionId, accessToken: "a\nb" },
    { sessionId, accessToken: "a\u0000b" }, { sessionId, accessToken: "a\u007fb" }]) {
    assert.throws(() => cortinaSessionCredentials(body), expectError(400, "invalid_session_credentials"));
  }
});

Deno.test("public successes retain payload status and CORS but cannot be cached", async () => {
  const body = { sessionId, accessToken, status: "support_required" };
  const original = Response.json(body, { status: 202, headers: { "Access-Control-Allow-Origin": "https://site.synthetic.invalid" } });
  const response = cortinaPublicResponse(original);
  assert.equal(response, original);
  assert.equal(response.status, 202);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("access-control-allow-origin"), "https://site.synthetic.invalid");
  assert.deepEqual(await response.json(), body);
});

Deno.test("server diagnostics are hidden while 500 and retryable 503 codes survive", async () => {
  for (const error of [new Error(accessToken), new HttpError(500, accessToken),
    new HttpError(503, accessToken, "new_payments_unavailable")]) {
    const response = cortinaPublicError(error);
    assert.equal(response.status, error instanceof HttpError ? error.status : 500);
    assert.deepEqual(await response.json(), { error: "Cortina request unavailable",
      code: error instanceof HttpError ? error.code ?? "internal_error" : "internal_error" });
    assert.equal(response.headers.get("cache-control"), "no-store");
  }
});

Deno.test("known validation authorization and unconfirmed-payment errors are preserved", async () => {
  for (const [status, code] of [[400, "invalid_json"], [401, "authentication_required"],
    [404, "session_not_found"], [409, "payment_not_confirmed"], [413, "body_too_large"]] as const) {
    const response = cortinaPublicError(new HttpError(status, "Known safe message", code));
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { error: "Known safe message", code });
  }
});
