# Human Wallet Spend Admission

FROZEN, INDEPENDENT QA ACCEPTED. Descartes reports **43 PostgreSQL cases + parent
= 44 passes**, exit 0, zero failures/skips/cancellations, 6069 ms, with the reviewed
Cortina coexistence prerequisites below. PG17.11 stopped and owned temporary root
`/private/tmp/cleanstream-wallet-locking-policy-pg-mw1PYm` removed; all processes
exited. QA released the slot; no author rerun. Local contract evidence only:
no remote action, deployment, provider call, or active checkout edit. Cleanup's
eight files and the four maintenance artifacts remain frozen and unchanged.

## Exact Ownership

Only writable root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup`.

- `supabase/migrations/20260930171558_human_wallet_spend_admission.sql`, created
  with installed Supabase CLI `migration new human_wallet_spend_admission`.
- `scripts/human-wallet-spend-admission.test.mjs`.
- Test-only exact reviewed SQL snapshots under `supabase/tests/human_wallet_spend_reviewed/`:
  `20260930154259_freeze_cortina_payment_bindings.sql` and
  `20260930163919_cortina_callback_provider_ownership.sql`.
- This note and root `HANDOFF.md`.

Existing migrations, fixtures, shared harness, provider/binding/worker files,
keys, email, UI, route and DI files are read-only. No new table/helper/framework,
ACL change, dependency, or background process. No existing function removed.

## Actual Definitions And Callers

1. `public.redeem_wallet_for_machine(target_user_id uuid, target_machine_id bigint,
   amount_cents integer, redemption_note text default null) returns jsonb`.
   Latest definition: `20260929231120_serialize_wallet_financial_writes.sql`.
   Active app `lib/services/supabase/supabase_wallet_service.dart::redeemForMachine`
   sends its current user ID via the signed-in Supabase client. The older
   `machine_payment/controller.dart` references this service, but its current
   route is inert containment, not the scanner's Cortina payment path.
2. `public.redeem_wallet_for_cortina(target_session_id uuid) returns jsonb`.
   Definition: `20260803150427_cortina_qr_remote_vend.sql`; invokes the machine RPC.
   Active `supabase/functions/cortina-vend/logic.ts::handleWallet` verifies the
   inbound bearer via `getOptionalUserId`, creates a session with the admin client,
   then invokes this RPC through a public-key client carrying the same request
   Authorization header. It does not debit with the service client.
3. App `supabase_cortina_vend_service.dart::payWithWallet` and web
   `src/supabase/repositories/CortinaVendRepository.ts::payWithWallet` call that
   Edge route. No additional direct web redemption RPC caller was found in `src`.

These are read-only active source observations, not hosted signature/transport
verification. Attribution is unambiguous at the SQL human boundary: original
`auth.uid()` ownership checks plus canonical subject/session/JWT validation.
No body-supplied actor, metadata role, service identity or delegation rule added.

## Smallest Change And Lock Order

Only the two function bodies are replaced, retaining signatures/defaults,
definer/search-path settings and existing ACLs. Canonical
`get_admission_status()->>'next_step' = 'home'` is required, so current session,
account/lifecycle, applicable MFA and current terms are all reused. Non-home is
PT403 `account_restricted`; existing PT401/PT503 canonical failures propagate.
Original valid-caller financial errors and JSON shapes stay unchanged.

- Canonical admission takes Auth SHARE through existing policy-status logic.
- Direct debit: Auth SHARE -> existing wallet NO KEY UPDATE -> caller profile
  NO KEY UPDATE. Recheck after these waits and before balance/debit decisions.
- Cortina: Auth SHARE -> existing session UPDATE -> inner wallet -> profile.
  The inner precheck re-evaluates after a session wait. Final outer admission
  recheck also covers waits in the status UPDATE's triggers.
- Lifecycle request/restore: Auth SHARE -> profile -> lifecycle. They do not
  take a wallet lock. Holding the profile during debit orders a new deletion
  request after that debit; a deletion that wins the profile first is observed
  by the debit's post-wait check. No new lifecycle lock or alternate evaluator.
- Preserve wallet-before-profile, used by funding and `sync_profile_wallet_balance`;
  no profile-before-wallet wrapper. Final admission checks roll back redemption,
  paid/promo ledger, top-up spend provenance, cache and Cortina paid-link changes
  when revocation is observed after trigger waits. Session/factor authority is
  rechecked, not globally locked; this does not promise perpetual revocation of
  work already committed or checks extending into provider/network operations.

Paid/promo cents, promo-first use, wallet status, insufficient-funds checks,
refund reservation balances, original notes and Cortina nonpayable replay
behavior are unchanged. `get_or_create_wallet_account`, cache sync, funding,
reversal, refunds, callbacks and provider settlement are not modified or gated.

## Verification

The unchanged candidate migration was originally verified with 43 child cases
plus parent. QA identified missing newer Cortina prerequisites in that harness.
The frozen follow-up retains all 43 cases and original assertions, loads actual
dryer/price selectors and link-history SQL once, then exact active binding and
ownership snapshots. It replaces duplicated history fixture DDL, not guards.
Synthetic vend setup now includes a real washer rate, machine type/availability,
pulse selector and enabled sandbox routing. Overspend creates its 2000-cent vend
at insertion instead of updating a frozen amount; successful debit and reversal
also assert binding preservation. Both snapshots were byte-identical to active.
Descartes source-reviewed and independently passed this final chain as reported
above. Composer will integrate only the migration and runner, reading the same
verified prerequisite bytes through `migration(n)` instead of adding duplicate
SQL snapshots to active. No further wallet reruns are authorized or needed here.

The following execution details describe the earlier author verification, not a
second author run of the coexistence chain:

New suite composes existing wallet/Cortina/financial-locking, authority, admission,
lifecycle and top-up-refund migrations/fixtures; it does not mock eligibility.
Bootstrap-only synthetic postgres superuser is removed before candidate/runtime
checks, retaining BYPASSRLS and explicit Auth metadata grants for the definer.
New DDL preserves original function metadata, unrelated function bodies and rows.

Auth/lifecycle/terms/MFA cases cover both human RPCs; financial cases cover
promo-first/cache/receipt preservation, empty-wallet rollback, reservations,
duplicate funding, and pending-account reversal/refund completion. Independent
sessions cover Auth, wallet, profile and Cortina waits; real wall-clock expiry;
ledger/cache/status trigger rollback; late factor removal; deletion ordering;
and cross-session overspend exclusion. All 43 child cases passed in the final run.

Exact single-process command executed serially after Leibniz explicitly confirmed
process exit and transferred the composer-preauthorized slot, from the owned root:

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/human-wallet-spend-admission.test.mjs
```

Used the existing disposable PG17.11 harness and authorized owned relocation/
teardown, with approved local shared-memory access. No installation/cache copy/
system links or existing databases. Assigned Node24 runtime, heap 1024 MiB.
No Deno/cleanup/maintenance or other older suite was run.

- First run: exit 1; 0 passes, failed first child and parent (2 failures). The
  synthetic postgres role lacked public-schema CREATE after removal of superuser,
  so DDL stopped before behavioral checks. Added the fixture's explicit schema
  USAGE/CREATE grant, matching the existing maintenance fixture's owner setup.
  Server stopped; `/private/tmp/cleanstream-wallet-locking-policy-pg-pvYeHc` removed.
- Second run: exit 1; 4 child passes, 40 reported failures including parent.
  The next fixture setup cleared the terms timestamp alone, violating the real
  `profiles_loyalty_policy_acceptance_pair` constraint and closing the shared
  session; subsequent failures cascaded from that exit. Source review corrected
  both test setups to clear version and timestamp together, preserving the
  existing constraint. Suppressed repetitive setup notices. Server stopped;
  `/private/tmp/cleanstream-wallet-locking-policy-pg-WLgctj` removed.
- Final run: **PostgreSQL 17.11 (Homebrew)**, private Unix socket and empty
  `listen_addresses`; **43 cases + parent = 44 passes**, 0 failures/skips/
  cancellations, exit **0**, **4994.81875 ms**. The harness confirmed server stop
  and removal of `/private/tmp/cleanstream-wallet-locking-policy-pg-kAqBjO`,
  including synthetic data, socket, relocated executables and links. Process
  exited. Slot explicitly released and transfer sender notified.

Only owned test setup changed during verification; no migration or shared
financial/canonical evaluator source changed, and no assertion was weakened.
Counts from failed attempts are not accumulated into final passing evidence.

## Remaining Boundaries

- Composer must coordinate migration order after reviewed financial locking,
  profile/admission and lifecycle migrations; reconcile actual deployed bodies,
  ownership/grants and provider/client transport before any release. Source
  review and synthetic fixtures are not deployed-schema proof.
- Home admission intentionally denies old clients without current terms/MFA or
  valid session claims; paired rollout and final terms approval remain required.
  Wallet read/funding/admin paths are not made lifecycle-complete by this batch.
- Cortina Edge creates a pending session before the human debit RPC. That existing
  service mutation and its error handling remain unchanged. Already-paid replay
  calls `startCortinaVend` without a new debit; preserve accepted execution rather
  than reinterpreting it as new human spending or blocking compensation.
- Legacy machine RPC still accepts caller-selected machine/amount and is not
  idempotent. Pricing, device wake, old-client retirement and direct-entrypoint
  containment are separate existing concerns; this patch neither expands nor
  claims to solve them. No provider calls or money movement were attempted.
