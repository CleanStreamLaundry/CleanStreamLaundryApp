import { cleanupExecutionAllowed, type CleanupExecutionConfig, isCleanupTimestamp as utc } from "./execution.ts";

export interface CleanupDeps {
  enabled: boolean;
  workerSecret?: string;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
  execution?: CleanupExecutionConfig;
  run?(): Promise<unknown>;
}

const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const json = (status: number, value: unknown) =>
  new Response(JSON.stringify(value), { status, headers });
const uuid = (v: unknown): v is string =>
  typeof v === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const exactKeys = (value: Record<string, unknown>, keys: string[]) =>
  Object.keys(value).length === keys.length &&
  keys.every((key) => Object.hasOwn(value, key));
const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);
const blockers = ["lease_active", "outcome_unknown", "retry_exhausted", "retry_wait"];

function previewAcknowledgement(limit: number, data: unknown): boolean {
  if (!record(data)) return false;
  return exactKeys(data, ["execution_enabled", "candidates", "next_cursor"]) &&
      data.execution_enabled === false && Array.isArray(data.candidates) &&
      data.candidates.length <= limit &&
      (data.next_cursor === null || (uuid(data.next_cursor) &&
        data.next_cursor === data.candidates.at(-1)?.user_id)) &&
      data.candidates.every((c) => record(c) &&
        exactKeys(c, ["user_id", "deletion_requested_at", "restore_until", "blocker", "eligible_to_claim"]) &&
        uuid(c.user_id) && utc(c.deletion_requested_at) && utc(c.restore_until) &&
        (c.blocker === null || blockers.includes(String(c.blocker))) &&
        c.eligible_to_claim === (c.blocker === null));
}

async function authorized(actual: string, expected: string): Promise<boolean> {
  const encode = new TextEncoder();
  const a = new Uint8Array(await crypto.subtle.digest("SHA-256", encode.encode(actual)));
  const b = new Uint8Array(await crypto.subtle.digest("SHA-256", encode.encode(expected)));
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function handleAccountCleanup(req: Request, deps: CleanupDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!deps.enabled || !deps.workerSecret || deps.workerSecret.length < 32) {
    return json(503, { error: "account_cleanup_disabled" });
  }
  const workerSecret = req.headers.get("X-Account-Cleanup-Secret");
  if (!workerSecret || workerSecret.length > 512 || !await authorized(workerSecret, deps.workerSecret)) {
    return json(401, { error: "unauthorized" });
  }
  const reader = req.body?.getReader();
  if (!reader) return json(400, { error: "invalid_request" });
  let body: unknown;
  try {
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 2048) {
        await reader.cancel();
        return json(413, { error: "request_too_large" });
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return json(400, { error: "invalid_request" });
  } finally {
    reader.releaseLock();
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json(400, { error: "invalid_request" });
  }
  const input = body as Record<string, unknown>;
  if (input.action === "run" && exactKeys(input, ["action"])) {
    if (!deps.execution || !cleanupExecutionAllowed(deps.execution) || !deps.run) {
      return json(503, { error: "cleanup_policy_unapproved", execution_enabled: false });
    }
    try {
      return json(200, await deps.run());
    } catch {
      return json(503, { error: "cleanup_execution_unavailable", automatic_retry: false });
    }
  }
  if (!(input.action === "preview" && exactKeys(input, ["action", "limit", "after_user_id"]) &&
    Number.isInteger(input.limit) && Number(input.limit) >= 1 && Number(input.limit) <= 100 &&
    (input.after_user_id === null || uuid(input.after_user_id)))) {
    return json(400, { error: "invalid_request" });
  }
  try {
    const data = await deps.rpc("preview_account_cleanup", {
      p_limit: input.limit, p_after_user_id: input.after_user_id,
    });
    if (!previewAcknowledgement(Number(input.limit), data)) throw new Error("Invalid acknowledgement");
    return json(200, { execution_enabled: false, data });
  } catch {
    return json(503, { error: "cleanup_preview_unavailable", automatic_retry: false });
  }
}
