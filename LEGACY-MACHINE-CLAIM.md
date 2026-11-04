# Legacy Machine Claim Contract

Implemented locally; **65 child cases + parent = 66 passes**, exit 0. Source frozen
and independently source-accepted by Descartes for bounded integration, with no
actionable findings. Test slot released to composer; all processes exited.
Wallet, maintenance and cleanup artifacts remain frozen. Active source is
read-only; composer owns client service adoption. No slot held while coding.

## Observed Contract

Sources below are relative to the active `CleanStreamLaundryApp` root:

- `lib/services/supabase/supabase_transaction_service.dart:77` reads an owned
  transaction, then for non-Cortina history separately updates `requested_refund`,
  inserts `Refunds` with that amount, and calls `increment_user_refund_attempts`.
  A failure after either committed write is not an atomic failed claim.
- `supabase/migrations/20260928132533_link_cortina_transaction_history.sql:116`
  defines `request_cortina_loyalty_credit(bigint,text) returns jsonb`: a session
  lock, owned started vend, server amount, one pending request, one counter call,
  and replay of the existing `refund_id/amount/status`. Its trigger protects
  Cortina inserts/approval; its early return deliberately leaves legacy unguarded.
- `lib/logic/parsing/transaction_parser.dart:13` and `docs/payments.md:43` establish
  the existing 14-day machine-claim window. The 48-hour top-up policy is different.
- `lib/features/machine_payment/controller.dart:174` writes legacy `type='laundry'`
  history after redemption but discards the redemption receipt. The transaction
  has no durable redemption/provider-session link. `wallet_redemptions` in
  `20260526010000_wallet_ledger_compliance.sql:69` has no transaction FK either.
  A persisted legacy amount is authoritative for the pending claim snapshot,
  NOT independently verified payment/vend evidence. Never infer a link by
  amount/time/description or reprice historical records from today's machine.

## Owned Implementation

One CLI-created migration:
`supabase/migrations/20260930180614_legacy_machine_claim_atomicity.sql`, plus
`scripts/legacy-machine-claim.test.mjs`, this note and root `HANDOFF.md`.
These are the only newly edited files in the approved follow-on batch.

Adds only `public.request_legacy_loyalty_credit(target_transaction_id bigint,
request_description text) returns jsonb`. Reuse `get_admission_status()`, the
existing transaction/Refunds rows, counter routine and Cortina-style receipt.
The Cortina-named RPC is unchanged; no dispatcher/framework/table is added.
Only authenticated EXECUTE is granted; anon/service/PUBLIC execution is revoked.

1. Require canonical Home admission (current authenticated subject/session,
   lifecycle, applicable MFA and current terms); never accept actor or amount
   arguments. No new support/refund exception or automatic terms acceptance.
2. Auth SHARE from admission, then owned transaction NO KEY UPDATE, then caller
   profile NO KEY UPDATE. Re-read eligibility after waits. No wallet/session lock
   is needed for an explicitly non-Cortina legacy row. Profile locking orders
   claim creation against deletion; final admission check covers trigger waits.
3. For a new claim, require non-Cortina laundry history, stored positive finite
   dollar amount representable by existing credit-resolution cents, and the
   original 14-day window checked against wall-clock time after waits. Validate
   the same trimmed 1..2000-character reason as Cortina. Do not classify by text
   alone or accept top-ups/rewards as laundry claims.
4. Read an existing matching request without locking/updating it; return its
   saved receipt without another counter increment, even after the new-claim
   window. Preserve resolved status. Multiple/conflicting historical requests
   fail closed for reconciliation, not arbitrary selection or deletion.
5. Otherwise insert one pending Refunds row, set requested_refund and invoke the
   existing counter once in the same transaction; any failure rolls all back.
   A true flag with no row does not establish a saved claim and may be repaired
   by valid creation. Do not reconstruct uncertain historical counter values.
6. Never call resolution, funding, redemption, reversal, refund-provider or cache
   money routines. Preserve wallet/load/ledger/reservation and balance records.

Do not lock an existing Refunds row while holding transaction/profile locks:
`20260929231120_serialize_wallet_financial_writes.sql:448` resolves in
Refunds UPDATE -> transaction SHARE -> wallet -> profile order. Replay is a
read-only receipt, not a second resolution or counter repair.

## Notice Coordination

Ramanujan owns the still-unverified additive source
`/Users/jamaki604/CleanStreamProjects/.campaign-work/email/supabase/migrations/20260930175136_refund_request_notice_outbox.sql`.
It defines `enqueue_refund_request_notice(target_transaction_id bigint) returns
jsonb`, looking up exactly one owned pending claim. It uses the existing mail
advisory lock, not wallet/transaction/refund row locks, and deduplicates on
`loyalty_credit_requested/<refund_id>`. Recipient is server-designated and unset;
disabled/unavailable states do not mean sent. Ramanujan confirmed this exact
contract and the separate post-commit boundary directly; source remains untested.

Keep this a separate post-commit notice request via the existing refund-email
adapter, as the current controller already does. No mail call/trigger inside the
atomic claim RPC: notice failures cannot roll back saved-claim success. No new
outbox, provider call, mail file edit, activation or delivery guarantee.

## Acceptance Boundaries

- This is pending manual machine-issue credit, not an approved payout or proof
  of a successful historic vend. If verified payment linkage is required for
  legacy eligibility, that missing authority is a blocker, not a guessed join.
- New-RPC calls serialize/replay by transaction. Unmodified legacy direct
  inserts do not participate in that whole transaction; universal mixed-client
  deduplication requires separately coordinated write guards/retirement. Do not
  add a global unique index over unreviewed historic duplicates or silently
  revoke old clients. Client adoption is required to fix the three-write path.
- Client service, Cortina claim/validation, admin resolution, top-up refund,
  failed-vend compensation and settlement remain unchanged. No lifecycle or terms
  gate is added to provider completion. Existing top-up support exceptions remain.
- Authored focused PG checks: rollback at each write/counter/trigger failure;
  parallel replay/lost response; old flag-only and ambiguous rows; foreign user,
  lifecycle/session/MFA/terms denials including waits; 14-day boundary/replay;
  top-up/Cortina exclusion; authoritative receipt; unchanged money snapshots.
  Initial focused run and correction are recorded below. Uses the existing private-socket disposable PG17 harness,
  authorized owned bottle relocation/teardown, non-superuser candidate owner,
  and actual financial/Cortina/admission/lifecycle migrations. Binding/ownership
  prerequisites reuse the frozen byte-identical reviewed snapshots; integrated
  runners should read those identical active migration files without duplication.

## Client And Test Handoff

Composer has the created migration path and keeps the owned metadata lookup only
to route Cortina versus legacy. Replace all three legacy writes with this RPC,
return its saved amount, and pass transaction identity as a decimal string into
the declared bigint parameter. The runner includes one PostgreSQL JSON-to-record
decode above the JS safe-integer limit; it is not a PostgREST/gateway simulation.
Hosted named-argument conversion and old-client retirement remain release checks.

Exact focused command, from the owned root, only after explicit slot grant:

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/legacy-machine-claim.test.mjs
```

No previous suite rerun, mail/provider call, remote operation or activation.

## Author Verification

Under explicit transfer from Leibniz, ran the exact command once with approved
local shared-memory access: PostgreSQL 17.11, private socket and no listeners,
**64 child passes, 1 child failure plus failed parent (66 total)**, zero skipped/
cancelled, exit 1, 6299.008708 ms. Harness confirmed server stop and removal of
`/private/tmp/cleanstream-wallet-locking-policy-pg-smu5Je`; all processes exited.
Slot explicitly transferred to Ramanujan per the latest composer instruction.

Failure was the late-factor-removal fixture using an ordinary User: after that
user's optional last TOTP factor is removed, canonical eligibility no longer
requires MFA. Existing evaluator mandates enrollment for missing Admin/Owner
factors. The fixture now sets Admin before its factor-removal race, matching the
intended mandatory-MFA assertion. No production function/assertion was weakened;
the candidate migration is unchanged. Initial partial passes are not accumulated
into final passing evidence.

Composer explicitly regranted the identical command after email/Flutter process
exit. The corrected runner ran exactly once: **65 child cases + parent = 66
passes**, 0 failures/skips/cancellations, exit **0**, **6348.343083 ms**.
PostgreSQL **17.11** used the reviewed owned relocation, private Unix socket and
empty `listen_addresses`. Harness confirmed server stop and removal of
`/private/tmp/cleanstream-wallet-locking-policy-pg-ZvIZyN`; all Node/psql/server
processes exited. Slot released directly to composer. No other check or suite ran.

Frozen source SHA256:

- Migration: `5d8039040e65edc15831b763797d86b535e9b7b8898f57a23e101d3df522f326`.
- Runner: `9810fed2c0ee23fc96903014ebf9469a1711c4e78c60b23bab52e230b9cc8150`.

Descartes accepted the source/fixture after reviewing lock order, post-wait and
trigger checks, atomicity, replay, financial preservation and release caveats.
QA retained the corrected author66 runtime evidence without another run.
Coordinated deployment/hosted transport remain separate.
