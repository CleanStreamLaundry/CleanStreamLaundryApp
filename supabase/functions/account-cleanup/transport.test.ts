import assert from "node:assert/strict";
import { handler } from "./index.ts";
import { CLEANUP_POLICY_SHA256, CLEANUP_POLICY_VERSION } from "./execution.ts";

const worker = "synthetic-cleanup-worker-secret-at-least-32-characters";
const named = "sb_secret_synthetic_cleanup_transport";
const legacy = "synthetic-legacy-cleanup-transport";
const privateBody = "SYNTHETIC-private-provider-body-must-not-escape";
const user = "00000000-0000-4000-8000-000000000901";
const operation = "00000000-0000-4000-8000-000000000902";
const timestamp = "2026-08-01T12:00:00.123456Z";
const objects = [
  { id: user, bucket: "maintenance-images", name: "synthetic/folder/image +%.png", version: "version/old+1" },
  { id: operation, bucket: "maintenance-images", name: "synthetic/folder/image +%.png", version: "version/new+2" },
];
const policy = { p_policy_version: CLEANUP_POLICY_VERSION, p_policy_sha256: CLEANUP_POLICY_SHA256 };
const wire = { policy_version: CLEANUP_POLICY_VERSION, policy_sha256: CLEANUP_POLICY_SHA256, purge_complete: false };
type Kind = "storage" | "auth" | "attachment";
type Outcome = "success" | "non-success" | "abort";

async function exercise(mode: "named" | "legacy", kind: Kind, outcome: Outcome, ackFailure = false) {
  const config: Record<string, string> = {
    ACCOUNT_CLEANUP_ENABLED: "true", ACCOUNT_CLEANUP_EXECUTION_ENABLED: "true",
    ACCOUNT_CLEANUP_WORKER_SECRET: worker,
    ACCOUNT_CLEANUP_POLICY_VERSION: CLEANUP_POLICY_VERSION,
    ACCOUNT_CLEANUP_POLICY_SHA256: CLEANUP_POLICY_SHA256,
    SUPABASE_URL: "https://cleanup.synthetic.invalid/",
    SUPABASE_SERVICE_ROLE_KEY: legacy,
    SUPABASE_SECRET_KEYS: JSON.stringify({ "cleanup-only": named, default: "sb_secret_wrong_component" }),
    ...(mode === "named" ? { CLEANSTREAM_CLEANUP_SECRET_KEY_NAME: "cleanup-only" } : {}),
  };
  const saved = { env: Deno.env.get, fetch: globalThis.fetch, timeout: AbortSignal.timeout,
    log: console.log, warn: console.warn, error: console.error };
  const calls: { request: Request; body: Record<string, unknown> }[] = [];
  const controllers: AbortController[] = [], deadlines: number[] = [], logs: unknown[][] = [];
  let canceledBodies = 0, claim = "", inspect = false;
  const providerResponse = (status: number) => new Response(new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode(privateBody)); },
    cancel() { canceledBodies++; },
  }), { status });
  try {
    // Same worker injection as selector.test.ts: never read process credentials.
    Deno.env.get = (name) => config[name];
    console.log = console.warn = console.error = (...args: unknown[]) => { logs.push(args); };
    AbortSignal.timeout = (ms) => {
      deadlines.push(ms);
      const controller = new AbortController();
      controllers.push(controller);
      return controller.signal;
    };
    globalThis.fetch = async (input, init) => {
      const request = new Request(input, init);
      const body = await request.clone().json();
      calls.push({ request, body });
      const path = new URL(request.url).pathname;
      if (request.method === "DELETE") {
        if (outcome === "abort") {
          controllers.at(-1)!.abort(new DOMException(privateBody, "AbortError"));
          throw request.signal.reason;
        }
        return providerResponse(outcome === "success" ? 200 : 503);
      }
      if (path.endsWith("/claim_closed_attachment_cleanup") && kind !== "attachment") {
        return Response.json({ ...wire, status: "idle" });
      }
      if (path.endsWith("/execute_account_cleanup_step") && kind === "attachment") {
        return Response.json({ ...wire, status: "idle" });
      }
      if (path.includes("/acknowledge_")) {
        if (ackFailure) return providerResponse(500);
        return Response.json({ purge_complete: false, status: outcome === "success"
          ? kind === "attachment" ? "attachment_removed" : kind === "auth" ? "account_removed" : "progress"
          : "outcome_unknown" });
      }
      if (!inspect && calls.some(c => new URL(c.request.url).pathname.includes("/acknowledge_"))) {
        return Response.json({ ...wire, status: "idle" });
      }
      if (!inspect) claim = body.p_claim_id as string;
      return Response.json({ ...wire, status: inspect ? "inspect" : "dispatch", claim_id: claim,
        operation_id: operation, ...(kind === "attachment"
          ? { report_id: "901", closed_at: timestamp, objects: objects.slice(0, 1) }
          : { user_id: user, requested_at: timestamp, action: kind, objects }) });
    };
    const invoke = () => handler(new Request("https://cleanup.synthetic.invalid/account-cleanup", {
      method: "POST", headers: { "X-Account-Cleanup-Secret": worker, Authorization: "Bearer unrelated-caller" },
      body: JSON.stringify({ action: "run" }),
    }));
    const response = await invoke();
    assert.equal(response.status, ackFailure ? 503 : 200);
    const result = await response.json();
    if (ackFailure) {
      assert.deepEqual(result, { error: "cleanup_execution_unavailable", automatic_retry: false });
    } else {
      assert.equal(result.purge_complete, false);
      assert.equal(result.automatic_retry, false);
      assert.equal(kind === "attachment" ? result.attachment_status : result.status,
        outcome !== "success" ? "outcome_unknown" : kind === "attachment" ? "attachment_removed"
          : kind === "auth" ? "account_removed" : "idle");
    }
    // SQL may return inspect on a later invocation. Inspection must never resend DELETE.
    if (outcome !== "success" && !ackFailure) {
      inspect = true;
      assert.equal((await invoke()).status, 200);
    }
    const deletes = calls.filter(c => c.request.method === "DELETE");
    assert.equal(deletes.length, 1);
    assert.equal(deletes[0].request.url, kind === "auth"
      ? `https://cleanup.synthetic.invalid/auth/v1/admin/users/${user}`
      : "https://cleanup.synthetic.invalid/storage/v1/object/maintenance-images");
    assert.deepEqual(deletes[0].body, kind === "auth" ? { should_soft_delete: false } : {
      prefixes: (kind === "attachment" ? objects.slice(0, 1) : objects).map(o => ({ path: o.name, versionId: o.version })),
    });
    const acknowledgements = calls.filter(c => new URL(c.request.url).pathname.includes("/acknowledge_"));
    assert.equal(acknowledgements.length, outcome !== "success" && !ackFailure ? 2 : 1);
    for (const [index, call] of acknowledgements.entries()) {
      assert.equal(new URL(call.request.url).pathname, kind === "attachment"
        ? "/rest/v1/rpc/acknowledge_closed_attachment_cleanup" : "/rest/v1/rpc/acknowledge_account_cleanup");
      assert.deepEqual(call.body, { ...policy, p_claim_id: claim, p_operation_id: operation,
        p_outcome: index === 1 ? "inspected" : outcome === "success" ? "returned" : "unknown",
        ...(kind === "attachment" ? { p_report_id: "901", p_closed_at: timestamp }
          : { p_user_id: user, p_requested_at: timestamp }) });
    }
    for (const { request, body } of calls) {
      assert.equal(new URL(request.url).origin, "https://cleanup.synthetic.invalid");
      assert.equal(request.headers.get("apikey"), mode === "named" ? named : legacy);
      assert.equal(request.headers.get("Authorization"), mode === "named" ? null : `Bearer ${legacy}`);
      assert.equal(request.headers.get("Content-Type"), "application/json");
      assert.equal(request.headers.has("X-Account-Cleanup-Secret"), false);
      if (request.method !== "DELETE") {
        assert.equal(request.method, "POST");
        assert.equal(body.p_policy_version, CLEANUP_POLICY_VERSION);
        assert.equal(body.p_policy_sha256, CLEANUP_POLICY_SHA256);
      }
    }
    assert.equal(deadlines.length, calls.length);
    assert(deadlines.every(ms => ms === 10_000));
    assert.equal(canceledBodies, (outcome === "abort" ? 0 : 1) + (ackFailure ? 1 : 0));
    const output = JSON.stringify({ result, logs });
    for (const sensitive of [named, legacy, worker, privateBody, user, objects[0].name]) {
      assert.equal(output.includes(sensitive), false, `Leaked ${sensitive}`);
    }
    assert.deepEqual(logs, []);
  } finally {
    Deno.env.get = saved.env;
    globalThis.fetch = saved.fetch;
    AbortSignal.timeout = saved.timeout;
    console.log = saved.log; console.warn = saved.warn; console.error = saved.error;
  }
}

for (const mode of ["named", "legacy"] as const) {
  for (const kind of ["storage", "auth", "attachment"] as const) {
    for (const outcome of ["success", "non-success", "abort"] as const) {
      Deno.test(`enabled index transport: ${mode} ${kind} ${outcome}`, () => exercise(mode, kind, outcome));
    }
  }
  Deno.test(`enabled index transport: ${mode} lost acknowledgement never repeats Auth DELETE`,
    () => exercise(mode, "auth", "success", true));
}
