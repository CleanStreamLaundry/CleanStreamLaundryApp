import { strict as assert } from "node:assert";
import {
  CLEANUP_POLICY_SHA256,
  CLEANUP_POLICY_VERSION,
  cleanupExecutionAllowed,
  type CleanupExecutionDeps,
  executeAccountCleanup,
  type StorageVersion,
} from "./execution.ts";

const user = "00000000-0000-4000-8000-000000000001";
const claim = "00000000-0000-4000-8000-000000000002";
const operation = "00000000-0000-4000-8000-000000000003";
const other = "00000000-0000-4000-8000-000000000004";
const requested = "2026-08-01T00:00:00.123456Z";
const policy = { p_policy_version: CLEANUP_POLICY_VERSION, p_policy_sha256: CLEANUP_POLICY_SHA256 };
const context = { user_id: user, claim_id: claim, operation_id: operation, requested_at: requested };
const object: StorageVersion = {
  id: "00000000-0000-4000-8000-000000000005",
  bucket: "maintenance-images", name: "requests/exact version.jpg", version: "archived-version-1",
};
const reply = (status: string, fields: Record<string, unknown> = {}) => ({
  policy_version: CLEANUP_POLICY_VERSION, policy_sha256: CLEANUP_POLICY_SHA256,
  purge_complete: false, status, ...fields,
});
const ack = (status: string) => ({ status, purge_complete: false });
const unavailable = /Cleanup acknowledgement unavailable/;

Deno.test("prospective surrender policy rejects former preservation approval and remains opt-in", () => {
  assert.equal(CLEANUP_POLICY_VERSION, "retention-voluntary-surrender-2026-10-05");
  assert.equal(cleanupExecutionAllowed({ executionEnabled: true,
    policyVersion: "retention-paid-credit-2026-10-05",
    policySha256: "0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04" }), false);
  assert.equal(cleanupExecutionAllowed({ executionEnabled: true,
    policyVersion: "retention-paid-credit-2026-10-02",
    policySha256: "756666436f8461458c8301f60c2c1b8ac5fee216d89d6268d67d8ea4521e4592" }), false);
  assert.equal(cleanupExecutionAllowed({ executionEnabled: true,
    policyVersion: "retention-draft-2026-10-01",
    policySha256: "3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be" }), false);
  assert.equal(cleanupExecutionAllowed({ executionEnabled: false,
    policyVersion: CLEANUP_POLICY_VERSION, policySha256: CLEANUP_POLICY_SHA256 }), false);
  assert.equal(cleanupExecutionAllowed({ executionEnabled: true,
    policyVersion: CLEANUP_POLICY_VERSION, policySha256: CLEANUP_POLICY_SHA256 }), true);
});

function setup(
  rpc: CleanupExecutionDeps["rpc"],
  attachment: unknown = reply("idle"),
  deleteError?: Error,
) {
  const calls: { name: string; args: unknown }[] = [];
  const users: string[] = [], objects: StorageVersion[][] = [];
  const deps: CleanupExecutionDeps = {
    async rpc(name, args) {
      calls.push({ name, args: structuredClone(args) });
      if (name === "claim_closed_attachment_cleanup") return attachment;
      return await rpc(name, args);
    },
    async deleteAuthUser(id) {
      users.push(id); calls.push({ name: "deleteAuthUser", args: id });
      if (deleteError) throw deleteError;
    },
    async removeStorageVersions(values) {
      objects.push(structuredClone(values)); calls.push({ name: "removeStorageVersions", args: values });
      if (deleteError) throw deleteError;
    },
  };
  return { deps, calls, users, objects };
}

Deno.test("executor rejects policy and envelope drift before any delete or account claim", async () => {
  for (const value of [null, reply("dispatch", { policy_version: "unapproved" }),
    reply("dispatch", { policy_sha256: "0".repeat(64) }), reply("idle", { purge_complete: true })]) {
    const f = setup(() => { throw new Error("Unexpected account RPC"); }, value);
    await assert.rejects(() => executeAccountCleanup(f.deps), unavailable);
    assert.deepEqual(f.users, []); assert.deepEqual(f.objects, []);
    assert.equal(f.calls.length, 1);
  }
});

Deno.test("executor rejects malformed account dispatch and version descriptors before deletes", async () => {
  const valid = reply("dispatch", { ...context, action: "storage", objects: [object] });
  for (const value of [
    { ...valid, policy_sha256: "wrong" }, { ...valid, purge_complete: true },
    { ...valid, user_id: "not-a-uuid" }, { ...valid, requested_at: "2026-08-01T00:00:00-04:00" },
    { ...valid, action: "purge" }, { ...valid, objects: [] },
    { ...valid, objects: [{ ...object, version: null }] },
    { ...valid, objects: [{ ...object, bucket: "unreviewed-bucket" }] },
    { ...valid, objects: Array.from({ length: 101 }, () => object) },
  ]) {
    const f = setup((name) => {
      assert.equal(name, "execute_account_cleanup_step"); return Promise.resolve(value);
    });
    await assert.rejects(() => executeAccountCleanup(f.deps), unavailable);
    assert.deepEqual(f.users, []); assert.deepEqual(f.objects, []);
    assert.equal(f.calls.length, 2);
  }
});

Deno.test("executor preserves exact subject timestamp and claim through storage then Auth acknowledgement", async () => {
  let token: unknown, steps = 0, acknowledgements = 0;
  const f = setup((name, args) => {
    if (name === "execute_account_cleanup_step") {
      steps++;
      if (steps === 1) {
        token = args.p_claim_id;
        assert.match(String(token), /^[0-9a-f-]{36}$/);
        assert.deepEqual(args, { ...policy, p_claim_id: token });
      } else {
        assert.equal(steps, 2);
        assert.deepEqual(args, { ...policy, p_claim_id: token, p_user_id: user, p_requested_at: requested });
      }
      return Promise.resolve(reply("dispatch", { ...context, claim_id: token,
        operation_id: steps === 1 ? operation : other, action: steps === 1 ? "storage" : "auth",
        ...(steps === 1 ? { objects: [object] } : {}) }));
    }
    assert.equal(name, "acknowledge_account_cleanup"); acknowledgements++;
    assert.deepEqual(args, { ...policy, p_user_id: user, p_requested_at: requested, p_claim_id: token,
      p_operation_id: acknowledgements === 1 ? operation : other, p_outcome: "returned" });
    return Promise.resolve(ack(acknowledgements === 1 ? "progress" : "account_removed"));
  });
  assert.deepEqual(await executeAccountCleanup(f.deps), { status: "account_removed", attachment_status: "idle",
    purge_complete: false, automatic_retry: false, financial_records_retained: true });
  assert.deepEqual(f.users, [user]); assert.deepEqual(f.objects, [[object]]);
  assert.equal(steps, 2); assert.equal(acknowledgements, 2);
});

Deno.test("executor rejects subject request or claim drift before the next delete", async () => {
  for (const drift of [{ user_id: other }, { requested_at: "2026-08-01T00:00:00.123457Z" }, { claim_id: other }]) {
    let steps = 0;
    const f = setup((name) => {
      if (name === "acknowledge_account_cleanup") return Promise.resolve(ack("progress"));
      assert.equal(name, "execute_account_cleanup_step"); steps++;
      return Promise.resolve(steps === 1
        ? reply("dispatch", { ...context, action: "storage", objects: [object] })
        : reply("dispatch", { ...context, ...drift, action: "auth" }));
    });
    await assert.rejects(() => executeAccountCleanup(f.deps), unavailable);
    assert.deepEqual(f.objects, [[object]]); assert.deepEqual(f.users, []);
    assert.equal(f.calls.filter((c) => c.name === "acknowledge_account_cleanup").length, 1);
    assert.equal(steps, 2);
  }
});

for (const [action, failure] of [
  ["auth", new Error("Synthetic delete rejection after possible side effect")],
  ["storage", new DOMException("Synthetic transport deadline", "TimeoutError")],
] as const) {
  Deno.test(`executor ${action} delete ${failure.name} acknowledges unknown once and never resends`, async () => {
    let steps = 0, acknowledgements = 0;
    const f = setup((name, args) => {
      if (name === "execute_account_cleanup_step") {
        assert.equal(++steps, 1);
        return Promise.resolve(reply("dispatch", { ...context, action, objects: [object] }));
      }
      assert.equal(name, "acknowledge_account_cleanup"); assert.equal(++acknowledgements, 1);
      assert.deepEqual(args, { ...policy, p_user_id: user, p_requested_at: requested,
        p_claim_id: claim, p_operation_id: operation, p_outcome: "unknown" });
      return Promise.resolve(ack("outcome_unknown"));
    }, reply("idle"), failure);
    const result = await executeAccountCleanup(f.deps);
    assert.equal(result.status, "outcome_unknown"); assert.equal(result.automatic_retry, false);
    assert.equal(result.purge_complete, false);
    assert.deepEqual(f.users, action === "auth" ? [user] : []);
    assert.deepEqual(f.objects, action === "storage" ? [[object]] : []);
    assert.equal(steps, 1); assert.equal(acknowledgements, 1);
  });
}

Deno.test("executor inspection adopts stored claim and acknowledges without deleting or continuing", async () => {
  const attachment = reply("inspect", { report_id: "9007199254740993", claim_id: other,
    operation_id: operation, closed_at: requested });
  let accountSteps = 0;
  const f = setup((name, args) => {
    if (name === "acknowledge_closed_attachment_cleanup") {
      assert.deepEqual(args, { ...policy, p_report_id: "9007199254740993", p_closed_at: requested,
        p_claim_id: other, p_operation_id: operation, p_outcome: "inspected" });
      return Promise.resolve(ack("outcome_unknown"));
    }
    if (name === "execute_account_cleanup_step") {
      assert.equal(++accountSteps, 1);
      return Promise.resolve(reply("inspect", context));
    }
    assert.equal(name, "acknowledge_account_cleanup");
    assert.deepEqual(args, { ...policy, p_user_id: user, p_requested_at: requested,
      p_claim_id: claim, p_operation_id: operation, p_outcome: "inspected" });
    return Promise.resolve(ack("progress"));
  }, attachment);
  const result = await executeAccountCleanup(f.deps);
  assert.equal(result.status, "progress"); assert.equal(result.attachment_status, "outcome_unknown");
  assert.equal(result.automatic_retry, false);
  assert.deepEqual(f.users, []); assert.deepEqual(f.objects, []); assert.equal(accountSteps, 1);
});

Deno.test("executor acknowledgement rejection or malformed receipt never retries RPC or delete", async () => {
  for (const receipt of [new Error("Synthetic lost acknowledgement"), { status: "account_removed", purge_complete: true }]) {
    let acknowledgements = 0;
    const f = setup((name) => {
      if (name === "execute_account_cleanup_step") return Promise.resolve(reply("dispatch", { ...context, action: "auth" }));
      assert.equal(name, "acknowledge_account_cleanup"); acknowledgements++;
      return receipt instanceof Error ? Promise.reject(receipt) : Promise.resolve(receipt);
    });
    await assert.rejects(() => executeAccountCleanup(f.deps), receipt instanceof Error ? /Synthetic lost acknowledgement/ : unavailable);
    assert.equal(acknowledgements, 1); assert.deepEqual(f.users, [user]); assert.deepEqual(f.objects, []);
    assert.equal(f.calls.filter((c) => c.name === "execute_account_cleanup_step").length, 1);
  }
});

Deno.test("executor handles one closed attachment then one account without mixing identities", async () => {
  const attachment = reply("dispatch", { report_id: "9007199254740993", claim_id: other,
    operation_id: operation, closed_at: requested, objects: [object] });
  const f = setup((name, args) => {
    if (name === "acknowledge_closed_attachment_cleanup") {
      assert.deepEqual(args, { ...policy, p_report_id: "9007199254740993", p_closed_at: requested,
        p_claim_id: other, p_operation_id: operation, p_outcome: "returned" });
      return Promise.resolve(ack("attachment_removed"));
    }
    if (name === "execute_account_cleanup_step") {
      assert.equal(Object.hasOwn(args, "p_user_id"), false);
      assert.equal(Object.hasOwn(args, "p_requested_at"), false);
      return Promise.resolve(reply("dispatch", { ...context, action: "auth" }));
    }
    assert.equal(name, "acknowledge_account_cleanup");
    assert.equal(args.p_claim_id, claim); assert.equal(args.p_user_id, user);
    return Promise.resolve(ack("account_removed"));
  }, attachment);
  const result = await executeAccountCleanup(f.deps);
  assert.equal(result.attachment_status, "attachment_removed"); assert.equal(result.status, "account_removed");
  assert.deepEqual(f.calls.map((c) => c.name), ["claim_closed_attachment_cleanup", "removeStorageVersions",
    "acknowledge_closed_attachment_cleanup", "execute_account_cleanup_step", "deleteAuthUser", "acknowledge_account_cleanup"]);
  assert.deepEqual(f.objects, [[object]]); assert.deepEqual(f.users, [user]);
});

Deno.test("executor validates attachment shape and never sends a multi-object closed-case batch", async () => {
  const attachment = reply("dispatch", { report_id: "12", claim_id: claim,
    operation_id: operation, closed_at: requested, objects: [object] });
  for (const value of [{ ...attachment, report_id: 12 }, { ...attachment, objects: [object, object] },
    { ...attachment, objects: [{ ...object, version: "" }] }]) {
    const f = setup(() => { throw new Error("Unexpected follow-up RPC"); }, value);
    await assert.rejects(() => executeAccountCleanup(f.deps), unavailable);
    assert.deepEqual(f.objects, []); assert.deepEqual(f.users, []); assert.equal(f.calls.length, 1);
  }
});

Deno.test("executor closed-attachment timeout is unknown and its failed acknowledgement stops account work", async () => {
  let acknowledgements = 0;
  const f = setup((name, args) => {
    assert.equal(name, "acknowledge_closed_attachment_cleanup"); acknowledgements++;
    assert.equal(args.p_outcome, "unknown");
    return Promise.reject(new Error("Synthetic attachment acknowledgement unavailable"));
  }, reply("dispatch", { report_id: "12", claim_id: claim, operation_id: operation,
    closed_at: requested, objects: [object] }), new DOMException("Timed out", "TimeoutError"));
  await assert.rejects(() => executeAccountCleanup(f.deps), /Synthetic attachment acknowledgement unavailable/);
  assert.equal(acknowledgements, 1); assert.deepEqual(f.objects, [[object]]); assert.deepEqual(f.users, []);
  assert.equal(f.calls.some((c) => c.name === "execute_account_cleanup_step"), false);
});

Deno.test("executor stops after eight account steps even while acknowledgements report progress", async () => {
  let steps = 0, acknowledgements = 0;
  const now = Date.now;
  try {
    Date.now = () => 0;
    const f = setup((name) => {
      if (name === "execute_account_cleanup_step") {
        steps++;
        return Promise.resolve(reply("dispatch", { ...context, action: "storage",
          operation_id: `00000000-0000-4000-8000-${String(steps + 100).padStart(12, "0")}`,
          objects: [{ ...object, version: `version-${steps}` }] }));
      }
      assert.equal(name, "acknowledge_account_cleanup"); acknowledgements++;
      return Promise.resolve(ack("progress"));
    });
    const result = await executeAccountCleanup(f.deps);
    assert.equal(result.status, "progress"); assert.equal(result.purge_complete, false);
    assert.equal(steps, 8); assert.equal(acknowledgements, 8); assert.equal(f.objects.length, 8);
    assert.deepEqual(f.users, []);
  } finally { Date.now = now; }
});

Deno.test("executor elapsed budget prevents another account step after a completed acknowledgement", async () => {
  let elapsed = 0, steps = 0;
  const now = Date.now;
  try {
    Date.now = () => elapsed;
    const f = setup((name) => {
      if (name === "execute_account_cleanup_step") {
        steps++; return Promise.resolve(reply("dispatch", { ...context, action: "storage", objects: [object] }));
      }
      assert.equal(name, "acknowledge_account_cleanup"); elapsed = 35_000;
      return Promise.resolve(ack("progress"));
    });
    assert.equal((await executeAccountCleanup(f.deps)).status, "progress");
    assert.equal(steps, 1); assert.deepEqual(f.objects, [[object]]);
  } finally { Date.now = now; }
});

Deno.test("executor rejects a nonexistent calendar date before destructive dispatch", async () => {
  const f = setup((name) => {
    if (name === "execute_account_cleanup_step") return Promise.resolve(reply("dispatch", {
      ...context, requested_at: "2026-02-30T00:00:00Z", action: "auth",
    }));
    assert.equal(name, "acknowledge_account_cleanup"); return Promise.resolve(ack("account_removed"));
  });
  await assert.rejects(() => executeAccountCleanup(f.deps), unavailable);
  assert.deepEqual(f.users, []); assert.deepEqual(f.objects, []);
});
