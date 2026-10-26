import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
// Initialize the existing SDK's Node compatibility layer before trapping app IO.
import "https://esm.sh/@supabase/supabase-js@2";

type Handler = (req: Request) => Promise<Response>;
let registered: Handler | undefined;
let registrations = 0;
const originalServe = Deno.serve;
const originalGet = Deno.env.get;
const originalFetch = globalThis.fetch;
let importIO = 0;
try {
  Deno.serve = ((handler: Handler) => {
    registered = handler;
    registrations++;
    return {};
  }) as typeof Deno.serve;
  Deno.env.get = () => {
    importIO++;
    throw new Error("environment access during import");
  };
  globalThis.fetch = () => {
    importIO++;
    throw new Error("transport during import");
  };
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
  Deno.env.get = originalGet;
  globalThis.fetch = originalFetch;
}

Deno.test("real entrypoint registers exactly once without environment or transport", () => {
  assertEquals(registrations, 1);
  assertEquals(importIO, 0);
  assert(registered);
});

function assertHeaders(response: Response) {
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(
    response.headers.get("Access-Control-Allow-Headers"),
    "authorization, x-client-info, apikey, content-type",
  );
  assertEquals(
    response.headers.get("Access-Control-Allow-Methods"),
    "POST, OPTIONS",
  );
  assertEquals(response.headers.get("Cache-Control"), "no-store");
}

for (const method of ["OPTIONS", "GET", "HEAD", "PUT", "PATCH", "DELETE"]) {
  Deno.test(`registered ${method} never initializes SDK dependencies or reads body`, async () => {
    assert(registered);
    let io = 0;
    const get = Deno.env.get;
    Deno.env.get = () => {
      io++;
      throw new Error("unexpected credentials");
    };
    try {
      const response = await registered(
        new Proxy({ method }, {
          get(target, key) {
            if (key !== "method") {
              throw new Error(`Unexpected request access ${String(key)}`);
            }
            return target.method;
          },
        }) as Request,
      );
      assertHeaders(response);
      assertEquals(response.status, method === "OPTIONS" ? 200 : 405);
      if (method === "OPTIONS") assertEquals(await response.text(), "ok");
      else {
        assertEquals(response.headers.get("Allow"), "POST, OPTIONS");
        assertEquals(await response.json(), {
          error: "Use POST.",
          code: "method_not_allowed",
        });
      }
      assertEquals(io, 0);
    } finally {
      Deno.env.get = get;
    }
  });
}

Deno.test("registered apikey-only POST is 401 without dependency initialization or body read", async () => {
  assert(registered);
  const req = new Request("http://localhost/maintenance-request", {
    method: "POST",
    headers: { apikey: "synthetic-public-key" },
    body: "{malformed",
  });
  const response = await registered(req);
  assertHeaders(response);
  assertEquals(response.status, 401);
  assertEquals(await response.json(), {
    error: "Sign in to submit a maintenance request.",
    code: "unauthorized",
  });
  assertEquals(req.bodyUsed, false);
});

const userId = "aaaaaaaa-0000-4000-8000-000000000001";
const body = {
  user_id: userId,
  category: "Other",
  description: "Synthetic report",
  location: "No Applicable Location",
  image: null,
};

for (
  const mode of [
    "success",
    "invalid_token",
    "anonymous",
    "unknown_anonymity",
    "auth_unavailable",
    "database_error",
    "empty_ack",
    "cross_user",
    "invalid_body",
    "bearer_key",
    "restricted",
    "with_image",
  ] as const
) {
  Deno.test(`registered handler with real SDK and synthetic transport: ${mode}`, async () => {
    assert(registered);
    const get = Deno.env.get;
    const fetch = globalThis.fetch;
    const calls: string[] = [];
    const envReads: string[] = [];
    let saved: Record<string, unknown> = {};
    let durable: unknown;
    Deno.env.get = (name) => {
      envReads.push(name);
      if (name === "SUPABASE_URL") return "https://supabase.invalid";
      if (name === "CLEANSTREAM_MAINTENANCE_PUBLISHABLE_KEY_NAME") {
        return undefined;
      }
      if (name === "SUPABASE_ANON_KEY") return "synthetic-public-key";
      throw new Error(`Unexpected environment name ${name}`);
    };
    globalThis.fetch =
      (async (input: RequestInfo | URL, init?: RequestInit) => {
        const req = new Request(input, init);
        const url = new URL(req.url);
        assertEquals(url.origin, "https://supabase.invalid");
        calls.push(url.pathname);
        if (url.pathname === "/auth/v1/user") {
          assertEquals(
            req.headers.get("authorization"),
            mode === "bearer_key"
              ? "Bearer synthetic-public-key"
              : "Bearer synthetic-user-token",
          );
          if (mode === "invalid_token" || mode === "bearer_key") {
            return Response.json({ message: "private token error" }, {
              status: 401,
            });
          }
          if (mode === "auth_unavailable") {
            return Response.json({ message: "private outage" }, {
              status: 500,
            });
          }
          return Response.json({
            id: userId,
            ...(mode === "unknown_anonymity"
              ? {}
              : { is_anonymous: mode === "anonymous" }),
          });
        }
        assertEquals(url.pathname, "/rest/v1/rpc/submit_maintenance_request");
        assertEquals(req.method, "POST");
        assertEquals(
          req.headers.get("authorization"),
          "Bearer synthetic-user-token",
        );
        assertEquals(req.headers.get("apikey"), "synthetic-public-key");
        assertEquals(url.search, "");
        saved = await req.json();
        if (mode === "database_error") {
          return Response.json(
            { message: "private SQL detail", code: "23505" },
            { status: 409 },
          );
        }
        if (mode === "restricted") {
          return Response.json({
            code: "PT403",
            message: "private restriction",
          }, { status: 403 });
        }
        const row = saved.p_request as Record<string, unknown>;
        durable = {
          success: true,
          message: "Request logged",
          record: [{
            user_id: userId,
            maint_id: 123,
            category: row.category,
            description: row.description,
            location: row.location,
            location_id: null,
            created_at: "2026-09-30T00:00:00Z",
            image_data: null,
            attachment_ref: mode === "with_image"
              ? {
                bucket: "maintenance-images",
                id: "bbbbbbbb-0000-4000-8000-000000000002",
                name: "requests/1_2.jpg",
                version: null,
              }
              : null,
          }],
        };
        return Response.json(
          mode === "empty_ack" ? [] : durable,
        );
      }) as typeof globalThis.fetch;
    try {
      const req = new Request("http://localhost/maintenance-request", {
        method: "POST",
        headers: {
          authorization: mode === "bearer_key"
            ? "Bearer synthetic-public-key"
            : "Bearer synthetic-user-token",
          apikey: "synthetic-public-key",
        },
        body: mode === "invalid_body" ? "{bad" : JSON.stringify({
          ...body,
          ...(mode === "with_image"
            ? {
              image:
                "https://supabase.invalid/storage/v1/object/public/maintenance-images/requests/1_2.jpg",
            }
            : {}),
          ...(mode === "cross_user"
            ? { user_id: "bbbbbbbb-0000-4000-8000-000000000002" }
            : {}),
        }),
      });
      const response = await registered(req);
      assertHeaders(response);
      assertEquals(envReads, [
        "SUPABASE_URL",
        "CLEANSTREAM_MAINTENANCE_PUBLISHABLE_KEY_NAME",
        "SUPABASE_ANON_KEY",
      ]);
      if (mode === "success" || mode === "with_image") {
        assertEquals(response.status, 200);
        assertEquals(saved, {
          p_request: {
            user_id: userId,
            category: body.category,
            description: body.description,
            location: body.location,
            attachment: mode === "with_image"
              ? { name: "requests/1_2.jpg" }
              : null,
            location_id: null,
          },
        });
        assertEquals(await response.json(), durable);
      } else {
        const expected = mode === "cross_user"
          ? [403, "user_mismatch"]
          : mode === "invalid_body"
          ? [400, "invalid_request"]
          : mode === "restricted"
          ? [403, "account_restricted"]
          : ["database_error", "empty_ack", "auth_unavailable"].includes(mode)
          ? [503, "maintenance_unavailable"]
          : [401, "unauthorized"];
        assertEquals(response.status, expected[0]);
        const data = await response.json();
        assertEquals(data.code, expected[1]);
        assertEquals(Object.keys(data).sort(), ["code", "error"]);
        assert(!JSON.stringify(data).includes("private"));
      }
      const writes = [
        "success",
        "database_error",
        "empty_ack",
        "restricted",
        "with_image",
      ].includes(mode);
      assertEquals(
        calls,
        writes
          ? ["/auth/v1/user", "/rest/v1/rpc/submit_maintenance_request"]
          : ["/auth/v1/user"],
      );
      if (
        [
          "invalid_token",
          "anonymous",
          "unknown_anonymity",
          "auth_unavailable",
          "bearer_key",
        ].includes(mode)
      ) assertEquals(req.bodyUsed, false);
    } finally {
      Deno.env.get = get;
      globalThis.fetch = fetch;
    }
  });
}
