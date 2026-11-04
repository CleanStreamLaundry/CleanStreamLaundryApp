import assert from "node:assert/strict";
import "https://esm.sh/@supabase/supabase-js@2.97.0";

type Handler = (req: Request) => Promise<Response>;
let handler: Handler | undefined;
let registrations = 0;
const originalServe = Deno.serve;
const originalGet = Deno.env.get;
const originalFetch = globalThis.fetch;
try {
  Deno.serve = ((value: Handler) => {
    handler = value;
    registrations++;
    return {};
  }) as typeof Deno.serve;
  Deno.env.get = () => {
    throw new Error("unexpected import environment read");
  };
  globalThis.fetch = () => {
    throw new Error("unexpected import HTTP");
  };
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
  Deno.env.get = originalGet;
  globalThis.fetch = originalFetch;
}

const project = "https://availability.example.invalid";
const selected = "sb_secret_synthetic_availability";
const legacy = "synthetic-legacy-service";
const selector = "CLEANSTREAM_AVAILABILITY_SECRET_KEY_NAME";
const request = (token = "caller-A") =>
  new Request(project, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      apikey: "sb_secret_untrusted_request",
      "x-key-name": "default",
    },
    body: JSON.stringify({ locationId: 7, key_name: "default" }),
  });
type Call = {
  path: string;
  auth: string | null;
  key: string | null;
  body: unknown;
};

async function offline(
  run: (fixture: {
    config: Record<string, string | undefined>;
    calls: Call[];
    reads: string[];
    fail: (path: string, status: number) => void;
    admissions: Call[];
    events: string[];
    admissionReply: (reply: (attempt: number) => Response) => void;
    providerLease: () => void;
    emptyMachines: () => void;
    allowSyntheticProvider: () => void;
  }) => Promise<void>,
) {
  const env = Deno.env.get;
  const transport = globalThis.fetch;
  const config: Record<string, string | undefined> = {
    SUPABASE_URL: project,
    [selector]: "availability",
    SUPABASE_SECRET_KEYS: JSON.stringify({
      availability: selected,
      default: "sb_secret_synthetic_other",
    }),
    SUPABASE_SERVICE_ROLE_KEY: legacy,
    SUPABASE_ANON_KEY: "synthetic-anon-key",
  };
  const calls: Call[] = [];
  const reads: string[] = [];
  const admissions: Call[] = [];
  const events: string[] = [];
  let reply = (_attempt: number) => Response.json({
    subject_id: "aaaaaaaa-0000-4000-8000-000000000001",
    account_access: "eligible", next_step: "home",
  });
  let lease = false;
  let empty = false;
  let syntheticProvider = false;
  let failure: { path: string; status: number } | undefined;
  Deno.env.get = (name) => {
    reads.push(name);
    return config[name];
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    if (url.origin === "https://lynx.nayax.com" && syntheticProvider) {
      // Fake responses only: global fetch is fully replaced, never forwarded.
      assert.equal(req.headers.get("authorization"), "Bearer synthetic-provider-token");
      events.push(url.pathname);
      if (url.pathname.endsWith("/machine")) return Response.json({ MachineID: 77 });
      if (url.pathname.endsWith("/lastAlerts")) return Response.json([]);
      assert(url.pathname.endsWith("/status"));
      return Response.json({ MachineMQTTStatus: true });
    }
    assert.equal(url.origin, project, "provider and external HTTP forbidden");
    const body = req.method === "POST" ? await req.json() : undefined;
    events.push(url.pathname);
    if (url.pathname === "/rest/v1/rpc/get_admission_status") {
      assert.equal(req.headers.get("apikey"), config.SUPABASE_ANON_KEY);
      assert.match(req.headers.get("authorization") ?? "", /^Bearer caller-[AB]$/);
      assert.deepEqual(body, {});
      assert.equal(req.redirect, "error");
      assert(req.signal instanceof AbortSignal);
      assert.equal(req.signal.aborted, false);
      admissions.push({ path: url.pathname, key: req.headers.get("apikey"),
        auth: req.headers.get("authorization"), body });
      return reply(admissions.length);
    }
    calls.push({
      path: url.pathname,
      key: req.headers.get("apikey"),
      auth: req.headers.get("authorization"),
      body,
    });
    if (failure?.path === url.pathname) {
      return Response.json({ message: "synthetic private failure" }, {
        status: failure.status,
      });
    }
    if (url.pathname === "/auth/v1/user") {
      return Response.json({ id: "aaaaaaaa-0000-4000-8000-000000000001" });
    }
    if (url.pathname === "/rest/v1/Machines") {
      assert.equal(url.searchParams.get("Location_ID"), "eq.7");
      assert.equal(
        url.searchParams.get("select"),
        "id,Name,Machine_type,Status,Location_ID",
      );
      return Response.json(empty ? [] : [{
        id: 1,
        Name: "Synthetic",
        Machine_type: "Washer",
        Status: "idle",
        Location_ID: 7,
      }]);
    }
    if (url.pathname === "/rest/v1/cortina_machine_config") {
      if (req.method === "HEAD") {
        assert(lease);
        return new Response(null, { headers: { "content-range": "0-0/1" } });
      }
      assert.equal(url.searchParams.get("machine_id"), "in.(1)");
      assert.equal(url.searchParams.get("is_enabled"), "eq.true");
      return Response.json(lease ? [{ machine_id: 1, nayax_terminal_id: "synthetic-terminal", is_enabled: true }] : []);
    }
    if (url.pathname === "/rest/v1/nayax_availability_state") {
      assert.equal(url.searchParams.get("machine_id"), "in.(1)");
      return Response.json([]);
    }
    if (url.pathname === "/rest/v1/rpc/finish_nayax_availability_sync") {
      assert(syntheticProvider);
      assert.equal(body.p_location_id, 7);
      assert.equal(body.p_states.length, 1);
      return Response.json(null);
    }
    assert.equal(url.pathname, "/rest/v1/rpc/claim_nayax_availability_sync");
    assert.deepEqual(body, { p_location_id: 7 });
    // Denied lease exercises DB reads and RPC without reaching any provider code.
    return Response.json(lease);
  };
  try {
    await run({
      config,
      calls,
      reads,
      admissions,
      events,
      admissionReply: (next) => { reply = next; },
      providerLease: () => { lease = true; config.NAYAX_LYNX_TOKEN = "synthetic-provider-token"; },
      emptyMachines: () => { empty = true; },
      allowSyntheticProvider: () => { syntheticProvider = true; },
      fail: (path, status) => {
        failure = { path, status };
      },
    });
  } finally {
    Deno.env.get = env;
    globalThis.fetch = transport;
  }
}

Deno.test("availability keys: registration does not read credentials or make HTTP calls", () => {
  assert.equal(registrations, 1);
  assert(handler);
});

for (const mode of ["named", "legacy"]) {
  Deno.test(`availability keys: actual SDK ${mode} preserves Auth caller and DB authority`, async () => {
    await offline(async ({ config, calls, reads, admissions }) => {
      if (mode === "legacy") delete config[selector];
      const result = await handler!(request());
      assert.equal(result.status, 200);
      const payload = await result.json();
      assert.equal(payload.configured, false);
      assert.equal(payload.refreshing, true);
      assert.equal(calls.length, 6);
      assert.equal(calls[0].path, "/auth/v1/user");
      assert.equal(calls[0].auth, "Bearer caller-A");
      assert(
        calls.every((call) =>
          call.key === (mode === "named" ? selected : legacy)
        ),
      );
      assert(
        calls.slice(1).every((call) =>
          call.auth === (mode === "named" ? null : `Bearer ${legacy}`)
        ),
      );
      assert(
        !reads.includes(
          mode === "named"
            ? "SUPABASE_SERVICE_ROLE_KEY"
            : "SUPABASE_SECRET_KEYS",
        ),
      );
      assert.equal(reads.filter((name) => name === selector).length, 1);
      assert.equal(admissions.length, 3);
      assert(admissions.every((call) => call.auth === "Bearer caller-A"));
    });
  });
}

Deno.test("availability keys: invalid explicit selector returns sanitized503 before HTTP", async () => {
  await offline(async ({ config, calls, reads }) => {
    for (
      const name of [
        "",
        " availability",
        "availability\n",
        "missing",
        "toString",
      ]
    ) {
      config[selector] = name;
      const req = request();
      const response = await handler!(req);
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: "Unable to check machine availability. Please try again.",
      });
      assert.equal(req.bodyUsed, false);
    }
    assert.equal(calls.length, 0);
    assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  });
});

Deno.test("availability keys: malformed or wrong-kind dictionary fails without fallback", async () => {
  await offline(async ({ config, calls, reads }) => {
    for (
      const dictionary of [
        undefined,
        "{broken",
        "null",
        "[]",
        JSON.stringify({ default: selected }),
        JSON.stringify({ availability: "sb_publishable_synthetic_wrong_kind" }),
        JSON.stringify({ availability: legacy }),
        JSON.stringify({ availability: `${selected}\n` }),
      ]
    ) {
      config.SUPABASE_SECRET_KEYS = dictionary;
      assert.equal((await handler!(request())).status, 503);
    }
    assert.equal(calls.length, 0);
    assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
  });
});

Deno.test("availability keys: removal stops next request; only explicit unset restores legacy", async () => {
  await offline(async ({ config, calls }) => {
    assert.equal((await handler!(request())).status, 200);
    config.SUPABASE_SECRET_KEYS = JSON.stringify({ default: selected });
    assert.equal((await handler!(request())).status, 503);
    assert.equal(calls.length, 6);
    delete config[selector];
    assert.equal((await handler!(request("caller-B"))).status, 200);
    assert.equal(calls.length, 12);
    assert.equal(calls[6].auth, "Bearer caller-B");
    assert(
      calls.slice(7).every((call) =>
        call.key === legacy && call.auth === `Bearer ${legacy}`
      ),
    );
  });
});

for (const path of ["/auth/v1/user", "/rest/v1/Machines"]) {
  Deno.test(`availability keys: rejected ${path} never retries with legacy credentials`, async () => {
    await offline(async ({ fail, calls, reads }) => {
      fail(path, 401);
      const response = await handler!(request());
      assert.equal(response.status, path === "/auth/v1/user" ? 401 : 503);
      assert.equal(calls.length, path === "/auth/v1/user" ? 1 : 2);
      assert(calls.every((call) => call.key === selected));
      assert(!reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
    });
  });
}

Deno.test("availability keys: explicit Auth bearer is not stripped even when equal to selected key", async () => {
  await offline(async ({ fail, calls }) => {
    fail("/auth/v1/user", 401);
    assert.equal((await handler!(request(selected))).status, 401);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].auth, `Bearer ${selected}`);
    assert.equal(calls[0].key, selected);
  });
});

Deno.test("availability keys: preflight methods and missing caller bypass bad configuration", async () => {
  await offline(async ({ config, reads, calls }) => {
    config[selector] = "";
    for (const method of ["OPTIONS", "GET", "DELETE"]) {
      const response = await handler!(new Request(project, { method }));
      assert.equal(response.status, method === "OPTIONS" ? 204 : 405);
      assert.equal(response.headers.get("access-control-allow-origin"), "*");
    }
    const req = request();
    req.headers.delete("authorization");
    assert.equal((await handler!(req)).status, 401);
    assert.equal(req.bodyUsed, false);
    assert.deepEqual(reads, []);
    assert.deepEqual(calls, []);
  });
});

Deno.test("availability keys: body-time mutation does not change Auth caller or promote it to DB", async () => {
  await offline(async ({ calls, admissions }) => {
    const req = request();
    const parse = req.json.bind(req);
    req.json = () => {
      req.headers.set("authorization", "Bearer caller-B");
      return parse();
    };
    assert.equal((await handler!(req)).status, 200);
    assert.equal(calls[0].auth, "Bearer caller-A");
    assert(calls.slice(1).every((call) => call.auth === null));
    assert(admissions.every((call) => call.auth === "Bearer caller-A"));
  });
});

Deno.test("availability keys: overlapping callers remain Auth-only identities", async () => {
  await offline(async ({ calls, admissions }) => {
    const responses = await Promise.all([
      handler!(request("caller-A")),
      handler!(request("caller-B")),
    ]);
    assert(responses.every((response) => response.status === 200));
    assert.deepEqual(
      calls.filter((call) => call.path === "/auth/v1/user").map((call) =>
        call.auth
      ).sort(),
      [
        "Bearer caller-A",
        "Bearer caller-B",
      ],
    );
    const databaseCalls = calls.filter((call) =>
      call.path.startsWith("/rest/v1/")
    );
    assert.equal(databaseCalls.length, 10);
    assert(
      databaseCalls.every((call) =>
        call.auth === null && call.key === selected
      ),
    );
    for (const token of ["caller-A", "caller-B"]) {
      assert.equal(admissions.filter((call) => call.auth === `Bearer ${token}`).length, 3);
    }
  });
});

const allowed = () => ({ subject_id: "aaaaaaaa-0000-4000-8000-000000000001",
  account_access: "eligible", next_step: "home" });
const admissionPath = "/rest/v1/rpc/get_admission_status";

for (const reason of ["pending_deletion", "deletion_expired", "mfa_required", "mfa_recovery_required", "profile_required"]) {
  Deno.test(`availability admission: ${reason} denies before service inventory or lease`, async () => {
    await offline(async ({ calls, events, admissionReply }) => {
      admissionReply(() => Response.json({ ...allowed(), account_access: "restricted", reason }));
      const req = request();
      const response = await handler!(req);
      assert.equal(response.status, 403);
      assert.equal(response.headers.get("cache-control"), "no-store");
      assert.deepEqual(await response.json(), { error: "Account access restricted" });
      assert.equal(req.bodyUsed, true);
      assert.equal(calls.length, 1);
      assert.deepEqual(events, ["/auth/v1/user", admissionPath]);
    });
  });
}

Deno.test("availability admission: eligible preterms account retains availability reads", async () => {
  await offline(async ({ admissions, admissionReply }) => {
    admissionReply(() => Response.json({ ...allowed(), next_step: "review_terms" }));
    assert.equal((await handler!(request())).status, 200);
    assert.equal(admissions.length, 3);
  });
});

Deno.test("availability admission: subject mismatch denies even with eligible server response", async () => {
  await offline(async ({ calls, admissionReply }) => {
    admissionReply(() => Response.json({ ...allowed(), subject_id: "another-subject" }));
    assert.equal((await handler!(request())).status, 401);
    assert.equal(calls.length, 1);
  });
});

Deno.test("availability admission: transport failure is sanitized and cannot reach service reads", async () => {
  await offline(async ({ calls, admissionReply }) => {
    admissionReply(() => { throw new Error("synthetic private timeout details"); });
    const response = await handler!(request());
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: "Unable to check machine availability. Please try again." });
    assert.equal(calls.length, 1);
  });
});

Deno.test("availability admission: removal during inventory wait denies before lease", async () => {
  await offline(async ({ events, admissionReply }) => {
    admissionReply((attempt) => Response.json({ ...allowed(), account_access: attempt === 1 ? "eligible" : "restricted" }));
    assert.equal((await handler!(request())).status, 403);
    assert(!events.includes("/rest/v1/rpc/claim_nayax_availability_sync"));
    assert.equal(events.at(-1), admissionPath);
  });
});

Deno.test("availability admission: removal during lease wait denies before provider dispatch", async () => {
  await offline(async ({ events, admissionReply, providerLease }) => {
    providerLease();
    admissionReply((attempt) => Response.json({ ...allowed(), account_access: attempt < 3 ? "eligible" : "restricted" }));
    const response = await handler!(request());
    assert.equal(response.status, 403);
    assert(events.includes("/rest/v1/rpc/claim_nayax_availability_sync"));
    assert(!events.includes("/rest/v1/rpc/finish_nayax_availability_sync"));
    assert.equal(events.at(-1), admissionPath);
    // The fixture rejects every non-project HTTP call, including provider calls.
  });
});

Deno.test("availability admission: restriction after cached read suppresses response", async () => {
  await offline(async ({ events, admissionReply }) => {
    admissionReply((attempt) => Response.json({ ...allowed(), account_access: attempt < 3 ? "eligible" : "restricted" }));
    const response = await handler!(request());
    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), { error: "Account access restricted" });
    assert.equal(events.at(-2), "/rest/v1/nayax_availability_state");
    assert.equal(events.at(-1), admissionPath);
  });
});

Deno.test("availability admission: empty inventory still rechecks before response", async () => {
  await offline(async ({ admissions, admissionReply, emptyMachines }) => {
    emptyMachines();
    admissionReply((attempt) => Response.json({ ...allowed(), account_access: attempt === 1 ? "eligible" : "restricted" }));
    assert.equal((await handler!(request())).status, 403);
    assert.equal(admissions.length, 2);
  });
});

Deno.test("availability admission: eligible refresh preserves provider/cache path with a check per dispatch", async () => {
  await offline(async ({ events, admissions, providerLease, allowSyntheticProvider }) => {
    providerLease();
    allowSyntheticProvider();
    assert.equal((await handler!(request())).status, 200);
    assert.equal(admissions.length, 6);
    assert.equal(events.filter((path) => path.startsWith("/operational/")).length, 3);
    assert(events.includes("/rest/v1/rpc/finish_nayax_availability_sync"));
    assert.equal(events.at(-1), admissionPath);
  });
});

Deno.test("availability admission: restriction after mapping prevents further provider work and cache commit", async () => {
  await offline(async ({ events, admissionReply, providerLease, allowSyntheticProvider }) => {
    providerLease();
    allowSyntheticProvider();
    admissionReply((attempt) => Response.json({ ...allowed(), account_access: attempt <= 3 ? "eligible" : "restricted" }));
    assert.equal((await handler!(request())).status, 403);
    assert.equal(events.filter((path) => path.startsWith("/operational/")).length, 1);
    assert(!events.includes("/rest/v1/rpc/finish_nayax_availability_sync"));
  });
});
