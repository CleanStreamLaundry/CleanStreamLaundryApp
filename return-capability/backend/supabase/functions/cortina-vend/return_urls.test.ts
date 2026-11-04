import assert from "node:assert/strict";
import { HttpError } from "../_shared/cortina.ts";
import { cortinaReturnUrls } from "./return_urls.ts";

const reference = { sessionId: "00000000-0000-4000-8000-000000000001", accessToken: "ABCDEF00-0000-4000-8000-000000000002" };
const payUrl = "https://web.synthetic.invalid/pay";

Deno.test("new success URL keeps the capability out of the server-visible path and query", () => {
  const { success_url } = cortinaReturnUrls(payUrl, reference, { machineToken: "public-qr" });
  const url = new URL(success_url);
  assert.equal(url.origin + url.pathname + url.search, payUrl + "?cortina_return=1");
  assert(!url.search.includes(reference.accessToken));
  assert(!url.pathname.includes(reference.accessToken));
  assert.deepEqual(Object.fromEntries(new URLSearchParams(url.hash.slice(1))), { session: reference.sessionId, access: reference.accessToken });
});

Deno.test("return marker survives a lost fragment without exposing either credential", () => {
  const url = new URL(cortinaReturnUrls(payUrl, reference, {}).success_url);
  url.hash = "";
  assert.equal(url.toString(), payUrl + "?cortina_return=1");
  assert(!url.toString().includes(reference.sessionId));
  assert(!url.toString().includes(reference.accessToken));
});

Deno.test("cancel URL preserves machine then terminal then uniQR precedence without a capability", () => {
  for (const [input, key, value] of [
    [{ machineToken: "machine", terminalId: "123", uniQr: "qr" }, "machine", "machine"],
    [{ terminalId: "123", uniQr: "qr" }, "terminal", "123"],
    [{ uniQr: "qr" }, "uniqr", "qr"],
  ] as const) {
    const url = new URL(cortinaReturnUrls(payUrl, reference, input).cancel_url);
    assert.equal(url.hash, "");
    assert.deepEqual(Object.fromEntries(url.searchParams), { [key]: value });
  }
});

Deno.test("structured URL encoding cannot promote opaque values into query fields", () => {
  const opaque = { sessionId: "session&x=1", accessToken: "token?query=1#fragment+%" };
  const urls = cortinaReturnUrls(payUrl, opaque, { machineToken: "public?x=1&access=not-a-capability#anchor" });
  const success = new URL(urls.success_url), cancel = new URL(urls.cancel_url);
  assert.deepEqual(Object.fromEntries(new URLSearchParams(success.hash.slice(1))), { session: opaque.sessionId, access: opaque.accessToken });
  assert.equal(cancel.searchParams.get("machine"), "public?x=1&access=not-a-capability#anchor");
  assert.equal(cancel.searchParams.has("access"), false);
  assert.equal(cancel.hash, "");
});

Deno.test("configured URL retains unrelated public query but strips stale credentials and selectors", () => {
  const base = payUrl + "?campaign=summer&access=stale&session=old&cortina_return=1&machine=old&terminal=old&uniqr=old#access=stale";
  const urls = cortinaReturnUrls(base, reference, { uniQr: "current" });
  assert.equal(new URL(urls.success_url).search, "?campaign=summer&cortina_return=1");
  assert.equal(urls.cancel_url, payUrl + "?campaign=summer&uniqr=current");
});

Deno.test("hosted development HTTP URLs remain supported without an invented live-mode restriction", () => {
  const urls = cortinaReturnUrls("http://localhost:5173/pay", reference, { machineToken: "public" });
  assert.equal(new URL(urls.success_url).origin, "http://localhost:5173");
  assert.equal(urls.cancel_url, "http://localhost:5173/pay?machine=public");
});

Deno.test("unsafe or malformed configured URLs fail closed with sanitized 503", () => {
  for (const value of ["/pay", "javascript:alert(1)", "https://user:private@web.synthetic.invalid/pay", "not a url"]) {
    assert.throws(() => cortinaReturnUrls(value, reference, {}), (error) => {
      assert(error instanceof HttpError);
      assert.equal(error.status, 503);
      assert.equal(error.code, "return_configuration_unavailable");
      assert.equal(error.message, "Payment return configuration unavailable");
      return true;
    });
  }
});
