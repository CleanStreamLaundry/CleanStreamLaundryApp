# Disabled Permanent Cleanup Candidate

UNTESTED / UNDEPLOYED. No test, typecheck, build, provider request, hosted mutation,
or customer-data read was performed. This is implementation source, not an
activation receipt or a claim that every draft retention class is implemented.

## Source and Integration

Paths below are relative to the owned root:
`/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/permanent-cleanup`.

1. Existing prerequisite: active `supabase/migrations/20260930154911_account_cleanup_claims.sql`.
   Composer's supplied catalog did not contain its jobs table; do not assume it is installed.
2. `supabase/migrations/20261001130137_permanent_account_cleanup.sql`: disabled controls,
   scoped holds/inventory, executor RPCs, request/operation fencing, support/mail clocks,
   Auth-delete guard and known-clock retention processing. Requires current lifecycle, wallet,
   newsletter/outbox, support/audit, customer MFA recovery, push and Storage schemas.
3. **Separate reference-protocol approval:**
   `supabase/migrations/20261001130950_retained_financial_subjects.sql`.
   Twelve FK replacements are validated before the original FK is removed. It projects
   existing referenced UUIDs into a private anchor; it does not rewrite financial rows,
   amounts, balances, provider IDs or transaction IDs. This UUID projection is explicit
   installation DML, not a claim of a no-backfill migration. Keep execution off throughout.
4. Integrate only `supabase/functions/account-cleanup/{index.ts,logic.ts,execution.ts}`.
   Reuse active `_shared/supabase_keys.ts` unchanged. No package/SDK/lock update.
5. Composer must explicitly configure this worker's gateway `verify_jwt=false` to use its
   existing `X-Account-Cleanup-Secret` authentication; human endpoints are unchanged.
   Local `supabase/config.toml` only prevents CLI parent-root discovery. **Do not integrate it.**
6. `ops/account-cleanup-setup.sql` maps to active `supabase/ops/account-cleanup-setup.sql`;
   likewise `ops/account-cleanup-disable.sql`. These operator scripts are not migrations,
   do not approve execution, and do not invoke the worker during setup.

## Hard Gates

Supported authoring identity: `retention-draft-2026-10-01`, SHA256
`3e14877eed8a552cef4fd5c7f2183d98d42897dbcb7bf2c3496b3ebcbd67c6be`.
Matching this draft does not constitute final approval. A changed policy needs reviewed
source changes; a request/environment hash cannot select arbitrary disposition rules.

Edge requires `ACCOUNT_CLEANUP_ENABLED`, `ACCOUNT_CLEANUP_EXECUTION_ENABLED`,
`ACCOUNT_CLEANUP_POLICY_VERSION`, `ACCOUNT_CLEANUP_POLICY_SHA256` and the existing worker secret.
Execution booleans are false when absent. Leave them false/unset now.
SQL independently requires execution, exact policy identity and a nonfuture final-policy
approval timestamp. No workflow-stage runtime flag remains. Install seeds only disabled configuration. `credit_forfeiture_enabled`
is constrained false; there is no balance-write-down path.

Hold/inventory tables grant no direct access to public, anon, authenticated, service or Auth-admin.
Only the PostgreSQL operator records externally established inventories/hold releases.
No Owner/Admin UI, seeded approval, inferred clearance or first-Owner mutation.
Each exact request needs custody and references for real hold, media, processor, backup and
financial-retention inventories. Empty balances/hold tables do not supply those facts.
Holds name subject, class, optional record, authority, purpose, custodian and review date.
Passing a review date never releases a hold; scope/authority and released evidence are immutable.
Record keys: media object UUID, support maint_id, consent/outbox UUID, or `mfa/<recovery_id>`.
Independent closed-attachment work additionally needs class-inventory reference, custodian
and recorded time in the existing execution singleton; none is populated by installation.

## Implemented Paths

- Auth SHARE -> wallet rows -> profile -> lifecycle -> job -> retained subject. Recheck D/E,
  request, claim, lease and policy after waits. Existing five-attempt claim budget and unknown
  parking remain; no wallet wait is added after a profile lock.
- Owned push-installation/budget removal after expiry; existing lifecycle nulls usable tokens
  at D. Never guess ownership of revoked NULL-user installation stubs.
- Exact-version Storage deletion in the known maintenance bucket, including archived versions.
  No path-only fallback, legacy URL ownership guess, SQL object deletion or bucket wipe.
  Unsupported bucket/ownership/version metadata and held objects stop Auth removal.
- Before account work, one independently closed attachment can expire ninety days after its
  known closure. Reuse the support row, exact Storage owner_id/descriptor and scoped holds;
  historical closure requires actual status history, not updated_at. The service-only
  claim/ack RPCs accept a decimal-string bigint report ID at the Edge boundary. No public API
  caller can claim/ack. A lost result is inspected once per day, never automatically resent.
  Reopen/replacement after dispatch cannot undo deletion; acknowledgement never clears a
  replacement. Account work waits on pending independent outcomes for the same subject.
- Closed, unheld support identifiers/notes are removed, retaining minimal private scheduling
  links. Known closed summaries/history expire after twelve months; open/held evidence remains.
  The immutable-history exception is PostgreSQL-only, exact-request/transaction fenced and
  lease-fenced before Auth removal. It allows note clearing and scoped twelve-month support
  history expiry, never arbitrary admin-audit mutation.
- Ordinary mail recipient/error fields are stripped thirty days after known terminal events.
  Known-clock withdrawn consent expires three years after the latest consent/use/withdrawal;
  future sending transitions record use. Historical unknown clocks are not guessed.
  Suppression, financial/lifecycle mail and event/provider/dedup IDs remain preserved.
- Unheld MFA recovery evidence expires after ninety days once Auth is removed.
- Auth hard deletion uses the supported admin API, never soft deletion or SQL Auth DELETE.
  Its trigger rechecks request/holds/lease/policy and captures reward progress under wallet-first
  locks in the Auth deletion transaction. Profiles physically cascade away; financial/lifecycle/
  MFA evidence references the retained UUID anchor instead.
- Funding/provenance/refund-release arithmetic stays intact; only profile-absent reward access
  uses the anchor. Existing Owner wallet search/detail already supports retained IDs.
- Staff invitation creator UUIDs use that same validated anchor and ensure-subject trigger.
  Only invited_by's FK changes; invited target CASCADE, roles, staff checks and ACLs remain.
  The removal guard requires the exact installed relation/column/parent FK, not just its name.
- At twelve months after confirmed Auth removal, full claim tokens, lease/retry history,
  disposition/policy fields and request inventory expire unless cleanup-held or unresolved.
  Preserve the financial-retention reference on the existing claimant anchor. With remaining
  support/consent/mail/security work, keep only UUID/request/completion timestamps, explicit
  class reasons and scheduling metadata plus the lifecycle D/E fence; reevaluate after each
  class pass. Otherwise delete job and lifecycle link. Financial/replay records alone do not
  justify retaining the full job. Independent active-account attachment metadata expires
  after twelve months without deleting its original support report.
- Each external dispatch has a distinct operation UUID. Unknown/lost responses park; inspection
  uses primary state and never resends deletion. An error is not proof of no side effect.
  `account_removed` means Auth/profile absent, not all data erased. `purge_complete` stays false.

## Dormant Scheduling

Fixed job `cleanstream-account-cleanup`, daily `0 3 * * *`; one closed attachment, then one subject and bounded phases per
invocation. Backlog/cost sizing remains Stage 3, not a throughput guarantee.
Dedicated Vault entries: `cleanstream_account_cleanup_project_url` and
`cleanstream_account_cleanup_worker_secret`; exact URL is
`https://dnuuhupoxjtwqzaqylvb.supabase.co`. No credential appears in Cron's command/output.
Reuse installed Cron/Vault/pg_net. Shared setup/disable advisory locking coordinates these
scripts only; pause independent dashboard edits. Setup rejects active/conflicting jobs and
commits inactive. Inactive/off tick calls do not read decrypted secrets or queue HTTP.
Disable pauses only this job, preserving credentials, claims, history and other schedulers.
Pause cannot undo dispatched work. For incidents also disable SQL/Edge execution. Never restore
unsafe financial CASCADE FKs once a retained subject has lost its Auth/profile parent.

## Required vs Deferred

Before ANY execution: final policy; actual hold/inventory records and processor receipts;
separately reviewed reference protocol; hosted version-addressed Storage/Auth named-key support;
ordinary API/Storage deletion admission coverage; Stage-3 concurrency/unknown-outcome QA.
No tests or test runners were authored/run under the current Stage-1 instruction.

Not implemented: tax/return/exception clocks and financial expiry; financial free-text minimization
pending approved minimum-record mapping; provider-specific erasure requests, CDN/backup expiry
and restore-time deletion replay; routine third-party/security-log classification/expiry;
ninety-day dedup expiry without an established replay window. These are real remaining implementation/
integration items, not reported as complete by this candidate.
Held Storage evidence needs supported ownership transfer before its owning Auth identity can be
removed. Staff invitation creator links block removal until the exact candidate FK is installed. Already-dispatched external
operations cannot be undone by later holds: preserve the operation/incident evidence.
No completion claim covers external physical copies.

Authoring references: [Auth deletion](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser),
[Auth/Storage constraints](https://supabase.com/docs/guides/auth/managing-user-data),
[version-addressed removal](https://supabase.com/docs/reference/javascript/storage-from-remove),
[official transport](https://github.com/supabase/supabase-js/blob/master/packages/core/storage-js/src/packages/StorageFileApi.ts).
