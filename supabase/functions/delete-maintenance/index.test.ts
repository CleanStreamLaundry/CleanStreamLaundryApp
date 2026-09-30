import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

type Handler = (req: Request) => Response | Promise<Response>;
let registered: Handler | undefined;
let registrations = 0;

async function withoutIO(action: () => Promise<void>) {
  const originalFetch = globalThis.fetch;
  const originalGet = Deno.env.get;
  const originalToObject = Deno.env.toObject;
  const calls: string[] = [];
  const forbidden = (name: string): never => {
    calls.push(name);
    throw new Error(`Unexpected ${name}`);
  };
  globalThis.fetch = () => forbidden("network/database transport");
  Deno.env.get = () => forbidden("environment/credential read");
  Deno.env.toObject = () => forbidden("environment enumeration");
  try {
    await action();
    assertEquals(calls, []);
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalGet;
    Deno.env.toObject = originalToObject;
  }
}

const originalServe = Deno.serve;
try {
  Deno.serve = ((handler: Handler) => {
    registered = handler;
    registrations++;
    return {};
  }) as typeof Deno.serve;
  await withoutIO(async () => {
    await import("./index.ts");
  });
} finally {
  Deno.serve = originalServe;
}

function assertCors(response: Response) {
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

Deno.test("entrypoint registers exactly once without credentials or transport", () => {
  assertEquals(registrations, 1);
  assert(registered);
});

for (
  const method of [
    "OPTIONS",
    "GET",
    "HEAD",
    "POST",
    "PUT",
    "PATCH",
    "DELETE",
    "CONNECT",
    "TRACE",
    "PURGE",
    "options",
    "",
    "UNKNOWN",
  ]
) {
  Deno.test(`${method || "empty method"}: only reads method, never parses or writes`, async () => {
    assert(registered);
    const reads: PropertyKey[] = [];
    // Synthetic methods also cover those the Request constructor disallows.
    const request = new Proxy({ method }, {
      get(target, key) {
        reads.push(key);
        if (key !== "method") {
          throw new Error(`Forbidden request access: ${String(key)}`);
        }
        return target.method;
      },
    }) as Request;
    await withoutIO(async () => {
      const response = await registered!(request);
      assertCors(response);
      if (method === "OPTIONS") {
        assertEquals(response.status, 200);
        assertEquals(await response.text(), "ok");
      } else {
        assertEquals(response.status, 403);
        assertEquals(response.headers.get("Content-Type"), "application/json");
        assertEquals(await response.json(), {
          error: "Maintenance deletion is temporarily unavailable.",
        });
      }
    });
    assertEquals(reads, ["method"]);
  });
}

for (
  const [label, authorization, body] of [
    ["no credentials", "", '{"id":123}'],
    ["synthetic anonymous token", "Bearer synthetic-anon", '{"id":123}'],
    ["synthetic privileged token", "Bearer synthetic-admin", '{"id":123}'],
    ["invalid JSON", "", "{malformed"],
    ["empty body", "", ""],
  ]
) {
  Deno.test(`real POST with ${label} returns identical denial without consuming body`, async () => {
    assert(registered);
    const request = new Request("http://localhost/delete-maintenance", {
      method: "POST",
      headers: { authorization, apikey: "synthetic-public-key" },
      body,
    });
    await withoutIO(async () => {
      const response = await registered!(request);
      assertEquals(response.status, 403);
      assertEquals(await response.json(), {
        error: "Maintenance deletion is temporarily unavailable.",
      });
      assertEquals(request.bodyUsed, false);
      assertCors(response);
    });
  });
}
