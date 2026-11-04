# Bounded Backend Lane Handoff

## Current Checkpoint

Composer recorded Owner development rollout on verified project `dnuuhupoxjtwqzaqylvb` (`e9296f`): refreshed preflight `05c0e9`, exact SQL `a66ff411` installed exit0 `a89d46`, postflight `fbe628` all14 bodies/owners/settings/ACLs matched, exact history `01632b`. Wallet policy/invoker view preserved; last-Owner trigger/index valid; deletion/bootstrap held. Admin-portal ACTIVEv3 gatewayfalse (`3e9604`), delete-account ACTIVEv30 gatewaytrue (`585196`), unauth401 both (`8d1fd3`). No account grants/roles/balances/customer changes. Owner43PG/96Deno and follow-up92 passes retained. Cortina post-wait source remains undeployed pending public return reader. Current detailed records: `owner-management/HANDOFF.md` and `deletion-admission-followup/HANDOFF.md`. Only documentation updated; no author runtime/remote/source changes.

## Historical Evidence

The older batch narratives below describe their original checkpoints, not current activation instructions; current per-batch handoffs and the checkpoint above supersede pending-state language. Do not replay installed schema/history or accepted tests.

Current source candidate, NOT integrated/activated: only the confirmed UNAPPLIED
`supabase/migrations/20260929234955_loyalty_policy_acceptance.sql` descriptor
text/version/hash/comment and `scripts/loyalty-policy-acceptance.test.mjs` fixture
source changed. Exact Avicenna seven paragraphs, 2098 UTF-8 bytes, two LF separators,
no trailing newline. New version `review-only-loyalty-d08c2c970e4fb2f7`, policy digest
`d08c2c970e4fb2f7255034ee643f6148454f7aca3c09e595c5eb94d10106e748`.
Migration SHA `259d42771722c6a51f84c9688624db3553fa377d770acedfb41d7f230c9c4c6a`;
runner SHA `b9af9b3e5c2abb6a256e8c1c9f224a921fe761466c0f3061f9c1acbbfa56d792`.
Reuses SQL descriptor constants; removes stale hardcoded version/hash and static
LegalPage extraction. Existing digest/public-status equality, exact consent,
first-timestamp replay, ACL and real-lock checks preserved, expected37 including
parent. Added fixture version/digest-prefix consistency assertion; no behavior
assertion removed. Source byte comparison and scoped whitespace check pass; new
runtime count is UNRUN. No new migration, SQL behavior, acceptance backfill,
retention decision, activation, active edits or provider call. Hosted runbook
above-baseline receipts remain frozen; its old descriptor hash is historical,
not this new candidate's approval. Composer/QA must accept the new source first.

QA command from this lane (single Node1024, existing private disposable harness):

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin POLICY_TEST_PROFILE_GUARD=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260929223124_protect_profile_authority.sql /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/loyalty-policy-acceptance.test.mjs
```

Current hosted checkpoint: composer installed exact guard1
`20260929223124_protect_profile_authority.sql`, SQL --linked exit0/922886, no DML;
trigger enabled=O confirmed exit0/d5cbcc. Six effective INSERT/UPDATE grant results
all false, exit0/452ac6; CLI migration repair recorded only20260929223124 applied,
exit0/0a5789, other history preserved. Recovery-only delete-account code and
helpers deployed --use-api exit0/ba4c52, no Auth deletes; missing lifecycle RPC
fails closed. NEVER restore the hard-delete handler. Inventory remains20+3=23
because this replaced an existing function. Other five SQL migrations remain HELD
for contradictory review-only terms alignment and whole-API lifecycle coverage.
Exclude installed guard1 from future bundles; no purge/retention changes or sends.

`HOSTED-ACTIVATION-PREFLIGHT.md` records source paths/hashes, remaining-five atomic
assembly and rollback boundaries, and pre-change catalog receipts on verified dev
dnuuhupoxjtwqzaqylvb (PG17.6, exits0/b856c2,fde77a). public.wallet_ledger_entries
exists: no foundation/backfill. Private schema/canonical/mail objects remain absent
per last catalog inspection. Composer alone is remote writer; this lane made only
documentation edits, no new queries, mutations or tests. Geocoding uses canonical
current Owner identity, no quota schema. Final read-only implementation review of
integrated active admin-portal logic/backend/index/geocoding and handler found no
required fix: captured actor/current Owner recheck before provider, five-second
abort covers fetch/body reads, 16KiB bound, controlled429/no retries. Review sent
to Kepler/composer; QA8+8 remains queued, not an author test claim.
Three new mail functions deployed individually; empty smoke503/401/401 establishes
disabled/auth boundaries, not feature activation. Component secrets absent;
restricted Resend-key approval pending. Never concatenate inner COMMITs into a
supposed outer transaction; re-freeze corrected terms before remaining-five use.

Current assignment: approved Owner-only verified customer MFA recovery implemented
locally, independently QA accepted and integrated exact by composer; no slot held. Own
`20260930202731_customer_mfa_recovery.sql`, dedicated
`customer-mfa-recovery/{index.ts,index.test.ts}`, and
`scripts/customer-mfa-recovery.test.mjs`. Reuses canonical staff/admission,
immutable audit, named-key helpers and existing PG fixture/harness. One durable
target fence precedes snapshot-only Auth removal, survives unknown outcomes,
rejects old sessions, and mandates fresh-session/new-TOTP reenrollment. Owner
freshness/post-wait checks, Admin/privileged target rejection, temporary role
guard. No Auth SQL writes, shared active edits, provider calls or deployment.
API/prereqs/rollback/QA commands in `LOST-MFA-RECOVERY.md`. QA PostgreSQL47 children
+ parent =48 passed, zero failures/skips, exit0/chunk48d196; PG17.11 stopped and
owned temp5L0X58 removed. Deno43 passed + typecheck, exit0/chunk3f260e; all
processes exited. No author rerun. Real SDK emits the synthetic timeout diagnostic
to stderr in its failure test; API response remains sanitized and no retry occurs.
Hosted Auth/gateway and frontend adoption remain release checks, not local proof.
Runbook now suitable for composer copy to `docs/customer-mfa-recovery.md`; gateway
recommendation is per-function verify_jwt=true for human Owner JWTs, with the
current documentation conflict and hosted asymmetric/named-key check explicit.
No config changes or runtime reruns. Composer reports hosted function absent;
source integration does not establish deployment. Frontend exact API/error rules
are documented and agreed with current UI owner Ramanujan, root
`.campaign-work/owner-mfa-ui`: session-bound adapter, Owner/nonpreview inspect-
confirm, same-case unknown-outcome recovery, fresh sign-in without autoreplay,
and no false completion. Frozen adapter review pending; no runtime source changes
or new backend scope.
Quote/status abuse frozen without code. Independently
reviewed Dalton's assigned authenticated request-ID lookup; he owns its files.
Lookup source accepted after returned Auth-error503 correction; runtime remains
unrun. Integrate only new pending_lookup helper/test + his
`qa/cortina_pending_status.patch`, not the older full lane logic.ts. Client
owner-lookup patch remains separate from secure-storage baseline; dependency and
QA acceptance belong to the owning lanes, not this handoff's completed tests.

Prior Edge follow-on: six production files independently accepted by QA and
integrated exact by composer:
new `_shared/new_payment_control.ts`, paymentIntent/createCheckoutSession
`logic.ts` and `index.ts`, and cortina-vend/logic.ts. Exact accepted active
Cortina behavior preserved; no `_shared/cortina.ts` edits. Nearest tests added/
adapted, no author execution. Feature-only deployment dependencies and development
authorization boundaries are in `NEW-PAYMENT-DEPLOYMENT.md`. Empty unfunded draft
on refusal is approved; no new charge/debit/Start, funded replay remains available.
QA source P2 corrected before runtime: exact SQL PT503/new_payments_unavailable
after the Edge precheck now returns503 without marking the draft failed or Start.
Other wallet errors retain402/failed handling. QA accepted **139 passes**:
primary105/typecheck0 (session93870, exit0/chunk3e246d) plus original nearest
logic34/typecheck0 (direct exit0/chunk8fa0ce). All processes exited. P2 closed
with exact late-refusal regression and unrelated-error controls. No admission85
or SQL rerun/runtime claim, no author execution. Existing logic-test changes are
necessary enabled-control fixture responses, not weakened assertions.
Current SQL migration/runner below remain frozen and accepted, no reruns.

Current integrated checkpoint: composer integrated the exact accepted four
funding-creation server-key files after **47 QA passes/typecheck**. No local
runtime work is pending for that batch; staging API-version/gateway checks remain.
Wallet-read48 and complaint45 are accepted/integrating as separately recorded.
Current assignment: local new-payment-only backend control, independently
accepted by QA and frozen for composer integration (no author execution). Owned migration
`supabase/migrations/20260930193130_new_payment_service_control.sql`, runner
`scripts/new-payment-service-control.test.mjs`, and `NEW-PAYMENT-CONTROL.md`.
One private singleton defaults enabled; fixed boolean reader/private assertion;
only the two existing human wallet debit bodies gain pre/post-wait checks.
Existing locks, admission wire, grants and settlement/recovery paths are retained.
QA accepted split-run evidence: retained first 23 child passes plus final
remaining 16 children + parent = 17 passes, zero final failures, exit 0 (3.6s,
session87006/chunk64557d). All 39 distinct children + parent covered; NOT a fresh
full40 run. Final --test-skip-pattern deliberately excluded the first 23.
PG17.11 stopped/temp 2UFy64 removed; all processes exited. Frozen runner SHA256
9c99dd9377d62749a5658f663046229d843cd254800c12804922d5e87179ffde;
migration SHA256 78ec7fa772441698e10eeb4109fb219ba2147f6759414e30720b63e16ee8021f.
Both initial QA runs stopped in setup:
duplicate Machines.is_out_of_service, each 0 child passes/parent failed, exit 1;
PG stopped/temps nuPTuZ and GnDd8S removed. Source-order review identified the
later admin-extension migration as column owner; earlier fixture addition removed.
Support-refund fixture now supplies the transaction required by portal assertCredit.
Next QA reached cases: 23 passed, then paired-terms fixture constraint failure
closed shared psql (16 child failures including 15 cascades, parent failed, exit 1).
PG stopped/temp a3qgtt removed. Fixture now clears version AND acceptance timestamp;
remaining mutations source-reviewed. Constraints/assertions/migration unchanged.
Corrected source independently accepted; no author execution or rerun needed.
QA owns checks; no process or test slot held by this lane. Operator grants,
rollback boundaries, exact command and Edge follow-on gap are in the runbook.
User now authorizes requested features on the DEVELOPMENT hosted project, then
testing; this lane has performed no remote action. No paid provider actions,
destructive retention cleanup or key retirement. No unrelated follow-on scope.

Wallet batch **frozen and independently accepted**: Descartes reports final
Cortina coexistence chain **43 child cases + parent = 44 passes**, no failures/
skips/cancellations, exit 0, 6069 ms. PG17.11 stopped; owned temporary root
`/private/tmp/cleanstream-wallet-locking-policy-pg-mw1PYm` removed; all processes
exited and QA released slot. No author rerun; this lane has no slot/process.
Owned frozen migration `supabase/migrations/20260930171558_human_wallet_spend_admission.sql`
is unchanged. Runner `scripts/human-wallet-spend-admission.test.mjs` now composes
actual selectors/history plus exact reviewed binding/ownership SQL snapshots in
`supabase/tests/human_wallet_spend_reviewed/`; valid vend fixtures exercise the
real insertion guard without weakening the original 43 cases. Composer integrates
only migration + runner, replacing snapshot reads with identical active migration
reads; no copied SQL duplication in active. Details and earlier author44 evidence
are in `WALLET-SPEND-ADMISSION.md`. No provider/active edits or activation.
Cleanup remains frozen except its separately assigned index-only secret selector
and new selector test below. Maintenance's four artifacts remain frozen.

Legacy machine claims are **integrated by composer** after author66, independent
source acceptance and paired Flutter19. Exact SQL preserved; runner snapshot
reads use identical active migrations without duplicating SQL. Frozen evidence:
Owned new CLI migration `supabase/migrations/20260930180614_legacy_machine_claim_atomicity.sql`
and `scripts/legacy-machine-claim.test.mjs`, plus `LEGACY-MACHINE-CLAIM.md` and
this handoff. Corrected PG17.11 run: **65 child cases + parent = 66 passes**, zero
failures/skips/cancellations, exit 0, 6348.343083 ms. Server stopped and owned
`/private/tmp/cleanstream-wallet-locking-policy-pg-ZvIZyN` removed; all processes
exited. Slot released to composer, no direct transfer or other checks. Initial
64-pass/one-child-failure run is recorded separately in the contract note: only
the late-factor fixture's role became Admin to match existing mandatory MFA.
Migration unchanged; no assertion or canonical policy weakened. Descartes reports
no actionable source findings and accepts the corrected fixture/contract while
retaining author66 evidence; no additional QA runtime run. Deployment remains
separate. No wallet/older suite rerun.
Composer owns paired client adoption; email
lane Ramanujan confirmed notice enqueue remains a separate post-commit call.
One legacy-only authenticated RPC reuses canonical Home admission and the existing
14-day window/claim receipt/counter; atomic claim+flag+counter, no money writes,
no new table/dispatcher, and read-only replay with historical ambiguity rejection.
No original routines, guards or grants removed. Auth -> transaction -> profile
locks and post-wait checks; tests use the existing disposable PG harness and
reviewed coexistence prerequisites, including decimal-string bigint decoding.
Exact command and boundaries are in `LEGACY-MACHINE-CLAIM.md`. Old direct writers
require coordinated rollout; no universal deduplication or verified-vend claim.

Other admission gap identified, not assigned/implemented: ordinary direct wallet
reads still use self ownership without canonical eligibility in
`20260526010000_wallet_ledger_compliance.sql` and
`20260930142406_admin_canonical_authorization.sql`. The invoker balances view
inherits those policies. Keep `list_voluntary_topup_refunds`' intentional
`lifecycle_identity_allowed` exception separate. Human funding intent/checkout
creation verifies Auth but lacks canonical admission; do not gate shared funding
settlement RPCs. Admin wallet RPCs remain revoked pending explicit authority.

## Integrated Funding Batch

Next assigned source inspection identifies **new human funding** as the highest
risk remaining ordinary entrypoint: active `supabase/functions/paymentIntent/logic.ts`
`handleCreatePaymentIntent` and `supabase/functions/createCheckoutSession/logic.ts`
`handleCheckout` authenticate identity but never evaluate canonical lifecycle,
session/MFA or terms before service wallet creation and Stripe payment creation.
Mobile `stripe_service_mobile.dart` and Flutter web `stripe_service_web.dart`
call these paths with `walletLoad`; existing provider status/webhook completion
uses the shared financial helper and must stay independent of human admission.

Composer approved and the owned source now implements caller-bound original-bearer
`get_admission_status()` must match the verified user and report eligible/Home,
first before wallet creation and again after its await before Stripe creation.
No new SQL/RPC. Changing shared `get_or_create_wallet_account` or
`record_wallet_load_from_stripe` would also affect settlement/refund paths.
Exact owned code: `supabase/functions/paymentIntent/{index.ts,logic.ts}`,
`supabase/functions/createCheckoutSession/{index.ts,logic.ts,logic.test.ts}` and
new `supabase/functions/_shared/wallet_funding_admission.ts` with its adjacent
`.test.ts`. Unchanged `paymentIntent/logic.test.ts` remains nearest coverage.
The dedicated helper removes duplicated caller-RPC transport, wire validation
and sanitized error handling from the two endpoints; it is not a new evaluator.
The canonical RPC must return the captured verified subject, eligible access and
Home; missing, malformed, failed or mismatched responses stop before Stripe.
Both checks keep the original bearer, never use an admin JWT as the human actor,
and the verified subject is captured before wallet awaits. Direct-machine
behavior, metadata, amounts and valid funding response shapes are retained.

Existing `_shared/supabase_keys.ts::callerPublishableKey` is reused unchanged.
This missing lane prerequisite was staged with exact active SHA256
`4d0397f536d26938d5e1bfeae07ca55c40c2f6f631583de25f3dead1c458e05b`;
do not integrate it as an overwrite. Optional
`CLEANSTREAM_FUNDING_PUBLISHABLE_KEY_NAME` selects an exact named public key;
absence preserves `SUPABASE_ANON_KEY`, explicit invalid selection fails closed.
No service key selection or key-helper logic was changed. Dalton confirmed his
`_shared/cortina.ts` ownership does not overlap; no payment worker/binding/callback
or settlement/refund source was edited. No global Owner/Admin policy assumed.

Author Deno2.9.6 heap768: new helper suite **81 passes, zero failures/skips**,
typecheck and exit 0 (18 ms tests); fmt/lint two new files passed. Initial combined
115-case load exited 1 before cases because locked std0.168 assertions were absent.
Composer subsequently cache-resolved the four exact locked public files without
version/lock/import changes and reports original **34 passes + typecheck, exit 0**.
All author processes exited; authorized slot transfer to Dalton completed.
QA source accepted the funding contract. No slot or process held here.

Composer integrated all seven funding files after exact existing-file baseline
match and final delta acceptance. Author timeout filter **4 passes, 0 failures,
81 filtered**, typecheck/exit 0, 6 ms. `AbortSignal.timeout(8000)` bounds both
canonical checks; rejection is sanitized 503 before provider creation. Signal
assertions run outside the handler catch path. Full source now contains 85 cases;
evidence is prior81 + delta4 + composer original34, not a full85 rerun.
Provider fetches are mocked; no network or environment secrets are permitted.

The gate is admission to new work, not atomic cancellation of an existing
external provider object; settlement and current refund exceptions stay intact.

## Funding Server Keys Integrated

New, separately approved four-file batch: existing
`supabase/functions/paymentIntent/index.ts` and
`supabase/functions/createCheckoutSession/index.ts`, plus new adjacent
`index.test.ts` in each directory. Previously integrated funding logic/helper and
all existing logic tests stay unchanged. Ramanujan owns STATUS indices, not these.

Optional exact selectors `CLEANSTREAM_PAYMENT_INTENT_SECRET_KEY_NAME` and
`CLEANSTREAM_CHECKOUT_SECRET_KEY_NAME` reuse unchanged `selectNamedSupabaseKey`.
Only absent selectors retain legacy service-role transport; explicit invalid
configuration returns sanitized 503 before body consumption or SDK construction,
with no default/other-component/legacy fallback. Modern service secrets remain
in apikey; the SDK-generated secret Authorization is removed while explicit
`getUser` caller bearer stays intact. Caller-bound public admission remains separate.
Plain exported handlers and `import.meta.main` Deno.serve guards permit actual
SDK/fake-HTTP tests. Checkout's old external serve import is removed. SDK clients
disable session persistence/refresh; Stripe uses its existing fetch HTTP adapter.

Per explicit composer instruction, paymentIntent's local API literal changes from
2024-06-20 to 2023-10-16 for locked Stripe14.25.0; checkout already uses that value.
Tests assert the real Stripe-Version header. No cast, SDK/lock upgrade, remote
Stripe account setting or webhook version change. Staging verification of both
request shapes and hosted modern-key/gateway behavior is a release gate.

Descartes source/runtime accepted the frozen batch: **47 passes** (24 intent,
23 checkout), typecheck/exit 0, 110 ms, completed process `ffd0a4`; all processes
exited, no source/lock edits. Production diff whitespace check exit 0; both new
test no-index checks exit 1 with empty output (additions, no whitespace errors).
Composer integrated exact accepted four files; no author duplicate run. The one authorized trailing-space
removal leaves intent test SHA256
`3a7b1c3e59a5787404a021d1044e702ff6f5f0c09e95dbdb94e00296cfe72675`.
Coverage starts with real Supabase/Stripe SDK named/legacy happy paths, then
invalid selector/maps, sanitized pre-SDK denial, independent public selector,
caller/auth/admission denial, CORS/method handling and existing direct-machine path.
No provider/network/env permissions or full funding/older suite reruns. Exact command:
`/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt supabase/functions/paymentIntent/index.test.ts supabase/functions/createCheckoutSession/index.test.ts`
QA owns the queue; no author checks or processes. No new shared transport framework.

## Server Release Control

Gap: inspected backend admission and payment paths have no server-owned global
new-payment shutdown policy. Firebase `release_policy_v1` is client policy only
(`config/firebase/RELEASE-CONTROLS.md`); its schema blocks platform build numbers,
not exact semantic versions. Public keys, channel/body claims and version headers
cannot prove which binary is running. No trusted build attestation contract exists
in these paths; do not claim server-enforced selective binary shutdown.

Existing controls and constraints, active app paths:
- `20260930063923_recoverable_account_deletion.sql:32` is the shared account
  evaluator; refund identity and staff/recovery paths rely on its exceptions.
  Do not add a broad operational block here.
- `20260930013417_enforce_profile_terms_admission.sql:138` projects Home admission;
  wallet reads/spend and walletLoad creation already consume it. The strict
  `lib/logic/models/admission_status.dart` six-field parser does not accept a new
  maintenance reason/state without paired adoption. Do not mislabel maintenance
  as an account ban or silently extend the wire.
- `paymentIntent/logic.ts` and `createCheckoutSession/logic.ts` check canonical
  admission only for walletLoad. Their legacy direct-machine branch would bypass
  a shutdown implemented only in the funding admission helper.
- `cortina-vend/logic.ts:71` permits guest card creation; `handleWallet` is a
  separate human creation/debit entrypoint. A signed-in-account-only stop misses
  guest card creation and pending-session creation replays.
- `_shared/cortina.ts` quote/session checks and SQL
  `20260930154259_freeze_cortina_payment_bindings.sql` enforce per-machine
  `is_enabled`/review flags. Those are real machine controls, not a global
  funding stop. `startCortinaVend` also consumes them for already-paid work and
  compensates when disabled; bulk-flipping them is not a creation-only shutdown.

Approved first backend contract: stop NEW payments while keeping
read-only status, support, recovery, callbacks, refunds, reversals and reconciliation
available. No existing global policy record was found to extend safely. A single
private singleton boolean plus a fixed read/check function is the minimal durable
configuration, not a generic flag/version framework. Write authority is
server/operator-only, never the unresolved Owner/Admin wallet authority.
The approved default is ENABLED: installation preserves behavior, no shutdown
is activated. Missing/corrupt configuration fails closed for creation only.

Enforcement belongs at existing human creation boundaries: both funding purposes,
Cortina card and wallet initiation, and both authenticated wallet-spend RPCs.
Revalidate at existing SQL financial waits and immediately before provider object
creation; include existing pending-session replay that can create a new object.
Keep shared financial recording/Start/compensation and confirm/status/callback/
worker paths ungated. Edge prechecks cannot undo an already dispatched provider
request or make a policy toggle atomic with Stripe; document that boundary.
Global maintenance UI can accompany this creation stop, but this is not a claim
that every authenticated read/support/admin API is disabled. Any broader server
maintenance scope needs an explicit allowlist contract first.

Backend-only source now ready: the new CLI migration, focused SQL runner and
operator runbook named at the top. No author tests run. This batch gates only
the two existing human wallet RPCs; Edge creation enforcement is a follow-on
after backend acceptance, not complete shutdown coverage yet. Cortina belongs
to another lane; no runtime/key edits. Global wallet roles/purge remain open.

## Cleanup Selector Accepted

Distinct two-file scope: `supabase/functions/account-cleanup/index.ts` and new
`supabase/functions/account-cleanup/selector.test.ts`. Reuses unchanged shared
`selectNamedSupabaseKey(name, SUPABASE_SECRET_KEYS, "secret")` for optional
`CLEANSTREAM_CLEANUP_SECRET_KEY_NAME`. Absent name preserves legacy service key
and bearer header; explicit invalid selection fails closed without fallback.
Modern selected secret travels only in apikey, matching accepted reconciliation
transport; no caller Authorization is forwarded. Credential selection is lazy
inside preview RPC, preserving disabled/worker authentication gates and sanitized
runtime error handling. No shared helper or cleanup logic/migration changes.
Run always returns policy-unapproved 503; no claims/purge/scheduler/provider path.

New **28 offline selector cases pass**, 0 failures, typecheck/exit 0, 17 ms.
Descartes independently source-accepted the two-file contract; composer integration
is pending. Scoped fmt/lint four files (funding helper/test + selector index/test)
both exit 0. All author processes exited; explicit slot transferred to Kepler,
who subsequently released it to composer. Checks cover named/legacy transport,
invalid configuration, disabled/auth failures, and no key/RPC for run. Command:
`/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt supabase/functions/account-cleanup/selector.test.ts`
No real secrets, environment permissions, provider calls, activation or old-suite
reruns. Hosted gateway validation remains a coordinated release check.

## Wallet Read QA Accepted

Composer approved only ordinary self-wallet admission; no global authority change.
Read-only source findings from the active app tree:

- `supabase/migrations/20260930142406_admin_canonical_authorization.sql:141`
  already ANDs self-only SELECT restrictions onto wallet accounts, loads, ledger
  and redemptions. These four predicates omit lifecycle/MFA/terms admission.
- `supabase/migrations/20260526010000_wallet_ledger_compliance.sql:119`
  defines the security-invoker `wallet_balances`; it inherits the table policies.
  `lib/services/supabase/supabase_wallet_service.dart` uses that view and ledger
  table for ordinary customer reads. Restricted callers can still read own rows
  under this SQL chain; no broad Admin cross-account permission is inferred.
- `supabase/migrations/20260930142406_admin_canonical_authorization.sql:108`
  revokes all three global money/status RPCs. Their actual locked implementations
  are in `20260929231120_serialize_wallet_financial_writes.sql:269`; do not regrant
  these functions or change financial invariants under the read-policy fix.
- `supabase/migrations/20260526010000_wallet_ledger_compliance.sql:527` and `:855`
  define/grant `record_deleted_account_complaint(uuid,text,text)`. It remains an
  authenticated-callable global definer with Owner/Admin eligible-role check,
  but no Home/terms requirement or post-wait recheck. The restrictive false
  complaint SELECT policy does not block this INSERT function. This is a distinct
  policy-sensitive gap, not a money mutation or approved deletion remedy.

Owned exact runtime/test paths: CLI-created
`supabase/migrations/20260930184955_wallet_read_admission.sql` and
`scripts/wallet-read-admission.test.mjs`. Four additive restrictive SELECT policies
require existing caller-bound `get_admission_status()` subject/eligible/Home via
scalar subquery; all prior self restrictions, functions, ACLs, money and invoker
view remain unchanged. Required self-only policies/RLS/view are checked before DDL.
No helper/RPC replacement or global guard changes. Canonical definer profile and
policy reads do not depend on wallet tables; actual-role tests exercise recursion.

Descartes source and focused runtime accepted the exact frozen pair without edits:
**47 child cases + parent = 48 passes**, zero failures/skips/cancellations,
Node24/PG17.11, exit 0; session 24604 closed. PostgreSQL stopped and owned temporary
directory ending `TjeFtp` removed. Composer notified by QA; no author duplicate run.
QA retains the sole test queue. Runner reuses existing disposable PG relocation and
loads actual financial/history/terms/lifecycle/refund/portal/admin SQL, with synthetic
data only. Tests preserve functions/ACLs/policies/view/data, exercise self/cross-user
and Owner/Admin self-only reads, restricted session/email/MFA/lifecycle/terms,
restoration, canonical lock waits, service late funding, and pending-deletion
top-up list/request/replay/Owner review/service settlement without reopening direct
reads. Complaint function and three global RPC revokes are asserted unchanged.
Exact completed QA command:
`PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/wallet-read-admission.test.mjs`

Conditional Owner-only global proposal, NOT an approved authority decision:
keep the three RPCs revoked until explicitly approved replacement scope. Any
replacement must use verified current actor + canonical Home + exact trusted
`profiles.roles='Owner'`, reject Admin/customer/anon/service impersonation, and
revalidate after existing wallet/profile/trigger waits before commit. Preserve
wallet-before-profile order and existing split/paid-balance/amount/status guards.
Never modify shared `is_admin_or_owner()` or reuse the top-up-specific Owner
helper as generic wallet authority. Wallets have no location column; infer none.
Complaint admission is handled separately below without changing the existing roles.

Existing `supabase_admin_wallet_service.dart` search/detail expects direct global
wallet/profile reads, currently closed by restrictive policies. A future Owner
read contract and paired client adoption need separate approval; do not reopen
profile RLS or grant all Admins access to make this old screen appear functional.
No client or global guard changes are made by this batch. RLS denial yields no
ordinary rows (or the canonical authorization error); existing client empty-wallet
presentation is not proof of zero balance. No remote policy/deployment changes.

## Complaint QA Accepted

Composer approved the bounded correction; Descartes source/runtime accepted the
exact frozen pair without edits. **44 child cases + parent = 45 passes**, zero
failures/skips/cancellations, Node24/PG17.11, 3429.73 ms, session 96114 exit 0.
PostgreSQL stopped, owned temporary directory ending `nbWd3q` removed, all
processes exited. Composer notified by QA; no author duplicate run.
Owned paths: CLI-generated
`supabase/migrations/20260930190143_complaint_admission_recheck.sql` and
`scripts/complaint-admission-recheck.test.mjs`. Existing
`record_deleted_account_complaint(uuid,text,text default 'denied') returns bigint`
is defined in the wallet foundation at line 527 and authenticated-granted at 855.
`SupabaseAdminWalletService.recordDeletedAccountComplaint` and the admin wallet
page call it. It inserts one note/resolution/wallet FK/actor record; it does not
move money, require a deleted wallet, or authorize a remedy/retention decision.
Current Owner/Admin predicate already checks canonical eligibility, but only
before INSERT; FK or trigger waits can outlive caller authority.

Implemented bounded correction: replace only that body, preserving signature, ACL,
default, note validation, table constraints, return ID and historical records.
Reuse `private.portal_staff_context()` before INSERT and after RETURNING for fresh
canonical session/email/MFA/lifecycle + existing Owner/Admin role; capture actor
for `created_by` and require the same actor afterward. Do not compare locations,
invent wallet location, or impose customer loyalty terms on the existing staff
review contract. Post-wait denial rolls back the INSERT. No new helper, target
lifecycle restriction, read grant, global money regrant, client or cleanup changes.
No global money RPC is regranted; empty definer search_path is explicit. The
existing staff helper and all shared/caller files are reused unchanged.

Frozen QA handoff: **45 accepted passes**, no author duplicate execution.
Runner loads actual canonical/admin/financial/refund SQL and accepted wallet-read
migration using the existing disposable PG helper. Coverage includes both staff
roles and wallet statuses without location/terms rules, preserved historical and
repeat records, note/resolution/FK constraints, pre-denials, nine real wallet FK
waits, three AFTER INSERT waits, captured-actor mismatch, and unchanged money,
ACLs, policies, defaults and global revokes. No caller/provider/retention changes.
QA owns serial execution and may write test output, not modify these sources.
Exact command from this lane:
`PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/complaint-admission-recheck.test.mjs`
Private socket/authorized owned relocation/PG stop and temporary-root removal
remain mandatory. No wallet48 rerun or automatic follow-on scope.

## Frozen Attachment Evidence

Maintenance attachment contract **TEST SLOT RELEASED**, **64 PG
cases + parent = 65 passes**, no failures/skips/cancellations, process exit 0.
PostgreSQL 17.11 stopped and owned temporary root removed; no activation.
Exact four owned paths, unchanged client behavior, source
findings, command and deployment gaps are in `MAINTENANCE-ATTACHMENTS.md`.
All edits are under this isolated root; no active
checkout or other lane writes. The additive migration alone leaves old runtime
paths unchanged; the separate Storage-owner policy artifact intentionally tightens
permissions and is held for coordinated client/authorized policy rollout, not
claimed safe to deploy independently. Public bucket privacy is unchanged.
`CLEANUP-ACTIVATION.md` is finalized as source-backed missing policy inputs. The
eight cleanup code/test files below remain frozen and were not rerun. Their
prior evidence is separate from the attachment results above.

## Frozen Cleanup Evidence

TEST SLOT RELEASED. **7/7 true PostgreSQL race cases passed** (8 runner passes
including the parent), exit 0. Server stopped and owned temporary root removed.
Prior **22/22 PGlite + 42/42 Deno** passes retained, not rerun. Node heap 1024 MiB;
earlier Deno heap 768 MiB. No host links/install, production/provider calls,
integration or activation. Request gates are unchanged. This verifies preparatory
metadata/locking, not completed purge.

## Owned Changes

- `supabase/migrations/20260930154911_account_cleanup_claims.sql`, created by
  Supabase CLI `migration new account_cleanup_claims`.
- `supabase/functions/account-cleanup/{index.ts,logic.ts,index.test.ts,logic.test.ts}`.
- `scripts/account-cleanup.test.mjs`, `scripts/account-cleanup-races.test.mjs`,
  `scripts/test-support/account-cleanup.mjs`, this handoff, and the requested
  source-backed policy-input note `CLEANUP-ACTIVATION.md`.

Only new files in this isolated lane. No active app/web or other lane edits.
Existing recovery/newsletter migrations, delete-account, mail and config untouched.

## Smaller Diff / Rationale

- Three tables reduced to **one eight-column private job table**, one row per
  account. Removed control/clearance tables, policy-version/review-reference
  fields, approval fixtures, private eligibility helper and manual-review state.
  No human approval system remains. Migration is now 154 lines; Edge logic 116.
- Removed Edge `claim`/`retry` actions and their acknowledgement machinery.
  Edge accepts only read-only `preview` or `run`. The environment gate defaults
  off; even enabled, `run` returns `cleanup_policy_unapproved` before any RPC.
  No supported/approved destructive policy exists in server code. Caller fields
  and flags cannot approve one. No purged/completed state or result exists.
- The job row contains only exact request identity, lease token, attempt count,
  bounded used-token list, retry/unknown state and server lease/retry times.
  It stores what lifecycle does not: ownership of attempted work and uncertainty
  across a lost response. At most five tokens prevent old-token reuse; one row
  replaces prior request metadata instead of growing an approval/history system.

## Preserved Contract

- Service-only preview/claim/retry SQL routines reuse existing lifecycle deadlines
  and Auth SHARE -> profile NO KEY UPDATE -> lifecycle UPDATE locking. Eligibility
  uses wall-clock time after lock waits and compares exact request microseconds.
  Existing restore, request, admission and newsletter code is untouched.
- Lost live-claim responses replay idempotently. Leases last five minutes;
  transient releases back off from 60 seconds with a five-attempt cap. Stale
  request/token releases cannot affect current work. Unknown outcomes remain
  parked as `outcome_unknown`, without automatic retry or a new approval flow.
- A lease is NOT permission to delete or evidence of settlement. The SQL routines
  only write job metadata; Edge cannot currently call the mutating routines.
  No Auth, wallet, payment, lifecycle, marketing or Storage mutation is added.
- Retained authored tests for exact 720-hour/non-UTC deadlines, expired restore,
  successful restore, post-lock rechecks, simultaneous claims, unknown outcomes,
  old tokens and byte-preservation snapshots. Single-session and Edge results are
  recorded below along with the independent-session lock-race results.
- Reused canonical lifecycle/locks, prerequisite fixtures and independent-session
  PostgreSQL harness. No existing behavior/dependency/shared helper was removed.

## Schema Coordination / Activation Blockers

Additive migration only: one private table and three service-only public RPCs.
Composer/backend must review names, owner permissions and migration order before
application. Migrations ran only in ephemeral synthetic PGlite and disposable
PostgreSQL fixtures; no persistent, shared or production database was changed.

Retention by data class and paid balance/unsettled payment treatment are NOT
approved. They remain external blockers, not database approval bookkeeping.
Approved destructive behavior, current settlement fencing and provider outcome
reconciliation must be implemented/reviewed separately before execution. Expired
job leases alone do not make replay of irreversible provider effects safe.
No flag activates purge in this candidate; the executor is blocked, not complete.

No schedules or server secrets were installed. Hosted gateway validation remains
a deployment gate; keep JWT checking and supply `X-Account-Cleanup-Secret`
separately. `ACCOUNT_CLEANUP_ENABLED` must equal `true` to even allow preview;
`ACCOUNT_CLEANUP_WORKER_SECRET` is server-only and at least 32 characters.
This lane did not read current vendor docs online under the no-provider/browser
restriction; no SDK dependency/API upgrade is proposed. Full-campaign/hosted and
actual destructive-executor/provider verification remain outside this evidence.

## Focused Source Self-Review

No runtime/migration changes during self-review; only owned tests/fixtures and
this handoff changed. Composer reported no required fixes from QA source review.
No source/test changes were needed during the granted test slot.

- Existing request/restore lock Auth SHARE then profile NO KEY UPDATE; restore's
  lifecycle UPDATE invokes the AFTER suppression trigger, which takes advisory
  `(726314,1)` and writes consent/outbox even with mail disabled. Existing restore
  rechecks authority/freshness/deadline after that trigger and rolls back on failure.
- Cleanup locks Auth -> profile -> lifecycle -> its job. It never writes lifecycle,
  invokes its trigger, takes the mail lock, or acquires mail rows. Inspected mail
  dispatch/token routines read lifecycle without row locks; newsletter request/
  withdrawal take Auth/profile before mail. No reverse lock path found in source;
  this is not runtime deadlock evidence or a claim about provider effects.
- Owned fixtures now load the unchanged newsletter fixture/migration. Preservation
  snapshots include mail tables and real suppression sentinels. An authored race
  queues cleanup behind restore while the actual mail trigger waits; deadline
  expiry must roll restore/mail writes back before cleanup claims pending state.
- Tests preserve original behavior: successful restore keeps marketing suppressed
  and suppresses late mail rows; a new window requires an explicit request after
  successful pre-deadline restore. Direct timestamp mutations in drift tests are
  explicitly synthetic, not a supported post-expiry restoration/re-request path.
- Exact equality is enforced by existing lifecycle constraints/server comparisons;
  boundary tests exercise denied pre-deadline claims, claim at/past the stored
  deadline, expired restore, microsecond identity and post-wait wall-clock checks.
  Single-session and seven independent-session race assertions passed.

## Runtime Evidence

- Node `v24.19.0` at the assigned runtime path, Deno `2.9.6` (V8
  `15.0.245.2-rusty`, TypeScript `6.0.3`), Supabase CLI `2.84.2`: actual `--version`
  output only, not test evidence. Lost Deno 2.9.7 was not used or copied.
- Shared read-only PGlite package `0.5.8`: 22 cases passed, 0 failed/skipped/cancelled;
  runner duration 1.013 seconds. Included real lifecycle/newsletter SQL in one
  in-memory backend. Closed through the test `after` hook; engine build version
  was not separately queried. PGlite does not establish concurrent lock behavior.
- Deno 2.9.6: 42 cases passed (5 adapter, 37 handler), 0 failed, plus type checks;
  test duration 50 ms. All fetches stubbed; no network permission. The generated
  lane-local Deno cache was removed after the process exited; no shared cache changed.
- Initial native preflight reported PostgreSQL 17.11 (Homebrew), executable directory
  `/opt/homebrew/Cellar/postgresql@17/17.11/bin`. Its compiled sharedir
  `/opt/homebrew/share/postgresql@17` lacks `postgres.bki`, `postgresql.conf.sample`,
  `pg_hba.conf.sample`, and `pg_ident.conf.sample`; compiled pkglibdir
  `/opt/homebrew/lib/postgresql@17` is also absent. Stopped at this first preflight
  failure; no race runner or server was attempted during that initial slot.
  Correction from composer: the complete assets exist under the pinned Cellar
  bottle's `share/postgresql` and `lib/postgresql`, including `plpgsql.dylib`.
  The bottle is unlinked, not incomplete. At composer's request, nine redundant
  preflight/import lines were removed from the race script. The unchanged shared
  harness may relocate executables and link those assets only inside its owned
  disposable root, validating paths and stopping/removing the cluster afterward.
  No system links, installation or cache copying occurred.
- Granted PostgreSQL race run: the first sandboxed attempt failed during `initdb`
  (`shmget: Operation not permitted`), before any race case; exit 1, parent failed,
  0 case passes. No server started; `/private/tmp/cleanstream-wallet-locking-policy-pg-tUS6XX`
  was removed. One approved escalation reran the identical command for local
  shared-memory access; no source changes or installation were required.
- PostgreSQL 17.11 escalation: **7 case passes + parent = 8 runner passes**, exit
  0, 0 failed/skipped/cancelled, duration 5.545 seconds. Cases: restore-first;
  claim-first/expired restore; mail-trigger deadline rollback before queued claim;
  distinct-worker exclusion; same-token replay; post-wait deadline; synthetic
  lifecycle generation drift. Private Unix socket only, `listen_addresses=''`.
  Harness confirmed `Owned PostgreSQL cluster stopped` and removed
  `/private/tmp/cleanstream-wallet-locking-policy-pg-RSrS9G`, including relocated
  executables, links, synthetic database and socket. The runner process exited.
- No test processes or native server remain from this lane. No historical or
  parent-runner counts were substituted for completed cases.

## Exact Commands

The first two ran **one at a time** under the explicit grant, from
`/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup`:

```sh
PGLITE_MODULE=/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/node_modules/@electric-sql/pglite/dist/index.js /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/account-cleanup.test.mjs
```

```sh
DENO_DIR=/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/.deno-cache /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --allow-env=ACCOUNT_CLEANUP_ENABLED,ACCOUNT_CLEANUP_WORKER_SECRET,SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/account-cleanup
```

Native version/path preflight (ran, followed by file-existence inspection above):

```sh
/opt/homebrew/opt/postgresql@17/bin/pg_config --version --bindir --sharedir --pkglibdir
/opt/homebrew/opt/postgresql@17/bin/postgres --version
```

Executed under the later explicit grant; first sandboxed, then with approved
local shared-memory escalation after the environmental failure:

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/account-cleanup-races.test.mjs
```

All Edge fetches are stubbed; no network permission. New Edge code has only local
and built-in imports. Record actual completed cases/errors; do not install or
copy dependencies if a runtime check is blocked. No automatic follow-up scope.
