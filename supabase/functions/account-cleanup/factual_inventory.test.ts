import { strict as assert } from "node:assert";
import { CLEANUP_POLICY_SHA256, CLEANUP_POLICY_VERSION, executeAccountCleanup } from "./execution.ts";

Deno.test("automatic inventory exposes concrete SQL hold reason without raw diagnostics", async () => {
  for (const reason of ["eligible_owner_custodian_unavailable", "media_inventory_requires_supported_mapping",
    "private error with subject and provider data"]) {
    const result = await executeAccountCleanup({
      rpc: (name) => Promise.resolve({ policy_version: CLEANUP_POLICY_VERSION,
        policy_sha256: CLEANUP_POLICY_SHA256, purge_complete: false,
        status: name === "claim_closed_attachment_cleanup" ? "idle" : "held", reason }),
      removeStorageVersions: () => { throw new Error("No dispatch expected"); },
      deleteAuthUser: () => { throw new Error("No dispatch expected"); },
    });
    assert.equal(result.status, "held");
    assert.equal("reason" in result ? result.reason : undefined,
      reason.includes(" ") ? undefined : reason);
  }
});
