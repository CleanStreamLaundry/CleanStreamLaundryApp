# Inventory Maintenance Privileges: Closed

Root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/inventory-maintenance-privileges`.
Composer-reported closure: exact two files integrated `6de0fe`; preflight `a8bbdf`; development deployment `beb819` EXIT0. Postflight `53822b` confirms the entire `preserve` object equal, only targeted ACL revokes, all 24 client D/x/t/m checks false and all client column REFERENCES false. History `895772` records exactly version `20261001103350`, source `eda70cb4`. Composer reports records were not read or changed and all CLI processes are terminal. Machines SELECT rollout hold remains. These are Composer receipts, not author hosted execution.

Author remained source-only: no tests/runtime, hosted access, provider actions, native builds, dependency installation or active-source edits. Independent QA accepted 23 cases (22 children + parent), session 60117 EXIT0 `66339a`, zero failures/skips/cancellations. Frozen source hashes verified `1e17c6`. PG17.11 stopped and `/private/tmp/cleanstream-wallet-locking-policy-pg-oWbwcL` was removed; all processes terminal and slot released. Batch closed; no more code, audit or runtime assigned. Exactly two integration files plus one metadata-only artifact:

| Owned path | Baseline | Frozen SHA256 |
| --- | --- | --- |
| `supabase/migrations/20261001103350_restrict_inventory_client_maintenance_privileges.sql` | New, created via existing CLI `migration new` | `eda70cb4e1add3dc0941278c5471c976f8310251ba2d246c0a1bcba3f2019303` |
| `scripts/inventory-maintenance-privileges.test.mjs` | New | `d3acf9aa3a95386c2082d46badf24d8b06fb196dd0015367e1eb0087ffff79c9` |
| `pre-postflight.sql` | New, catalog SELECT only | `6e955ea2332268dd329373adb21c61d305e9eff249174389a71f9192b3e0d3e4` |

## Scope and Reuse

Composer's historical hosted preflight `01137c` confirmed exactly `public."Locations"`, `public.washer_size_rates`, and `public.cortina_machine_config`: postgres-owned, RLS enabled, anon/authenticated SELECT true and INSERT/UPDATE/DELETE false, TRUNCATE/REFERENCES/TRIGGER/MAINTAIN true; service grants all true. The post-install receipt above supersedes those targeted privileges. This is Composer evidence, not author remote inspection.

Reuse the accepted Machines privilege-removal approach in a fixed three-table loop. Remove only PUBLIC/anon/authenticated table D/x/t/m and column REFERENCES. Preserve SELECT and DML grants, all RLS/policies/functions/triggers/rows, service and owner rights. Machines is excluded from the migration and metadata target list. No new trigger, table, RPC, configuration system or framework. The loop avoids three copies of the same checks and revokes; it has no configurable target list.

Unexpected client role authority/inheritance, missing/reowned/non-RLS target, dependent grant chain, residual effective rights or changed service authority aborts the entire transaction. `RESTRICT` avoids cascading into other roles. Tests place failure on the third table to verify earlier revokes roll back too. No data backfill or deletion enablement.

Current canonical operation sources are reused read-only: `20260928135006_admin_portal_operations.sql` implements Owner-only `createLocation`, `saveRate`, `saveConfig`; `20260930142406_admin_canonical_authorization.sql` supplies caller-bound pre/post-wait staff context. The fixture also uses the actual `20260804015500_cortina_rls_policy_cleanup.sql`, so it preserves the accepted rate/config RLS rather than assuming public row visibility from SELECT grants. Existing Owner requirements are asserted as `42501 / Owner access required`, not broadened to Admin.

## Focused QA Command

Accepted **22 children + parent = 23 passes** in the independent run above. Recorded command only; no rerun requested. From this root:

```sh
INVENTORY_PRIVILEGES_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/inventory-maintenance-privileges.test.mjs
```

Reuse the existing accepted private-socket/disposable-cluster relocation and teardown helper. The synthetic prerequisite chain is the previous focused inventory fixture with actual canonical migrations read from the active app. Include the already installed Machines grant-removal migration as fixture baseline; do not execute its old tests or replay any hosted migration. No copied dependency cache or new harness framework.

Cases: baseline per table; three inherited/SET-only privilege paths; unexpected bypass; third-table RLS/dependent-grant/trusted-column failures with all-table rollback; successful explicit rollback; fixed-scope PUBLIC/direct effective removal; both client roles on each table preserving current read outcome and rejecting truncate/FK/trigger/reindex operations; each actual Owner createLocation/saveRate/saveConfig operation plus explicit Admin rejection and service update; unchanged rows, audit, policies, functions, triggers, unrelated ACLs including Machines, and deletion hold. Read preservation does not claim anonymous rate/config row visibility where existing RLS denies it.

QA confirmed the completed case count, EXIT0, PG17.11 and diagnostics for stopped server/removed temporary root before releasing the slot. No author checks run; no prior suites are requested. The accepted command used the pinned Node24 path/heap1024 and installed PG17.11.

## Metadata and Rollout

Composer-reported hosted preflight `a8bbdf` EXIT0 used final metadata `6e955ea2` unchanged: all three tables postgres-owned/RLS enabled, no missing tables/functions or client parents, originally all 24 targeted client table privileges true, deletion held. Postflight `53822b` confirms exact saved `preserve` equality and only approved ACL removal. Historical absence check `0de50e` is superseded by exact one-version history receipt `895772`. No further author scope is assigned.

`pre-postflight.sql` is the same single catalog SELECT for both phases. It reads no application records, credentials, function bodies, or executable RPCs and writes no history. Fixed targets are the three tables above. It captures definitions/owner/RLS, policies, indexes/constraints/triggers, relevant canonical/trigger function hashes and ACLs, role authority/parents, effective SELECT/DML/service rights, targeted D/x/t/m and column REFERENCES, plus deletion EXECUTE hold.

The reported pre/postflight satisfied the reviewed role/owner/RLS prerequisites and exact `preserve` comparison. All 24 client table D/x/t/m checks and every client column REFERENCES check are false afterward. Explicit ACL delta contains only the approved removals from PUBLIC/anon/authenticated, with no other grantee/privilege change. Do not replay this or earlier migrations.

Composer completed the exact single-migration development install and history recording after QA acceptance. This non-SELECT batch does not alter the separate Machines projection rollout hold or justify any new inventory visibility. No remote deployment was performed by the author. Do not blindly regrant unnecessary client privileges as a rollback. No unresolved business-policy choice was invented. Source remains frozen; batch closed and author idle.
