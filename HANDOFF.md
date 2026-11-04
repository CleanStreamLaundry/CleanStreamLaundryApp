# Email Lane Handoff

## Mail Scheduler Accepted

FINAL QA SOURCE/RUNTIME ACCEPT: 25 SQL scenarios plus parent = 26 passed,
0 failed, 0 skipped; completion20e371/session57109 exit0. PostgreSQL17.11
stopped and owned disposable directory SMpooa removed; no processes remain.
The exact run used PG_BIN=/opt/homebrew/opt/postgresql@17/bin, freshly verified
by QA. Unnamed wrapper/direct-URL regression and all original24 passed.
No author rerun or hosted setup/provider action. Candidate remains frozen.

Current frozen candidate: `supabase/ops/mail-worker-setup.sql`,
`supabase/ops/mail-worker-disable.sql`, `docs/mail-worker-scheduler.md`,
`scripts/mail-worker-scheduler.test.mjs`. Source-only; no author tests/processes,
provider calls or remote changes. No existing scheduler found in lane/active
migrations/scripts; hosted scheduler state is not inferred from source.

Reuses Supabase Cron/pg_net/Vault and the existing one-job delivery worker.
Idempotent named minute job, 55-second HTTP timeout, private SECURITY INVOKER
tick with application-role EXECUTE revoked. Setup requires existing extensions,
mail schema and exact Vault entry names, refuses conflicting/recognizable duplicate
mail jobs, and changes no rollout/outbox/secret state. Disabled/unreached DB rollout
queues no request; existing Edge MAIL_ENABLED and mailConfig checks remain intact.
Vault entries are `cleanstream_mail_project_url` and `cleanstream_mail_worker_secret`,
provided via trusted secret UI and read only on enabled ticks. No credential is
embedded in the cron command; errors are sanitized. Disable is repeatable and
preserves unrelated jobs and all outbox attempt/dedup records. It cannot cancel an
already dispatched request; runbook includes existing gates for an immediate pause.

QA source review found unnamed pg_cron jobs could evade the duplicate guard
through SQL NULL comparison. Corrected to IS DISTINCT FROM and added one case
covering unnamed wrapper/direct endpoint jobs; existing 24 cases preserved.
QA completed ONLY 25 focused SQL scenarios plus parent (26 runner cases), using
the existing disposable PostgreSQL17 helper and synthetic cron/Vault/net adapters:
`PG_BIN=/opt/homebrew/opt/postgresql@17/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/mail-worker-scheduler.test.mjs`
Real hosted extension/runtime delivery remains a separate development check.
No older mail/key/SQL suite repeat; prior accepted files are unchanged.

## Current Email Activation Status

Composer verified Chrome profile Jacob, Resend team cleanstreamlaundry and domain
updates.cleanstreamlaundry.com Verified (created 11 months ago). Account access
and domain-verification blockers are CLEARED; older account-unavailable statements
below are historical and superseded. Composer is checking webhook/API-key metadata
read-only. No credential values read here and no activation performed.

## Operator Keys Ready For QA

Frozen source-only candidate in `.campaign-work/operator-keys`, exactly
`scripts/bootstrap-admin-owner.mjs` and `scripts/bootstrap-admin-owner.test.mjs`.
No active-web edits, package copies/changes, key actions, provider calls, actual
CLI execution or author tests. Existing preflight/apply/invite/reset/RPC flow is
unchanged. Explicit `CLEANSTREAM_ADMIN_OWNER_SECRET_KEY_NAME` selects an own
secret entry from operator-supplied `SUPABASE_SECRET_KEYS`; undefined alone uses
legacy. Invalid explicit config fails sanitized before HTTP without fallback.
Named transport retains apikey, removes only the generated secret bearer, pins
requests to the configured origin and refuses redirects. Legacy transport stays
unchanged. No framework or cross-repository production dependency added.

QA queue: 30 planned offline cases using exact candidate bytes in SourceTextModule,
actual installed Supabase2.103.3, synthetic env/argv/console/exit and fake HTTP with
no network fallback. Counts: 12 named/legacy flow/guard/pagination, 12 invalid
selection, rollback, remote401 and 4 existing input/config guards. Not yet run.
Node24 command from operator-keys root:
`/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --experimental-vm-modules --max-old-space-size=768 --test --test-concurrency=1 scripts/bootstrap-admin-owner.test.mjs`
Source SHA256 `5927b52e774cb97472e8ae6ceaf09ad94001e18a7ba50badf7a1cb4e10d2a6fc`;
test SHA256 `3564876e226084e4415602353e685b09a9d2058775590eb54f64a85d0f07a6e3`.
Rollback is explicit selector removal with a separately still-valid legacy key.
No automatic retry/fallback after named-key rejection. No author processes running.

Email completion boundary: requested local account/newsletter welcome, unsubscribe,
suppression, retry/dedup, templates and refund-alert outbox are integrated; no new
local-code defect is identified. Account access/domain verification are cleared.
Remaining activation inputs are runtime sender/contact/postal/URL/secret settings,
webhook events/signing secret, worker invocation, mail_settings enablement/rollout
and designated verified Owner recipient. Remote configuration presence is being
checked by composer; not presumed absent. Delivery is not yet proven.
No alternate account substitution or automatic follow-on implementation.

## Caller Keys Integrated

Composer confirmed exact caller5 integrated; no shared baseline overwritten.
Paths: `supabase/functions/cortina-vend/logic.ts`, adjacent `keys.test.ts`,
`supabase/functions/voluntary-topup-refund/index.ts`, adjacent `keys.test.ts`
and `index.test.ts` (only synthetic-env fixture delta against active original10).
QA: new23 plus original refund10 and unchanged vendlogic8 = 41 distinct passes;
typecheck exit0. Final compatibility completion5cbbce; all processes exited.
Known lint6 retained; no suppressions. All original financial/authorization
assertions preserved. No original wallet-route suite exists; pure vend8 and
new Start-claim-null fixture do not establish provider Start coverage.
Reused unchanged callerPublishableKey; no SDK/key/lock/framework changes.
No activation, provider calls or further41 reruns authorized.

Next operator named-secret candidate is source-frozen for QA as recorded above.
No real admin:owner invocation performed.
Resend access/domain verification now cleared per current activation status above.

## Current Payment Status Key Candidate

SOURCE FROZEN, QA queue owner Descartes; no author checks run or slot held.
FINAL VERIFIED QA RECEIPT: corrected intent13 PASS/0failed/typecheckexit0,
completion chunk436e44; testfmtcheckexit0 chunkdea36e. Retained checkout18 was not
repeated:31 UNIQUE passing status cases. QA source/runtime ACCEPT subject to
staging gate/import-policy caveat below. All QA processes/handles exited.
QA source4 ACCEPT. Combined31 typecheck stopped before ANY cases with existing
TS2322: paymentIntentStatus/index.ts apiVersion2024-06-20 incompatible with locked
Stripe14.25.0 types expecting2023-10-16. Composer approved the narrow baseline
resolution: intent index apiVersion now2023-10-16; existing fakeHTTP Stripe branch
additionally asserts actual Stripe-Version2023-10-16 on every intent retrieval.
All13 cases/financial assertions retained. No import/lock/cast/no-check changes.
QA separately completed checkout18 PASS/typecheckexit0 (new13+existing5).
CORRECTION: QA withdrew its premature pass receipt. Session21375 exited1:
intent13 completed6passed/7FAILED; typecheck cleared, testfmtcheck0. Stripe retrieval
paths returned400 rather than expected200/403. Intent was placed ON HOLD and the
premature31pass claim withdrawn. Checkout18 remained accepted. Source-only
diagnosis confirmed pinnedStripe capturesfetch during construction. It retained
the test's import-time throwing trap, not later pertest fakefetch. Harness-only
fix now installs a stable guarded dispatcher at import and binds it only to an
active fake fixture, clearing afterward; never falls through to host transport.
Production code and all13 financial/header assertions unchanged. Corrected13
then passed per final completion receipt above, including actual Stripe-Version
header assertion. No author rerun or assertion weakening; failed history retained.
All QA processes exited. No provider/deploy/SDK-upgrade proof implied.
Scoped lint4:10 import-policy findings only (5existing production,5 matching
newtest preloads), no suppressions. QA fmtcheck2 found both newtests unformatted;
author applied Deno fmt ONLY those newtests afterward, exit0. No runtime/check
repeat. All processes exited; productionfiles unmodified by formatting.
Approved4 paths: `supabase/functions/paymentIntentStatus/index.ts` and new
`keys.test.ts`; `supabase/functions/checkPaymentResult/index.ts` and new
`keys.test.ts`. Production edits limited to perrequest secret selection/transport
and intent's narrowly typed configuration503 plus approved API-version correction.
Untouched formatting preserved;
no wholefilefmt, logic/RPC/Daltonfactory/helper/SDK/lock edits.

Current QA evidence: corrected intent13 + retained checkout18 PASS,31unique.
All fakeHTTP, actual pinnedSDK/Stripe client; no real provider
requests, host env/secret reads, install or cache mutation. Existing source uses
the repo's frozen SDK/Stripe pins. This local request-version correction changes
intent retrieval's Stripe-Version header, not any remote account or webhook
version. STAGING GATE before deployment: verify representative succeeded/processing/
canceled/failed intent responses, ownership checks, amount/charge metadata and
wallet reconciliation against2023-10-16 under separately approved staging access.
No staging/provider run or deployment performed here. Common Stripe SDK upgrade
remains a separate campaign batch. Official references:
[Stripe versioning](https://docs.stripe.com/api/versioning) and
[stripe-node14.25 API version](https://raw.githubusercontent.com/stripe/stripe-node/v14.25.0/src/apiVersion.ts).
Single QAqueue owns scheduling; no author run/repeat.

Completed corrective QA command from this lane root (no automatic rerun):
```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/paymentIntentStatus/keys.test.ts
```
Report existing URL/npm lint policy separately; do not suppress or change imports.
QA may produce outputs in this lane per composer; source remains frozen except
newfile formatting explicitly above. Detailed revocation contract below.

## Current Maintenance Public-Key Delta

TEST SLOT RELEASED directly to Kant01a0f300-1f21-7631-9bdf-de3caf10329b for
composer-approved fundingtimeout4+cleanup28. All processes exited; no fixtures,
services or cleanup outstanding. Candidate frozen; QA source ACCEPT received.
Deno2.9.6 heap768:32 passed/0failed (new12+existing20), typecheck enabled,
--cached-only --frozen. fmt/check3 exit0; formatter only wrapped new/fixture test
code, production index unchanged. Lint exit1 with4 no-import-prefix findings:
3 pre-existing URL imports (index.ts1,index.test.ts4/6), plus matching existing
SDK preload in new keys.test.ts2. No other diagnostics, config/import rewrites
or suppressions. This is not a clean lint result.
Owned source: `supabase/functions/maintenance-request/index.ts` (helper import and
key argument only), new `supabase/functions/maintenance-request/keys.test.ts`.
Uses unchanged `callerPublishableKey` with trusted
`CLEANSTREAM_MAINTENANCE_PUBLISHABLE_KEY_NAME` and injected
`SUPABASE_PUBLISHABLE_KEYS`. Undefined-only legacy fallback; explicit invalid,
missing or wrong-kind selection fails inside the existing guarded 503 response
before HTTP. No new catch/CORS implementation, SDK version/helper/lock change,
privileged credentials, altered bearer, or logic.ts modification. Existing
unconditional Deno.serve registration preserved; test traps registration only.

32 cases completed: 12 new real-SDK/fake-HTTP adapter cases plus the
existing20 in index.test.ts. Composer-approved fixture extension applied ONLY to
the undefined optional selector stub and exact envReads list; all20 cases and
behavioral assertions retained. No assertions/source changes needed for passes.

Completed scoped commands (no automatic rerun):
```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/maintenance-request/keys.test.ts supabase/functions/maintenance-request/index.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt supabase/functions/maintenance-request/index.ts supabase/functions/maintenance-request/keys.test.ts supabase/functions/maintenance-request/index.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt --check supabase/functions/maintenance-request/index.ts supabase/functions/maintenance-request/keys.test.ts supabase/functions/maintenance-request/index.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno lint supabase/functions/maintenance-request/index.ts supabase/functions/maintenance-request/keys.test.ts supabase/functions/maintenance-request/index.test.ts
```

## Machine Availability Accepted Candidate

TEST SLOT RELEASED TO COMPOSER. All processes exited, no services/fixtures or
cleanup outstanding. QA source ACCEPT plus author Deno12 actualSDKfakeHTTP passed
0fail/typecheckexit0, cached-only frozen heap768; unchanged nearest Node24 logic5
passed0fail heap1024. fmt/check2 exit0 after formatter-only cleanup of both files.
Lint exit1:4 import-policy findings, comprising3 on existing production imports
(JSR no-import-prefix + no-unversioned-import; SDK URL no-import-prefix) and1 on
newtest sameSDK preload. No suppressions, dependency/config upgrades or installs.
Deno reported ignored existing npm:supabase lifecycle script; none ran.
Candidate frozen. Owned
`supabase/functions/machine-availability/index.ts` narrow adapter delta and new
`supabase/functions/machine-availability/keys.test.ts` (12 cases). SDK remains2.97.0.
`supabase/config.toml:419` sets verify_jwt=false; adapter explicitly calls
admin.auth.getUser(captured token) before inventory/provider access. DB transport
is intentionally privileged, unlike maintenance's caller-bound public transport.

Reuses unchanged selectNamedSupabaseKey(name,SUPABASE_SECRET_KEYS,"secret") with trusted
CLEANSTREAM_AVAILABILITY_SECRET_KEY_NAME. Undefined-only legacy service-role key;
explicit invalid/missing/wrong-kind fails before HTTP, never fallback. Client
construction moved inside existing guarded POST flow after missing-token check,
so bad selection returns existing sanitized503 and leaves OPTIONS204/405 intact.
Selection read each request so dictionary removal is observed. Exact getUser token
and privileged DB authority preserved. Named mode ONLY wraps existing SDK fetch
to remove Authorization on this project's rest/v1 requests; retains apikey and all
Auth requests. Legacy SDK transport unchanged. No generic helper/framework added.
Confirmed pinned SDK defaults to Bearer <key> in its
[fetch source](https://raw.githubusercontent.com/supabase/supabase-js/v2.97.0/packages/core/supabase-js/src/lib/fetch.ts).

Unchanged: nayax(), NAYAX_LYNX_TOKEN/base URL, provider timeouts/redaction,
queries, sync lease/finish RPCs, deriveAvailability/summary logic or gateway config.
Nearest existing `scripts/nayax-availability.test.mjs` has5 pure derivation cases,
not adapter/key coverage. New real-SDK fakeHTTP tests cover named/legacy,
bad config noHTTP, revocation/unset rollback, method/missing-token ordering and
Auth explicitBearer versus DB apikey-only, header mutation and overlapping callers.
Tests deny the lease, so no provider branch runs; fakeHTTP rejects every nonfixture
origin. No real data/provider call. All12 completed once; unchangedlogic5 completed once.

Completed commands, no automatic rerun:
```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/machine-availability/keys.test.ts
/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/nayax-availability.test.mjs
```

## Payment Status Revocation Contract

Approved implementation completed source-only. Exact owned paths:
`supabase/functions/paymentIntentStatus/index.ts`, adjacent new `keys.test.ts`;
`supabase/functions/checkPaymentResult/index.ts`, adjacent new `keys.test.ts`.
Existing nearest tests included only if additive optional-env fixture support is
needed. Do not touch either logic.ts, financial RPC definitions, or Dalton factory.

Active baseline adapters directly use SUPABASE_SERVICE_ROLE_KEY. Candidate intent
client now constructs perrequest inside its existing guarded POST; checkout stays
in its existing guarded factory. Reuses selectNamedSupabaseKey(secret), with trusted
trusted per-component names CLEANSTREAM_PAYMENT_INTENT_STATUS_SECRET_KEY_NAME
and CLEANSTREAM_CHECK_PAYMENT_RESULT_SECRET_KEY_NAME. Both select from injected
SUPABASE_SECRET_KEYS; undefined-onlylegacy, no default/other/legacy fallback once
selected. Read each request to observe removal. Named REST transport apikey-only;
explicit Auth getUser caller bearer retained. No new generic framework or SDK.

Revocation/error mapping to preserve and prove with realSDK fakeHTTP:
- Explicit missing/malformed/wrong-kind selection: sanitized503 before Auth/Stripe/DB.
  checkPaymentResult retains existing config503; paymentIntentStatus distinguishes
  a local KeyConfigurationError as503 while preserving other outercatch400.
- Dictionary removal on next request:503, no retained module client or legacy retry.
- Remote key rejected during getUser: existing401, no Stripe/DB request/fallback.
- Key rejected at record_wallet_load_from_stripe: existing successful payment status
  with walletLoadRecorded=false (pending reconciliation), not failed payment or
  repeat claim/charge. Preserve logic catches and exact RPC/payment ownership checks.
- Explicit unset: staged legacy rollback only while legacykey remains valid.

Keep Stripe SDK versions, metadata/amount/ownership validation, ledger
parameters, error semantics outside new configuration branch, CORS/method ordering
and provider calls unchanged. New tests must fake all HTTP including Stripe and
prove no provider/network side effects. Source approved; QA runtime evidence pending.

## Current Mail Public-Key Delta

TEST SLOT RELEASED directly to Descartes 01a0f300-204c-7161-baab-8f8726580213;
receipt confirmed. All processes exited, no services/fixtures or cleanup outstanding.
Deno2.9.6 heap768: 40 passed / 0 failed (new32 + unchanged compatibility8),
with typechecking enabled, --cached-only --frozen and no network permission.
Scoped fmt/check/lint2 all exit0. Formatter changed only new test wrapping;
mail.ts unchanged by formatter. No assertion/source fixes needed. Candidate frozen.
Owned: `supabase/functions/_shared/mail.ts` databaseRpc selection only;
new `supabase/functions/_shared/mail_public_keys.test.ts`. Existing pure selector,
secret/no-login branches, exact caller bearer, project binding, 10-second timeout,
outbox SQL and renderer unchanged. No SDK/package/helper/lock changes.

Optional trusted `CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME` selects the exact named
entry in injected `SUPABASE_PUBLISHABLE_KEYS`. Only absent/undefined selection uses
`SUPABASE_ANON_KEY`. Empty/malformed names or dictionaries, missing entries and
wrong-kind keys fail with existing sanitized 503 mail_unavailable before HTTP.
No default/legacy/secret fallback after explicit selection or removal. Rollback
requires explicitly unsetting the selector while a valid legacy public key still
exists; this does not restore a revoked legacy key. No live settings changed.
Current dictionary contract verified in [official Supabase docs](https://supabase.com/docs/guides/functions/secrets).

Completed: 32 new fake-HTTP adapter cases plus 8 unchanged independent mail cases;
scoped fmt/lint on these two owned files.
No Deno56, SQL23, older109/94 reruns requested. Synthetic injected config only.

```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/_shared/mail_public_keys.test.ts supabase/functions/_shared/mail.independent-qa.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt supabase/functions/_shared/mail.ts supabase/functions/_shared/mail_public_keys.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt --check supabase/functions/_shared/mail.ts supabase/functions/_shared/mail_public_keys.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno lint supabase/functions/_shared/mail.ts supabase/functions/_shared/mail_public_keys.test.ts
```

## Current Request-Alert Delta

TEST SLOT RETURNED DIRECTLY TO COMPOSER. All processes exited; candidate frozen.
Deno 2.9.6 / 768 MB: 56 passed, 0 failed (48 new + 8 unchanged compatibility).
Initial typecheck stopped before cases; added two success-shape assertions for
TypeScript narrowing without removing or weakening any assertion.
PostgreSQL 17.11 / Node24 1024 MB: corrected SQL23 passed, 0 failed/skipped/cancelled
(runner reports 24/24 including parent). Includes recipient-settings switch after
lease: suppressed without retargeting or changing claim/financial records.
Prior SQL run had 13 passed / 9 failed from JSON parsing psql boolean t/f responses;
test adapter now decodes booleans explicitly. No assertion weakened or production
RPC changed. Corrected suite ran ONCE after Kant's explicit transfer.
Scoped fmt/check/lint6 passed after formatting-only cleanup; git diff --check clean.
Earlier Deno56 was not repeated. Frozen key helper/lock untouched by notice work;
lock diff remains only the previously accepted 11 additions / 0 removals.
First sandbox initdb failed shared-memory permission; approved escalation ran PG.
Final cluster stopped and directory removed: /private/tmp/cleanstream-wallet-locking-policy-pg-S29zIV.
Both earlier disposable directories also removed. No running process or retained slot.
QA source accepted per composer; local author checks complete, ready for integration.
Activation remains blocked on approved sender/account and server-designated verified
Owner recipient configuration. No sends, providers, DNS, deployment or activation.

Owned changed/new files in this batch:
- `supabase/functions/refund-email/index.ts`, `logic.ts`, `logic.test.ts`, new `index.test.ts`.
- `supabase/functions/_shared/mail.ts`: refund job/template branch only, key transport unchanged.
- New `supabase/functions/_shared/refund_notice.test.ts`.
- CLI-generated `supabase/migrations/20260930175136_refund_request_notice_outbox.sql`.
- New `scripts/refund-request-notice.test.mjs`; this handoff.

Endpoint accepts existing transaction_id payload with captured caller bearer;
all submitted user/recipient/amount/content fields are ignored. Authenticated-only
enqueue_refund_request_notice(bigint) uses current admission and exactly one own
pending Refunds row joined to an own transaction. SELECT only on claim/financial
records; sole business write is private.mail_outbox. Only mail advisory lock,
no wallet/refund/transaction/profile row locks. Kant confirmed atomic legacy claim
proposal remains separate; composer owns Flutter notice-error isolation after
recordRefundRequest succeeds. No caller/service contract changes in this lane.

Server-only private.mail_settings.refund_notice_recipient UUID defaults NULL and
must designate a verified, active Owner. Existing enabled/sender gates retained;
no configuration or activation performed. Missing recipient/disabled/suppressed
states return HTTP 200 with success/claimRecorded=true, notificationSent=false,
notificationState and notificationWarning after verifying the saved claim. Actual
RPC/session failures remain sanitized errors; callers must not resubmit a claim
to retry a notice. Accepted/delivered evidence alone permits notificationSent=true.

Permanent event loyalty_credit_requested/<refund_id>; duplicates preserve state,
attempts, payload fingerprint and recipient. Never marks Refunds.notification_sent_at,
resolves a claim, increments attempts or writes ledger/balance. Enqueue stays a
separate POST-COMMIT call, not a trigger or inner financial RPC. Reused existing
outbox/worker/template wrapper; removed direct Resend adapter, hardcoded mailbox,
raw HTML injection and obsolete GET decision links. Template uses escaped stored
details and existing /admin route; explicitly describes requested loyalty credit,
not paid-vend proof or money returned. Newsletter unsubscribe now explicitly targets
only newsletter kinds. Bounce/complaint, identity/lifecycle and eligibility gates
still apply; Owner/claim changes rechecked by existing claim/prepare flow.

Completed Deno evidence: 48 focused cases + 8 unchanged independent mail cases.
Completed SQL evidence: 23 PostgreSQL scenarios (+ parent runner case), including duplicate enqueue,
financial snapshots, ownership/recipient/session gates, stale claim, deletion,
unsubscribe isolation, original newsletter confirmation and delivery retry states.
Prior109 key cases remain accepted/frozen and were not rerun.
The old refund-email tests intentionally change contract: no provider-id response
or approve/deny links; now assert persisted-record authority, warnings and no retry.

No next run requested. Commands below retain the completed commands for
reproducibility. Existing disposable PG harness owns isolated cluster
startup/stop/removal. All HTTP in Deno tests is fake.

```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/refund-email/logic.test.ts supabase/functions/refund-email/index.test.ts supabase/functions/_shared/refund_notice.test.ts supabase/functions/_shared/mail.independent-qa.test.ts
PG_BIN=/opt/homebrew/opt/postgresql@17/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/refund-request-notice.test.mjs
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt --check supabase/functions/refund-email/index.ts supabase/functions/refund-email/logic.ts supabase/functions/refund-email/logic.test.ts supabase/functions/refund-email/index.test.ts supabase/functions/_shared/mail.ts supabase/functions/_shared/refund_notice.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno lint supabase/functions/refund-email/index.ts supabase/functions/refund-email/logic.ts supabase/functions/refund-email/logic.test.ts supabase/functions/refund-email/index.test.ts supabase/functions/_shared/mail.ts supabase/functions/_shared/refund_notice.test.ts
```

Migration created with existing CLI through Node24, empty process environment and
isolated HOME after default-home permission failure. Generated CLI-only metadata
removed. No private config, provider endpoint, sender/account/DNS changes, new
framework, other lane files or existing migrations edited. Customer decision
notifications and frozen key helper/lock remain untouched. Integration/activation
must wait for checks, independent QA and existing sender/recipient approvals.

## Accepted Public-Key Delta

TEST SLOT RELEASED. All processes exited; candidate frozen for independent QA.
Exact owned paths, config, rollback
and serial bounded commands: [PUBLIC-KEY-CUTOVER.md](PUBLIC-KEY-CUTOVER.md).
Deno 2.9.6 / 768 MB: missing 50 passed, 0 failed (new real-SDK 26 + admin backend
17 + independent admin 6 + existing deletion adapter 1). Earlier 59 passed
(26 pure + 33 retained mail) were not repeated: 109 distinct cases now complete.
No assertions/source behavior changed to get these passes.

Additional owned integration path: deno.lock. Deno generated exactly the approved
11 std@0.182.0 HTTP/async checksum additions, verified by full diff: no removals,
existing-pin changes or lock-format churn. deno.json unchanged. Tests passed with
--cached-only --frozen against this lock. Cache/lock blockers are resolved.
Integrate those 11 additions with the candidate; no test lock or shadow helper.
No installs, scripts, cache copies, source/test weakening or provider calls.
Network access was limited to the approved public pinned test graph.
Scoped fmt passes all 11 files after wrapping-only formatting in five files.
Lint reports only four pre-existing no-import-prefix findings on unchanged URL
imports in admin-portal/backend.ts and delete-account/index.ts/index.test.ts.
No lint suppressions/config/import rewrites; not a clean lint result. git diff
--check clean. Old mail_keys.ts absent and no stale selector imports found.
No assertions or source behavior changed during this check turn.

Four caller entrypoints use trusted per-component publishable selection with
legacy behavior only when selection is absent. Explicit invalid/missing/wrong-kind
selection fails closed; bearer and SQL/MFA authority unchanged. Reused mail's
pure validator by one rename to supabase_keys; mail.ts differs from active only
in import/call. Remove the old helper path during integration, no duplicate shim.
Composer-authorized createCreditDependencies initialization now lazy/memoized
inside its existing guard; removed proposed duplicate refund catch/CORS responses.
Original method/body ordering and one captured-bearer client per credit request.
No maintenance, payments, storage, actor/auth implementation, gateway or live edits.

## Accepted Named Email Delta

Composer reports integrated; independent QA's unchanged 33 passed. Historical
author evidence below predates the current helper rename/public-key delta.

TEST SLOT RELEASED: email-only named secret candidate frozen for review.
Deno 2.9.6, 768 MB: 41 passed, 0 failed (33 new + 8 existing independent).
Final scoped fmt/lint clean across 3 files; all processes exited. No broad
94-case/BOM rerun, missing imports, installs or remote actions.
See [configuration, rollback and exact commands](MAIL-KEY-CUTOVER.md).
New `mail_keys.ts`/`mail_keys.test.ts`; existing `mail.ts` changes limited to import
and databaseRpc key/header selection. No other consumer or accepted behavior edits.
Explicit named selection fails closed; absent selection preserves legacy mode.
Prior accepted email evidence below does not verify this new transport delta.

## Accepted Email Batch

Status: TEST SLOT RELEASED; focused author BOM recheck complete, ready for composer integration.
New decoder/bounds delta: 10 passed, 0 failed; scoped fmt/lint clean (2 files).
QA independently reran its unchanged 7 cases against the fix and closed the finding.
No 94-case repeat was run for this delta. All processes exited; no slot retained.
Before this delta, Deno 2.9.6: 94 passed, 0 failed (86 mail + 8 existing independent tests),
including 13 new cases. Initial and post-format runs both completed; unique
completed case count is 94, not 188. Format and lint checks pass all 5 scoped
files for the pre-BOM candidate only. No missing cached imports, installs, builds, provider calls, sends, DNS
edits, activation or browser runs. All verification processes exited; none running.
Composer correction: Flutter newsletter preferences are integrated and the
public newsletter's 51 independent tests are accepted. Neither was rebuilt;
composer owns corrections to stale email status docs. That accepted frontend
evidence is distinct from this lane's completed focused backend checks.

## Changed Paths

- `supabase/functions/_shared/mail.ts`: branded responsive email markup with
  semantic heading, presentational table, descriptive links, escaped postal/contact
  content and text fallback; invalid UTF-8 now returns 400 instead of retryable 503.
- `supabase/functions/newsletter/index.ts`: URL-encoded mailbox-provider forms
  can only unsubscribe; they cannot confirm consent or invoke authenticated actions.
- `supabase/functions/mail-webhook/index.ts`: reject non-string correlation tags
  before UUID coercion/database calls; preserve valid object/array tags and ID lookup.
- `supabase/functions/_shared/mail.test.ts`: 13 new cases, plus expanded existing
  template assertions for layout, purpose separation and accessible link labels.
- `supabase/functions/_shared/mail.bounds.test.ts`: seven QA bounds/signature
  assertions preserved from website-qa (imports localized, formatting normalized), plus three
  leading-BOM preservation/malformed JSON regressions. Original 94 cases unchanged.
- `HANDOFF.md`: this checkpoint. No existing or additive migrations needed.

## Completed BOM Recheck

QA reproduced unsigned EF BB BF prepended to valid signed JSON being accepted
because TextDecoder stripped the prefix. The sole runtime delta adds
`ignoreBOM: true` to the strict decoder, preserving wire bytes for HMAC input.
Existing JSON.parse catches already return 400 for genuinely signed BOM-prefixed
JSON; no handler changes needed. QA source/report remain untouched. The granted
author run completed all 10 bounds cases (7 ported QA + 3 new) on Deno 2.9.6.
Historical 94-case evidence remains separate; no claim of a fresh 104-case run.
Formatter then normalized imports/wrapping only; fmt check and lint passed.

Executed separately from this root after staff MFA released the slot:

```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/_shared/mail.bounds.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt --check supabase/functions/_shared/mail.ts supabase/functions/_shared/mail.bounds.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno lint supabase/functions/_shared/mail.ts supabase/functions/_shared/mail.bounds.test.ts
```

Inventory complete: `KEY-MIGRATION-INVENTORY.md` records active consumer paths,
official key/gateway contracts, named-key support gaps and cutover/rollback tests.
All 49 local links resolve. No key values or consumer changes; no migration tests
or provider actions. Email source/tests now frozen again for composer integration.

## Preserved / Reused

Reused the existing renderer, escaping, HMAC capabilities, plain-text copy,
brand blue/yellow from docs/theming.md, dedicated sender gates, worker,
database outbox and RPC contracts. Removed generic regex URL auto-linking.
No new framework, package, asset request, scheduler or parallel delivery path.
Account welcome remains nonpromotional and independent of double opt-in.
Unsubscribe stays no-login and works while sending is disabled. Signed webhook
verification, bounce/complaint suppression, permanent event deduplication,
bounded 429 retries and uncertain-send quarantine are unchanged.

Lifecycle coordination: no baseline schema conflict found. Existing mail SQL
depends on private.account_lifecycle(user_id, restored_at, marketing_suppressed)
and private.current_account_access(); preserve those contracts during integration.
Deletion suppresses queued mail/consent; restoration never re-subscribes.
HTML changes intentionally change payload_hash. Previously attempted jobs must
not have their fingerprints/event keys reset: existing payload_changed protection
will fail closed. Reconcile old attempts before any approved template rollout.

## Pre-BOM Verification

Composer reviewed the scoped diff and explicitly granted the slot after website
QA released it. Commands ran separately in this worktree. Tests were capped at
768 MB V8 heap; fmt/lint used the same DENO_V8_FLAGS environment setting.
The initial fmt check found wrapping only in mail.ts and mail.test.ts; scoped
formatting corrected it, then fmt/lint and the final 94-case run passed.

```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/_shared/mail.test.ts supabase/functions/_shared/mail.independent-qa.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt --check supabase/functions/_shared/mail.ts supabase/functions/_shared/mail.test.ts supabase/functions/_shared/mail.independent-qa.test.ts supabase/functions/newsletter/index.ts supabase/functions/mail-webhook/index.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno lint supabase/functions/_shared/mail.ts supabase/functions/_shared/mail.test.ts supabase/functions/_shared/mail.independent-qa.test.ts supabase/functions/newsletter/index.ts supabase/functions/mail-webhook/index.ts
git diff --check
```

Composer verified surviving Deno 2.9.6 and the Node 24 path this turn; no repeated
version commands are needed. Lost Deno 2.9.7 evidence is not reused as a pass.
Tests used injected fake HTTP/RPC, no network/environment permissions. No cached
import was missing and no source/test workaround was needed. PostgreSQL integration and
real email-client rendering remain unrun; PGlite was not needed or accessed.

## Activation Blockers

Clean Stream account/sender ownership, DNS authentication, approved postal/contact
details/content, webhook/gateway configuration and delivery verification remain
unresolved. Never assume the Gundex account. Local edits do not activate email.
No other lane or active app/web checkout was edited. No automatic follow-up scope.

Public documentation only was read: Resend idempotency and webhook verification,
and Supabase changelog HTML (markdown fetch unsupported). Existing HTTP/provider
contracts remain unchanged; no authenticated provider/account requests were made.
