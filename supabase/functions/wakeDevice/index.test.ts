import assert from "node:assert/strict";

type Handler = (request: Request) => Response | Promise<Response>;
const denial = {
  success: false,
  error: "upgrade_required",
  message: "This legacy endpoint is retired. Update Clean Stream to continue.",
};

async function withoutIO(action: () => Promise<void>) {
  const originalFetch = globalThis.fetch;
  const originalGet = Deno.env.get;
  const originalToObject = Deno.env.toObject;
  const calls: string[] = [];
  const forbidden = (name: string): never => {
    calls.push(name);
    throw new Error("Unexpected " + name);
  };
  globalThis.fetch = () => forbidden("provider/database transport");
  Deno.env.get = () => forbidden("environment/credential read");
  Deno.env.toObject = () => forbidden("environment enumeration");
  try {
    await action();
    assert.deepEqual(calls, []);
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalGet;
    Deno.env.toObject = originalToObject;
  }
}

function assertHeaders(response: Response) {
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.equal(
    response.headers.get("Access-Control-Allow-Headers"),
    "authorization, x-client-info, apikey, content-type",
  );
  assert.equal(
    response.headers.get("Access-Control-Allow-Methods"),
    "POST, OPTIONS",
  );
  assert.equal(response.headers.get("Cache-Control"), "no-store");
}

for (
  const endpoint of [
    "wakeDevice",
    "ping-device",
    "verifyPayment",
    "changePassword",
    "resetToken",
  ]
) {
  let handler: Handler | undefined;
  let registrations = 0;
  const originalServe = Deno.serve;
  try {
    // Exercise each deployed entrypoint without opening a listener.
    Deno.serve = ((registered: Handler) => {
      handler = registered;
      registrations++;
      return {};
    }) as typeof Deno.serve;
    await withoutIO(async () => {
      await import("../" + endpoint + "/index.ts");
    });
  } finally {
    Deno.serve = originalServe;
  }

  Deno.test(
    endpoint + ": import registers once without credentials or IO",
    () => {
      assert.equal(registrations, 1);
      assert(handler);
    },
  );

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
    Deno.test(endpoint + ": method " + JSON.stringify(method), async () => {
      assert(handler);
      const reads: PropertyKey[] = [];
      // Includes synthetic methods the Request constructor disallows.
      const request = new Proxy({ method }, {
        get(target, key) {
          reads.push(key);
          if (key !== "method") {
            throw new Error("Forbidden request access: " + String(key));
          }
          return target.method;
        },
      }) as Request;
      await withoutIO(async () => {
        const response = await handler!(request);
        assertHeaders(response);
        if (method === "OPTIONS") {
          assert.equal(response.status, 200);
          assert.equal(await response.text(), "ok");
        } else {
          assert.equal(response.status, 410);
          assert.equal(
            response.headers.get("Content-Type"),
            "application/json",
          );
          assert.deepEqual(await response.json(), denial);
        }
      });
      assert.deepEqual(reads, ["method"]);
    });
  }

  for (
    const [label, authorization, body] of [
      ["no credentials", "", '{"deviceId":"synthetic-machine"}'],
      ["anonymous", "Bearer synthetic-anon", '{"session_id":"cs_synthetic"}'],
      [
        "privileged",
        "Bearer synthetic-admin",
        '{"code":"synthetic-code","password":"synthetic-password"}',
      ],
      ["malformed JSON", "", "{malformed"],
      ["empty body", "", ""],
    ]
  ) {
    Deno.test(
      endpoint + ": POST " + label + " never consumes body",
      async () => {
        assert(handler);
        const request = new Request("https://synthetic.invalid/" + endpoint, {
          method: "POST",
          headers: { authorization, apikey: "synthetic-public-key" },
          body,
        });
        await withoutIO(async () => {
          const response = await handler!(request);
          assert.equal(response.status, 410);
          assert.deepEqual(await response.json(), denial);
          assert.equal(request.bodyUsed, false);
          assertHeaders(response);
        });
      },
    );
  }
}
