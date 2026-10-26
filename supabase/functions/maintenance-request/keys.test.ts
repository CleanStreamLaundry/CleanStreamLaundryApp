import assert from "node:assert/strict";
import "https://esm.sh/@supabase/supabase-js@2";

type Handler = (request: Request) => Promise<Response>;
let handler: Handler | undefined;
let registrations = 0;
const originalServe = Deno.serve;
const originalEnv = Deno.env.get;
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
  Deno.env.get = originalEnv;
  globalThis.fetch = originalFetch;
}

const project = "https://maintenance.example.invalid";
const userId = "aaaaaaaa-0000-4000-8000-000000000001";
const selected = "sb_publishable_synthetic_maintenance";
const legacy = "synthetic-legacy-public";
const selector = "CLEANSTREAM_MAINTENANCE_PUBLISHABLE_KEY_NAME";
const body = {
  user_id: userId,
  category: "Other",
  description: "Synthetic maintenance report",
  location: "No Applicable Location",
  image: null,
};
const request = (token = "caller-A") =>
  new Request(project, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      apikey: "sb_secret_untrusted_request",
      "x-key-name": "default",
    },
    body: JSON.stringify({ ...body, key_name: "default" }),
  });
type Call = {
  path: string;
  key: string | null;
  bearer: string | null;
  args: unknown;
};

async function offline(
  run: (fixture: {
    config: Record<string, string | undefined>;
    calls: Call[];
    reads: string[];
    reject: (path: string) => void;
  }) => Promise<void>,
) {
  const get = Deno.env.get;
  const fetch = globalThis.fetch;
  const config: Record<string, string | undefined> = {
    SUPABASE_URL: project,
    SUPABASE_ANON_KEY: legacy,
    [selector]: "maintenance",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      maintenance: selected,
      default: "sb_publishable_synthetic_other",
    }),
  };
  const calls: Call[] = [];
  const reads: string[] = [];
  let rejectedPath = "";
  Deno.env.get = (name) => {
    reads.push(name);
    assert(
      !["SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY"].includes(name),
    );
    return config[name];
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    assert.equal(url.origin, project);
    const args = req.method === "POST" ? await req.json() : undefined;
    calls.push({
      path: url.pathname,
      key: req.headers.get("apikey"),
      bearer: req.headers.get("authorization"),
      args,
    });
    if (url.pathname === rejectedPath) {
      return Response.json({ code: "PT401", message: "private auth failure" }, {
        status: 401,
      });
    }
    if (url.pathname === "/auth/v1/user") {
      return Response.json({ id: userId, is_anonymous: false });
    }
    assert.equal(url.pathname, "/rest/v1/rpc/submit_maintenance_request");
    assert.equal(req.method, "POST");
    assert.deepEqual(args, {
      p_request: {
        user_id: userId,
        category: body.category,
        description: body.description,
        location: body.location,
        location_id: null,
        attachment: null,
      },
    });
    return Response.json({
      success: true,
      message: "Request logged",
      record: [{
        ...args.p_request,
        maint_id: 7,
        created_at: "2026-09-30T00:00:00Z",
        image_data: null,
        attachment_ref: null,
      }],
    });
  };
  try {
    await run({
      config,
      calls,
      reads,
      reject: (path) => {
        rejectedPath = path;
      },
    });
  } finally {
    Deno.env.get = get;
    globalThis.fetch = fetch;
  }
}

Deno.test("maintenance keys: registration still performs no environment or HTTP access", () => {
  assert.equal(registrations, 1);
  assert(handler);
});

for (const mode of ["named", "legacy"]) {
  Deno.test(`maintenance keys: ${mode} keeps caller auth and exact submission contract`, async () => {
    await offline(async ({ config, calls, reads }) => {
      if (mode === "legacy") delete config[selector];
      const result = await handler!(request());
      assert.equal(result.status, 200);
      assert.equal((await result.json()).success, true);
      assert.deepEqual(calls.map((call) => call.path), [
        "/auth/v1/user",
        "/rest/v1/rpc/submit_maintenance_request",
      ]);
      assert(calls.every((call) => call.bearer === "Bearer caller-A"));
      assert(
        calls.every((call) =>
          call.key === (mode === "named" ? selected : legacy)
        ),
      );
      assert(
        !reads.includes(
          mode === "named" ? "SUPABASE_ANON_KEY" : "SUPABASE_PUBLISHABLE_KEYS",
        ),
      );
      assert.equal(reads.filter((name) => name === selector).length, 1);
    });
  });
}

Deno.test("maintenance keys: invalid explicit names fail before HTTP without reading body", async () => {
  await offline(async ({ config, calls, reads }) => {
    for (
      const name of ["", " maintenance", "maintenance\n", "absent", "toString"]
    ) {
      config[selector] = name;
      const req = request();
      const result = await handler!(req);
      assert.equal(result.status, 503);
      assert.deepEqual(await result.json(), {
        code: "maintenance_unavailable",
        error: "Maintenance request unavailable.",
      });
      assert.equal(req.bodyUsed, false);
      assert.equal(result.headers.get("access-control-allow-origin"), "*");
    }
    assert.equal(calls.length, 0);
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
});

Deno.test("maintenance keys: invalid dictionaries and wrong-kind entries never use legacy", async () => {
  await offline(async ({ config, calls, reads }) => {
    for (
      const dictionary of [
        undefined,
        "{broken",
        "null",
        "[]",
        JSON.stringify({ default: selected }),
        JSON.stringify({ maintenance: "sb_secret_synthetic_wrong_kind" }),
        JSON.stringify({ maintenance: `${selected}\n` }),
      ]
    ) {
      config.SUPABASE_PUBLISHABLE_KEYS = dictionary;
      assert.equal((await handler!(request())).status, 503);
    }
    assert.equal(calls.length, 0);
    assert(!reads.includes("SUPABASE_ANON_KEY"));
  });
});

Deno.test("maintenance keys: removal stops calls until explicit legacy rollback", async () => {
  await offline(async ({ config, calls }) => {
    assert.equal((await handler!(request())).status, 200);
    config.SUPABASE_PUBLISHABLE_KEYS = JSON.stringify({ default: selected });
    assert.equal((await handler!(request())).status, 503);
    assert.equal(calls.length, 2);
    delete config[selector];
    assert.equal((await handler!(request("caller-B"))).status, 200);
    assert.equal(calls.length, 4);
    assert(
      calls.slice(2).every((call) =>
        call.key === legacy && call.bearer === "Bearer caller-B"
      ),
    );
  });
});

for (
  const path of ["/auth/v1/user", "/rest/v1/rpc/submit_maintenance_request"]
) {
  Deno.test(`maintenance keys: rejected ${path} never retries with other credentials`, async () => {
    await offline(async ({ calls, reads, reject }) => {
      reject(path);
      const result = await handler!(request());
      assert.equal(result.status, 401);
      assert.equal((await result.json()).code, "unauthorized");
      assert.equal(calls.length, path === "/auth/v1/user" ? 1 : 2);
      assert(calls.every((call) => call.key === selected));
      assert(!reads.includes("SUPABASE_ANON_KEY"));
    });
  });
}

Deno.test("maintenance keys: methods and missing bearer precede bad configuration", async () => {
  await offline(async ({ config, reads, calls }) => {
    config[selector] = "";
    for (const method of ["OPTIONS", "GET", "DELETE"]) {
      const response = await handler!(new Request(project, { method }));
      assert.equal(response.status, method === "OPTIONS" ? 200 : 405);
      assert.equal(response.headers.get("cache-control"), "no-store");
    }
    const req = request();
    req.headers.delete("authorization");
    assert.equal((await handler!(req)).status, 401);
    assert.equal(req.bodyUsed, false);
    assert.deepEqual(reads, []);
    assert.deepEqual(calls, []);
  });
});

Deno.test("maintenance keys: body-time header mutation cannot rebind the captured bearer", async () => {
  await offline(async ({ calls }) => {
    const req = request();
    const stream = req.body!;
    const read = stream.getReader.bind(stream);
    stream.getReader = (() => {
      req.headers.set("authorization", "Bearer caller-B");
      return read();
    }) as typeof stream.getReader;
    assert.equal((await handler!(req)).status, 200);
    assert.equal(calls.length, 2);
    assert(calls.every((call) => call.bearer === "Bearer caller-A"));
  });
});

Deno.test("maintenance keys: overlapping submissions keep their own caller", async () => {
  await offline(async ({ calls }) => {
    const responses = await Promise.all([
      handler!(request("caller-A")),
      handler!(request("caller-B")),
    ]);
    assert(responses.every((response) => response.status === 200));
    for (const bearer of ["Bearer caller-A", "Bearer caller-B"]) {
      assert.deepEqual(
        calls.filter((call) => call.bearer === bearer).map((call) => call.path),
        [
          "/auth/v1/user",
          "/rest/v1/rpc/submit_maintenance_request",
        ],
      );
    }
    assert.equal(calls.length, 4);
  });
});

Deno.test("maintenance keys: invalid project configuration stays inside existing 503 guard", async () => {
  await offline(async ({ config, calls }) => {
    config.SUPABASE_URL = "not-a-url";
    const result = await handler!(request());
    assert.equal(result.status, 503);
    assert.equal((await result.json()).code, "maintenance_unavailable");
    assert.equal(calls.length, 0);
  });
});
