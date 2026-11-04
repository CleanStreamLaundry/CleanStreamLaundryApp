# Permanent Cleanup: Second Batch

**FROZEN LOCAL SOURCE / UNTESTED / UNDEPLOYED.** First seven files were integrated
by composer; this follow-up modifies four of those candidate paths only.
No tests, typechecks, builds, provider/cloud calls, customer reads or active edits.
Runtime checks completed: **0**. Execution and credit forfeiture remain off.

Owned root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/permanent-cleanup`.
Exact changed integration paths, relative to that root and the active app:
- `supabase/migrations/20261001130137_permanent_account_cleanup.sql`
- `supabase/migrations/20261001130950_retained_financial_subjects.sql`
- `supabase/functions/account-cleanup/execution.ts`
- `supabase/functions/account-cleanup/index.ts`

Docs only: this file and `CLEANUP-IMPLEMENTATION.md`. Do not copy CLI authoring
`supabase/config.toml`. Existing `logic.ts` and both dormant ops scripts unchanged.
Both SQL files remain UNAPPLIED candidates; integrate replacements, not a replay.

## Implemented Locally
- One exact-version closed attachment per invocation before account work, at
  ninety days from authoritative closure; active accounts need no deletion request.
  Uses existing support rows, known history/new closure clocks, authoritative
  owner_id, exact descriptor, scoped holds and operator class-inventory evidence.
- Separate claim/operation/closure fencing; lost outcomes inspect primary state
  without resend. Reopened/replaced attachments are never cleared by an old receipt.
  Pending attachment outcomes fence account finalization; report locking is NOWAIT.
- Twelve months after confirmed Auth removal, erase full job/inventory metadata.
  Delete the lifecycle link when no consumer remains; otherwise retain only the
  minimal link and explicit support/newsletter/mail/security reasons. Future class
  pruning removes the link when those reasons clear. Unknown outcomes/cleanup holds
  retain evidence. Active-account attachment receipts also expire at twelve months.
- Twelfth validated FK: only `admin_invitations.invited_by` targets the existing
  retained UUID anchor/trigger. Target-user CASCADE, roles and ACLs unchanged.
  Auth removal still fails until the exact validated relation/column FK is installed.
- Removed redundant Edge final-policy/Stage-3 booleans and SQL Stage-3 timestamp.
  Keep master/executor off defaults, exact policy identity and actual SQL policy
  approval for irreversible work. No workflow stage is a runtime authority signal.

Reuse: existing support/job persistence, locks, scheduler and versioned Storage
transport. No new table/service/queue; no financial arithmetic or balance change.
Claim lease/retry/deadline behavior retained for live jobs; completed jobs excluded.
Always `purge_complete=false`; retained financial identities are not full profiles.

## Required / Not Implemented
Final approved policy/scope and real hold/processor/media/backup/financial inventories
are still required, not inferred from this draft or an empty hold table. Tax clocks,
minimum financial free-text mapping, external processor/CDN/backup erasure/replay,
routine-log classification and uncertain dedup expiry remain unimplemented/input-gated.
Unknown historical closure/ownership is not guessed. Held Storage evidence can still
block Auth removal. No credit forfeiture or blanket financial deletion exists.
Runtime SQL/Edge concurrency, metadata expiry and hosted versioned API compatibility
remain untested. Composer owns integration/activation; no further batch started.

Details/install boundaries: `CLEANUP-IMPLEMENTATION.md` (targeted update only).
