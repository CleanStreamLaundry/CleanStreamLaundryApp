import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { CortinaDeps } from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";

const key = "NAYAX_CALLBACK_AUTH_TOKEN";
const forbiddenDeps = new Proxy({}, {
  get() {
    throw new Error("Unauthorized callback accessed dependencies");
  },
}) as CortinaDeps;

for (const environment of ["sandbox", "production"] as const) {
  for (
    const route of ["StaticQR/Sale", "StaticQR/Void", "SaleEndNotification"]
  ) {
    Deno.test(`${environment} ${route} rejects missing/blank configuration before parsing or effects`, async () => {
      const previous = Deno.env.get(key);
      try {
        for (const secret of [undefined, "", "   "]) {
          if (secret === undefined) Deno.env.delete(key);
          else Deno.env.set(key, secret);
          const response = await handleNayaxCallback(
            new Request(
              `https://example.invalid/Cortina/${route}`,
              {
                method: "POST",
                headers: { "x-nayax-auth": "arbitrary" },
                body: "invalid json",
              },
            ),
            environment,
            forbiddenDeps,
          );
          assertEquals((await response.json()).Status, {
            Verdict: "Declined",
            Code: 5,
            StatusMessage: "Unauthorized callback",
          });
        }
      } finally {
        if (previous === undefined) Deno.env.delete(key);
        else Deno.env.set(key, previous);
      }
    });
  }
}

const invalidHeaders: Record<string, string>[] = [
  {},
  { "x-nayax-auth": "wrong" },
  { authorization: "Bearer wrong" },
  { "x-nayax-auth": "wrong", authorization: "Bearer test-secret" },
];
for (const headers of invalidHeaders) {
  Deno.test(`rejects absent or incorrect callback credential ${JSON.stringify(headers)}`, async () => {
    const previous = Deno.env.get(key);
    Deno.env.set(key, "test-secret");
    try {
      const response = await handleNayaxCallback(
        new Request("https://example.invalid/Cortina/StaticQR/Sale", {
          method: "POST",
          headers,
          body: "invalid json",
        }),
        "production",
        forbiddenDeps,
      );
      assertEquals(
        (await response.json()).Status.StatusMessage,
        "Unauthorized callback",
      );
    } finally {
      if (previous === undefined) Deno.env.delete(key);
      else Deno.env.set(key, previous);
    }
  });
}

const validHeaders: Record<string, string>[] = [
  { "x-nayax-auth": "test-secret" },
  { authorization: "Bearer test-secret" },
];
for (const headers of validHeaders) {
  Deno.test(`configured credential reaches normal body validation ${JSON.stringify(headers)}`, async () => {
    const previous = Deno.env.get(key);
    Deno.env.set(key, "test-secret");
    try {
      const response = await handleNayaxCallback(
        new Request("https://example.invalid/Cortina/StaticQR/Sale", {
          method: "POST",
          headers,
          body: "invalid json",
        }),
        "production",
        forbiddenDeps,
      );
      assertEquals(
        (await response.json()).Status.StatusMessage,
        "Invalid JSON body",
      );
    } finally {
      if (previous === undefined) Deno.env.delete(key);
      else Deno.env.set(key, previous);
    }
  });
}
