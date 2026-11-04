# Customer Credit Decision Notices

## Current Hosted Scheduler Receipt

Composer completed the explicitly approved dedicated worker credential and
dormant scheduler setup in Clean Stream project `dnuuhupoxjtwqzaqylvb`. This is
composer-supplied evidence; no author remote action or source change occurred.

- Before-state `289820`: required extensions installed, mail disabled with NULL
  rollout, no scheduler job/tick/Vault entries.
- Privileged UI created Edge `CLEANSTREAM_MAIL_WORKER_SECRET`, matching Vault
  `cleanstream_mail_worker_secret` and exact project URL entry
  `cleanstream_mail_project_url`. Reload and boolean hash-match proof `a3e209`;
  no plaintext secret files, argv or logs. Existing Resend/webhook preserved.
- Exact reviewed setup SHA256
  `51524d70969cd3f387bdeae3ff5d5505c5181e459f42d15e37f8de798d3a7503`
  executed `695b3c`, exit0, returned job1.
- Postflight `6ca9af`: one active `cleanstream-mail-delivery` job1, schedule
  `* * * * *`, owner `postgres`, command `select private.mail_worker_tick();`.
  Tick is SECURITY INVOKER; anon/authenticated/service_role EXECUTE all false.
  Database mail remains disabled, rollout NULL.
- Passive metadata `d29ccd`: named job1/run1 succeeded from
  `2026-10-01T01:37:00.140492Z` to `2026-10-01T01:37:00.154527Z`, with sending
  false and rollout NULL. This proves real Cron execution of the disabled no-op,
  NOT HTTP dispatch or delivery. No manual trigger or email HTTP/send.
  Postal address and test recipient are explicitly deferred placeholders only;
  no invalid placeholder was installed. Sender/delivery remain off. This setup
  is not delivery, campaign, test-recipient or mail-policy acceptance.

Source remains frozen. Idle pending an actual finding; no runtime action assigned.

Integrated batch QA runtime PASSED: Deno45/typecheck exit0 `568a43`, compatibility8/
typecheck exit0 `c955f8`, SQL25 children +1 parent26 exit0 `3ba597`. PostgreSQL17.11
stopped and disposable `temp1ehw5k` removed (QA receipt). Author completed 0 tests;
no author test/build process, provider call, hosted change or email send.

Actual lint finding: scoped8 exit1 `d9e4aa`, seven diagnostics. Three URL imports
are unchanged (refund_resolution.test.ts:5, backend.ts:1, backend.test.ts:4).
Three require-await callbacks are inherited (refund_resolution.test.ts:39 default
authenticate, :66 idempotent resolve, :108 denied authenticate), confirmed against
the saved pre-change source/HEAD. The newly introduced :80 failed-notice resolve
callback is corrected ONLY in this lane to `() => Promise.resolve(...)`; no
assertion/application change. Composer must integrate this one-line test-only
delta. Runtime evidence above predates that equivalent fixture correction; no
author rerun or slot requested. Remaining six baseline diagnostics not suppressed.

## Integration Scope

Root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/email/credit-decision`.
Destination: composer-owned active `CleanStreamLaundryApp`; no author active edits.

1. `supabase/migrations/20260930220243_credit_decision_mail_outbox.sql` (new, CLI-created)
2. `supabase/functions/_shared/mail.ts` (credit kind/snapshot/render branch only)
3. `supabase/functions/_shared/refund_resolution.ts` (outbox receipt summary; remove direct-send interface/old renderer)
4. `supabase/functions/_shared/refund_resolution.test.ts` (retain six cases, updated notification semantics)
5. `supabase/functions/_shared/mail.credit-decision.test.ts` (new26)
6. `supabase/functions/admin-portal/backend.ts` (remove disabled notify/mark hooks only)
7. `supabase/functions/admin-portal/handler.ts` (shared summary import/result warning only)
8. `supabase/functions/admin-portal/backend.test.ts` (three affected fixture/receipt hunks only)
9. `supabase/functions/admin-portal/credit-notice.test.ts` (new13 actual SDK/fake HTTP)
10. `scripts/credit-decision-mail.test.mjs` (new disposable real-PG tests)

DELETE active `supabase/functions/_shared/refund_resolution_backend.ts` with this
batch. `rg` over active functions/scripts found ZERO importers; only its own
definition. Its old direct Resend/Auth-admin sender and sent-timestamp writer are
replaced by the existing queue, not retained as an alternate path. Removal SHA256:
`9fac49ee93e1783882b86bf97750593d2b93faf9d719826847638a0240e5e3ce`.
It is not copied into this sparse lane. Integrate deletion with the removed
legacy HTML export. No baseline/helper/config/lock/dependency integration targets.

## Contract and Preservation

- AFTER pending-to-approved/denied transition enqueues the immutable server
  decision snapshot in the same transaction. Permanent event keys are
  `loyalty_credit_approved/<refund_id>` / `loyalty_credit_denied/<refund_id>`.
  Repeated decisions do not insert jobs, issue credit again, or reset unknown mail.
- Existing nonnull `mail_settings.rollout_at` bounds new intent. Delivery may be
  disabled when intent is recorded; existing database enabled and worker
  MAIL_ENABLED gates still control dispatch. No old-decision backfill.
- Exact stored cents use the financial function's existing rounding expression.
  Approved notices require matching promotional-only wallet ledger evidence.
  Wording says loyalty promotional credit, explicitly not cash/payment refund.
- Current verified email, bans, suppression, lifecycle, decision timestamp/status,
  amount and staff note are rechecked at claim/prepare. Snapshot content is never
  rewritten for retries. Newsletter unsubscribe remains independent.
- Existing canonical pre/post-wait actor, MFA, location and admission guards stay
  intact. `resolve_refund_request` and financial amounts/writes are unchanged.
  Only `admin_resolve_credit` final result gains queue evidence.
- Refund/wallet writers may take mail_lock; mail completion never locks/updates
  Refunds. Existing notification_sent_at is not written. Accepted/delivered or
  historical sent evidence is distinct from queued/unknown/failed/suppressed.
  Receipt warnings never undo a committed decision or recommend replay to send.
- Reuses current branded renderer, configured support replyTo, durable queue,
  retry, idempotency and webhook handling. Existing lifecycle/refund_request and
  welcome/newsletter branches, retention, sender policy, onboarding/geocode and
  caller bearer remain unchanged. No new environment settings/framework.

## QA Commands

Run against the integrated active candidate and existing real dependencies, NOT
a sparse overlay. Composer integration (including dead helper deletion) is the
prerequisite. No author run and no claim of cached-import availability for this
new batch. Stop/report missing cache; no install/provider/network permissions.
Serial queue only; no older94/key/full lifecycle reruns.

```sh
cd /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp
DENO=/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno
NODE=/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node

# 45 = actual SDK13 + renderer/receipt/worker26 + retained handler6; includes typecheck.
"$DENO" test --v8-flags=--max-old-space-size=768 --cached-only --frozen --config=deno.json --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env=CLEAN_STREAM_WEB_ORIGIN supabase/functions/admin-portal/credit-notice.test.ts supabase/functions/_shared/mail.credit-decision.test.ts supabase/functions/_shared/refund_resolution.test.ts

# 8 = existing adapter4 + captured-bearer1 + lifecycle render2 + request-alert render1.
"$DENO" test --v8-flags=--max-old-space-size=768 --cached-only --frozen --config=deno.json --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env=CLEAN_STREAM_WEB_ORIGIN --filter '/legacy approved|legacy denied|legacy endpoint preserves|portal credit keeps|independent legacy handler|lifecycle scheduled: exact|lifecycle restored: confirms|refund template: escaped/' supabase/functions/admin-portal/backend.test.ts supabase/functions/admin-portal/backend.independent.test.ts supabase/functions/_shared/mail.lifecycle.test.ts supabase/functions/_shared/refund_notice.test.ts

# 25 SQL children + parent26; private Unix socket, fixture-only, helper owns teardown.
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin "$NODE" --max-old-space-size=1024 --test scripts/credit-decision-mail.test.mjs

"$DENO" lint supabase/functions/_shared/mail.ts supabase/functions/_shared/refund_resolution.ts supabase/functions/_shared/refund_resolution.test.ts supabase/functions/_shared/mail.credit-decision.test.ts supabase/functions/admin-portal/backend.ts supabase/functions/admin-portal/handler.ts supabase/functions/admin-portal/backend.test.ts supabase/functions/admin-portal/credit-notice.test.ts
```

Known runtimes from accepted campaign evidence: Node24, Deno2.9.6, PG17.11; not
rechecked by author. SQL runner optionally accepts CLEANSTREAM_CREDIT_BASELINE
for source review in this sparse root, but integrated active QA is preferred.
Formatting was not run; preserve existing-file untouched formatting. Format
only new files or changed ranges if needed, never whole existing backend bodies.
Report real test counts, failures, process exits and PG stopped/directory removed.

Tests retain six original handler cases and four nearest backend cases. Changed
assertions explicitly replace disabled/direct-send semantics with queue receipts;
no financial/auth assertions are weakened. SQL includes duplicate/rollback,
disabled/pre-rollout, unknown/rate-limit, stale-after-lease, suppression, immutable
snapshot, missing-ledger, foreign-location/MFA, post-lock revocation, no lock
inversion, request-alert and lifecycle compatibility coverage.

## Frozen SHA256

```text
b38a778b72f7882b95b3b9fd175dc5906f1e86e2184d3a96f337899c3bfe752b  supabase/migrations/20260930220243_credit_decision_mail_outbox.sql
5142d9dd41943af55afa3521867821fb12d70dfbaa726932a29112d22384d476  supabase/functions/_shared/mail.ts
b4051222e4029b9c26dd6a7ad7151991d09eb88ed4742aedf81be7c62c3d86bf  supabase/functions/_shared/refund_resolution.ts
5d073f248da744e66926145969b859d9760fb2d5997973aa24749a78632525f9  supabase/functions/_shared/refund_resolution.test.ts
878391ebfec6d71dd7255f6fe28de2e9cec54db2169c322bb29180da5e9dfa08  supabase/functions/_shared/mail.credit-decision.test.ts
b643a12c6f231b6331f29355da62de43399bc20b6ffefd9e9c1bdfc1c4ca003a  supabase/functions/admin-portal/backend.ts
54e39a57a3c97ccdf6d3ee0cf3dcc1cc61781e90bfed5c9985f1d7f584e4a2eb  supabase/functions/admin-portal/handler.ts
8dc2557254b8f6873d6f6ac46dc5a4c4b9e1641f2a26c410a5ba62de09e45334  supabase/functions/admin-portal/backend.test.ts
dc68049b9940db7695492e090097d904f62914dc2adaf1e7b7eb1b95415c4161  supabase/functions/admin-portal/credit-notice.test.ts
0a4e7d5b8c64619b3ed9fa87e503f5a0695be25a0565fd423836946d28bca194  scripts/credit-decision-mail.test.mjs
```
