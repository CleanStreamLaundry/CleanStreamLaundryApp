import assert from "node:assert/strict";
import { CortinaDeps, createAdminClient, HttpError, sha256 } from "../_shared/cortina.ts";
import { cortinaPublicError } from "./public_controls.ts";
import { CORTINA_CAPACITY_TIMEOUT_MS, cortinaRequestCapacity } from "./request_limits.ts";
import { handleCortinaVend } from "./logic.ts";

const allowed = { allowed: true, retry_after_seconds: 0 };
const denied = { allowed: false, retry_after_seconds: 6 };
const sessionId = "00000000-0000-4000-8000-000000000001";
const requestId = "00000000-0000-4000-8000-000000000002";
const owner = "00000000-0000-4000-8000-000000000003";

function unavailable(error: unknown) {
  assert(error instanceof HttpError);
  assert.equal(error.status, 503);
  assert.equal(error.code, "capacity_unavailable");
  assert.equal(error.message, "Cortina capacity unavailable");
  return true;
}

function capacityClient(data: unknown = allowed, error: unknown = null) {
  const calls: Array<{ name: string; args: unknown; signal?: AbortSignal }> = [];
  return { calls, rpc(name: string, args: unknown) {
    const call: typeof calls[number] = { name, args };
    calls.push(call);
    return { abortSignal(signal: AbortSignal) {
      call.signal = signal;
      return Promise.resolve({ data, error });
    } };
  } };
}

Deno.test("capacity helper uses only fixed bucket argument and the existing SDK abort signal", async () => {
  for (const bucket of ["quote", "card", "status"] as const) {
    const f = capacityClient();
    assert.equal(await cortinaRequestCapacity(f, bucket), null);
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].name, "consume_cortina_request_capacity");
    assert.deepEqual(f.calls[0].args, { p_bucket: bucket });
    assert(f.calls[0].signal instanceof AbortSignal);
    assert.equal(f.calls[0].signal.aborted, false);
    assert.equal(CORTINA_CAPACITY_TIMEOUT_MS, 2000);
  }
});

Deno.test("exhaustion returns sanitized429 with exposed Retry-After and no-store", async () => {
  const response = await cortinaRequestCapacity(capacityClient(denied), "card");
  assert(response);
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "6");
  assert.equal(response.headers.get("Access-Control-Expose-Headers"), "Retry-After");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(response.headers.get("Referrer-Policy"), "no-referrer");
  assert.deepEqual(await response.json(), { error: "Cortina request capacity exceeded", code: "capacity_exceeded" });
});

Deno.test("malformed, empty or inconsistent RPC decisions fail closed", async () => {
  for (const data of [null, [], {}, "true", { allowed: "true", retry_after_seconds: 0 },
    { allowed: true }, { allowed: true, retry_after_seconds: 1 }, { allowed: false, retry_after_seconds: 0 },
    { allowed: false, retry_after_seconds: "6" }, { allowed: false, retry_after_seconds: 7 },
    { allowed: false, retry_after_seconds: 0.5 }, { allowed: false, retry_after_seconds: NaN }]) {
    await assert.rejects(() => cortinaRequestCapacity(capacityClient(data), "card"), unavailable);
  }
});

Deno.test("missing schema, lock contention or upstream error cannot fail open or leak diagnostics", async () => {
  for (const code of ["PGRST202", "42P01", "55P03", "55000", "57014"]) {
    await assert.rejects(() => cortinaRequestCapacity(capacityClient(allowed,
      { code, message: `secret:${requestId}` }), "status"), (error) => {
      unavailable(error);
      const response = cortinaPublicError(error);
      assert.equal(response.status, 503);
      assert.equal(response.headers.get("Retry-After"), null);
      return true;
    });
  }
});

Deno.test("synchronous SDK and asynchronous transport failures both sanitize503", async () => {
  const sync = { rpc(): never { throw new Error(`secret:${requestId}`); } };
  const asyncClient = { rpc() { return { abortSignal: () => Promise.reject(new Error(`secret:${requestId}`)) }; } };
  for (const client of [sync, asyncClient]) {
    await assert.rejects(() => cortinaRequestCapacity(client, "quote"), unavailable);
  }
});

async function sdkFixture(
  transport: typeof fetch,
  action: (admin: CortinaDeps["admin"]) => Promise<void>,
) {
  const originalFetch = globalThis.fetch;
  const values: Record<string, string> = { SUPABASE_URL: "https://database.synthetic.invalid",
    CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME: "vend",
    SUPABASE_SECRET_KEYS: JSON.stringify({ vend: "sb_secret_synthetic_vend" }) };
  globalThis.fetch = transport;
  try { await action(createAdminClient("cortina-vend", (key) => values[key])); }
  finally { globalThis.fetch = originalFetch; }
}

Deno.test("real SDK uses existing component secret apikey-only and one bounded capacity RPC", async () => {
  const calls: unknown[] = [];
  await sdkFixture(((_url: RequestInfo | URL, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    assert.equal(String(_url), "https://database.synthetic.invalid/rest/v1/rpc/consume_cortina_request_capacity");
    assert.equal(init?.method, "POST");
    assert.equal(headers.get("apikey"), "sb_secret_synthetic_vend");
    assert.equal(headers.get("Authorization"), null);
    assert(init?.signal instanceof AbortSignal);
    calls.push(JSON.parse(String(init.body)));
    return Promise.resolve(Response.json(allowed));
  }) as typeof fetch, async (admin) => {
    assert.equal(await cortinaRequestCapacity(admin, "quote"), null);
    assert.deepEqual(calls, [{ p_bucket: "quote" }]);
  });
});

Deno.test("real SDK denial remains429 rather than a provider or database failure", async () => {
  let calls = 0;
  await sdkFixture((() => { calls++; return Promise.resolve(Response.json(denied)); }) as typeof fetch,
    async (admin) => {
      const response = await cortinaRequestCapacity(admin, "card");
      assert.equal(response?.status, 429);
      assert.equal(response?.headers.get("Retry-After"), "6");
      assert.equal(calls, 1);
    });
});

Deno.test("real SDK missing RPC maps503 without retry or bypass", async () => {
  let calls = 0;
  await sdkFixture((() => {
    calls++;
    return Promise.resolve(Response.json({ code: "PGRST202", message: `secret:${requestId}` }, { status: 404 }));
  }) as typeof fetch, async (admin) => {
    await assert.rejects(() => cortinaRequestCapacity(admin, "status"), unavailable);
    assert.equal(calls, 1);
  });
});

Deno.test("real SDK stalled fake HTTP is aborted by the two-second helper deadline", async () => {
  let aborted = false, calls = 0;
  await sdkFixture(((_url: RequestInfo | URL, init?: RequestInit) => {
    calls++;
    const signal = init?.signal;
    assert(signal);
    return new Promise<Response>((_resolve, reject) => {
      const abort = () => { aborted = true; reject(signal.reason); };
      if (signal.aborted) abort();
      else signal.addEventListener("abort", abort, { once: true });
    });
  }) as typeof fetch, async (admin) => {
    await assert.rejects(() => cortinaRequestCapacity(admin, "quote"), unavailable);
    assert.equal(aborted, true);
    assert.equal(calls, 1);
  });
});

type Row = Record<string, unknown>;
function routeFixture(options: { decision?: unknown; capacityError?: unknown; existingStatus?: string;
  shutdown?: boolean; restricted?: boolean; row?: Row; waitForCapacity?: () => Promise<void> } = {}) {
  const buckets: unknown[] = [], reads: string[] = [], inserts: Row[] = [], updates: Row[] = [];
  const charges: Array<{ kind: string; params: Row; options: Row }> = [], auth: string[] = [];
  const admissions: Array<string | null> = [];
  const row: Row = { id: sessionId, client_request_id: requestId, machine_id: 1, user_id: null,
    amount_cents: 400, dryer_minutes: null, pulse_line_number: 1, product_code: null,
    payment_method: "card", channel: "app", status: options.existingStatus ?? "payment_pending", currency: "USD",
    nayax_environment: "sandbox", nayax_terminal_id: "4434331126150568", stripe_livemode: false,
    checkout_return_version: 2, stripe_payment_intent_id: "pi_synthetic",
    created_at: "2000-01-01T00:00:00Z", ...options.row };
  const filters: Array<[string, unknown]> = [];
  const admin = {
    from(table: string) {
      reads.push(table);
      let insert: Row | undefined, update: Row | undefined;
      const run = () => {
        if (table === "cortina_machine_config") return { data: { machine_id: 1, public_machine_token: "public-qr",
          is_enabled: true, review_required: false, product_codes: null, pulse_line_number: 1 }, error: null };
        if (table === "Machines") return { data: { id: 1, Name: "Washer", Machine_type: "washer", Status: "Idle",
          Location_ID: 1, washer_size_rate_id: 1, is_out_of_service: false }, error: null };
        if (table === "washer_size_rates") return { data: { id: 1, size_label: "12kg", price_cents: 400,
          is_active: true, review_required: false }, error: null };
        assert.equal(table, "cortina_vend_sessions");
        if (insert) {
          inserts.push(structuredClone(insert));
          if (options.existingStatus) return { data: null, error: { code: "23505" } };
          Object.assign(row, insert);
        }
        if (update) { updates.push(structuredClone(update)); Object.assign(row, update); }
        return { data: structuredClone(row), error: null };
      };
      const query = { select: (_columns: string) => query,
        eq: (key: string, value: unknown) => { filters.push([key, value]); return query; },
        in: (_key: string, _values: string[]) => query,
        insert: (value: Row) => { insert = value; return query; },
        update: (value: Row) => { update = value; return query; },
        single: () => Promise.resolve(run()), maybeSingle: () => Promise.resolve(run()),
        then: <T, U>(resolve?: ((value: ReturnType<typeof run>) => T | PromiseLike<T>) | null,
          reject?: ((reason: unknown) => U | PromiseLike<U>) | null) => Promise.resolve(run()).then(resolve, reject) };
      return query;
    },
    rpc(name: string, args: Row) {
      if (name === "new_payments_enabled") return { abortSignal: (_signal: AbortSignal) => Promise.resolve({ data: !options.shutdown, error: null }) };
      assert.equal(name, "consume_cortina_request_capacity");
      buckets.push(structuredClone(args));
      return { abortSignal: async (signal: AbortSignal) => {
        assert(signal instanceof AbortSignal);
        await options.waitForCapacity?.();
        return { data: options.decision === undefined ? allowed : options.decision,
          error: options.capacityError ?? null };
      } };
    },
    auth: { getUser(token: string) { auth.push(token); return Promise.resolve({ data: { user: { id: owner, is_anonymous: false } }, error: null }); } },
  };
  const deps = { admin, stripe: {
    paymentIntents: { create(params: Row, opts: Row) {
      charges.push({ kind: "intent", params, options: opts });
      return Promise.resolve({ id: "pi_synthetic", client_secret: "synthetic", livemode: false });
    } },
    checkout: { sessions: { create(params: Row, opts: Row) {
      charges.push({ kind: "checkout", params, options: opts });
      return Promise.resolve({ id: "cs_synthetic", url: "https://checkout.synthetic.invalid/session", livemode: false });
    } } },
  }, fetcher: (url: RequestInfo | URL, init?: RequestInit) => {
    assert.equal(String(url), "https://database.synthetic.invalid/rest/v1/rpc/get_admission_status");
    admissions.push(new Headers(init?.headers).get("Authorization"));
    return Promise.resolve(Response.json({ subject_id: owner,
      account_access: options.restricted ? "restricted" : "eligible", next_step: "home" }));
  } } as unknown as CortinaDeps;
  return { deps, buckets, reads, inserts, updates, charges, auth, row, filters, admissions };
}

const cardBody = (channel = "app") => ({ channel, machineToken: "public-qr", amountCents: 400, clientRequestId: requestId });
const credentials = { sessionId, accessToken: requestId };
const request = (route: string, body: unknown, authorization?: string) => new Request(`https://edge.synthetic.invalid/cortina-vend/${route}`, {
  method: "POST", body: JSON.stringify(body), headers: { "X-Forwarded-For": "spoofed-identity",
    ...(authorization ? { Authorization: authorization } : {}) },
});
async function withEnv(action: () => Promise<void>) {
  const get = Deno.env.get;
  const values: Record<string, string> = { SUPABASE_URL: "https://database.synthetic.invalid", SUPABASE_ANON_KEY: "synthetic-public",
    CLEAN_STREAM_PAY_URL: "https://web.synthetic.invalid/pay" };
  Deno.env.get = (key) => values[key];
  try { await action(); } finally { Deno.env.get = get; }
}

Deno.test("quote denial uses fixed bucket before quote reads and ignores caller quotas or spoofed IP", async () => {
  const f = routeFixture({ decision: denied });
  const response = await handleCortinaVend(request("quote", { machineToken: "public-qr", bucket: "status", capacity: 999999 }), f.deps);
  assert.equal(response.status, 429);
  assert.deepEqual(f.buckets, [{ p_bucket: "quote" }]);
  assert.deepEqual(f.reads, []);
  assert.deepEqual(f.charges, []);
});

Deno.test("quote missing-schema failure cannot proceed to quote reads", async () => {
  const f = routeFixture({ capacityError: { code: "PGRST202" } });
  await assert.rejects(() => handleCortinaVend(request("quote", { machineToken: "public-qr" }), f.deps), unavailable);
  assert.deepEqual(f.reads, []);
});

Deno.test("allowed quote continues through the existing authoritative quote reader", async () => {
  const f = routeFixture();
  const response = await handleCortinaVend(request("quote", { machineToken: "public-qr" }), f.deps);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).amountCents, 400);
  assert.deepEqual(f.buckets, [{ p_bucket: "quote" }]);
  assert.deepEqual(f.reads, ["cortina_machine_config", "Machines", "washer_size_rates"]);
});

Deno.test("status and owner recovery share only the isolated status bucket and denied work has no side effects", async () => {
  for (const body of [credentials, { clientRequestId: requestId, machineId: 1 }]) {
    const f = routeFixture({ decision: denied, row: { status: "paid" } });
    const response = await handleCortinaVend(request("status", body, "Bearer original-owner"), f.deps);
    assert.equal(response.status, 429);
    assert.deepEqual(f.buckets, [{ p_bucket: "status" }]);
    assert.deepEqual(f.reads, []);
    assert.deepEqual(f.auth, []);
    assert.deepEqual(f.updates, []);
    assert.equal(f.row.status, "paid");
  }
});

Deno.test("status limiter failure leaves even an aged paid session unchanged", async () => {
  const f = routeFixture({ capacityError: { code: "55P03" }, row: { status: "paid" } });
  await assert.rejects(() => handleCortinaVend(request("status", credentials), f.deps), unavailable);
  assert.deepEqual(f.reads, []);
  assert.deepEqual(f.updates, []);
  assert.equal(f.row.status, "paid");
});

Deno.test("allowed status keeps exact capability verification and existing status result", async () => {
  await withEnv(async () => {
    const f = routeFixture({ row: { status: "started" } });
    const response = await handleCortinaVend(request("status", credentials), f.deps);
    assert.equal((await response.json()).status, "started");
    assert.deepEqual(f.filters, [["id", sessionId], ["client_access_token_hash", await sha256(requestId)], ["id", sessionId]]);
    assert.deepEqual(f.buckets, [{ p_bucket: "status" }]);
    assert.deepEqual(f.updates, []);
  });
});

Deno.test("allowed owner recovery remains authenticated and returns only the original reference", async () => {
  const f = routeFixture({ row: { user_id: owner, client_access_token_hash: await sha256(requestId) } });
  const response = await handleCortinaVend(request("status", { clientRequestId: requestId, machineId: 1 }, "Bearer original-owner"), f.deps);
  assert.deepEqual(await response.json(), credentials);
  assert.deepEqual(f.auth, ["original-owner"]);
  assert.deepEqual(f.buckets, [{ p_bucket: "status" }]);
  assert.deepEqual(f.updates, []);
  assert.deepEqual(f.charges, []);
});

Deno.test("new app and web card denial never enters provider compensation or changes the pending draft", async () => {
  await withEnv(async () => {
    for (const channel of ["app", "web"]) {
      const f = routeFixture({ decision: denied });
      const response = await handleCortinaVend(request("card", cardBody(channel)), f.deps);
      assert.equal(response.status, 429);
      assert.deepEqual(f.buckets, [{ p_bucket: "card" }]);
      assert.equal(f.inserts.length, 1);
      assert.equal(f.row.status, "payment_pending");
      assert.deepEqual(f.updates, []);
      assert.deepEqual(f.charges, []);
    }
  });
});

Deno.test("new card limiter missing-schema503 leaves the pending draft and Stripe untouched", async () => {
  const f = routeFixture({ capacityError: { code: "PGRST202" } });
  await assert.rejects(() => handleCortinaVend(request("card", cardBody()), f.deps), unavailable);
  assert.equal(f.row.status, "payment_pending");
  assert.deepEqual(f.updates, []);
  assert.deepEqual(f.charges, []);
});

Deno.test("allowed new card keeps existing Stripe idempotency keys and a single provider-create attempt", async () => {
  await withEnv(async () => {
    for (const channel of ["app", "web"]) {
      const f = routeFixture();
      const response = await handleCortinaVend(request("card", cardBody(channel)), f.deps);
      assert.equal(response.status, 200);
      assert.deepEqual(f.buckets, [{ p_bucket: "card" }]);
      assert.equal(f.charges.length, 1);
      assert.equal(f.charges[0].options.idempotencyKey, `${channel === "app" ? "cortina-card" : "cortina-checkout"}-${sessionId}`);
      assert.equal(f.row.status, "payment_pending");
      assert.equal(f.updates.length, 1);
    }
  });
});

Deno.test("funded or other nonpending card replay bypasses depleted capacity and makes no provider writes", async () => {
  for (const status of ["paid", "starting", "awaiting_sale", "started", "support_required", "timed_out", "refunded"]) {
    const f = routeFixture({ decision: denied, existingStatus: status });
    const response = await handleCortinaVend(request("card", cardBody()), f.deps);
    assert.deepEqual(await response.json(), { ...credentials, status });
    assert.deepEqual(f.buckets, []);
    assert.deepEqual(f.updates, []);
    assert.deepEqual(f.charges, []);
  }
});

Deno.test("shutdown and caller admission refusal precede capacity debit", async () => {
  await withEnv(async () => {
    for (const options of [{ shutdown: true }, { restricted: true }]) {
      const f = routeFixture(options);
      await assert.rejects(() => handleCortinaVend(request("card", cardBody(), "Bearer original-owner"), f.deps),
        (error) => error instanceof HttpError && error.code === (options.shutdown ? "new_payments_unavailable" : "account_restricted"));
      assert.deepEqual(f.buckets, []);
      assert.deepEqual(f.charges, []);
      assert.deepEqual(f.updates, []);
    }
  });
});

for (const channel of ["app", "web"]) {
  Deno.test(`post-capacity ${channel} shutdown rejects before Stripe without changing the pending draft`, async () => {
    await withEnv(async () => {
      let entered!: () => void, release!: () => void;
      const waiting = new Promise<void>((resolve) => { entered = resolve; });
      const gate = new Promise<void>((resolve) => { release = resolve; });
      const options = { shutdown: false, waitForCapacity: () => { entered(); return gate; } };
      const f = routeFixture(options);
      const rejected = assert.rejects(() => handleCortinaVend(
        request("card", cardBody(channel), "Bearer original-owner"), f.deps),
        (error) => error instanceof HttpError && error.status === 503 &&
          error.code === "new_payments_unavailable" && error.message === "new_payments_unavailable");
      await waiting;
      assert.deepEqual(f.admissions, ["Bearer original-owner"]);
      assert.deepEqual(f.charges, []);
      const pending = structuredClone(f.row);
      options.shutdown = true;
      release();
      await rejected;
      assert.deepEqual(f.auth, ["original-owner"]);
      assert.deepEqual(f.admissions, ["Bearer original-owner", "Bearer original-owner"]);
      assert.deepEqual(f.buckets, [{ p_bucket: "card" }]);
      assert.equal(f.row.status, "payment_pending");
      assert.deepEqual(f.row, pending);
      assert.deepEqual(f.charges, []);
      assert.deepEqual(f.updates, []);
    });
  });

  Deno.test(`post-capacity ${channel} admission rejects a newly restricted caller before Stripe`, async () => {
    await withEnv(async () => {
      let entered!: () => void, release!: () => void;
      const waiting = new Promise<void>((resolve) => { entered = resolve; });
      const gate = new Promise<void>((resolve) => { release = resolve; });
      const options = { restricted: false, waitForCapacity: () => { entered(); return gate; } };
      const f = routeFixture(options);
      const req = request("card", cardBody(channel), "Bearer original-owner");
      const rejected = assert.rejects(() => handleCortinaVend(req, f.deps),
        (error) => error instanceof HttpError && error.status === 403 && error.code === "account_restricted");
      await waiting;
      assert.deepEqual(f.admissions, ["Bearer original-owner"]);
      assert.deepEqual(f.charges, []);
      options.restricted = true;
      req.headers.set("Authorization", "Bearer switched-owner");
      release();
      await rejected;
      assert.deepEqual(f.auth, ["original-owner"]);
      assert.deepEqual(f.admissions, ["Bearer original-owner", "Bearer original-owner"]);
      assert.deepEqual(f.buckets, [{ p_bucket: "card" }]);
      assert.equal(f.row.status, "payment_pending");
      assert.deepEqual(f.charges, []);
      assert.deepEqual(f.updates, []);
    });
  });
}

Deno.test("post-capacity eligible caller retains one charge and captured admission on both card channels", async () => {
  await withEnv(async () => {
    for (const channel of ["app", "web"]) {
      const f = routeFixture({ waitForCapacity: () => Promise.resolve() });
      const response = await handleCortinaVend(request("card", cardBody(channel), "Bearer original-owner"), f.deps);
      assert.equal(response.status, 200);
      assert.deepEqual(f.admissions, ["Bearer original-owner", "Bearer original-owner"]);
      assert.equal(f.charges.length, 1);
      assert.equal(f.charges[0].options.idempotencyKey, `${channel === "app" ? "cortina-card" : "cortina-checkout"}-${sessionId}`);
    }
  });
});

Deno.test("confirm is excluded from capacity guard even when buckets are depleted", async () => {
  const f = routeFixture({ decision: denied, row: { status: "started" } });
  const response = await handleCortinaVend(request("confirm", credentials), f.deps);
  assert.deepEqual(await response.json(), { status: "started" });
  assert.deepEqual(f.buckets, []);
  assert.deepEqual(f.charges, []);
});

Deno.test("wallet remains outside the new capacity guard", async () => {
  await withEnv(async () => {
    const f = routeFixture({ decision: denied });
    await assert.rejects(() => handleCortinaVend(request("wallet", cardBody()), f.deps),
      (error) => error instanceof HttpError && error.code === "unauthorized");
    assert.deepEqual(f.buckets, []);
  });
});

Deno.test("existing byte limit rejects oversized quote/card/status before capacity or other dependencies", async () => {
  const deps = new Proxy({}, { get(): never { throw new Error("No dependency allowed before body validation"); } }) as CortinaDeps;
  for (const route of ["quote", "card", "status"]) {
    await assert.rejects(() => handleCortinaVend(request(route, { padding: "x".repeat(8192) }), deps),
      (error) => error instanceof HttpError && error.status === 413);
  }
});
