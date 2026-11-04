# Machines Maintenance Privileges: Closed

Root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/machine-write-privileges`.
Composer-reported closure: both files integrated at exact hashes `1eff37` (`172b6edb` migration / `ebcaf913` runner); updated metadata preflight `383c4b`, development install `b63c6a` EXIT0, postflight `088326`. The entire `preserve` catalog compares equal, including SELECT/DML/service/function/policy/trigger/schema/deletion metadata. Only the targeted ACLs changed; all eight client D/x/t/m and all column REFERENCES checks are false. Exact one-version history `20261001101347`, source `172b6edb`, recorded `2f6072` EXIT0. Composer reports no records read or changed. These are Composer's hosted receipts, not author execution.

Corrected independent QA run `53ffda`, session 14705 EXIT0: 26 PASS (25 children + parent), zero failures/skips/cancellations. This standalone result supersedes the initial fixture failure `2c43bf`; do not add its prior 24 passes. PG17.11 stopped and `/private/tmp/cleanstream-wallet-locking-policy-pg-gnvXex` was removed; all processes closed and slot released. Exact source hashes reverified `f33ec5`. Owner-only availability write, both staff reads and service writes are preserved. No author runtime, cloud access, provider activity or data changes. Batch closed; no further work assigned.

| Owned path | Baseline | Frozen SHA256 |
| --- | --- | --- |
| `supabase/migrations/20261001101347_restrict_machine_client_maintenance_privileges.sql` | New, generated with installed Supabase CLI 2.84.2 `migration new` | `172b6edb9679ab8a63f9bfd4ae961f61084f4ab4c5084f877e5e494a8f5a070a` |
| `scripts/machine-client-maintenance-privileges.test.mjs` | New | `ebcaf9132cae2fa41131a8bf15f037e1205dde71ec2bec147878bc8a123eeb3f` |

## Minimal Contract

Remove only Machines table TRUNCATE/REFERENCES/TRIGGER/MAINTAIN and column REFERENCES from PUBLIC, anon and authenticated. Retain SELECT exactly as found (broad current reads or the separately reviewed eleven-column projection), INSERT/UPDATE/DELETE, RLS, existing functions/triggers, service-role and postgres-owner authority, all other tables and all rows. No new trigger, RPC, table or framework is needed: these operations require the revoked privileges before ordinary row guards matter.

The migration refuses unexpected client role inheritance/authority and owner/RLS drift. `RESTRICT` refuses dependent grant chains instead of cascading into another role. Postconditions assert effective table/column denial and unchanged service-role table/column authority; an error rolls back the transaction. Existing canonical staff definer writes retain owner privileges. This is narrow grant removal, not removal of existing constraints/triggers or a claim that all database misuse is covered. PostgreSQL's [REVOKE rules](https://www.postgresql.org/docs/17/sql-revoke.html) govern inheritance, column rights and dependent grants.

Source basis: active `20260928135006_admin_portal_operations.sql:62` and `20260930142406_admin_canonical_authorization.sql:154` cover direct INSERT/UPDATE/DELETE; `20260928151021_admin_operations_extensions.sql:135` is the row audit trigger, not a TRUNCATE guard. Composer's fresh hosted `0443df EXIT0` confirms rDxtm, service-role full grants, postgres ownership/RLS, no client parent roles or super/bypass/createrole, null column ACLs and deletion held. No new hosted query or mutation was performed here.

## Focused QA

Full suite passed 25 children + parent = 26 cases in the corrected run above. The runner reuses the existing disposable PG17/private-socket/relocation/teardown helper and the already accepted machine-privacy synthetic prerequisite chain. No older suite executes and no copied production SQL is embedded. Actual canonical staff/admission bodies are read from the active app, read only; the SELECT candidate is read separately and hash-pinned.

Coverage: observed baseline; three inheritance cases; bypass/RLS drift; dependent-grant rollback; PUBLIC-only trusted column-right preservation; successful rollback; effective PUBLIC/direct table/column denial; actual client TRUNCATE/FK/trigger/reindex denial; unchanged current wildcard/count reads; either order with the SELECT candidate; both staff reads, Owner availability write, Admin write rejection and service updates; unchanged rows/audit/functions/policies/triggers/other grants and deletion hold. Temporary probe schema/function exist only in the disposable synthetic test database to distinguish the intended privilege denial from a missing unrelated prerequisite.

Recorded accepted QA command; no rerun requested. Author remains source-only. From this root:

```sh
MACHINE_PRIVILEGES_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp MACHINE_COLUMNS_MIGRATION=/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/machine-column-privacy/supabase/migrations/20261001095826_machine_public_read_columns.sql PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/machine-client-maintenance-privileges.test.mjs
```

Require exit status, completed case counts and helper diagnostics for server stopped/temp directory removed. No install/cache copy, external DB, native build or provider tests. Do not rerun the preceding privacy/Flutter/web suite for this batch.

Correction contract source: active `20260928151021_admin_operations_extensions.sql:376-377`. Composer/source confirmed existing SQLSTATE `42501` and message `Owner access required`, not shorthand `PT403`; this was a source-contract correction, not a user business-policy decision. No permission broadening or production change.

## Install and Rollback Boundaries

Historical preflight `727221` and history query `55a729` established the original grants and absent versions. Composer's updated `c3b01a8c` metadata preflight `383c4b` and postflight `088326` now establish exact preservation across the successful install; the history receipt is recorded above. The separate six-file column-privacy source is integrated `77c206` but its SQL remains held for compatible client release.

Metadata-only pre/postflight: `pre-postflight.sql`, SHA256 `c3b01a8c2e5563a577702667ecf927f5258303af4e87dfe854c28f2af3e6dc9c`. Composer used this same single catalog SELECT for the reported comparison; author has not executed it. No rows, credentials, function bodies, RPC calls or history writes. It reports Machines owner/RLS/column definitions/constraints/indexes/policies/triggers, hashes and ACLs of its trigger functions plus the exact canonical staff writer chain (including the existing `admin_portal_data_before_reporting` body containing the Owner check), role authority/parents, and effective table/column permissions for anon/authenticated/service_role. `REFERENCES` is the only column-level privilege among D/x/t/m; SELECT/INSERT/UPDATE column rights are included for preservation comparison.

Compare the entire `preserve` object for equality. Require `target_present=true`, no missing named functions, the reviewed postgres/RLS/role state and deletion hold. In `expected_acl_delta`, every client table D/x/t/m and column REFERENCES value must be false afterward. Explicit ACL changes must be limited to removing those privileges from PUBLIC/anon/authenticated; no added rights or other grantee/privilege changes. This preserves SELECT whether the separate projection candidate is absent or already installed; do not run both migrations between the two snapshots when validating this batch alone. The migration remains at its original frozen hash; only the permitted runner expectation and metadata coverage changed.

This standalone non-SELECT migration does not require new client projections and can be reviewed independently while the SELECT privacy migration remains blocked on compatible client release. Its runtime SQL is one atomic transaction with no data backfill, cleanup or deletion enablement. It can precede or follow the projection migration; it does not make that earlier rollout blocker disappear. No author deployment is authorized or performed.

Composer completed the exact single development install and one-version history recording. Postflight confirmed the four effective table privileges and all column REFERENCES are false for anon/authenticated, with previous SELECT shape, service grants, owner/RLS, functions/triggers and deletion hold unchanged. Do not replay this or prior migrations; no additional audit, tests or deployment is assigned.

Failed installation rolls back the ACL changes. A successful rollback must not blindly regrant unnecessary client maintenance privileges; stop and review the specific legitimate consumer/role if one is discovered. No unresolved business-policy choice was invented for this batch. QA and Composer integration/activation are complete.

The only prior-lane edit was the machine-column-privacy HANDOFF correction to `/Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter`; its six sources remain frozen. QA owns its configuration-only harness corrections and serial runtime.
