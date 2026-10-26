import { assertEquals } from "https://deno.land/std@0.182.0/testing/asserts.ts";
import { type DeleteUserDeps, handleDeleteUser } from "./logic.ts";

const pending = {
  subject_id: "caller",
  account_access: "restricted",
  next_step: "blocked",
  reason: "explicit_restore_required",
  account_state: "pending_deletion",
  restore_until: "2026-10-30T00:00:00Z",
};

const invalidAcknowledgements: [string, unknown][] = [
  ["truthy string", "success"],
  ["truthy boolean", true],
  ["truthy number", 1],
  ["array", [pending]],
  ["unrelated object", { success: true }],
  [
    "missing reason",
    Object.fromEntries(
      Object.entries(pending).filter(([key]) => key !== "reason"),
    ),
  ],
  ["extra key", { ...pending, success: true }],
  [
    "replaced key",
    Object.fromEntries(
      Object.entries(pending).map((
        [key, value],
      ) => [key === "reason" ? "unrelated" : key, value]),
    ),
  ],
  ["wrong subject", { ...pending, subject_id: "other" }],
  ["active status", {
    ...pending,
    account_state: "legacy_active",
    account_access: "eligible",
    next_step: "home",
    reason: null,
    restore_until: null,
  }],
  ["non-pending state", { ...pending, account_state: "legacy_active" }],
  ["eligible pending", { ...pending, account_access: "eligible" }],
  ["home pending", { ...pending, next_step: "home", reason: null }],
  ["unknown next step", { ...pending, next_step: "restore", reason: null }],
  ["null blocked reason", { ...pending, reason: null }],
  ["non-pending blocked reason", { ...pending, reason: "account_restricted" }],
  ["reason array", { ...pending, reason: ["explicit_restore_required"] }],
  ["prerequisite with blocked reason", {
    ...pending,
    next_step: "challenge_totp",
  }],
];
for (
  const restore_until of [
    null,
    1793318400000,
    "",
    "not-a-date",
    "2026-10-30",
    "2026-10-30T00:00:00",
    "2026-10-30T01:00:00+01:00",
    "2026-02-30T00:00:00Z",
    "2026-13-01T00:00:00Z",
    "2026-10-30T24:00:00Z",
    "2026-10-30T00:60:00Z",
    "2026-10-30T00:00:00.1234567Z",
  ]
) {
  invalidAcknowledgements.push([
    `invalid deadline ${JSON.stringify(restore_until)}`,
    { ...pending, restore_until },
  ]);
}

for (const [name, data] of invalidAcknowledgements) {
  Deno.test(`pending acknowledgement rejects ${name} without retry`, async () => {
    let dispatches = 0;
    const { deps } = fixture({
      requestDeletion: () => {
        dispatches++;
        return Promise.resolve({ data, error: null });
      },
    });
    const response = await handleDeleteUser(request(), deps);
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {
      error: "deletion_outcome_unknown",
      retryable: true,
      status_rpc: "get_account_lifecycle_status",
    });
    assertEquals(dispatches, 1);
  });
}

for (
  const [next_step, reason] of [
    ["blocked", "explicit_restore_required"],
    ["blocked", "restore_expired"],
    ["blocked", "profile_missing"],
    ["blocked", "role_unavailable"],
    ["blocked", "unsupported_factor"],
    ["verify_email", null],
    ["enroll_totp", null],
    ["challenge_totp", null],
  ] as const
) {
  Deno.test(`pending acknowledgement accepts ${next_step}/${reason}`, async () => {
    // A past server deadline is valid, including idempotent expired requests.
    const data = {
      ...pending,
      next_step,
      reason,
      restore_until: "2020-02-29T23:59:59.123456+00:00",
    };
    let dispatches = 0;
    const { deps } = fixture({
      requestDeletion: () => {
        dispatches++;
        return Promise.resolve({ data, error: null });
      },
    });
    const response = await handleDeleteUser(request(), deps);
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { success: true, data });
    assertEquals(dispatches, 1);
  });
}
function fixture(overrides: Partial<DeleteUserDeps> = {}) {
  const calls: string[] = [];
  const deps: DeleteUserDeps = {
    getUser: (jwt) => {
      calls.push(`auth:${jwt}`);
      return Promise.resolve({ userId: "caller", error: false });
    },
    requestDeletion: (jwt) => {
      calls.push(`request:${jwt}`);
      return Promise.resolve({ data: pending, error: null });
    },
    ...overrides,
  };
  return { calls, deps };
}
const request = (
  body: unknown = { user_id: "caller" },
  bearer = "Bearer captured-token",
  method = "POST",
) =>
  new Request("http://localhost/delete-account", {
    method,
    headers: { Authorization: bearer },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });

for (const method of ["OPTIONS", "GET", "DELETE"]) {
  Deno.test(`${method} has no authentication or mutation`, async () => {
    const { calls, deps } = fixture();
    assertEquals(
      (await handleDeleteUser(request({}, "", method), deps)).status,
      method === "OPTIONS" ? 200 : 405,
    );
    assertEquals(calls, []);
  });
}
for (const bearer of ["", "token", "Bearer ", "Bearer one two"]) {
  Deno.test(`reject invalid bearer ${JSON.stringify(bearer)}`, async () => {
    const { calls, deps } = fixture();
    assertEquals(
      (await handleDeleteUser(request({}, bearer), deps)).status,
      401,
    );
    assertEquals(calls, []);
  });
}
for (
  const identity of [{ userId: null, error: false }, {
    userId: "caller",
    error: true,
  }]
) {
  Deno.test(`reject invalid identity ${JSON.stringify(identity)}`, async () => {
    const { deps, calls } = fixture({
      getUser: () => Promise.resolve(identity),
    });
    assertEquals((await handleDeleteUser(request(), deps)).status, 401);
    assertEquals(calls, []);
  });
}
Deno.test("authentication outage is sanitized without dispatch", async () => {
  const { calls, deps } = fixture({
    getUser: () => Promise.reject(new Error("secret")),
  });
  const response = await handleDeleteUser(request(), deps);
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "authentication_unavailable" });
  assertEquals(calls, []);
});
for (
  const body of [null, {}, { user_id: "" }, { user_id: 7 }, {
    user_id: "other",
  }]
) {
  Deno.test(`reject malformed/cross-account body ${JSON.stringify(body)}`, async () => {
    const { deps, calls } = fixture();
    assertEquals(
      (await handleDeleteUser(request(body), deps)).status,
      body?.user_id === "other" ? 403 : 400,
    );
    assertEquals(calls, ["auth:captured-token"]);
  });
}
Deno.test("malformed JSON is a 400 after authentication", async () => {
  const { deps } = fixture();
  assertEquals(
    (await handleDeleteUser(
      new Request("http://localhost", {
        method: "POST",
        headers: { Authorization: "Bearer token" },
        body: "{",
      }),
      deps,
    )).status,
    400,
  );
});
Deno.test("captured bearer requests only caller-bound deletion with server deadline", async () => {
  const { calls, deps } = fixture();
  const response = await handleDeleteUser(
    request({ user_id: "caller", restore_until: "attacker-value" }),
    deps,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { success: true, data: pending });
  assertEquals(calls, ["auth:captured-token", "request:captured-token"]);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
});
for (
  const [code, status, error] of [
    ["PT401", 401, "session_invalid"],
    ["PT403", 403, "account_restricted"],
  ] as const
) {
  Deno.test(`RPC ${code} maps to sanitized ${status}`, async () => {
    const { deps } = fixture({
      requestDeletion: () => Promise.resolve({ data: null, error: { code } }),
    });
    const response = await handleDeleteUser(request(), deps);
    assertEquals(response.status, status);
    assertEquals(await response.json(), { error });
  });
}
Deno.test("known last-Owner PT409 is deterministic without retry or pending acknowledgement", async () => {
  let dispatches = 0;
  const { deps } = fixture({
    requestDeletion: (jwt) => {
      assertEquals(jwt, "captured-token");
      dispatches++;
      return Promise.resolve({ data: null, error: { code: "PT409", message: "owner_last_required" } });
    },
  });
  const response = await handleDeleteUser(request(), deps);
  assertEquals(response.status, 409);
  assertEquals(await response.json(), { error: "owner_last_required" });
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(dispatches, 1);
});

for (const error of [
  { code: "PT409" },
  { code: "PT409", message: "unrecognized private diagnostic" },
  { code: "XX000", message: "owner_last_required" },
]) {
  Deno.test(`unknown conflict remains status-led uncertain outcome ${JSON.stringify(error)}`, async () => {
    let dispatches = 0;
    const { deps } = fixture({ requestDeletion: () => {
      dispatches++;
      return Promise.resolve({ data: null, error });
    } });
    const response = await handleDeleteUser(request(), deps);
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {
      error: "deletion_outcome_unknown", retryable: true, status_rpc: "get_account_lifecycle_status",
    });
    assertEquals(dispatches, 1);
  });
}

for (const failure of ["throw", "PT503", "XX000", "null"]) {
  Deno.test(`uncertain ${failure} response gives status/retry contract`, async () => {
    const { deps } = fixture({
      requestDeletion: () =>
        failure === "throw"
          ? Promise.reject(new Error("secret"))
          : Promise.resolve({
            data: null,
            error: failure === "null" ? null : { code: failure },
          }),
    });
    const response = await handleDeleteUser(request(), deps);
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {
      error: "deletion_outcome_unknown",
      retryable: true,
      status_rpc: "get_account_lifecycle_status",
    });
  });
}
