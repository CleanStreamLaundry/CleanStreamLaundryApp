# Availability Admission / Storage Closure

## Current Storage Checkpoint

The helper-only and owner-only statements below are historical. The composer
verified existing `supautils.policy_grants` delegation to postgres; no roles,
ownership, server configuration or privileges changed. Corrected active policy
artifact SHA256 `4ed6c4a3115c5aaf46ebeb1c3729b900bf383f7a89b8a9e31f20fdb1738b1dc9`
preserves all five policy bodies and passes independent69 (eb1c6f). Rollback-only
hosted rehearsal3d6873 and unchanged-state readback10e248 passed; actual install
778b3c and postflight e00a26 confirm all five policies. Helper history remains
installed; never replay either installation. The bucket is still public, with
unchanged limits/records/deletion hold. Steps4-5 below remain the HTTP-proof and
coordinated private-bucket transition gates, not completed privacy acceptance.

## Historical Helper / Availability Receipt

Availability independently **46 distinct cases/typechecks ACCEPTED**: transport20/d3d260 retained plus keys-only26 exit0/db4477, no repeat20. Composer integrated all four files at exact hashes, receiptd836e2; deployed version13 ACTIVE with gatewayfalse, receipt61827a. Unsigned401 smoke ff8b1e made no provider call. QA processes closed/slot released. Earlier TS7053 was corrected only with test config's explicit `Record<string, string>` annotation; assertions/runtime/dependencies unchanged. Author ran **0 tests**, no remote/provider actions or active-repo edits. C/D18 and four payment SQL/history are already hosted; callbacks updated. Never replay them or enable deletion from this batch.

Storage helper exact `fc0f5f16` installed by Composer, exit0/7d8631 after absence preflight e4870f. Postflight4d3644 matches helper ACLs, Storage-owner/RLStrue, policiesnull, bucket publictrue and deletionheld. Exact1 history applied/read back exit0/8df2b4: version20260930165320, sourcefc0f5f16. **Batch CLOSED, helper only; lane idle.** No Storage policies/bucket/object changes or privacy activation claimed. Completed history artifact `record-storage-history.sql` SHA256 `9a34c1dffc1f3a871c032e47b7b2f9a997a6564b4a7147cef9d4ba36e6fd7800` stores the exact accepted helper as inert text; no schema replay or other migration included. No pending recording, runtime or new work.

Completed Composer history command for verified `dnuuhupoxjtwqzaqylvb`, receipt8df2b4; provenance only, do not rerun:

```sh
/opt/homebrew/bin/supabase db query --linked --workdir /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp --file /Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/ordinary-access/record-storage-history.sql
```

Unknown result requires history readback, not an overwrite/retry loop. Mechanical generation verified source SHA; author did not run SQL or remote checks. History recording does not activate policies/privacy or enable deletion.

## Exact Candidate

Four source/test files under `supabase/functions/machine-availability/`:

| File | SHA256 |
| --- | --- |
| `index.ts` | `b1a98449bbcae2c44fb163ca0dd45b9ec8f2f8cfad62a0b7e57f7b5c48223d5f` |
| `admission.ts` | `c89986ba5f87e322f259e4b485213a68f72662c2c524ab24f43d214f319953a5` |
| `keys.test.ts` | `91d8dd4c63aa8fbbe11779f328cd21a0ee2dbd583a980855c7c8d27e56688d55` |
| `admission.test.ts` | `5fe3f7460ed95f751f5f93729405c3907879abd43353d8bca6db34477f52b8d3` |

`baseline.sha256` pins the two active files before edits. Symlinked `logic.ts` and `_shared/supabase_keys.ts` are read-only accepted dependencies, not integration changes. No shared helper, SQL, SDK, lockfile, frontend, money or provider-completion edits.

Actual gap: getUser alone admits pending-deletion/stale-session/MFA-restricted callers to service-backed inventory, refresh leases and provider reads. New endpoint-local helper calls existing `get_admission_status()` with the original bearer and matches Auth's captured subject. Reuses `callerPublishableKey`; optional `CLEANSTREAM_AVAILABILITY_PUBLISHABLE_KEY_NAME`, absent-only `SUPABASE_ANON_KEY` fallback, invalid explicit names fail503. Eight-second abort, redirects rejected, sanitized401/403/503. The unchanged component secret remains confined to service operations; callers never become service identity.

Eligibility is exactly canonical `account_access=eligible`, NOT funding's `next_step=home` condition. Eligible `review_terms` remains allowed; recovery, MFA and profile restrictions remain authoritative. Endpoint-local transport avoids turning funding's stronger policy into a generic shared framework or weakening it. Checks occur after request parsing before inventory, after inventory/config waits before lease, before every provider dispatch, and after the final read before response (including empty inventory). Admission errors escape provider-error caching. Existing response shape, provider/cache behavior, leases and no-store remain. Work already dispatched cannot be undone; an aborted refresh lease expires through existing machinery. No claim of instant cancellation or whole-API deletion coverage.

## QA Queue

Accepted **46 Deno cases**: original12 real-SDK key tests retained,14 endpoint admission/provider-race cases,20 transport cases. Transport20 passed d3d260; remaining26 passed db4477. All HTTP was replaced with synthetic responses; no network permission or provider action. Existing unchanged availability logic5 and Storage65 receipts are reused. Typechecking passed. Completed focused26 command below is provenance only, NOT a rerun request:

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --cached-only --frozen --node-modules-dir=none --allow-read=/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/ordinary-access/supabase/functions/machine-availability/logic.ts,/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/ordinary-access/supabase/functions/_shared/supabase_keys.ts,/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/functions/machine-availability/logic.ts,/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/functions/_shared/supabase_keys.ts --config /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.json --lock /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --v8-flags=--max-old-space-size=768 supabase/functions/machine-availability/keys.test.ts
```

Do not fetch missing imports, edit lockfiles or rerun older suites on failure. Report cache/type/runtime gaps separately. No PG fixture is added. After source QA, integrate four files then deploy only `machine-availability` with its existing `logic.ts`, unchanged key helper and new `admission.ts`; preserve configured gateway `verify_jwt=false` because handler performs explicit Auth + canonical admission. Required RPC is already installed through A/B; no SQL prerequisite replay. Anonymous/malformed bearer must401 before configuration/DB/provider; positive live refresh is NOT a no-provider smoke.

## Storage: Existing Code, Next Ordered Activation

No new Storage code is needed for this contract. Exact accepted active inputs:

1. **INSTALLED AND RECORDED, never replay:** `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930165320_maintenance_attachment_access.sql`, SHA256 `fc0f5f1697314d785eee18afdca9b5dad8e5e3af1be3ab1adb2b6ad161ce4d54`, exit0/7d8631 after absence preflight e4870f. C/D supplies maintenance/location guards and A/B supplies lifecycle. This added descriptor/predicates only, no policies, bucket or object writes. Postflight4d3644 accepted; exact1 history applied/read back8df2b4. Later steps below are preserved coordination boundaries, not assigned work; this lane is closed and idle.

2. Pair existing web `src/admin/maintenanceAttachment.ts` + `MaintenancePage.tsx` before privacy change: descriptor RPC then captured-bearer authenticated object GET, not legacy public URL rendering. Existing helper16/page6 receipts retained. Flutter `lib/features/maintenance_request/controller.dart` uploads once without upsert, retaining `requests/<filename>`; its public-URL-shaped string is a parser reference, not a public-download dependency. No new signed-URL framework or path rewrite.
3. Apply accepted `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/storage/maintenance_attachment_policies.sql`, SHA256 `38898d389268444f2746f0dcad531af1fa5502cf385aedf849ec4eae1db77ea1`, ONLY through supported Storage-owner authority. Existing postgres/BYPASSRLS access is insufficient for policy DDL; do not assume role, alter ownership/membership or weaken its owner guard. Supported operator execution path remains an explicit deployment prerequisite, not permission for a workaround. Five policies: restrictive read/upload/update/delete plus authenticated read; existing permissive upload policy remains. Other buckets unchanged.
4. Composer's separately coordinated synthetic HTTP proof: eligible customer upload -> canonical maintenance submission -> own descriptor/authenticated download; authorized location staff read; different customer, wrong-location staff, missing/stale session, MFA-required and pending account denied. Eligible preterms support remains allowed. Unlinked upload cannot be downloaded until bound to a report. Assert overwrite/move/delete denied and no existing rows changed. Public GET is expected to bypass RLS WHILE bucket remains public; do not misreport policy-only install as privacy.
5. After paired consumers and authenticated proof, coordinated supported bucket configuration change to private. This file contains NO bucket mutation. Then anonymous/public URL denial and authenticated proof must hold. Previously issued signed URLs/cached/downloaded bytes are not retroactively revoked. Historical URL-only/missing-owner reports fail closed and require a separately approved support/migration path; no historical attachment writes or deletion here.

`storage-postflight.sql` is a single metadata/config SELECT for Composer after each relevant stage: exact function ACLs, five policies, Storage owner/RLS, bucket privacy/limits and deletion hold. It does not read object/report/customer rows or invoke authority RPCs. Expected descriptor authenticated-only; private predicates callable by anon/authenticated policies (not exposed RPCs), service denied. Public flag stays true until the separately coordinated privacy step. Existing synthetic Storage65 proves policy composition/owner/location/lifecycle/preservation, NOT hosted HTTP/cache behavior.

Keep deletion request ACL held until this proof and separately assigned ordinary-path closure are accepted. Preserve restoration, Auth recovery, onboarding, owner-bound already-funded status, settlement/refunds/reconciliation. No further API audit/retirement implementation in this batch. Rollback is forward repair/controlled availability failure, never restore getUser-only service bypass, make a private bucket public, regrant unsafe writes, migrate historical records or enable purge/mail.
