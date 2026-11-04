# Lifecycle Transactional Email

ACCEPTED ACTIVE: corrected SQL28 children + parent =29 passed exit0/32e6c1;
owned PostgreSQL17 stopped and private q13knV directory removed. Retained
Deno30/typecheck exit0/e6dff6 and TS2 lint exit0/51380a. Total59 checks accepted
by independent QA. All lifecycle processes exited. No hosted mail or paired
website rollout is claimed; no repeats required.

QA finding: initial integrated SQL run exit1 (7 pass / 22 fail including parent),
owned PG stopped/directory removed. Fixture reset omitted recreating mail_settings
after TRUNCATE auth.users CASCADE. One-line fixture repair now matches accepted
refund-request harness. All 28 scenario assertions and production files unchanged;
corrected SQL29 subsequently passed as recorded above. Independent Deno30/typecheck
passed exit0/e6dff6; scoped TS2 lint clean exit0/51380a. No renderer rerun needed.

Four integration paths below are integrated and QA accepted. Author completed zero
tests; no checks, hosted calls, sends, browser or background processes. Descartes
owns serial verification. This is local code, not an activation/delivery receipt.

## Exact Paths

- `supabase/migrations/20260930213049_account_lifecycle_mail_outbox.sql`
- `supabase/functions/_shared/mail.ts` (only lifecycle type/helper/render hunks)
- `supabase/functions/_shared/mail.lifecycle.test.ts` (30 declared Deno cases)
- `scripts/lifecycle-mail.test.mjs` (28 declared SQL children plus parent)

`supabase/functions/_shared/supabase_keys.ts` is an unchanged, read-only dependency
baseline for sparse Deno resolution. DO NOT integrate it. No lock/config/package
copies. Mail baseline and all SQL fixture prerequisites are current active
`CleanStreamLaundryApp` source; SQL reads those files directly, not an old lane.
The migration filename was created by local Supabase CLI, not invented.
Composer/Kant confirmed no shared-outbox writer overlap before edits.

## Actual Gap

Active deletion063923 had request/explicit restore RPCs; newsletter125527 only
suppressed on lifecycle changes. Active mail.ts had account/newsletter welcomes
and refund_request, no lifecycle kinds. Credit decision notices were therefore
not substituted or added to this batch.

One additive migration extends the existing outbox with typed request/deadline/
restoration timestamps and two kinds: account_deletion_scheduled/account_restored.
The existing lifecycle AFTER trigger is replaced in place: same mail lock,
newsletter suppression, then event enqueue. Queue writes commit/roll back with
the lifecycle action. No post-commit HTTP or new enqueue endpoint.

Event keys use kind/user/exact UTC deletion-request timestamp. Request retries,
restore retries and no-op updates cannot duplicate or requeue the event. Another
deletion cycle gets a new key and suppresses the previous cycle's notices.
mail_allowed checks exact current lifecycle snapshot, verified current mailbox,
ban/deletion/bounce/complaint suppression; expired scheduled notices are skipped.
Restore cancels leased/sending/uncertain old notices locally. It cannot retract
an external email already dispatched after prepare; existing worker semantics
remain unchanged and no false delivery/cancellation guarantee is added.

Existing refund_request and welcome/newsletter eligibility branches remain
intact inside the new lifecycle-or-existing-kind grouping. No admission/RPC,
cleanup, retention, balance/ledger, financial or Auth changes. No new tables,
grants, frameworks, provider service, retry machinery or activation settings.

Existing DB mail_settings enabled/rollout_at gates enqueue; worker MAIL_ENABLED
and sender/content/link gates still apply. Events while DB mail is disabled or
before rollout are not backfilled later. Disabling only the worker can retain
durable queued jobs. Existing five-attempt/rate-limit-only retries, uncertainty
parking, permanent event key and provider idempotency all remain unchanged.

## Copy and Flow

Reuse established HTML/text brand and configured replyTo (support address, not
a newly invented sender). Exact server deadline is shown in UTC preserving
microseconds. Scheduled copy instructs: open Clean Stream app, sign in again,
verify identity, choose Restore account before the deadline. Login alone does
not restore. Restoration confirmation is emitted only by a committed null-to-
restored_at transition. Neither notice claims permanent cleanup occurred;
newsletter is not reactivated and no welcome/reward is created.

No verified hosted Flutter origin exists. Per composer direction, no new URL
config or fabricated direct restore link. Information link uses existing approved
newsletter page origin plus `/account-deletion`, labeled "Account deletion and
restoration information". The public page is staged for paired rollout, not
claimed live. A future direct hosted-app route needs a separate host decision;
it does not block these explicit in-app instructions.

## QA Commands

Run from this sparse root, one process at a time, existing toolchains only:

```sh
CLEANSTREAM_LIFECYCLE_BASELINE=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test scripts/lifecycle-mail.test.mjs
```

Uses existing disposable PostgreSQL17 harness, private socket, no network
listener/live credentials. Verify exit and owned cluster/directory teardown.
Loads actual wallet/refund, admission, deletion, newsletter, cleanup and current
refund-notice prerequisites. Covers rollback and real mail-lock/session-revocation
race, same-event dedup, new cycles, stale leases, suppression, disabled rollout,
financial snapshots, refund behavior and unchanged function/ACL definitions.

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --config=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.json --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --node-modules-dir=none --no-prompt supabase/functions/_shared/mail.lifecycle.test.ts
```

Deno2.9.6 with Node24/PG17.11 existing paths; no repeated version checks by author.
No Deno network/env/read permission needed by renderer tests. Fake transport
never calls global fetch. Covers exact deadlines/microseconds, accessible HTML,
escaping/support reply, honest restore copy, four prior kind contracts, one-send
result classification and stale prepare rejection. Typecheck is part of deno test.
Scoped lint may follow for two changed TS files; do not format unchanged mail.ts
body or rerun old mail94/key/caller suites. Report missing cache before fetch or
install. No new dependencies or pin changes are approved.

Reference: current [Supabase trigger docs](https://supabase.com/docs/guides/database/postgres/triggers)
and actual integrated lifecycle/newsletter/refund contracts. Changelog markdown
fetch returned unsupported-content-type; this batch changes no SDK/API contract.

Remaining: QA evidence and composer paired integration/rollout. No permanent-
deletion-complete notice: no cleanup-completion authority exists in this scope.
