import assert from "node:assert/strict";
import {
  databaseRpc,
  deliverOne,
  type Env,
  type MailConfig,
  type MailJob,
  type Rpc,
} from "./mail.ts";
import { newsletterHandler } from "../newsletter/index.ts";
import { deliveryHandler } from "../mail-delivery/index.ts";

const values: Record<string, string> = {
  SUPABASE_URL: "https://local.example.test",
  CLEANSTREAM_MAIL_PROJECT_URL: "https://local.example.test",
  SUPABASE_ANON_KEY: "synthetic-public",
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
};
const env: Env = (name) => values[name];
const job: MailJob = {
  id: "00000000-0000-4000-8000-000000000001",
  lease_id: "00000000-0000-4000-8000-000000000002",
  kind: "newsletter_confirm",
  email: "synthetic@example.test",
  consent_id: "00000000-0000-4000-8000-000000000003",
};
const config: MailConfig = {
  key: "re_synthetic",
  from: "news@updates.cleanstreamlaundry.com",
  replyTo: "support@cleanstreamlaundry.com",
  postal: "SYNTHETIC ONLY",
  publicUrl: "https://local.example.test/functions/v1/newsletter",
  pageUrl: "https://www.cleanstreamlaundry.com/newsletter",
  tokenSecret: "x".repeat(64),
};

for (const action of ["status", "withdraw"]) {
  Deno.test(`independent: ${action} binds each overlapping caller to its exact bearer`, async () => {
    const calls: {
      auth: string | null;
      key: string | null;
      url: string;
      body: string;
    }[] = [];
    const pending: (() => void)[] = [];
    const transport: typeof fetch = async (input, init) => {
      const request = new Request(input, init);
      const entry = {
        auth: request.headers.get("authorization"),
        key: request.headers.get("apikey"),
        url: request.url,
        body: await request.text(),
      };
      calls.push(entry);
      await new Promise<void>((resolve) => pending.push(resolve));
      return Response.json({ subject_id: entry.auth, state: "not_subscribed" });
    };
    const handler = newsletterHandler(env, databaseRpc(env, transport));
    const send = (bearer: string) =>
      handler(
        new Request("https://local.example.test/functions/v1/newsletter", {
          method: "POST",
          headers: { Authorization: bearer },
          body: JSON.stringify({ action }),
        }),
      );
    const a = send("Bearer actor-A"), b = send("Bearer actor-B");
    while (pending.length < 2) {
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    pending[1]();
    pending[0]();
    assert.equal((await (await a).json()).subject_id, "Bearer actor-A");
    assert.equal((await (await b).json()).subject_id, "Bearer actor-B");
    assert.deepEqual(calls.map((c) => c.key), [
      "synthetic-public",
      "synthetic-public",
    ]);
    assert.deepEqual(calls.map((c) => JSON.parse(c.body)), [{}, {}]);
    assert(calls.every((c) => c.url.endsWith(`/newsletter_${action}`)));
  });
}

Deno.test("independent: prepare acknowledgement loss never dispatches provider or retries", async () => {
  const calls: string[] = [];
  let sends = 0;
  const rpc: Rpc = <T>(name: string) => {
    calls.push(name);
    if (name === "mail_claim") return Promise.resolve(job as T);
    return Promise.reject(new Error("Synthetic prepare acknowledgement lost"));
  };
  await assert.rejects(() =>
    deliverOne(rpc, config, () => {
      sends++;
      return Promise.resolve(Response.json({ id: "provider" }));
    })
  );
  assert.deepEqual(calls, ["mail_claim", "mail_prepare"]);
  assert.equal(sends, 0);
});

for (
  const reply of [
    new Response("not JSON", { status: 200 }),
    Response.json({ id: "" }),
    Response.json(null),
  ]
) {
  Deno.test("independent: malformed provider success is uncertain, with one dispatch", async () => {
    const calls: { name: string; args: Record<string, unknown> | undefined }[] =
      [];
    let sends = 0;
    const rpc: Rpc = <T>(name: string, args?: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve(
        (name === "mail_claim"
          ? job
          : name === "mail_prepare"
          ? true
          : null) as T,
      );
    };
    assert.equal(
      await deliverOne(rpc, config, () => {
        sends++;
        return Promise.resolve(reply);
      }),
      "uncertain",
    );
    assert.equal(sends, 1);
    assert.equal(calls.at(-1)?.args?.p_result, "uncertain");
  });
}

Deno.test("independent: late lost DB finish acknowledgement never causes another provider send", async () => {
  let sends = 0;
  const calls: string[] = [];
  const rpc: Rpc = <T>(name: string) => {
    calls.push(name);
    if (name === "mail_finish") {
      return Promise.reject(new Error("Synthetic finish loss"));
    }
    return Promise.resolve((name === "mail_claim" ? job : true) as T);
  };
  await assert.rejects(() =>
    deliverOne(rpc, config, () => {
      sends++;
      return Promise.resolve(Response.json({ id: "provider-1" }));
    })
  );
  assert.equal(sends, 1);
  assert.deepEqual(calls, ["mail_claim", "mail_prepare", "mail_finish"]);
});

Deno.test("independent: user bearer cannot invoke worker even with enabled-looking request body", async () => {
  let calls = 0, sends = 0;
  const handler = deliveryHandler(
    (name) =>
      name === "CLEANSTREAM_MAIL_WORKER_SECRET" ? "w".repeat(48) : env(name),
    <T>() => {
      calls++;
      return Promise.resolve(null as T);
    },
    () => {
      sends++;
      return Promise.resolve(Response.json({ id: "provider-1" }));
    },
  );
  const response = await handler(
    new Request("https://local.example.test/functions/v1/mail-delivery", {
      method: "POST",
      headers: { Authorization: "Bearer user-session" },
      body: JSON.stringify({ enabled: true, role: "service_role" }),
    }),
  );
  assert.equal(response.status, 401);
  assert.equal(calls, 0);
  assert.equal(sends, 0);
});
