# New-Payment Service Control

Local backend source independently accepted by QA; frozen for integration.
No remote write, deployment or activation performed.
The CLI-created migration is
`supabase/migrations/20260930193130_new_payment_service_control.sql`.
Its enabled initial row preserves existing behavior. This is not a general
maintenance system or a trusted client-build/version control.

## Contract

- `private.new_payment_service_control`: exactly one boolean-keyed row,
  `singleton=true`, `enabled boolean NOT NULL`. No arbitrary keys or settings.
- `public.new_payments_enabled()`: zero arguments, boolean only, VOLATILE,
  SECURITY DEFINER, empty search path. Exactly one valid enabled row returns true;
  disabled, absent or malformed data returns false. Lookup failure raises
  sanitized `PT503 new_payments_unavailable`. Consumers must accept only true.
- `private.require_new_payments_enabled()`: internal assertion with the same
  sanitized PT503 on refusal. No direct client/service execution grant.
- Only `redeem_wallet_for_machine(uuid,bigint,integer,text)` and
  `redeem_wallet_for_cortina(uuid)` gain checks. Existing signatures, ACLs,
  caller attribution, canonical Home admission, financial lock order, cents,
  promo-first split, routing and replay behavior remain unchanged when enabled.
  Checks occur before work and after existing wallet/profile/session and
  ledger/cache/status-trigger waits. Post-wait failure rolls back the statement.

The existing READ COMMITTED request contract gives volatile post-wait reads a
fresh committed snapshot. This is not transaction cancellation: a transaction
past its last check can still commit after an operator update. Do not treat a
disable response as a drained queue, a linearizable commit barrier, or a way to
undo an already-dispatched provider request. Longer-lived repeatable-read
transactions are not the supported request contract for this control.

## Exact Authority

Table owned by migration role `postgres`; RLS enabled. PUBLIC, anon,
authenticated and service_role table grants are explicitly revoked first.
Only service_role receives schema USAGE, table SELECT and column UPDATE(enabled),
with service-only SELECT/UPDATE RLS policies. No service INSERT, DELETE, TRUNCATE
or UPDATE(singleton). Database owner retains normal owner administration.
Clients, including profile Owner/Admin roles, cannot read/write this table.

Reader EXECUTE is granted to anon, authenticated and service_role, not PUBLIC.
It exposes only operational availability, without identity or money authority.
Assertion EXECUTE is revoked from PUBLIC and all three runtime roles. Existing
global wallet RPC revokes are untouched. No public setter or operator UI exists;
the private schema must remain outside the exposed Data API schemas.

## Operator Boundaries

These are runbook examples, not authorization to execute against any deployment.
Require a separately approved environment, operator identity and incident scope.
Use a privileged database connection, not a customer JWT or client RemoteConfig.

```sql
begin;
update private.new_payment_service_control
set enabled = false where singleton is true
returning singleton, enabled;
commit;
select public.new_payments_enabled();
```

Expect exactly one returned row and a false reader result. A missing row is
fail-closed; do not substitute a client default. Service cannot recreate it.
An approved owner repair must inspect constraints/ownership and restore exactly
one explicitly chosen value, not blindly seed enabled during an incident.

Operational rollback is the same reviewed transaction setting enabled=true,
followed by a true reader result. It permits future attempts; it does not replay
failed requests or repair/refund settled money. Do not drop the table/functions
as rollback: missing configuration deliberately refuses creation. A code rollback
requires separately reviewed restoration of the two prior function definitions
and any future Edge consumers, preserving the canonical admission migration.

## Preserved Paths And Release Gaps

No gates are added to wallet reads, account admission/support/recovery, status,
confirmation, callbacks, funding settlement, refunds, reversals, reconciliation
or already-paid Start. No existing paid vend is cancelled or repathed. Shared
financial helpers and machine configuration flags are unchanged.

This backend batch gates only the two human wallet debit RPCs. Edge payment
creation (including guest/direct-machine and funding paths) is a separately
approved follow-on after this contract is accepted. Until integrated, this is
not a complete new-payment shutdown. Future Edge checks must use the fixed
reader immediately before new provider creation, fail closed on transport/wire
errors, and leave status/confirm/paid Start independent. Even then, dispatched
provider requests cannot be undone by the switch; reconciliation remains needed.
Hosted gateway, production grants and rollout validation remain release checks.
No AdmissionStatus fields, global Owner/Admin authority or purge policy change.

## Verification Handoff

New focused runner: `scripts/new-payment-service-control.test.mjs`.
QA accepted 39 distinct child cases plus parent = 40 across two case-bearing runs:
first 23 child passes retained, final remaining 16 children + parent = 17 passes,
zero final failures, exit 0, 3.6s (session87006/chunk64557d). Final run deliberately
excluded first23 with --test-skip-pattern: NOT a fresh full40 pass. All six races
and preservation paths passed. PG17.11 stopped and owned directory `2UFy64`
removed; all processes exited. No author execution or additional rerun needed.
Frozen runner SHA256 `9c99dd9377d62749a5658f663046229d843cd254800c12804922d5e87179ffde`;
migration SHA256 `78ec7fa772441698e10eeb4109fb219ba2147f6759414e30720b63e16ee8021f`.
QA's first two runs stopped during fixture setup (duplicate `is_out_of_service`),
each before child cases: 0 child passes, parent failed, exit 1. PG17.11 stopped
and owned temporary directories `nuPTuZ` / `GnDd8S` removed. Making the earlier
fixture addition conditional did not fix the later unconditional production DDL.
Source-order review identifies `20260928151021_admin_operations_extensions.sql:13`
as its sole owner; the fixture addition is now removed. Binding trigger creation
precedes it but no vend insertion occurs until after the entire prerequisite chain.
The same review supplies the support-refund fixture's required legacy transaction
for the existing portal `assertCredit` join. No assertion or migration changed.
The next QA run reached cases: first 23 passed; the terms fixture violated the
existing paired acceptance constraint, closing the shared SQL session and causing
15 later setup failures. Totals: 23 child passes, 16 child failures plus parent
failure, exit 1; PG stopped and directory `a3qgtt` removed. Fixture now clears both
version and timestamp; constraint/assertions/production SQL unchanged. Remaining
mutations reviewed against existing session, MFA and wallet contracts. Corrected
source accepted with the final delta above. Scoped whitespace checks had empty
diagnostics, not runtime passes.
Coverage includes grants/defaults/malformed config, six real lock/trigger waits,
unchanged canonical restrictions, enabled money invariants, recovery, settlement,
internal support refunds and full topup-refund completion while disabled.
Existing SQL functions/policies/ACLs are compared before and after the migration.
No provider, hosted gateway or actual Start execution is claimed by SQL tests.

QA owns the serialized queue. Exact command from this owned root:

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/new-payment-service-control.test.mjs
```

Reuse unchanged `scripts/test-support/policy-admission-pg.mjs`: one synthetic
PG17 cluster, private socket, approved unlinked-bottle relocation, mandatory stop
and owned-directory removal. No installed runtime changes or remote credentials.
The two existing binding/ownership fixture snapshots are reused without adding
copies. Composer should substitute their byte-identical active migration reads
on integration, as for the accepted wallet/legacy runners. No older suite rerun.
