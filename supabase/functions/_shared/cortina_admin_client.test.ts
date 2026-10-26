import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createAdminClient, getOptionalUserId, HttpError } from "./cortina.ts";
import { handler as vend } from "../cortina-vend/index.ts";
import { handler as webhook } from "../stripeWebhook/index.ts";
import { handler as production } from "../nayax-sale-end/index.ts";
import { handler as sandbox } from "../nayax-sale-end-sandbox/index.ts";
import { handler as refund } from "../voluntary-topup-refund/index.ts";

const components = [
  ["cortina-vend", "CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME", vend, 405],
  ["stripeWebhook", "CLEANSTREAM_STRIPE_WEBHOOK_SECRET_KEY_NAME", webhook, 400],
  ["nayax-production", "CLEANSTREAM_NAYAX_PRODUCTION_SECRET_KEY_NAME", production, 200],
  ["nayax-sandbox", "CLEANSTREAM_NAYAX_SANDBOX_SECRET_KEY_NAME", sandbox, 200],
  ["voluntary-topup-refund", "CLEANSTREAM_TOPUP_REFUND_SECRET_KEY_NAME", refund, 405],
] as const;
const secret = "sb_secret_component_fixture";
const legacy = "synthetic-legacy-service-key";
const invalidSelections: [string, string | undefined, string | undefined][] = [
  ["empty name", "", JSON.stringify({ default: secret })],
  ["whitespace name", " component", JSON.stringify({ component: secret })],
  ["missing dictionary", "component", undefined],
  ["malformed dictionary", "component", "{"],
  ["array dictionary", "component", "[]"],
  ["other component only", "component", JSON.stringify({ other: secret, default: secret })],
  ["wrong key kind", "component", JSON.stringify({ component: "sb_publishable_wrong" })],
  ["legacy in named slot", "component", JSON.stringify({ component: legacy })],
  ["prototype name", "toString", "{}"],
];

for (const [component, selector, handler, validStatus] of components) {
  Deno.test(`admin factory ${component}: absent selector cannot adopt a named default when legacy is missing`, () => {
    const reads: string[] = [];
    const error = assertThrows(() => createAdminClient(component, (key) => {
      reads.push(key);
      return key === "SUPABASE_SECRET_KEYS" ? JSON.stringify({ default: secret }) : undefined;
    }), HttpError, "Database key configuration unavailable");
    assertEquals(error.status, 503);
    assertEquals(reads, [selector, "SUPABASE_SERVICE_ROLE_KEY"]);
  });

  for (const named of [false, true]) {
    Deno.test(`admin factory ${component}: ${named ? "named" : "legacy"} RPC and explicit user bearer`, async () => {
      const reads: string[] = [];
      const env: Record<string, string> = {
        SUPABASE_URL: "https://database.invalid",
        SUPABASE_SERVICE_ROLE_KEY: legacy,
        SUPABASE_SECRET_KEYS: JSON.stringify({ component: secret, default: "sb_secret_wrong" }),
        ...(named ? { [selector]: "component" } : {}),
      };
      const originalFetch = globalThis.fetch;
      const calls: { path: string; key: string | null; auth: string | null }[] = [];
      globalThis.fetch = (input, init) => {
        const request = new Request(input, init);
        const path = new URL(request.url).pathname;
        calls.push({ path, key: request.headers.get("apikey"), auth: request.headers.get("Authorization") });
        return Promise.resolve(Response.json(path === "/auth/v1/user" ? { id: "user_fixture" } : true));
      };
      try {
        const admin = createAdminClient(component, (key) => { reads.push(key); return env[key]; });
        const result = await admin.rpc("synthetic_probe", {});
        assertEquals(result.error, null);
        assertEquals(result.data, true);
        assertEquals(await getOptionalUserId(new Request("https://app.invalid", {
          headers: { Authorization: "Bearer captured-user-token" },
        }), admin), "user_fixture");
        // Human verification must not leave its token on later privileged calls.
        await admin.rpc("synthetic_probe", {});
        const key = named ? secret : legacy;
        assertEquals(calls, [
          { path: "/rest/v1/rpc/synthetic_probe", key, auth: named ? null : `Bearer ${legacy}` },
          { path: "/auth/v1/user", key, auth: "Bearer captured-user-token" },
          { path: "/rest/v1/rpc/synthetic_probe", key, auth: named ? null : `Bearer ${legacy}` },
        ]);
        assertEquals(reads, [selector, named ? "SUPABASE_SECRET_KEYS" : "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_URL"]);
      } finally {
        globalThis.fetch = originalFetch;
      }
    });
  }

  for (const [label, selectedName, dictionary] of invalidSelections) {
    Deno.test(`admin factory ${component}: rejects ${label} without legacy fallback or SDK construction`, () => {
      const reads: string[] = [];
      const env: Record<string, string | undefined> = {
        [selector]: selectedName, SUPABASE_SECRET_KEYS: dictionary,
        SUPABASE_SERVICE_ROLE_KEY: legacy,
      };
      const error = assertThrows(() => createAdminClient(component, (key) => {
        reads.push(key);
        if (key === "SUPABASE_URL") throw new Error("SDK construction must not be reached");
        return env[key];
      }), HttpError, "Database key configuration unavailable");
      assertEquals(error.status, 503);
      assertEquals(error.code, "key_configuration_unavailable");
      assertEquals(reads, [selector, "SUPABASE_SECRET_KEYS"]);
    });
  }

  for (const valid of [false, true]) {
    Deno.test(`entrypoint ${component}: fixed selector ${valid ? "ignores other components" : "fails sanitized before HTTP/body/SDK"}`, async () => {
      const env: Record<string, string> = {
        ...Object.fromEntries(components.map(([, name]) => [name, "missing-other-component"])),
        [selector]: valid ? "component" : "",
        SUPABASE_SECRET_KEYS: JSON.stringify({ component: secret, default: secret }),
        SUPABASE_SERVICE_ROLE_KEY: legacy,
        SUPABASE_URL: valid ? "https://database.invalid" : "invalid-url-must-not-be-read-by-SDK",
        SUPABASE_ANON_KEY: "synthetic-public-key",
        STRIPE_SECRET_KEY: valid ? "sk_test_fixture" : "",
      };
      const saved = new Map(Object.keys(env).map((key) => [key, Deno.env.get(key)]));
      const originalFetch = globalThis.fetch;
      const originalError = console.error;
      let httpCalls = 0, bodyReads = 0;
      const logs: string[] = [];
      globalThis.fetch = () => { httpCalls++; throw new Error("Unexpected HTTP"); };
      console.error = (...args) => logs.push(args.map(String).join(" "));
      for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
      try {
        const request = new Request(`https://app.invalid/${component}?secret_key_name=default`);
        if (!valid) {
          request.text = () => { bodyReads++; throw new Error("Unexpected body read"); };
          request.json = () => { bodyReads++; throw new Error("Unexpected body read"); };
        }
        const response = await handler(request);
        assertEquals(response.status, valid ? validStatus : 503);
        const body = await response.text();
        if (!valid) {
          assertEquals(JSON.parse(body), component.startsWith("nayax-")
            ? { Status: { Verdict: "Declined", Code: 999, StatusMessage: "Internal error" } }
            : { error: "Database key configuration unavailable", code: "key_configuration_unavailable" });
        }
        assertEquals(httpCalls, 0);
        assertEquals(bodyReads, 0);
        for (const value of [secret, legacy, "missing-other-component"]) {
          assertEquals((body + logs.join(" ")).includes(value), false);
        }
      } finally {
        globalThis.fetch = originalFetch;
        console.error = originalError;
        for (const [key, value] of saved) {
          if (value === undefined) Deno.env.delete(key);
          else Deno.env.set(key, value);
        }
      }
    });
  }
}
