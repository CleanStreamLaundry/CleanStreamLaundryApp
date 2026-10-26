import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  handleMaintenance,
  type MaintenanceDeps,
  type MaintenanceSubmission,
  type MaintenanceUser,
} from "./logic.ts";

const userId = "aaaaaaaa-0000-4000-8000-000000000001";
const otherId = "bbbbbbbb-0000-4000-8000-000000000002";
const input = {
  user_id: userId,
  category: "Other",
  description: "  A report with its original whitespace.  ",
  location: "No Applicable Location",
  image: null,
};
const failures = {
  unauthorized: [401, "Sign in to submit a maintenance request."],
  user_mismatch: [403, "The request does not match the signed-in account."],
  account_restricted: [
    403,
    "This account cannot submit a maintenance request.",
  ],
  invalid_request: [400, "Invalid maintenance request."],
  request_too_large: [413, "Maintenance request is too large."],
  maintenance_unavailable: [503, "Maintenance request unavailable."],
} as const;

function request(
  body: unknown = input,
  authorization = "Bearer synthetic-user",
) {
  return new Request("http://localhost/maintenance-request", {
    method: "POST",
    headers: { authorization, apikey: "synthetic-public-key" },
    body: JSON.stringify(body),
  });
}

const origin = "https://supabase.invalid";
const imagePrefix = `${origin}/storage/v1/object/public/maintenance-images/`;
function acknowledgement(row: MaintenanceSubmission) {
  return {
    success: true,
    message: "Request logged",
    record: [{
      user_id: row.user_id,
      category: row.category,
      description: row.description,
      location: row.location,
      location_id: row.location_id === null ? null : Number(row.location_id),
      image_data: null,
      created_at: "2026-09-30T00:00:00Z",
      maint_id: 123,
      attachment_ref: row.attachment === null ? null : {
        bucket: "maintenance-images",
        id: otherId,
        name: row.attachment.name,
        version: null,
      },
    }],
  };
}

function fixture(overrides: Partial<MaintenanceDeps> = {}) {
  const calls: string[] = [];
  const rows: MaintenanceSubmission[] = [];
  const deps: MaintenanceDeps = {
    storageUrl: origin,
    authenticate: (token) => {
      calls.push("auth");
      assertEquals(token, "synthetic-user");
      return Promise.resolve({ id: userId, is_anonymous: false });
    },
    submit: (row) => {
      calls.push("submit");
      rows.push(row);
      return Promise.resolve({ data: acknowledgement(row), error: null });
    },
    ...overrides,
  };
  return {
    calls,
    rows,
    run: (req: Request) => handleMaintenance(req, () => deps),
  };
}

function assertFailure(result: unknown, code: keyof typeof failures) {
  const [status, error] = failures[code];
  assertEquals(result, { status, body: { error, code } });
}

for (const authorization of ["", "Bearer", "Basic synthetic", "Bearer a b"]) {
  Deno.test(`missing/malformed bearer ${JSON.stringify(authorization)} never initializes dependencies or reads body`, async () => {
    const req = request(input, authorization);
    let calls = 0;
    const result = await handleMaintenance(req, () => {
      calls++;
      throw new Error("must not initialize");
    });
    assertFailure(result, "unauthorized");
    assertEquals(calls, 0);
    assertEquals(req.bodyUsed, false);
  });
}

for (
  const user of [null, { id: userId, is_anonymous: true }, { id: userId }, {
    id: "invalid",
    is_anonymous: false,
  }]
) {
  Deno.test(`unverified/non-user identity ${JSON.stringify(user)} cannot parse or write`, async () => {
    let authenticated = false;
    const f = fixture({
      authenticate: () => {
        authenticated = true;
        return Promise.resolve(user);
      },
    });
    const req = request("malformed payload");
    assertFailure(await f.run(req), "unauthorized");
    assert(authenticated);
    assertEquals(req.bodyUsed, false);
    assertEquals(f.rows, []);
  });
}

Deno.test("authentication must settle before consuming JSON or writing", async () => {
  let finish!: (user: MaintenanceUser) => void;
  const verified = new Promise<MaintenanceUser>((resolve) => finish = resolve);
  const f = fixture({ authenticate: () => verified });
  const req = request();
  const pending = f.run(req);
  await Promise.resolve();
  assertEquals(req.bodyUsed, false);
  assertEquals(f.rows, []);
  finish({ id: userId, is_anonymous: false });
  assertEquals((await pending).status, 200);
  assertEquals(f.rows.length, 1);
});

for (
  const category of [
    "Washer/Dryer Maintenance",
    "App Maintenance",
    "Location Maintenance",
    "Other",
  ]
) {
  Deno.test(`current category ${category} preserves the success wire and original report`, async () => {
    const f = fixture();
    const result = await f.run(request({ ...input, category }));
    const row = f.rows[0];
    assertEquals(f.calls, ["auth", "submit"]);
    assertEquals(row, {
      user_id: userId,
      category,
      description: input.description,
      location: input.location,
      attachment: null,
      location_id: null,
    });
    assertEquals(result, {
      status: 200,
      body: acknowledgement(row),
    });
  });
}

for (const legacyUserId of [undefined, userId, userId.toUpperCase()]) {
  Deno.test(`optional/matching user_id ${legacyUserId} uses only verified identity`, async () => {
    const f = fixture();
    assertEquals(
      (await f.run(request({ ...input, user_id: legacyUserId }))).status,
      200,
    );
    assertEquals(f.rows[0].user_id, userId);
  });
}

Deno.test("cross-user UUID is rejected before insert", async () => {
  const f = fixture();
  assertFailure(
    await f.run(request({ ...input, user_id: otherId })),
    "user_mismatch",
  );
  assertEquals(f.calls, ["auth"]);
});

const invalidInputs = [
  null,
  [],
  "text",
  5,
  true,
  {},
  ...[null, 7, {}, "not-a-uuid"].map((user_id) => ({ ...input, user_id })),
  ...[undefined, null, {}, "", "Other ", "Unknown"].map((category) => ({
    ...input,
    category,
  })),
  ...[undefined, null, {}, "", "  ", "x".repeat(4001), "bad\0text"].map((
    description,
  ) => ({ ...input, description })),
  ...[undefined, null, {}, "", "  ", "x".repeat(1001), "bad\0location"].map((
    location,
  ) => ({ ...input, location })),
  ...[{}, 7, "", " ", "x".repeat(2049), "bad\0image"].map((image) => ({
    ...input,
    image,
  })),
];
for (const [index, body] of invalidInputs.entries()) {
  Deno.test(`invalid input matrix ${index + 1} never writes`, async () => {
    const f = fixture();
    assertFailure(await f.run(request(body)), "invalid_request");
    assertEquals(f.calls, ["auth"]);
  });
}

for (const raw of ["", "{malformed", new Uint8Array([0xff])]) {
  Deno.test(`malformed JSON/UTF-8 ${String(raw)} is a safe 400`, async () => {
    const f = fixture();
    const req = new Request("http://localhost/maintenance-request", {
      method: "POST",
      headers: { authorization: "Bearer synthetic-user" },
      body: raw,
    });
    assertFailure(await f.run(req), "invalid_request");
    assertEquals(f.calls, ["auth"]);
  });
}

Deno.test("empty body is rejected", async () => {
  const f = fixture();
  assertFailure(
    await f.run(
      new Request("http://localhost/maintenance-request", {
        method: "POST",
        headers: { authorization: "Bearer synthetic-user" },
      }),
    ),
    "invalid_request",
  );
  assertEquals(f.calls, ["auth"]);
});

Deno.test("declared oversized body is rejected after authentication without reading", async () => {
  const f = fixture();
  const req = request();
  req.headers.set("content-length", "32769");
  assertFailure(await f.run(req), "request_too_large");
  assertEquals(req.bodyUsed, false);
  assertEquals(f.calls, ["auth"]);
});

Deno.test("chunked UTF-8 bytes are bounded even with a forged small content-length", async () => {
  const f = fixture();
  let canceled = false;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode('"'));
      controller.enqueue(new TextEncoder().encode("\u00e9".repeat(16384)));
    },
    cancel() {
      canceled = true;
    },
  });
  const req = new Request("http://localhost/maintenance-request", {
    method: "POST",
    headers: { authorization: "Bearer synthetic-user", "content-length": "1" },
    body: stream,
  });
  assertFailure(await f.run(req), "request_too_large");
  assert(canceled);
  assertEquals(f.calls, ["auth"]);
});

Deno.test("exact body-byte limit and text boundaries are accepted without truncation", async () => {
  const f = fixture();
  const body = {
    ...input,
    description: "d".repeat(4000),
    location: "l".repeat(1000),
    image: imagePrefix + "i".repeat(2048 - imagePrefix.length),
  };
  const text = JSON.stringify(body).padEnd(32768, " ");
  const req = new Request("http://localhost/maintenance-request", {
    method: "POST",
    headers: { authorization: "Bearer synthetic-user" },
    body: text,
  });
  assertEquals((await f.run(req)).status, 200);
  assertEquals(f.rows[0].description, body.description);
  assertEquals(f.rows[0].attachment, {
    name: body.image.slice(imagePrefix.length),
  });
});

for (
  const image of [undefined, null, `${imagePrefix}requests/photo.jpg`]
) {
  Deno.test(`recognized attachment ${String(image)} delegates ownership and never fetches`, async () => {
    const f = fixture();
    assertEquals((await f.run(request({ ...input, image }))).status, 200);
    assertEquals(
      f.rows[0].attachment,
      image == null ? null : { name: "requests/photo.jpg" },
    );
    assertEquals(f.calls, ["auth", "submit"]);
  });
}

Deno.test("unknown management fields cannot override the insert whitelist or server time", async () => {
  const f = fixture();
  assertEquals(
    (await f.run(request({
      ...input,
      maint_id: 999,
      created_at: "1970-01-01",
      image_data: "forged",
      status: "resolved",
      assigned_to: otherId,
      roles: "Owner",
    }))).status,
    200,
  );
  assertEquals(Object.keys(f.rows[0]).sort(), [
    "attachment",
    "category",
    "description",
    "location",
    "location_id",
    "user_id",
  ]);
  assertEquals(f.rows[0].attachment, null);
});

for (const failAt of ["factory", "authenticate", "submit"] as const) {
  Deno.test(`thrown ${failAt} failure is sanitized and never retried`, async () => {
    let count = 0;
    const error = () => {
      count++;
      throw new Error("private database/token detail");
    };
    const f = fixture(failAt === "factory" ? {} : { [failAt]: error });
    const req = request();
    const result = failAt === "factory"
      ? await handleMaintenance(req, error)
      : await f.run(req);
    assertFailure(result, "maintenance_unavailable");
    assertEquals(count, 1);
    if (failAt !== "submit") assertEquals(req.bodyUsed, false);
    assertEquals(f.rows, []);
  });
}

for (
  const data of [null, {}, [], [null], [[]], [{}], [{
    maint_id: 1,
    user_id: otherId,
  }], [{ maint_id: 1, user_id: userId }, { maint_id: 2, user_id: userId }]]
) {
  Deno.test(`invalid database acknowledgement ${JSON.stringify(data)} is not success`, async () => {
    const f = fixture({ submit: () => Promise.resolve({ data, error: null }) });
    assertFailure(await f.run(request()), "maintenance_unavailable");
  });
}

Deno.test("insert must settle before success is acknowledged", async () => {
  let finish!: (value: unknown) => void;
  let entered!: () => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  const inserted = new Promise<unknown>((resolve) => finish = resolve);
  const f = fixture({
    submit: async () => {
      entered();
      return { data: await inserted, error: null };
    },
  });
  let settled = false;
  const pending = f.run(request()).then((result) => {
    settled = true;
    return result;
  });
  await started;
  assertEquals(settled, false);
  finish(acknowledgement({ ...input, location_id: null, attachment: null }));
  assertEquals((await pending).status, 200);
});

for (
  const image of [
    "https://legacy.invalid/requests/photo.jpg",
    `${origin}/storage/v1/object/public/other/photo.jpg`,
    `${imagePrefix}a?download=1`,
    `${imagePrefix}a#x`,
    `${imagePrefix}a?`,
    `${imagePrefix}a#`,
    `${imagePrefix}../a`,
    `${imagePrefix}%2e%2e/a`,
    `${imagePrefix}%2Foutside`,
    `${imagePrefix}%5coutside`,
    `${imagePrefix}a//b`,
    `${imagePrefix}%00a`,
    `${imagePrefix}%XX`,
    `${imagePrefix}a%2fb`,
    `${imagePrefix}a\\b`,
    `https://user@supabase.invalid/storage/v1/object/public/maintenance-images/a`,
    `https://supabase.invalid:444/storage/v1/object/public/maintenance-images/a`,
    ` ${imagePrefix}a`,
    `${imagePrefix}`,
    `${imagePrefix}a/`,
  ]
) {
  Deno.test(`ambiguous/foreign image rejected without submission: ${image}`, async () => {
    const f = fixture();
    assertFailure(await f.run(request({ ...input, image })), "invalid_request");
    assertEquals(f.calls, ["auth"]);
  });
}

for (
  const location_id of [
    0,
    1,
    "0",
    "01",
    "-1",
    "bad",
    "9223372036854775808",
    {},
    [],
  ]
) {
  Deno.test(`invalid explicit location ID ${JSON.stringify(location_id)}`, async () => {
    const f = fixture();
    assertFailure(
      await f.run(request({ ...input, location_id })),
      "invalid_request",
    );
    assertEquals(f.rows.length, 0);
  });
}
for (const location_id of [null, "1", "9223372036854775807"]) {
  Deno.test(`explicit bigint location wire ${location_id} is not rounded before RPC`, async () => {
    const f = fixture();
    assertEquals(
      (await f.run(request({ ...input, location_id }))).status,
      location_id === "9223372036854775807" ? 503 : 200,
    );
    assertEquals(f.rows[0].location_id, location_id);
  });
}
for (
  const [code, message, expected] of [
    ["PT400", "private", "invalid_request"],
    ["PT401", "private", "unauthorized"],
    ["PT403", "user_mismatch", "user_mismatch"],
    ["PT403", "private", "account_restricted"],
    ["PT503", "private", "maintenance_unavailable"],
    ["23505", "private", "maintenance_unavailable"],
    ["PGRST301", "private", "maintenance_unavailable"],
  ] as const
) {
  Deno.test(`RPC ${code}/${message} fixed error mapping and no retry`, async () => {
    let calls = 0;
    const f = fixture({
      submit: () => {
        calls++;
        return Promise.resolve({ data: null, error: { code, message } });
      },
    });
    assertFailure(await f.run(request()), expected);
    assertEquals(calls, 1);
  });
}
Deno.test("new attachment success passes the exact durable row; legacy F3 image equality is intentionally incompatible", async () => {
  const f = fixture();
  const result = await f.run(
    request({ ...input, image: `${imagePrefix}requests/1_2.jpg` }),
  );
  assertEquals(result.status, 200);
  assertEquals(result.body, acknowledgement(f.rows[0]));
  assertEquals(f.rows[0].attachment, { name: "requests/1_2.jpg" });
});

for (const maint_id of [null, "123", 0, -1, 1.5, 9007199254740992]) {
  Deno.test(`invalid or imprecise durable ID ${maint_id} is unavailable without retry`, async () => {
    let calls = 0;
    const f = fixture({
      submit: (row) => {
        calls++;
        const data = acknowledgement(row);
        return Promise.resolve({
          data: { ...data, record: [{ ...data.record[0], maint_id }] },
          error: null,
        });
      },
    });
    assertFailure(await f.run(request()), "maintenance_unavailable");
    assertEquals(calls, 1);
  });
}

const canonicalRef = {
  bucket: "maintenance-images",
  id: otherId,
  name: "requests/report photo.jpg",
  version: null,
};
const malformedRefs: [string, unknown][] = [
  ["empty object", {}],
  ...[undefined, null, "other-bucket"].map((bucket): [string, unknown] => [
    `bucket ${String(bucket)}`,
    { ...canonicalRef, bucket },
  ]),
  ...[undefined, null, "", "not-a-uuid", 123].map((id): [string, unknown] => [
    `id ${String(id)}`,
    { ...canonicalRef, id },
  ]),
  ...[undefined, "", "requests/different.jpg", "requests/report%20photo.jpg"]
    .map(
      (
        name,
      ): [string, unknown] => [`name ${String(name)}`, {
        ...canonicalRef,
        name,
      }],
    ),
  ...[undefined, false, 0, {}, []].map((version): [string, unknown] => [
    `version ${JSON.stringify(version)}`,
    { ...canonicalRef, version },
  ]),
];
for (const [label, attachment_ref] of malformedRefs) {
  Deno.test(`malformed attachment acknowledgement ${label} is unknown without retry or fetch`, async () => {
    let submits = 0;
    let fetches = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () => {
      fetches++;
      throw new Error("unexpected attachment fetch");
    };
    try {
      const f = fixture({
        submit: (row) => {
          submits++;
          assertEquals(row.attachment, { name: canonicalRef.name });
          const data = acknowledgement(row);
          return Promise.resolve({
            data: { ...data, record: [{ ...data.record[0], attachment_ref }] },
            error: null,
          });
        },
      });
      const result = await f.run(request({
        ...input,
        image: `${imagePrefix}requests/report%20photo.jpg`,
      }));
      assertEquals(submits, 1);
      assertEquals(fetches, 0);
      assertFailure(result, "maintenance_unavailable");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
}

for (
  const version of [null, "", "opaque/version?x=1#part", "  v\u00e9rsion  "]
) {
  Deno.test(`canonical attachment acknowledgement preserves opaque version ${JSON.stringify(version)}`, async () => {
    let submits = 0;
    let durable: unknown;
    const f = fixture({
      submit: (row) => {
        submits++;
        assertEquals(row.attachment, { name: canonicalRef.name });
        const data = acknowledgement(row);
        durable = {
          ...data,
          record: [{
            ...data.record[0],
            attachment_ref: { ...canonicalRef, version },
          }],
        };
        return Promise.resolve({ data: durable, error: null });
      },
    });
    const result = await f.run(request({
      ...input,
      image: `${imagePrefix}requests/report%20photo.jpg`,
    }));
    assertEquals(result.status, 200);
    assert(result.body === durable);
    assertEquals(submits, 1);
  });
}
