import assert from "node:assert/strict";
import type { CortinaDeps } from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";

const environments = ["sandbox", "production"] as const;
const routes = ["StaticQR/Sale", "StaticQR/Void", "SaleEndNotification"];
const keys = [
  "NAYAX_CALLBACK_AUTH_TOKEN",
  ...environments.flatMap((env) => [
    `NAYAX_${env.toUpperCase()}_CALLBACK_USERNAME`,
    `NAYAX_${env.toUpperCase()}_CALLBACK_PASSWORD`,
  ]),
];

async function configured(values: Record<string, string>, run: () => Promise<void>) {
  const before = keys.map((key) => Deno.env.get(key));
  try {
    for (const key of keys) {
      if (values[key] === undefined) Deno.env.delete(key);
      else Deno.env.set(key, values[key]);
    }
    await run();
  } finally {
    keys.forEach((key, i) => {
      if (before[i] === undefined) Deno.env.delete(key);
      else Deno.env.set(key, before[i]!);
    });
  }
}

async function check(
  environment: "sandbox" | "production",
  route: string,
  headers: HeadersInit,
  authorized: boolean,
) {
  let dependencyReads = 0;
  const deps = new Proxy({}, {
    get() {
      dependencyReads++;
      throw new Error("Body validation must precede dependencies");
    },
  }) as CortinaDeps;
  const req = new Request(`https://example.invalid/Cortina/${route}`, {
    method: "POST", headers, body: "invalid JSON",
  });
  const response = await handleNayaxCallback(req, environment, deps);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    Status: {
      Verdict: "Declined",
      Code: authorized ? 8 : 5,
      StatusMessage: authorized ? "Invalid JSON body" : "Unauthorized callback",
    },
  });
  assert.equal(req.bodyUsed, authorized);
  assert.equal(dependencyReads, 0);
}

Deno.test("callback declines log only fixed reasons, without credentials or request data", async () => {
  await configured({
    NAYAX_SANDBOX_CALLBACK_USERNAME: "private-test-user",
    NAYAX_SANDBOX_CALLBACK_PASSWORD: "private-test-password",
  }, async () => {
    const messages: unknown[][] = [];
    const previousWarn = console.warn;
    console.warn = (...args: unknown[]) => { messages.push(args); };
    try {
      await check("sandbox", "StaticQR/Sale", {
        username: "untrusted-private-user", password: "untrusted-private-password",
      }, false);
      await check("sandbox", "StaticQR/Sale", {
        username: "private-test-user", password: "private-test-password",
      }, true);
      const deps = new Proxy({}, {
        get() { throw new Error("Missing transaction must not read dependencies"); },
      }) as CortinaDeps;
      const response = await handleNayaxCallback(new Request(
        "https://example.invalid/Cortina/StaticQR/Sale?private=test-marker",
        {
          method: "POST",
          headers: { username: "private-test-user", password: "private-test-password" },
          body: JSON.stringify({ BasicInfo: {}, privateData: "private-body-marker" }),
        },
      ), "sandbox", deps);
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        Status: { Verdict: "Declined", Code: 2, StatusMessage: "Transaction ID unknown" },
      });
      assert.deepEqual(messages, [
        ["Cortina callback authentication rejected", {
          environment: "sandbox", usernameHeaderPresent: true,
          passwordHeaderPresent: true, usernameMatches: false,
          passwordMatches: false, authorizationScheme: "absent",
        }],
        ["Cortina callback declined", { code: 5, reason: "Unauthorized callback" }],
        ["Cortina callback declined", { code: 8, reason: "Invalid JSON body" }],
        ["Cortina callback declined", { code: 2, reason: "Transaction ID unknown" }],
      ]);
    } finally {
      console.warn = previousWarn;
    }
  });
});

Deno.test("callback auth diagnostics distinguish missing and mismatched fields without disclosing values", async () => {
  await configured({
    NAYAX_SANDBOX_CALLBACK_USERNAME: "private-test-user",
    NAYAX_SANDBOX_CALLBACK_PASSWORD: "private-test-password",
  }, async () => {
    const messages: unknown[][] = [];
    const previousWarn = console.warn;
    console.warn = (...args: unknown[]) => { messages.push(args); };
    try {
      await check("sandbox", "StaticQR/Sale", {
        username: "private-test-user", authorization: "Basic private-secret-marker",
      }, false);
      await check("sandbox", "StaticQR/Sale", {
        password: "private-test-password", authorization: "Bearer private-secret-marker",
      }, false);
      await check("sandbox", "StaticQR/Sale", {}, false);
      const diagnostics = messages.filter((entry) => entry[0] === "Cortina callback authentication rejected");
      assert.deepEqual(diagnostics.map((entry) => entry[1]), [
        { environment: "sandbox", usernameHeaderPresent: true, passwordHeaderPresent: false, usernameMatches: true, passwordMatches: false, authorizationScheme: "basic" },
        { environment: "sandbox", usernameHeaderPresent: false, passwordHeaderPresent: true, usernameMatches: false, passwordMatches: true, authorizationScheme: "bearer" },
        { environment: "sandbox", usernameHeaderPresent: false, passwordHeaderPresent: false, usernameMatches: false, passwordMatches: false, authorizationScheme: "absent" },
      ]);
      assert.equal(JSON.stringify(messages).includes("private-"), false);
    } finally {
      console.warn = previousWarn;
    }
  });
});

for (const environment of environments) {
  const prefix = `NAYAX_${environment.toUpperCase()}_CALLBACK`;
  const pair = {
    [`${prefix}_USERNAME`]: "test-user",
    [`${prefix}_PASSWORD`]: "test-password",
  };
  for (const route of routes) {
    Deno.test(`${environment} ${route}: observed Basic transport authorizes the same configured pair`, async () => {
      await configured(pair, async () => {
        const encoded = btoa("test-user:test-password");
        await check(environment, route, { Authorization: `Basic ${encoded}` }, true);
        await check(environment, route, { authorization: `bAsIc ${encoded}` }, true);
        await check(environment, route, { authorization: `Basic ${encoded.replace(/=+$/, "")}` }, true);
      });
    });

    Deno.test(`${environment} ${route}: invalid Basic never bypasses pair or environment checks`, async () => {
      await configured({ ...pair, NAYAX_CALLBACK_AUTH_TOKEN: "old-token" }, async () => {
        const valid = `Basic ${btoa("test-user:test-password")}`;
        const invalid: HeadersInit[] = [
          { authorization: `Basic ${btoa("wrong:test-password")}` },
          { authorization: `Basic ${btoa("test-user:wrong")}` },
          { authorization: `Basic ${btoa("test-usertest-password")}` },
          { authorization: `Basic ${btoa(":test-password")}` },
          { authorization: `Basic ${btoa("test-user:")}` },
          { authorization: `Basic ${btoa("test-user:test-password\u0000")}` },
          { authorization: `Basic ${btoa("test-user:\xff")}` },
          { authorization: "Basic !!!" },
          { authorization: "Basic A" },
          { authorization: `Basic ${btoa("test-user:test-password")}==` },
          { authorization: `Bearer ${btoa("test-user:test-password")}` },
          { authorization: "Basic bad", "x-nayax-auth": "old-token" },
          { authorization: valid, username: "test-user" },
          { authorization: valid, password: "test-password" },
          { authorization: valid, username: "wrong", password: "wrong" },
          [["authorization", valid], ["authorization", valid]],
        ];
        for (const headers of invalid) await check(environment, route, headers, false);
        await check(environment === "sandbox" ? "production" : "sandbox", route, {
          authorization: valid,
        }, false);
      });
    });

    Deno.test(`${environment} ${route}: both provider headers authorize body validation`, async () => {
      await configured(pair, async () => {
        await check(environment, route, { UserName: "test-user", Password: "test-password" }, true);
      });
    });

    Deno.test(`${environment} ${route}: missing, wrong, duplicated or legacy-only headers deny before body`, async () => {
      await configured({ ...pair, NAYAX_CALLBACK_AUTH_TOKEN: "old-token" }, async () => {
        const invalid: HeadersInit[] = [
          {},
          { username: "test-user" },
          { password: "test-password" },
          { username: "wrong", password: "test-password" },
          { username: "test-user", password: "wrong" },
          { username: "TEST-USER", password: "test-password" },
          { username: "test-user", password: "TEST-PASSWORD" },
          [["username", "test-user"], ["username", "wrong"], ["password", "test-password"]],
          [["username", "test-user"], ["password", "test-password"], ["password", "wrong"]],
          { "x-nayax-auth": "old-token" },
          { authorization: "Bearer old-token" },
          { username: "wrong", password: "wrong", "x-nayax-auth": "old-token" },
        ];
        for (const headers of invalid) await check(environment, route, headers, false);
      });
    });

    Deno.test(`${environment} ${route}: incomplete or blank configuration cannot fall back`, async () => {
      const invalid = [
        { [`${prefix}_USERNAME`]: "test-user" },
        { [`${prefix}_PASSWORD`]: "test-password" },
        { ...pair, [`${prefix}_USERNAME`]: "" },
        { ...pair, [`${prefix}_PASSWORD`]: " " },
        { [`${prefix}_USERNAME`]: "", [`${prefix}_PASSWORD`]: "" },
      ];
      for (const values of invalid) {
        await configured({ ...values, NAYAX_CALLBACK_AUTH_TOKEN: "old-token" }, async () => {
          await check(environment, route, {
            username: "test-user", password: "test-password", "x-nayax-auth": "old-token",
          }, false);
          await check(environment, route, {
            authorization: `Basic ${btoa("test-user:test-password")}`,
          }, false);
        });
      }
    });

    Deno.test(`${environment} ${route}: the other environment's credentials cannot authorize`, async () => {
      await configured(pair, async () => {
        await check(environment === "sandbox" ? "production" : "sandbox", route, {
          username: "test-user", password: "test-password",
        }, false);
      });
      await configured({
        ...pair,
        [`NAYAX_${environment === "sandbox" ? "PRODUCTION" : "SANDBOX"}_CALLBACK_USERNAME`]: "other-user",
        [`NAYAX_${environment === "sandbox" ? "PRODUCTION" : "SANDBOX"}_CALLBACK_PASSWORD`]: "other-password",
      }, async () => {
        await check(environment, route, { username: "other-user", password: "other-password" }, false);
        await check(environment, route, { authorization: `Basic ${btoa("other-user:other-password")}` }, false);
        await check(environment, route, { username: "test-user", password: "test-password" }, true);
      });
    });
  }
}

Deno.test("Basic passwords retain colons and rejected Basic credentials stay out of logs", async () => {
  await configured({
    NAYAX_SANDBOX_CALLBACK_USERNAME: "private-test-user",
    NAYAX_SANDBOX_CALLBACK_PASSWORD: "private:password:with:colons",
  }, async () => {
    const messages: unknown[][] = [];
    const previousWarn = console.warn;
    console.warn = (...args: unknown[]) => { messages.push(args); };
    try {
      const valid = btoa("private-test-user:private:password:with:colons");
      const wrong = btoa("private-test-user:private-wrong-password");
      await check("sandbox", "StaticQR/Sale", { authorization: `Basic ${valid}` }, true);
      await check("sandbox", "StaticQR/Sale", { authorization: `Basic ${wrong}` }, false);
      assert.deepEqual(messages.filter((entry) => entry[0] === "Cortina callback authentication rejected"), [
        ["Cortina callback authentication rejected", {
          environment: "sandbox", usernameHeaderPresent: false, passwordHeaderPresent: false,
          usernameMatches: true, passwordMatches: false, authorizationScheme: "basic",
        }],
      ]);
      const logged = JSON.stringify(messages);
      for (const secret of ["private-", "private:password", valid, wrong]) {
        assert.equal(logged.includes(secret), false);
      }
    } finally {
      console.warn = previousWarn;
    }
  });
});
