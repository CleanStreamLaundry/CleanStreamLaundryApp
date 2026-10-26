import assert from "node:assert/strict";
import { AvailabilityAdmissionError, captureAvailabilityAdmission } from "./admission.ts";

const subject = "aaaaaaaa-0000-4000-8000-000000000001";
const selector = "CLEANSTREAM_AVAILABILITY_PUBLISHABLE_KEY_NAME";
const allowed = { subject_id: subject, account_access: "eligible", next_step: "review_terms" };
const request = () => new Request("https://availability.invalid", {
  headers: { Authorization: "Bearer original-caller", apikey: "untrusted-request-key" },
});
const settings: Record<string, string> = {
  SUPABASE_URL: "https://project.invalid/",
  SUPABASE_ANON_KEY: "synthetic-anon",
  [selector]: "availability",
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ availability: "sb_publishable_synthetic_availability" }),
};
const denies = (operation: () => Promise<void>, status: number) =>
  assert.rejects(operation, (error: unknown) => {
    assert(error instanceof AvailabilityAdmissionError);
    assert.equal(error.status, status);
    assert(!error.message.includes("private-detail"));
    return true;
  });

for (const mode of ["named", "legacy"]) {
  Deno.test(`availability admission transport: ${mode} public key and original subject`, async () => {
    const config = { ...settings };
    if (mode === "legacy") delete config[selector];
    const req = request();
    const check = captureAvailabilityAdmission(req, (name) => config[name], (input, init) => {
      assert(init);
      assert.equal(input, "https://project.invalid/rest/v1/rpc/get_admission_status");
      assert.equal(init?.method, "POST");
      assert.equal(init?.body, "{}");
      assert.equal(init?.redirect, "error");
      assert(init.signal instanceof AbortSignal);
      assert.equal(init.signal.aborted, false);
      const headers = new Headers(init.headers);
      assert.equal(headers.get("Authorization"), "Bearer original-caller");
      assert.equal(headers.get("apikey"), mode === "named" ? "sb_publishable_synthetic_availability" : "synthetic-anon");
      return Promise.resolve(Response.json(allowed));
    });
    req.headers.set("Authorization", "Bearer later-caller");
    await check(subject);
  });
}

for (const name of ["", " missing", "missing", "toString"]) {
  Deno.test(`availability admission transport: invalid explicit selector ${JSON.stringify(name)} has no fallback`, async () => {
    const config: Record<string, string> = { ...settings, [selector]: name };
    let calls = 0;
    const check = captureAvailabilityAdmission(request(), (key) => config[key], () => {
      calls++;
      return Promise.resolve(Response.json(allowed));
    });
    await denies(() => check(subject), 503);
    assert.equal(calls, 0);
  });
}

for (const [status, expected] of [[401, 401], [403, 403], [429, 503], [500, 503]]) {
  Deno.test(`availability admission transport: HTTP ${status} sanitizes without retry`, async () => {
    let calls = 0;
    const check = captureAvailabilityAdmission(request(), (key) => settings[key], () => {
      calls++;
      return Promise.resolve(Response.json({ private: "private-detail" }, { status }));
    });
    await denies(() => check(subject), expected);
    assert.equal(calls, 1);
  });
}

for (const payload of [null, [], {}, { ...allowed, subject_id: null }, { ...allowed, account_access: true }]) {
  Deno.test(`availability admission transport: malformed response ${JSON.stringify(payload)} fails closed`, async () => {
    const check = captureAvailabilityAdmission(request(), (key) => settings[key], () => Promise.resolve(Response.json(payload)));
    await denies(() => check(subject), 503);
  });
}

Deno.test("availability admission transport: bounded fetch rejection sanitizes and does not retry", async () => {
  let calls = 0;
  const check = captureAvailabilityAdmission(request(), (key) => settings[key], (_input, init) => {
    calls++;
    assert(init?.signal instanceof AbortSignal);
    assert.equal(init.signal.aborted, false);
    throw new DOMException("private-detail", "TimeoutError");
  });
  await denies(() => check(subject), 503);
  assert.equal(calls, 1);
});

for (const authorization of [null, "caller-only", "Bearer ", "Bearer A B"]) {
  Deno.test(`availability admission transport: malformed bearer ${JSON.stringify(authorization)} avoids configuration and HTTP`, async () => {
    const req = request();
    if (authorization === null) req.headers.delete("Authorization");
    else req.headers.set("Authorization", authorization);
    const check = captureAvailabilityAdmission(req, () => { throw new Error("configuration must not be read"); }, () => {
      throw new Error("HTTP must not run");
    });
    await denies(() => check(subject), 401);
  });
}
