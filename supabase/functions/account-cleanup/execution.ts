// Business policy identity only; matching it does not authorize execution.
export const CLEANUP_POLICY_VERSION = "retention-voluntary-surrender-2026-10-05";
export const CLEANUP_POLICY_SHA256 =
  "95f4128b8045ff83b9a625c10dc084b7146c520c818d3186767dd3a283e155ac";

export interface CleanupExecutionConfig {
  executionEnabled: boolean;
  policyVersion?: string;
  policySha256?: string;
}

export function cleanupExecutionAllowed(config: CleanupExecutionConfig): boolean {
  return config.executionEnabled && config.policyVersion === CLEANUP_POLICY_VERSION &&
    config.policySha256 === CLEANUP_POLICY_SHA256;
}

export interface CleanupExecutionDeps {
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
  removeStorageVersions(objects: StorageVersion[]): Promise<void>;
  deleteAuthUser(userId: string): Promise<void>;
}

export interface StorageVersion {
  id: string;
  bucket: "maintenance-images";
  name: string;
  version: string;
}

const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const uuid = (v: unknown): v is string => typeof v === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const isCleanupTimestamp = (v: unknown): v is string => {
  if (
    typeof v !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(v)
  ) return false;
  const date = new Date(v);
  return Number.isFinite(date.getTime()) &&
    date.toISOString().slice(0, 19) === v.slice(0, 19);
};
const unavailable = () => new Error("Cleanup acknowledgement unavailable");
const storageVersions = (value: unknown, maximum: number): value is StorageVersion[] =>
  Array.isArray(value) && value.length > 0 && value.length <= maximum &&
  value.every((o) => record(o) && uuid(o.id) && o.bucket === "maintenance-images" &&
    typeof o.name === "string" && o.name.length > 0 && o.name.length <= 1024 &&
    typeof o.version === "string" && o.version.length > 0 && o.version.length <= 200);

async function cleanClosedAttachment(deps: CleanupExecutionDeps, policy: Record<string, string>) {
  const result = await deps.rpc("claim_closed_attachment_cleanup", { ...policy, p_claim_id: crypto.randomUUID() });
  if (!record(result) || result.policy_version !== CLEANUP_POLICY_VERSION ||
    result.policy_sha256 !== CLEANUP_POLICY_SHA256 || result.purge_complete !== false) throw unavailable();
  if (["idle", "held", "progress"].includes(String(result.status))) return result.status;
  if ((result.status !== "dispatch" && result.status !== "inspect") ||
    typeof result.report_id !== "string" || !/^[1-9]\d{0,18}$/.test(result.report_id) ||
    !uuid(result.claim_id) || !uuid(result.operation_id) || !isCleanupTimestamp(result.closed_at)) throw unavailable();
  let outcome = "inspected";
  if (result.status === "dispatch") {
    if (!storageVersions(result.objects, 1)) throw unavailable();
    try {
      await deps.removeStorageVersions(result.objects);
      outcome = "returned";
    } catch {
      outcome = "unknown";
    }
  }
  const ack = await deps.rpc("acknowledge_closed_attachment_cleanup", {
    ...policy, p_report_id: result.report_id, p_closed_at: result.closed_at,
    p_claim_id: result.claim_id, p_operation_id: result.operation_id, p_outcome: outcome,
  });
  if (!record(ack) || ack.purge_complete !== false ||
    !["attachment_removed", "outcome_unknown"].includes(String(ack.status))) throw unavailable();
  return ack.status;
}

// One closed attachment, then one account within the same time budget. SQL
// selects/fences both; a case closure is never treated as an account request.
export async function executeAccountCleanup(deps: CleanupExecutionDeps) {
  const policy = { p_policy_version: CLEANUP_POLICY_VERSION, p_policy_sha256: CLEANUP_POLICY_SHA256 };
  let context: { p_user_id: string; p_requested_at: string } | undefined;
  let claimId: string = crypto.randomUUID();
  const started = Date.now();
  const attachmentStatus = await cleanClosedAttachment(deps, policy);
  for (let step = 0; step < 8 && Date.now() - started < 35_000; step++) {
    const result = await deps.rpc("execute_account_cleanup_step", {
      ...policy, p_claim_id: claimId, ...context,
    });
    if (!record(result) || result.policy_version !== CLEANUP_POLICY_VERSION ||
      result.policy_sha256 !== CLEANUP_POLICY_SHA256 || result.purge_complete !== false) throw unavailable();
    if (result.status === "idle" || result.status === "held" || result.status === "progress") {
      return { status: result.status, attachment_status: attachmentStatus,
        ...(typeof result.reason === "string" && /^[a-z_]{1,80}$/.test(result.reason)
          ? { reason: result.reason } : {}),
        purge_complete: false, automatic_retry: false };
    }
    if ((result.status !== "dispatch" && result.status !== "inspect") ||
      !uuid(result.user_id) || !uuid(result.claim_id) || !uuid(result.operation_id) ||
      !isCleanupTimestamp(result.requested_at)) throw unavailable();
    if (context && (context.p_user_id !== result.user_id ||
      context.p_requested_at !== result.requested_at || claimId !== result.claim_id)) throw unavailable();
    context = { p_user_id: result.user_id, p_requested_at: result.requested_at };
    claimId = result.claim_id;
    let outcome = "inspected";
    if (result.status === "dispatch") {
      if (result.action === "storage") {
        if (!storageVersions(result.objects, 100)) throw unavailable();
      } else if (result.action !== "auth") throw unavailable();
      try {
        if (result.action === "auth") await deps.deleteAuthUser(result.user_id);
        else await deps.removeStorageVersions(result.objects as StorageVersion[]);
        outcome = "returned";
      } catch {
        // Timeout/rejection is not proof of no side effect. Never resend here.
        outcome = "unknown";
      }
    }
    const ack = await deps.rpc("acknowledge_account_cleanup", {
      ...policy, ...context, p_claim_id: claimId, p_operation_id: result.operation_id, p_outcome: outcome,
    });
    if (!record(ack) || ack.purge_complete !== false ||
      !["progress", "account_removed", "outcome_unknown"].includes(String(ack.status))) throw unavailable();
    if (ack.status !== "progress" || result.status === "inspect") {
      return { status: ack.status, purge_complete: false, automatic_retry: false,
        attachment_status: attachmentStatus, financial_records_retained: true };
    }
  }
  return { status: "progress", attachment_status: attachmentStatus,
    purge_complete: false, financial_records_retained: true };
}
