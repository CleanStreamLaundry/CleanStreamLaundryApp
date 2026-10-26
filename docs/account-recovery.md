# Account Recovery Contract

## Current Release (October 5)

Confirmed hosted release: all seven migrations through `20261005181711` are
applied, current policy is `2026-10-05.2`, and recovery is 90 days. Deletion uses
the available `request_account_deletion_with_consent(p_context_id,
p_acknowledged)` RPC. Explicit restoration remains required before the server
deadline; login alone does not restore an account. The published policy replaces
the earlier preservation direction with voluntary-deletion surrender after the
recovery deadline, subject to applicable-law exceptions and existing claim rights.

Automatic-inventory migration `20261005183040` is also applied after a
rolled-back hosted rehearsal and QA 9/9 records (four install, four behavior,
one parent); the one Deno check is retained. All 13 release functions are
deployed, including cleanup v2 with its final worker hash already verified
by readback.

Daily cleanup is enabled under the approved prospective 90-day policy;
past acceptances are not applied retroactively, and holds remain preserved.
Activation SQL exited 0; remote readback confirms execution/surrender enabled,
the daily Cron active, and zero pending requests/external cleanup operations.
No actual customer deletion or provider-erasure test was performed; activation
is not proof of completed erasure.

The website is promoted to cleanstreamlaundry.com; the release handoff confirms
asset `index-CMpgsZxw.js` and HTTP 200 for Terms, Privacy and Account Deletion with
the October 5, 2026 effective date. Android build succeeded and the signed APK
is ready. Samsung installation and device tests are explicitly user-deferred.
No runtime/provider tests were performed for this docs update and no legal
enforceability is asserted. See [retention](retention.md), [loyalty terms](loyalty-terms.md)
and Composer's [operations](operations.md) release evidence.

## Historical October 5 Source Revision

The source-stage record below predates the confirmed release. Local-only claims,
preservation policy pins, `2026-10-05.1` rollout steps and the original no-argument
deletion wire are historical, not current publication or activation instructions.

`20261005134908_ninety_day_account_recovery.sql` was created through Supabase CLI
2.84.2. It is an unapplied local candidate. Composer's serial QA passes 17 focused
SQL records (16 scenarios plus parent), paired Flutter cases, historical
lifecycle/publication regression and 105 cleanup-worker cases. No hosted mutation
or native build occurred. Receipt: `.campaign-work/review-followup-20261005/QA-RECEIPT.md`.

- New requests use exactly 2160 hours (90 UTC days). Duplicate pending requests
  keep the original request time/deadline; restored accounts can explicitly
  request deletion again under the new window.
- Pending, non-retired identities with both Auth and profile remaining receive
  `greatest(existing deadline, request timestamp + 2160 hours)`, including requests
  whose old 30-day deadline passed. Requests older than 90 days remain expired.
  Restored requests and completed/retired purges keep their historical deadlines;
  no identity, wallet or credentials are recreated. A private policy-duration
  column distinguishes historical 30-day requests from new/extended 90-day ones.
- The candidate requires cleanup disabled, takes non-waiting table/identity locks,
  and refuses pending identities with destructive disposition or unresolved
  external work. Pause/drain the worker and reconcile those records before rollout;
  do not clear their evidence to make installation pass. Claims remain fenced by
  the original request ID/time and recheck the extended deadline after locks.
- Existing `public.restore_account()` is verified in source and unchanged. It is
  called only by explicit client recovery through `AdmissionGate._restore` and
  `SupabaseProfileService.restoreAccount`. Verified email, current session/MFA,
  post-request session age strictly under ten minutes, caller binding and strict
  before-deadline/post-wait checks remain in force. Login/status never restores.
- Only the lifecycle-mail SQL constraint is adjusted for longer deadlines. Existing
  suppression rejects stale unsent notices; old notice payloads are not rewritten
  and the extension does not enqueue a replacement notice. Renderer/copy alignment
  belongs to the email owner; no mail renderer was edited here.
- Cleanup policy pins become `retention-paid-credit-2026-10-05`, hash
  `0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04` in SQL, worker and
  dormant setup source. The candidate clears old approvals and never enables
  cleanup. No ledger, paid-credit ownership, refund clock or reward rule changes.

### Immutable Loyalty Publication

The same transaction creates **`2026-10-05.1`** from the current reviewed
`2026-10-02.1` or `2026-10-03.1` document. Composer added the matching restricted-use
prepayment and same-day machine-remedy clauses to the 90-day candidate, so one
version covers this batch. Purchased-credit preservation and 48-hour voluntary
refund conditions remain unchanged. Unexpected current content fails
and rolls back the entire candidate. No reusable publish helper exists in this
checkout; the existing locked publication pattern and descriptor reader are reused.
Historical documents, publication dates and customer acceptance records are not
edited. Old migrations remain unchanged.

Deployment will require existing users to explicitly accept `2026-10-05.1` through
the existing `review_terms` flow; stale-version acceptance is rejected. Restoration
may return `review_terms` and never auto-accepts. Composer must coordinate the
descriptor publication with client/legal/email rollout. The hosted immutable
descriptor still has 30-day wording per the supplied report; changing local legal
drafts does not publish this revision. No remote publish occurred.

The user's explicit October 5 instruction approves the 90-day duration. Clearing
old cleanup metadata does not create a pending business-policy decision: do not
ask for retention approval again. The candidate now includes the corresponding
machine claim clause; deploy the backend claim change and customer surfaces as a
coherent batch. The Owner confirmed same-day on-site reporting, a same-day
resolution target, and later reconciliation/approval if staff response is delayed.
Composer owns the final version and must avoid competing `2026-10-05.1` publications. Never edit a
published document or the old 30-day migration to reconcile that work.

### Coordinated Rollout Metadata

These are agent/operator implementation steps, not outstanding user policy choices
and not authorization to execute them in this source-only lane:

1. Keep Cron inactive and worker execution disabled, drain dispatched work, inspect
   unresolved outcomes, and verify database execution is off. Preserve the concrete
   race guards; never clear pending destructive evidence just to install.
2. After serial acceptance and terms/claim coordination, install only the reviewed
   candidate against its known prerequisites. Read back extended deadlines,
   preserved retired requests, unchanged ACLs and the new descriptor/version/hash.
3. Deploy the matching worker and update `ACCOUNT_CLEANUP_POLICY_VERSION` to
   `retention-paid-credit-2026-10-05` and `ACCOUNT_CLEANUP_POLICY_SHA256` to
   `0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04`. Reinstall/read back
   the dormant tick's matching pins while `ACCOUNT_CLEANUP_ENABLED=false`,
   `ACCOUNT_CLEANUP_EXECUTION_ENABLED=false` and Cron remains inactive.
4. Record the existing approved decision in `approved_policy_version`,
   `approved_policy_sha256` and `final_policy_approved_at`, using the reviewed
   decision evidence rather than treating the cleared fields as a new approval
   request. Keep `credit_forfeiture_enabled=false` permanently under this policy.
5. Once hosted Auth/Storage acceptance, truthful inventory/holds/processor evidence
   and coordinated rollout gates are satisfied, the activation operator can set
   database `execution_enabled=true`, both worker enabled flags true, and finally
   activate the existing Cron job. Read back each state; do not infer activation
   from source/config labels. These activation changes have not been performed.

### Composer Serial Stage

Implementation and focused local acceptance are complete. Reproduction commands,
run separately,
one at a time, from `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp`.
Use the existing pinned caches; do not bootstrap dependencies or start a simulator.

```sh
RECOVERY_90_DAY_ONLY=1 PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --test scripts/account-cleanup-execution.test.mjs
PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --test scripts/account-lifecycle.test.mjs
PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --test scripts/server-managed-loyalty-terms.test.mjs
DENO_DIR=/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/.deno-cache /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env=ACCOUNT_CLEANUP_ENABLED,ACCOUNT_CLEANUP_WORKER_SECRET,ACCOUNT_CLEANUP_EXECUTION_ENABLED,ACCOUNT_CLEANUP_POLICY_VERSION,ACCOUNT_CLEANUP_POLICY_SHA256,SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,CLEANSTREAM_CLEANUP_SECRET_KEY_NAME,SUPABASE_SECRET_KEYS supabase/functions/account-cleanup
FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 /Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter test --no-pub --concurrency=1 test/logic/models/admission_status_test.dart test/features/edit_profile/edit_profile_test.dart test/features/edit_profile/widgets/danger_zone_test.dart test/features/admission/admission_test.dart test/services/supabase/profile/profile_service_test.dart
```

The focused 90-day SQL mode reuses the full cleanup prerequisite harness and
installs real mail/immutable-publication migrations, then covers extension,
completed removal, no-shortening, unchanged money/ACLs/restore body, disabled
execution, in-flight dispatch refusal, cleanup/restore lock races, explicit
fresh-session/MFA restore, expiry, duplicate requests, 90-day outbox records and
new-version acceptance. The older lifecycle/publication commands retain historical
auth and publication-race regression coverage, not proof of the new migration.
Actual counts/exits and initial corrected failures are recorded in the receipt above.
The Flutter path above is the current package-config SDK; the historical
`/private/tmp/cleanstream-flutter-3.38.10` path no longer exists. Binary/cache paths
were checked for presence only; no runtime was started.

### Hosted Evidence, Separate From Source

The existing September 30/October 2 repository receipts report request/status/restore
RPCs installed, authenticated request activation and disabled cleanup setup.
The October 1 [hosted support QA receipt](../../.campaign-work/hosted-auth-20261001/RESULTS.md),
also summarized in `docs/operations.md` at the hosted Auth acceptance checkpoint,
records successful explicit restoration of the original account to Home. Login
alone did not restore or extend the 30-day deadline; the prior JWT was restricted,
terms acceptance was preserved and a restoration notice was delivered once.
That is recorded hosted happy-flow evidence, not a new test in this lane. Its
scope excludes Flutter UI, OAuth/MFA, expiry/races, funded-wallet isolation and
permanent cleanup. This lane verified source and read the existing receipt only.
Hosted 90-day migration presence,
pending-request extension counts, policy/worker pins, immutable descriptor hash,
ACLs, current execution/Cron state and signed-in restore/expiry behavior remain
unverified. No remote state changed. Keep destructive execution disabled pending
separately authorized rollout and hosted Auth/Storage/inventory acceptance.

## Historical Cleanup Preparation

The following describes the original preparatory batches; installation statements
are historical and superseded by the October 2 setup receipt and October 5 notes above.

The local `20260930154911_account_cleanup_claims.sql` migration adds one private,
RLS-protected job row per account and three service-only preview/claim/retry RPCs.
It reuses the lifecycle identity/deadline and existing lock order. Claims are
fenced by the exact request timestamp and token, with at most five attempts;
uncertain outcomes remain parked. Only job metadata can change. A lease is not
permission to delete, nor proof that a payment or provider action failed.

`account-cleanup` defaults disabled. The existing worker-secret preview remains;
local source now adds a policy-gated executor and dormant scheduling. The new
`20261001130137_permanent_account_cleanup.sql` and separate
`20261001130950_retained_financial_subjects.sql` are unapplied candidates. They
reuse existing claims, preserve financial UUIDs/amounts/replay references through
Auth/profile removal, and add scoped holds plus known-clock post-removal cleanup.
Three financial routines gain profile-absent reward progress without changing
financial arithmetic. No new service or dependency. Exact-version Storage deletion
and supported Auth hard deletion never retry an uncertain destructive dispatch.
`account_removed` is not full erasure; `purge_complete` stays false.

The second integrated batch adds independent ninety-day closed-attachment cleanup
and twelve-month cleanup-metadata expiry/compaction through the same worker.
The validated retained-subject protocol includes staff invitation creators without
changing target-user removal or management permissions. Redundant workflow-stage
flags are removed; the October 2 business approval does not activate irreversible actions.
Tax/minimum financial-record, processor/backup/CDN and unknown replay/history
mappings require agent follow-through against the approved retention schedule. Source integration is not
deployment or functional acceptance; neither cleanup batch has been run or tested.

Author verification: 22 PGlite cases, 42 Edge cases and seven real PostgreSQL race
cases. Independent QA reran the seven races on PostgreSQL 17.11, including the
actual newsletter trigger and restore rollback; all passed and the disposable
server was stopped/removed. Test inputs match integrated prerequisites exactly.
These checks establish preparatory locking only, not full deployed-schema or
destructive-cleanup safety. Commands and ownership are in [operations](operations.md).

The October 2 approval resolves the business retention and credit-treatment decision.
Before irreversible activation, implement the approved per-class fields, linkage,
retention/start event and exceptions for identity, financial/provider evidence,
support/media, email/suppression, device tokens and cleanup records. Validate
paid/promo legal classification, permitted disposition and settlement evidence;
pending settlements and refund obligations survive deletion. A zero spendable balance
is not proof of no unsettled obligations. Inventory current FKs/triggers/Storage
ownership and supported provider deletion paths. Do not remove restrictive FKs,
zero balances or use wallet anonymization as a substitute for approved erasure.
Wallet writers lock wallet before profile; cleanup must not append wallet locks
to its profile-first order without a reviewed cross-writer protocol.

## Storage and Authority

- `private.account_lifecycle` stores the existing profile ID, last request/deadline,
  optional restoration timestamp and persistent `marketing_suppressed=true`.
  It is private, RLS enabled, has no client/service-role grants or policies, and
  cannot be deleted through a cascading profile FK. No financial or Auth writes.
- The existing `private.current_account_access()` is replaced in place, preserving
  its session binding, verified email, bans, roles and current TOTP checks. Its new
  internal `lifecycle_identity_allowed` is not exposed or callable by clients.
  Pending state always denies `account_access_allowed()`, even after expiry.
- Request and restore take Auth `FOR SHARE`, then the caller's profile
  `FOR NO KEY UPDATE`, then re-evaluate the canonical authority. The profile lock
  serializes first requests (including absent lifecycle rows), duplicate requests,
  and restores, in the same order as the existing terms/provisioning paths.
- All new deadlines are server-generated timestamptz values. Exactly 2160 hours is
  used for 90 UTC days, independent of DST or caller timezone. Wire timestamps
  are rendered in UTC. Duplicate pending requests never move either timestamp.
- Restore requires a current valid session owned by the caller, verified email,
  applicable current MFA, and `auth.sessions.created_at > deletion_requested_at`.
  At mutation time the session must be no more than ten minutes old (strictly
  less than ten minutes), non-null and not in the future. Ten minutes is a
  technical fresh-auth window for explicit recovery, not a retention decision.
  A refreshed JWT, `iat`, `updated_at`, or MFA challenge on an old session cannot
  substitute for a newly created session. Ordinary login/status never restores.
- Checks use wall-clock time after lock waits. Restore at/after the deadline is
  denied; the row remains pending indefinitely with no cleanup. A restore retry
  inside the same deadline/freshness limits preserves the first restored time.
- Auth/users/sessions/factors, profile IDs/roles, wallet IDs/links, funds, loads,
  rewards, acceptance/refund timestamps and other financial records are unchanged.
  Pre-request sessions cannot regain canonical access after another session
  restores. Restore never reinstates a revoked role or grants privileges.
- The original lifecycle batch adds no managed Auth SQL mutation, admin sign-out,
  purge RPC, scheduler or provider action. The newer local executor is not deployed
  authority. Logical restriction is authoritative only on covered
  APIs; it is not a claim of global session revocation. Global sign-out would not
  close missing API gates and a delayed retry could revoke a successful recovery
  session. Any later supported Auth revocation must be separately scoped and
  post-commit with explicit uncertainty/retry behavior, never destructive SQL.

## Historical Recovery-Only Wire

Current deletion requires the consent RPC named above; this original wire record
does not authorize bypassing consent. Status and explicit restoration remain
separate from the deletion request.

Authenticated caller-bound RPCs take **no arguments**:

| RPC | Result / effect |
| --- | --- |
| `request_account_deletion()` | Commit pending state and return the six-key status |
| `get_account_lifecycle_status()` | Read-only alias of existing admission status |
| `restore_account()` | Explicit fresh-auth restore, returning admission status |

The existing six keys remain `subject_id`, `account_access`, `next_step`, `reason`,
`account_state`, `restore_until`. Active accounts still use `legacy_active`.
Pending adds `account_state=pending_deletion`, a non-null UTC `restore_until`,
`account_access=restricted`, and normally `next_step=blocked` with reason
`explicit_restore_required` or `restore_expired`. Email/TOTP/role/factor checks
retain precedence and can return `verify_email`, `enroll_totp`, `challenge_totp`,
`role_unavailable`, or `unsupported_factor` with pending state/deadline. Auth bans
and account restrictions keep the existing blocked response, without a deadline.
No `restore` next-step enum is invented. Status is not a promise that restore is
authorized; the explicit RPC rechecks everything. Restored admission can still
require terms review, without modifying previous consent.

**Paired client:** `AdmissionStatus.fromJson` now validates canonical pending
combinations and UTC deadlines. Existing ProfileService exposes caller-bound
`requestAccountDeletion()` and `restoreAccount()` with identity/expiry completion
guards and exact subject/state acknowledgements; `getAdmissionStatus()` provides
the status check after an unknown outcome. Independent QA passes 345 client and
neighbor cases with clean scoped analysis. Recovery presentation passes 26 independent widget cases;
later batches wire edit-profile and the admission gate as noted above. No mutation retries, automatic
restoration or logout are added by these adapters.

SQL errors: `PT401 session_invalid`, `PT403 account_restricted` or restore-specific
`fresh_session_required` / `restore_expired` / `restore_unavailable`, and sanitized
`PT503` failures. No subject argument, metadata claim, date or client clock is trusted.

`delete-account` retains POST `{ "user_id": "<caller>" }` for compatibility,
validates ownership via `getUser`, then calls the no-argument request RPC using
the exact same bearer with the public anon key. It no longer has a service key,
anonymization or Auth deletion. Success is `{ "success": true, "data": <status> }`.
401/403 are sanitized; uncertain RPC failures return 503
`{ "error": "deletion_outcome_unknown", "retryable": true,
"status_rpc": "get_account_lifecycle_status" }`. Check status before retry;
pending retries preserve the deadline. A lost response is not evidence of rollback.
Success requires an exact six-key canonical pending acknowledgement for the
verified caller, restricted access, a valid UTC deadline, and an allowed pending
next-step/reason combination. Active, unrelated or malformed acknowledgements
return the same unknown-outcome 503. Expired pending and canonical email/MFA/role
prerequisite responses remain valid acknowledgements; the Edge clock does not
decide restoration eligibility. The handler dispatches once and never retries
automatically; `retryable` is guidance for explicit status-led caller recovery.
After explicit restoration a new confirmed request may start a new 90-day period;
do not automatically replay an earlier user intent with a different session.

## Email Suppression

The original lifecycle batch contains no newsletter or outbox. The subsequent
newsletter migration now covers consent/outbox suppression. Request atomically persists
`marketing_suppressed=true`; restore never clears it or recreates consent/welcome
events. A future sender must read committed lifecycle state immediately before
dispatch, honor this suppression plus independent unsubscribe/bounce/complaint
suppression, and require separately approved opt-in before any resubscription.
Future deletion notices must match the current request timestamp and still-pending
state; restore invalidates stale deletion work. No emails/templates/DNS/provider
settings or email framework are created. See the active repository's `docs/email.md`.

## Historical Activation Gaps

This earlier campaign checkpoint is not the current release queue. Current
cleanup work is automatic-inventory SQL QA and activation only; no provider or
device acceptance is inferred from the release.

The October 1 bounded source review found no new ordinary-human API code gap in
the original inventory. Profile/terms, maintenance, wallet/record reads, human
financial writes, staff, availability and push guards have accepted integrated
contracts and recorded installations. Retired legacy handlers stay denied.
Reuse those receipts in [operations](operations.md); do not replay migrations or
add another admission framework. Exact source references are retained in the
workspace's `.campaign-work/account-cleanup/ordinary-api-closure/HANDOFF.md`.
This source review is not a fresh remote audit or whole-API certification.

| Remaining prerequisite | Current state and required next action |
| --- | --- |
| Authenticated new Cortina card requests | Public version-2 return reader and paired `cortina-vend` are published. SQL/callback prerequisites are installed; stage-3 hosted acceptance remains. |
| Maintenance attachments | Descriptor/helper and five policies installed; authenticated reader published and `maintenance-images` made private under the approved setup stage. No objects rewritten/deleted. Authorized and cross-account/location/MFA/pending denials remain untested on hosted Storage. |
| Private machine notes/staff IDs | User explicitly waived older-build support; approved column-privacy migration installed. Current app/web projections are implemented. Hosted client acceptance remains stage 3. |
| Hosted lifecycle acceptance | With paired deployments complete, verify signed-in pending denial, explicit fresh-auth restoration and necessary refund/settlement exceptions using authorized disposable identities. Then review the exact deletion-request activation and user-facing wording. No enabling grant is supplied by this checkpoint. |

Public inventory browsing and Auth sign-in/password recovery remain intentional;
login never restores lifecycle access. Ordinary RLS uses statement snapshots,
not cancellation of in-flight operations. Preserve provider completion,
reconciliation and accepted refund exceptions independently of human admission.
Permanent cleanup, its scheduler and implementation of the approved retention/balance
treatment remain separate unfinished agent work under Cleanup Preparation above.

## Local Verification

Independent local gate: 345 client/neighbor VM cases, 41 reported PostgreSQL
passes (40 scenarios plus parent), and all 62 final Edge cases; zero failures.
Scoped client analysis is clean. Evidence and precise boundaries:
`/private/tmp/cleanstream-lifecycle-independent-qa-20260930/HANDOFF.md`.
These are overlapping focused checks, not additions to the campaign full-suite count.

Prerequisites are read-only symlinks to the approved app files: profile authority,
loyalty policy, admission, profile/terms enforcement, their three synthetic fixtures,
and `scripts/test-support/policy-admission-pg.mjs`. No whole workspace or website
financial source was copied. Apply the candidate only after those prerequisites.

Focused SQL: PostgreSQL 17.11 with disposable private Unix socket, no listeners,
40 scenario tests plus the parent test (41 passed). Covers real lock waits,
request/restore ordering, stale/cross-account sessions, bans, current TOTP and
unsupported factors, exact deadline exclusion, session freshness, unchanged
Auth/profile/representative linked financial rows, ACLs and suppression. These
fixtures do not prove hosted JWT signatures, full financial schema compatibility,
or deployed owner privileges. No campaign rerun or production test was performed.

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin node --test scripts/account-lifecycle.test.mjs
DENO_DIR=/tmp/cleanstream-backend-tooling/cache /tmp/cleanstream-backend-tooling/deno-2.9.7/deno test --cached-only --lock=/private/tmp/cleanstream-account-recovery-test.lock --frozen --node-modules-dir=none --allow-env supabase/functions/delete-account
```

Initial Edge verification: 24 tests passed, including real `index.ts` adapter HTTP interception with
no network permission. Actual `deno.json` compiler/test configuration used;
`nodeModulesDir=none` avoids unrelated npm installation. Repository frozen lock
is missing eleven standard-library entries for the already-existing server import.
The temporary test lock copies every repository pin and adds only those eleven
entries. No repository config, dependency or lockfile change. Local package-cache
fetches were needed; no project/provider endpoints were contacted. A frozen run
against the unchanged repository lock remains a pre-existing verification gap.
Formatting and `git diff --check` pass. Default Deno 2.9.7 lint reports four
`no-import-prefix` diagnostics for the repository-style HTTPS imports (including
the new adapter test); no lint config changes or suppression were introduced.

Focused acknowledgement follow-up: 40 changed Edge cases passed, 22 unchanged
cases filtered out, using the same Deno command with
`--filter '/pending acknowledgement|captured bearer|actual adapter/'`.
Coverage includes malformed shapes, exact key membership, wrong subject, active
state, invalid UTC/calendar dates, expired pending, and all canonical pending
prerequisite combinations. Invalid responses dispatch once and return unknown
503, never retry automatically. Only the handler logic, its two nearest test
files and this document changed. Lifecycle migration, SQL fixture and PostgreSQL
runner hashes remain identical; SQL and financial suites were not rerun.

Official references checked: [Supabase sessions](https://supabase.com/docs/guides/auth/sessions)
for `session_id` validation and [RPC](https://supabase.com/docs/reference/javascript/rpc)
for caller-authenticated calls. Read the existing local changelog snapshot after
the markdown endpoint fetch failed; no applicable Auth/RPC breaking change found.
