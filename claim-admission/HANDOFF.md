# Claim Admission And Financial INSERT

Source/runtime accepted by serial QA and integrated exact by composer (c415380e/d2b1df09). Not hosted. Author ran **0 tests**, no remote calls, no active-repository edits. A/B remains deployed with deletion-request ACL held; no A/B/foundation rerun.

## Owned Files

- `supabase/migrations/20260930223814_cortina_claim_admission.sql`, CLI-created; SHA256 `c415380e645d4c13b92c0183863bd50ab5c7281f4aa2d614d8bf922a42e2bfe5`.
- `scripts/cortina-claim-admission.test.mjs`; SHA256 `d2b1df09e145141388836b8c02f006b3c0109597b49b198a09561ddd63c2ce8e`.

## Change And Preservation

The existing `request_cortina_loyalty_credit(bigint,text)` now calls canonical Home admission before work, after the existing session lock and after claim/counter/trigger waits, including replay. Existing session-first serialization, caller identity, authoritative vend amount, original 14-day transaction-time check, read-only replay and return shape remain. No wallet-money writes or new helper/framework. CREATE OR REPLACE preserves the function's OID, ACL and owner; no settlement/reversal/refund function body is changed.

Direct `transactions` and `Refunds` client INSERT is retired: revoke table and every column INSERT from PUBLIC/anon/authenticated, assert no inherited effective INSERT remains, add two restrictive INSERT-false policies. Existing service INSERT must remain or the transaction aborts. UPDATE/DELETE/SELECT grants and all existing rows remain unchanged. Trusted postgres-definer claims/admin resolution and service/provider history writers continue through their existing paths, not a client-priced replacement RPC. No global wallet authority is added.

Current consumer evidence, active sources read-only:

- App `lib/services/supabase/supabase_transaction_service.dart` routes claims via `request_legacy_loyalty_credit` or `request_cortina_loyalty_credit`; no current Refunds INSERT.
- Remaining `recordTransaction` callers are the old `lib/features/machine_payment/controller.dart` and PaymentProcessor's direct-machine branch. Current `machine_payment.dart` is an inert informational page; current loyalty controller passes exact `Loyalty Card`, which does not invoke that branch.
- Web RefundRepository/TranscationRepository use SELECT, not INSERT. No current customer write consumer needs these direct financial grants.
- Unsupported old clients attempting raw writes will intentionally receive denial. This is an approved security boundary, not claimed backward compatibility. No new Google account/provider action or other payment-lane changes.

## QA

QA accepted **30 children + parent = 31 pass**, session94149 exit0/c73140. Frozen migration/runner hashes unchanged (14ffb3). PG17.11 stopped, temporary root VZvnhv removed; all QA processes exited and slot released. One process used the existing private PG17.11 harness/authorized relocation. Command retained for provenance, not a rerun request; from this root:

```sh
CLAIM_ADMISSION_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/cortina-claim-admission.test.mjs
```

Current accepted SQL is read-only fixture input, including selector/frozen bindings, ownership guard, canonical admin/MFA, atomic legacy claim and customer SELECT. Synthetic fixture setup may use foundations; these are **not deployment instructions**. Cases cover inherited-grant atomic abort, preserved non-INSERT grants/other writers/rows, both direct INSERT denials and future-grant RLS defense, actual legacy/Cortina definer claims, canonical restrictions, session/terms/deletion changes during waits, late counter-factor/session loss rolling back all claim metadata, exact existing 14-day boundary/replay, concurrent replay, service card-payment/history and late wallet settlement, admin credit resolution, pending-account voluntary refund/reconciliation exceptions. No provider HTTP or paid transaction occurs.

## Deployment Prerequisites

Not authorized for remote application by this lane. Require installed A/B canonical/lifecycle, existing Cortina history/validation/current claim RPC and refund counter, and accepted `20260930180614_legacy_machine_claim_atomicity.sql` before retiring the old direct writes. Require postgres ownership/RLS without FORCE on both tables and existing service INSERT. Existing hosted metadata already covers those table/service properties; no new catalog requested. Test-only broader coexistence migrations are not all direct prerequisites of this replacement. Do not replay history backfill, wallet foundation, balances or provider bindings to install this batch.

No retention, purge, deletion activation, mail enablement, routing, UI or payment-provider deployment is included. QA source/runtime acceptance and exact integration are complete; hosted activation remains separate through C/D.
