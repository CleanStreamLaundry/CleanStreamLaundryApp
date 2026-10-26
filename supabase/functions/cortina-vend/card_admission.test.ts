import assert from "node:assert/strict";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import { CortinaDeps, HttpError } from "../_shared/cortina.ts";
import { resolveCardCaller } from "./card_admission.ts";
import { handleCard } from "./logic.ts";

const owner = "00000000-0000-4000-8000-000000000003";
const sessionId = "00000000-0000-4000-8000-000000000001";
const requestId = "00000000-0000-4000-8000-000000000002";
const values: Record<string, string> = { SUPABASE_URL: "https://database.synthetic.invalid",
  SUPABASE_ANON_KEY: "legacy-public-key", CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME: "vend",
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ vend: "sb_publishable_vend", other: "sb_publishable_other" }),
  CLEANSTREAM_FUNDING_PUBLISHABLE_KEY_NAME: "other" };
const eligible = { subject_id: owner, account_access: "eligible", next_step: "home" };
const env = (key: string) => values[key];
function isError(status: number, code: string) {
  return (error: unknown) => {
    assert(error instanceof HttpError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    assert.equal(error.message, code);
    return true;
  };
}

function fixture(options: { authError?: unknown; noUser?: boolean; authThrow?: boolean;
  payload?: unknown; status?: number; transportThrow?: boolean } = {}) {
  const auth: string[] = [];
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const admin = { auth: { getUser(token: string) {
    auth.push(token);
    if (options.authThrow) throw new Error("secret external message");
    return Promise.resolve({ data: { user: options.noUser ? null : { id: owner, is_anonymous: false } }, error: options.authError ?? null });
  } } } as unknown as CortinaDeps["admin"];
  const transport = ((url: string | URL | Request, init: RequestInit) => {
    assert.equal(String(url), "https://database.synthetic.invalid/rest/v1/rpc/get_admission_status");
    calls.push({ url: String(url), init });
    if (options.transportThrow) throw new Error("secret transport detail");
    return Promise.resolve(Response.json(options.payload === undefined ? eligible : options.payload, { status: options.status ?? 200 }));
  }) as typeof fetch;
  return { admin, transport, auth, calls };
}

Deno.test("genuine guest accepts only absent header or exact selected public key", async () => {
  for (const [authorization, read] of [[null, env], ["Bearer sb_publishable_vend", env],
    ["Bearer legacy-public-key", (key: string) => key === "CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME" ? undefined : env(key)]] as const) {
    const f = fixture();
    const caller = await resolveCardCaller(authorization, f.admin, read, f.transport);
    assert.equal(caller.userId, null);
    await caller.requireAdmission();
    assert.deepEqual(f.auth, []);
    assert.deepEqual(f.calls, []);
  }
});

Deno.test("real SDK guest client keys resolve without user Auth while signed-in callers retain admission", async () => {
  const read = (key: string) => key === "CLEANSTREAM_VEND_GUEST_PUBLISHABLE_KEY_NAMES"
    ? '["web","app"]'
    : key === "SUPABASE_PUBLISHABLE_KEYS"
    ? JSON.stringify({ vend: "sb_publishable_vend", web: "sb_publishable_web", app: "sb_publishable_app" })
    : env(key);
  for (const key of ["sb_publishable_web", "sb_publishable_app"]) {
    const f = fixture();
    const sdk = createClient(values.SUPABASE_URL, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: async (input, init) => {
        const request = new Request(input, init);
        assert.equal(request.headers.get("apikey"), key);
        const caller = await resolveCardCaller(request.headers.get("authorization"), f.admin, read, f.transport);
        await caller.requireAdmission();
        return Response.json({ userId: caller.userId });
      } },
    });
    const guest = await sdk.functions.invoke("cortina-vend/card", { body: {} });
    assert.equal(guest.error, null);
    assert.deepEqual(guest.data, { userId: null });
    assert.equal(f.auth.length, 0);
    assert.equal(f.calls.length, 0);
    const human = await sdk.functions.invoke("cortina-vend/card", {
      body: {}, headers: { Authorization: "Bearer original-token" },
    });
    assert.equal(human.error, null);
    assert.deepEqual(human.data, { userId: owner });
    assert.deepEqual(f.auth, ["original-token"]);
    assert.equal(new Headers(f.calls[0].init.headers).get("apikey"), "sb_publishable_vend");
    assert.equal(new Headers(f.calls[0].init.headers).get("authorization"), "Bearer original-token");
  }
});

Deno.test("guest key configuration fails closed for invalid or removed names, including partial matches", async () => {
  for (const configured of ["", "{bad", "{}", "null", '[1]', '["missing"]', '["other","missing"]', '[" other"]', '["toString"]']) {
    const f = fixture();
    const read = (key: string) => key === "CLEANSTREAM_VEND_GUEST_PUBLISHABLE_KEY_NAMES" ? configured : env(key);
    await assert.rejects(() => resolveCardCaller("Bearer sb_publishable_other", f.admin, read, f.transport), isError(503, "admission_unavailable"));
    assert.deepEqual(f.auth, []);
    assert.deepEqual(f.calls, []);
  }
});

Deno.test("configured guest keys never turn unknown, secret, or invalid human credentials into guests", async () => {
  const read = (key: string) => key === "CLEANSTREAM_VEND_GUEST_PUBLISHABLE_KEY_NAMES" ? '["other"]' : env(key);
  for (const token of ["sb_publishable_unknown", "sb_secret_other", "invalid-jwt", "legacy-public-key"]) {
    const f = fixture({ authError: { status: 401, name: "AuthApiError" } });
    await assert.rejects(() => resolveCardCaller(`Bearer ${token}`, f.admin, read, f.transport), isError(401, "session_invalid"));
    assert.deepEqual(f.auth, [token]);
    assert.deepEqual(f.calls, []);
  }
  const f = fixture();
  const removed = (key: string) => key === "SUPABASE_PUBLISHABLE_KEYS" ? '{"vend":"sb_publishable_vend"}' : read(key);
  await assert.rejects(() => resolveCardCaller("Bearer sb_publishable_other", f.admin, removed, f.transport), isError(503, "admission_unavailable"));
  assert.deepEqual(f.auth, []);
});

Deno.test("malformed explicit Authorization is never downgraded to guest", async () => {
  for (const authorization of ["", "Basic token", "Bearer", "Bearer ", "Bearer a b", "Bearer  token"]) {
    const f = fixture();
    await assert.rejects(() => resolveCardCaller(authorization, f.admin, env, f.transport), isError(401, "session_invalid"));
    assert.deepEqual(f.auth, []);
    assert.deepEqual(f.calls, []);
  }
});

Deno.test("unselected public-looking and invalid human tokens must undergo explicit Auth verification", async () => {
  for (const token of ["sb_publishable_other", "sb_publishable_unknown", "legacy-public-key", "invalid-jwt"]) {
    const f = fixture({ authError: { status: 401, name: "AuthApiError" } });
    await assert.rejects(() => resolveCardCaller(`Bearer ${token}`, f.admin, env, f.transport), isError(401, "session_invalid"));
    assert.deepEqual(f.auth, [token]);
    assert.deepEqual(f.calls, []);
  }
});

Deno.test("invalid named public configuration fails closed before SDK or HTTP, without legacy fallback", async () => {
  for (const name of ["", "missing", " vend "]) {
    const f = fixture();
    await assert.rejects(() => resolveCardCaller("Bearer legacy-public-key", f.admin,
      (key) => key === "CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME" ? name : env(key), f.transport), isError(503, "admission_unavailable"));
    assert.deepEqual(f.auth, []);
    assert.deepEqual(f.calls, []);
  }
});

Deno.test("transient returned or thrown Auth errors sanitize503 rather than becoming guests", async () => {
  for (const options of [{ authThrow: true }, ...[0, 429, 500, 503].map((status) => ({ authError: { status } })),
    { authError: { name: "AuthRetryableFetchError", status: 400 } }]) {
    const f = fixture(options);
    await assert.rejects(() => resolveCardCaller("Bearer original-token", f.admin, env, f.transport), isError(503, "admission_unavailable"));
    assert.deepEqual(f.calls, []);
  }
});

Deno.test("empty verified identity is denied instead of creating a guest payment", async () => {
  const f = fixture({ noUser: true });
  await assert.rejects(() => resolveCardCaller("Bearer original-token", f.admin, env, f.transport), isError(401, "session_invalid"));
});

Deno.test("verified human reuses exact caller bearer and VEND public-key mapping for canonical admission", async () => {
  const f = fixture();
  const caller = await resolveCardCaller("bEaReR original-token", f.admin, env, f.transport);
  assert.equal(caller.userId, owner);
  assert.deepEqual(f.auth, ["original-token"]);
  assert.equal(f.calls.length, 0, "funded replay can return before creation-only admission");
  await caller.requireAdmission();
  assert.equal(f.calls.length, 1);
  const call = f.calls[0];
  assert.equal(call.url, "https://database.synthetic.invalid/rest/v1/rpc/get_admission_status");
  const headers = new Headers(call.init.headers);
  assert.equal(headers.get("Authorization"), "bEaReR original-token");
  assert.equal(headers.get("apikey"), "sb_publishable_vend");
  assert.equal(call.init.method, "POST");
  assert.equal(call.init.body, "{}");
  assert.equal(call.init.redirect, "error");
  assert(call.init.signal instanceof AbortSignal);
});

Deno.test("admission RPC status preserves401/403 and sanitizes other upstream errors503", async () => {
  for (const status of [401, 403, 429, 500, 503]) {
    const f = fixture({ status });
    const caller = await resolveCardCaller("Bearer original-token", f.admin, env, f.transport);
    const expected = status === 401 ? 401 : status === 403 ? 403 : 503;
    await assert.rejects(caller.requireAdmission, isError(expected,
      expected === 401 ? "session_invalid" : expected === 403 ? "account_restricted" : "admission_unavailable"));
  }
});

Deno.test("admission must match the verified subject, never another account", async () => {
  const f = fixture({ payload: { ...eligible, subject_id: "different-owner" } });
  const caller = await resolveCardCaller("Bearer original-token", f.admin, env, f.transport);
  await assert.rejects(caller.requireAdmission, isError(401, "session_invalid"));
});

Deno.test("canonical restricted or incomplete onboarding admission cannot create new charges", async () => {
  for (const payload of [{ ...eligible, account_access: "restricted" }, { ...eligible, next_step: "consent" }]) {
    const f = fixture({ payload });
    const caller = await resolveCardCaller("Bearer original-token", f.admin, env, f.transport);
    await assert.rejects(caller.requireAdmission, isError(403, "account_restricted"));
  }
});

Deno.test("malformed admission stays unavailable without permissive defaults", async () => {
  for (const payload of [null, [], {}, { subject_id: owner }, { ...eligible, next_step: null }]) {
    const f = fixture({ payload });
    const caller = await resolveCardCaller("Bearer original-token", f.admin, env, f.transport);
    await assert.rejects(caller.requireAdmission, isError(503, "admission_unavailable"));
  }
});

Deno.test("admission transport exceptions never authorize a new charge", async () => {
  const f = fixture({ transportThrow: true });
  const caller = await resolveCardCaller("Bearer original-token", f.admin, env, f.transport);
  await assert.rejects(caller.requireAdmission, isError(503, "admission_unavailable"));
});

function routeFixture(options: { status?: string; restricted?: boolean; invalid?: boolean; shutdown?: boolean } = {}) {
  const f = fixture({ payload: options.restricted ? { ...eligible, account_access: "restricted" } : eligible,
    authError: options.invalid ? { status: 401 } : undefined });
  const inserts: Record<string, unknown>[] = [], updates: Record<string, unknown>[] = [];
  const charges: unknown[] = [];
  const row = { id: sessionId, user_id: owner, machine_id: 1, amount_cents: 400, dryer_minutes: null,
    payment_method: "card", channel: "app", status: options.status ?? "payment_pending", currency: "USD",
    product_code: null, pulse_line_number: 1, nayax_environment: "sandbox",
    nayax_terminal_id: "4434331126150568", stripe_livemode: false };
  const admin = Object.assign(f.admin, {
    from(table: string) {
      let insert: Record<string, unknown> | undefined, update: Record<string, unknown> | undefined;
      const run = () => {
        if (table === "cortina_machine_config") return { data: { machine_id: 1, public_machine_token: "public-qr",
          is_enabled: true, review_required: false, product_codes: null, pulse_line_number: 1 }, error: null };
        if (table === "Machines") return { data: { id: 1, Name: "Washer", Machine_type: "washer", Status: "Idle",
          Location_ID: 1, washer_size_rate_id: 1, is_out_of_service: false }, error: null };
        if (table === "washer_size_rates") return { data: { id: 1, size_label: "12kg", price_cents: 400,
          is_active: true, review_required: false }, error: null };
        assert.equal(table, "cortina_vend_sessions");
        if (insert) {
          inserts.push(insert);
          if (options.status) return { data: null, error: { code: "23505" } };
          Object.assign(row, insert);
        }
        if (update) { updates.push(update); Object.assign(row, update); }
        return { data: row, error: null };
      };
      const q = { select: (_columns: string) => q, eq: (_column: string, _value: unknown) => q,
        insert: (value: Record<string, unknown>) => { insert = value; return q; },
        update: (value: Record<string, unknown>) => { update = value; return q; },
        single: () => Promise.resolve(run()), maybeSingle: () => Promise.resolve(run()),
        then: <T, U>(resolve?: ((value: ReturnType<typeof run>) => T | PromiseLike<T>) | null,
          reject?: ((reason: unknown) => U | PromiseLike<U>) | null) => Promise.resolve(run()).then(resolve, reject) };
      return q;
    },
    rpc(name: string, args?: Record<string, unknown>) {
      if (name === "consume_cortina_request_capacity") {
        assert.deepEqual(args, { p_bucket: "card" });
        return { abortSignal: (_signal: AbortSignal) => Promise.resolve({
          data: { allowed: true, retry_after_seconds: 0 }, error: null,
        }) };
      }
      assert.equal(name, "new_payments_enabled");
      return { abortSignal: (_signal: AbortSignal) => Promise.resolve({ data: !options.shutdown, error: null }) }; },
  });
  const deps = { admin, fetcher: f.transport, stripe: { paymentIntents: { create(params: unknown, options: unknown) {
    charges.push({ params, options });
    return Promise.resolve({ id: "pi_synthetic", client_secret: "synthetic", livemode: false });
  } } } } as unknown as CortinaDeps;
  return { ...f, deps, inserts, updates, charges, row };
}

async function withEnv(action: () => Promise<void>) {
  const get = Deno.env.get;
  Deno.env.get = env;
  try { await action(); } finally { Deno.env.get = get; }
}
function request(authorization: string | null = "Bearer original-token") {
  return new Request("https://edge.synthetic.invalid/cortina-vend/card", { method: "POST",
    headers: authorization === null ? {} : { Authorization: authorization },
    body: JSON.stringify({ channel: "app", machineToken: "public-qr", amountCents: 400, clientRequestId: requestId,
      userId: "forged-body-owner" }) });
}

Deno.test("card handler refuses invalid bearer before draft insertion or Stripe instead of making a guest", async () => {
  await withEnv(async () => {
    const f = routeFixture({ invalid: true });
    await assert.rejects(() => handleCard(request(), f.deps), isError(401, "session_invalid"));
    assert.deepEqual(f.inserts, []);
    assert.deepEqual(f.charges, []);
    assert.deepEqual(f.updates, []);
  });
});

Deno.test("card handler admission refusal preserves pending draft and never enters compensation catch", async () => {
  await withEnv(async () => {
    const f = routeFixture({ restricted: true });
    await assert.rejects(() => handleCard(request(), f.deps), isError(403, "account_restricted"));
    assert.equal(f.inserts.length, 1);
    assert.equal(f.row.status, "payment_pending");
    assert.deepEqual(f.charges, []);
    assert.deepEqual(f.updates, []);
  });
});

Deno.test("already-funded card replay bypasses creation-only admission and all provider writes", async () => {
  await withEnv(async () => {
    for (const status of ["paid", "started", "support_required", "refunded"]) {
      const f = routeFixture({ status, restricted: true });
      const response = await handleCard(request(), f.deps);
      assert.deepEqual(await response.json(), { sessionId, accessToken: requestId, status });
      assert.deepEqual(f.calls, []);
      assert.deepEqual(f.charges, []);
      assert.deepEqual(f.updates, []);
    }
  });
});

Deno.test("new card uses captured caller despite header mutation during body read and ignores body owner", async () => {
  await withEnv(async () => {
    const f = routeFixture();
    const req = request();
    const stream = req.body;
    assert(stream);
    const read = stream.getReader.bind(stream);
    stream.getReader = (() => {
      req.headers.set("Authorization", "Bearer switched-token");
      return read();
    }) as typeof stream.getReader;
    await handleCard(req, f.deps);
    assert.deepEqual(f.auth, ["original-token"]);
    assert.equal(new Headers(f.calls[0].init.headers).get("Authorization"), "Bearer original-token");
    assert.deepEqual(f.calls.map((call) => new Headers(call.init.headers).get("Authorization")),
      ["Bearer original-token", "Bearer original-token"]);
    assert.equal(f.inserts[0].user_id, owner);
    assert.equal(f.charges.length, 1);
    assert.deepEqual(f.updates, [{ stripe_payment_intent_id: "pi_synthetic" }]);
  });
});

Deno.test("genuine guest card creation retains current payment contract without human admission", async () => {
  await withEnv(async () => {
    for (const authorization of [null, "Bearer sb_publishable_vend"]) {
      const f = routeFixture();
      await handleCard(request(authorization), f.deps);
      assert.equal(f.inserts[0].user_id, null);
      assert.deepEqual(f.auth, []);
      assert.deepEqual(f.calls, []);
      assert.equal(f.charges.length, 1);
    }
  });
});

Deno.test("global new-payment shutdown still denies before admission HTTP or Stripe", async () => {
  await withEnv(async () => {
    const f = routeFixture({ shutdown: true });
    await assert.rejects(() => handleCard(request(), f.deps), isError(503, "new_payments_unavailable"));
    assert.deepEqual(f.calls, []);
    assert.deepEqual(f.charges, []);
    assert.deepEqual(f.updates, []);
  });
});
