# Machine Column Privacy: QA Accepted, SQL Rollout Held

Root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/machine-column-privacy`.
Six integration files only, integrated by Composer at exact frozen hashes `77c206`. Independent QA accepted 69 cases (PG24 `eb6a45`, pinned Flutter 3.38.10 15 `8ab311`, web30 `3d6a57`); all processes terminal. Author ran no tests, cloud commands, provider calls, builds or installs. SQL is not deployed: actual compatible client release remains the blocker. No deletion enablement or data migration.

QA receipt: PG24 `eb6a45` (23 children + parent), pinned Flutter 3.38.10 15 PASS `8ab311`, Vitest 4.1.11 30 PASS `3d6a57`; all processes exited, PG stopped and its owned temporary directory removed. Six frozen hashes reverified `562c51`. Zero-case setup blockers are not passes: Flutter missing package_graph `a27bb9`, Vite external setup symlink `559e20/cf3f5c`. QA-only metadata/setup corrections preserved assertions and six source bytes. Initial Flutter tool bootstrap reported no dependency changes `0d505d`; QA prevented repetition. No reruns requested.

**OLD CLIENT ROLLOUT BLOCKER: DO NOT INSTALL THIS SQL before actual compatible app/web distribution and usage evidence, or an explicit decision accepting the known old-client impact. Source integration alone is insufficient. Installed/cached wildcard clients can fail, including silent zero app counts. No SQL install this turn.**

## Contract and Evidence

Composer's fresh hosted metadata `0443df EXIT0` confirms exactly 13 Machines columns, table-wide SELECT and both private columns readable by anon/authenticated, no parent roles, RLS enabled/postgres owner, column ACLs null, existing PUBLIC SELECT and restrictive BlockUpdates policies, service_role access and deletion hold. This is the current prerequisite evidence; do not repeat the query without a concrete drift concern. `preflight.sql` SHA256: `1e88cb68de386b2bbeba29df04dc4338483f1a30572bce84f9caa53b8f36087a`.

Public eleven: `id, Name, Price, Runtime, Status, Location_ID, Machine_type, Weight_kg, washer_size_rate_id, is_out_of_service, service_updated_at`. Private two: `service_reason, service_updated_by`.

- Migration changes SELECT only: remove table/column SELECT from PUBLIC, anon and authenticated, then grant the public eleven to anon/authenticated. Effective-grant assertions and unexpected role inheritance/authority fail atomically. No policies, functions, rows, other grants, service grants or staff contracts change. Existing `rDxtm` privileges beyond SELECT are deliberately out of scope and preserved.
- App: replace three count-only `select('*')` requests with `select('id')`; existing count filters/error fallback and Name/Price lookup stay unchanged. Nearest tests add projection checks without removing existing assertions.
- Web: replace Machines `*` with the existing nine DTO fields, retaining `cortina_machine_config(*)` and its original normalization. Add one projection/nested-config test; all 29 original cases and expectations remain unchanged.
- Staff notes/actor remain available through the existing canonical `admin_portal_request('machines',...)` definer path; availability writes and durable auditing remain unchanged. No direct client read expansion or new API. Existing service-role Edge projections are unchanged.
- Reuse the existing disposable PostgreSQL helper and actual canonical staff/admission SQL prerequisites. No new authorization framework, table, field, RPC, package or cache copy.

## Exact Owned Files and SHA256

Paths below are relative to the root above. `NEW` means no installed/original source was edited.

| File | Baseline SHA256 | Frozen SHA256 |
| --- | --- | --- |
| `supabase/migrations/20261001095826_machine_public_read_columns.sql` | NEW, CLI-generated with installed Supabase 2.84.2 | `338a1aa3b3f8b2841c0fcfdd52cd81316870bc275c9d2a66aa2ef472917d82e8` |
| `scripts/machine-public-read-columns.test.mjs` | NEW | `e0e225a1cee0fb8bc72d2f972e292f825f1c145d8948b01ee73523dbc5d503aa` |
| `lib/services/supabase/supabase_machine_service.dart` | `ad2ccf166ac8a1caa604d0dab9641694773ac901c67cfa3b3f038fb263ed3e45` | `b4d1148b02592667d00ebe5fe11910f2791ab1c9371d800c16a7a8a199703a8f` |
| `test/services/supabase/machine/machine_service_test.dart` | `c06a8a64d73c1e6e22c3782212a3df78353f4bf6635a2eb1e777e26eee312562` | `3e40d309eadea20ee20e240524b30e8e1bfab1cb330e67ee99365c43404d2d85` |
| `src/supabase/repositories/LocationRepository.ts` | `31bfd11f39dc32e6de007207d49f2e41a8114fb67acd0e041582945d8eab42a1` | `8a0b9c69fe647337fc7f1122961e7de30533c44f9ef748f6d5ac083b3416e531` |
| `src/supabase/repositories/LocationRepositoryTests.test.ts` | `791f0341404fd85ae985495956449736872020b84ee513e942df743b4e81503c` | `0184864f2800342c1ed927705d41eb115a2e41eb6d72dfdf34489d8e7a94595b` |

App originals are in `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp`; web originals are in `/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR`. Active sources were read only. `baseline.sha256` preserves the original four hashes. Supporting handoff/preflight and QA-only references are not integration files.

## Sequential Focused QA Commands

Recorded sequential QA commands; acceptance is above. No author runtime requested or held, and no rerun requested. Completed counts: PostgreSQL 23 children + parent = 24, Flutter 15, Vitest 30; total 69 including PG parent. Future reruns require a specific QA grant.

Working directory for all three commands:

```sh
cd /Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/machine-column-privacy
```

1. PostgreSQL, existing private-socket relocation/teardown helper, heap 1024:

```sh
MACHINE_COLUMNS_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/machine-public-read-columns.test.mjs
```

Cases cover baseline exposure; table/column/SET-only inherited authority and bypass/schema failure rollback; PUBLIC and explicit column grants; both clients' public projection/count/price and private note/actor/wildcard/whole-row/filter denial; pending-account public browsing; actual canonical Owner/Admin staff reads/availability writes and service writes; unchanged rows, functions, policies, non-SELECT privileges, service privileges and deletion hold. Require helper diagnostics confirming server stopped and temporary directory removed before proceeding.

2. Pinned workspace Flutter 3.38.10, existing packages only, no pub/assets/native build, one test worker (not Homebrew Flutter 3.47):

```sh
/Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10/bin/flutter --packages=/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/machine-column-privacy/.dart_tool/package_config.json test --no-pub --no-test-assets --concurrency=1 test/services/supabase/machine/machine_service_test.dart
```

3. Web, existing installed dependencies and actual repository config, heap 768/one worker/no result cache:

```sh
NODE_OPTIONS=--max-old-space-size=768 /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/node_modules/vitest/vitest.mjs run --config qa.vite.config.mjs --configLoader native --root . --maxWorkers=1 --no-file-parallelism --no-cache src/supabase/repositories/LocationRepositoryTests.test.ts
```

QA-only setup uses links to existing app logic/test mocks/pubspec/analysis configuration and web interfaces/DI/node_modules/package metadata. Do not write through those links. `.dart_tool/package_config.json` resolves existing dependencies and maps the app package to this lane, with pinned workspace Flutter 3.38.10 SDK references rather than Homebrew. QA added the read-only active package_graph reference and local `qa.setup.mjs` containing the actual jest-dom setup import; `qa.vite.config.mjs` retains the active config/test settings except this setup reference and local cache. Native config loading avoids bundling into active node_modules. No dependency copying; the initial tool bootstrap caveat is recorded above. QA used Flutter 3.38.10 and Vitest 4.1.11; installed Vite is 8.3.1. Deno is not used.

## Rollout and Rollback Boundary

First integrate and deliver the app/web explicit projections; only then consider the separately approved SQL install against the verified development project. Old wildcard clients fail 42501 after the grant change: app count methods retain their existing zero-on-error fallback and old web getMachines throws. This is an explicit client-version rollout dependency, not seamless old-client compatibility. Do not deploy SQL while supported wildcard clients still require these paths.

The public eleven remain readable for signed-out, signed-in and pending-deletion browsing; no Home/MFA gate is added to public inventory. RLS and internal service/definer staff access remain as before. No Machines/Locations rows, attachments, financial history, retention settings or deletion ACLs change. Do not restore table SELECT merely to roll back a client failure: that reopens the private fields. Prefer retaining/fixing the explicit projections; any privilege rollback needs a separately reviewed privacy decision.

Existing `TRUNCATE/REFERENCES/TRIGGER/MAINTAIN` grants are a separate remaining privilege-hardening follow-up, not neutralized by the inspected Machines guards. Active `supabase/migrations/20260928135006_admin_portal_operations.sql:62` and `20260930142406_admin_canonical_authorization.sql:154` revoke only INSERT/UPDATE/DELETE (plus INSERT/UPDATE columns); `20260928151021_admin_operations_extensions.sql:135` installs a row audit trigger for INSERT/UPDATE/DELETE, not a statement TRUNCATE guard. The BlockUpdates RLS policy does not cover these other privileges. This source finding does not assert a currently exposed HTTP execution route for them. No grant expansion, revocation or extra test scope for those privileges is included here.

Independent membership batch is closed and must not be replayed: 17 PASS `ba5f8f`, integrated `6c1006`, installed `ee05b4`, postflight `d4865d`, exact history `c1c500` and anonymous denial `10f00e`. Storage activation/receipts are Composer-owned and outside this six-file batch.
