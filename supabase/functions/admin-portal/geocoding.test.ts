// Match the adjacent backend tests' pinned std imports without changing their graph.
// deno-lint-ignore no-import-prefix
import { assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
// deno-lint-ignore no-import-prefix
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { createPortalDependencies } from "./backend.ts";
import { dispatchPortal, PortalError } from "./logic.ts";
import { geocodeAddress, parseGeocodeAddress } from "./geocoding.ts";

const address = { address: "12 A&B #4", city: "Indianapolis", state: "IN", zipCode: "46201", country: "US" };
function fixture(identities: unknown[] = [{ id: "A", role: "Owner" }, { id: "A", role: "Owner" }]) {
  const calls: Request[] = [];
  const deps = createPortalDependencies("captured-A", {
    url: "https://synthetic.invalid", anonKey: "public-test-key", geocodeKey: "synthetic-provider-key",
    fetch: (async (input, init) => {
      const request = new Request(input, init);
      calls.push(request);
      const url = new URL(request.url);
      if (url.origin === "https://synthetic.invalid") {
        assertEquals(url.pathname, "/rest/v1/rpc/admin_portal_request");
        assertEquals(request.headers.get("authorization"), "Bearer captured-A");
        assertEquals(await request.json(), { action: "identity", payload: {} });
        const identity = identities.shift();
        return identity instanceof Response ? identity : Response.json(identity);
      }
      assertEquals(url.origin, "https://geocode.maps.co");
      assertEquals(url.pathname, "/search");
      assertEquals(url.searchParams.get("q"), "12 A&B #4 Indianapolis IN 46201 US");
      assertEquals(url.searchParams.get("limit"), "1");
      assertEquals(url.searchParams.has("api_key"), false);
      assertEquals(request.headers.get("authorization"), "Bearer synthetic-provider-key");
      assertEquals(request.redirect, "error");
      return Response.json([{ lat: "39.7684", lon: "-86.1581", display_name: "not returned" }]);
    }) as typeof fetch,
  });
  return { calls, deps };
}

Deno.test("geocode uses actual caller SDK, two canonical identities and one fixed encoded provider request", async () => {
  const { calls, deps } = fixture();
  assertEquals(await dispatchPortal("captured-A", { action: "geocode", address, actor: "forged-B", role: "Owner" }, deps),
    { coordinates: { lat: 39.7684, lon: -86.1581 } });
  assertEquals(calls.length, 3);
});

Deno.test("geocode denies Admin, changed actor, changed role and stale canonical admission before provider", async () => {
  for (const next of [{ id: "A", role: "Admin" }, { id: "B", role: "Owner" },
    Response.json({ code: "PT403", message: "challenge_totp" }, { status: 403 })]) {
    const { deps, calls } = fixture([{ id: "A", role: "Owner" }, next]);
    const error = await assertRejects(() => dispatchPortal("captured-A", { action: "geocode", address }, deps), PortalError);
    assertEquals(error.status, 403);
    assertEquals(calls.length, 2);
  }
  const { deps, calls } = fixture([{ id: "A", role: "Admin" }, { id: "A", role: "Admin" }]);
  await assertRejects(() => dispatchPortal("captured-A", { action: "geocode", address }, deps), PortalError);
  assertEquals(calls.length, 2);
});

Deno.test("missing bearer and invalid bounded addresses never reach provider", async () => {
  const { deps, calls } = fixture();
  await assertRejects(() => dispatchPortal("", { action: "geocode", address }, deps), PortalError);
  assertEquals(calls.length, 0);
  for (const value of [null, [], {}, { ...address, address: " " }, { ...address, city: "x".repeat(101) },
    { ...address, zipCode: "x".repeat(21) }, { ...address, state: "IN\n" }, { ...address, country: 42 }]) {
    assertThrows(() => parseGeocodeAddress(value), PortalError);
  }
});

Deno.test("missing server key fails closed without provider access", async () => {
  let calls = 0;
  await assertRejects(() => geocodeAddress("bounded", undefined, () => { calls++; throw Error("unexpected"); }), PortalError);
  assertEquals(calls, 0);
});

Deno.test("provider 429 is controlled, redacted and never retried", async () => {
  let calls = 0;
  const error = await assertRejects(() => geocodeAddress("private address", "private key", () => {
    calls++;
    return Promise.resolve(new Response("private address/private key", { status: 429 }));
  }), PortalError);
  assertEquals(error.status, 429);
  assertEquals(error.code, "geocode_rate_limited");
  assertEquals(error.message, "Address lookup is busy. Try again later.");
  assertEquals(calls, 1);
});

Deno.test("empty provider result is a normal no-match", async () => {
  assertEquals(await geocodeAddress("bounded", "key", () => Promise.resolve(Response.json([]))), null);
});

Deno.test("oversized, malformed and invalid coordinate responses are rejected without raw data", async () => {
  for (const body of ["x".repeat(16385), "not json", "{}", '[{},{}]', '[{"lat":"","lon":1}]',
    '[{"lat":91,"lon":1}]', '[{"lat":1,"lon":181}]', '[{"lat":"0x20","lon":1}]']) {
    const error = await assertRejects(() => geocodeAddress("private", "secret", () => Promise.resolve(new Response(body))), PortalError);
    assertEquals(error.code, "geocode_unavailable");
    assertEquals(error.message, "Address lookup is unavailable. Try again later.");
  }
});

Deno.test("provider timeout aborts at five seconds without retry", async () => {
  const time = new FakeTime();
  try {
    let calls = 0;
    const pending = assertRejects(() => geocodeAddress("bounded", "key", (_input, init) => {
      calls++;
      return new Promise((_resolve, reject) => {
        init!.signal!.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
      });
    }), PortalError);
    time.tick(5000);
    assertEquals((await pending).code, "geocode_unavailable");
    assertEquals(calls, 1);
  } finally { time.restore(); }
});
