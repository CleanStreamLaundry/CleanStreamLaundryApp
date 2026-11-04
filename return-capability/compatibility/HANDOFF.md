# Immutable Return Compatibility: Source Ready

**Integrated QA accepted:** SQL13 passed exit0/8fd84b against composer-generated active migration `20260930223000_immutable_checkout_return_version.sql`, byte-equal candidate comparison3a652a. Deno16 passed with typechecking exit0/38940a. No author rerun or remote migration. Source remains frozen; commands below are completed QA scope, not a repeat request.

Composer authorized this additive migration ownership; Kant is aware. All files are confined to this sparse lane. Active app/web unchanged by Dalton. No author runtime, provider, migration application, native process or test slot held.

## Integrate Together

- `checkout_return_version.sql`: complete additive migration candidate. Composer assigns the final migration filename through the normal repository workflow; CLI creation was not run under the source-only restriction. Permanent `smallint NOT NULL DEFAULT 1`, allowed values1/2, v2 only web-card; separate immutable UPDATE trigger, no additional client grants. Existing rows get legacy1 without UPDATE/backfill, timestamp/state/audit changes, history repair or default switch.
- `helper.patch`: append version selection and exact legacy construction to the frozen `../backend/supabase/functions/cortina-vend/return_urls.ts`; do not replace the v2 builder.
- `integration.patch`: tiny current-active `_shared/cortina.ts` and `cortina-vend/logic.ts` hunks. Fresh web-card INSERT explicitly selects2. Duplicate requests return the stored row, not the attempted insert version. Web pending replay requires stored1/2 before the provider compensation catch; unknown/missing version returns409/support_required without failing the draft. App and funded replay stay on their current paths.
- `checkout_return_version.test.mjs`: 13 authored PGlite cases against actual foundation/binding/reconciliation/ownership migrations, one database, closed at teardown.
- `supabase/functions/cortina-vend/return_version.test.ts`: 16 authored Deno cases through the current handler/helper, fake DB and idempotent fake Checkout only. Full create parameters and unchanged idempotency key are asserted for fresh2 retry and preexisting1/2 lost-response replay. Eight legacy edge cases retain original bytes, including truthiness, Unicode/punctuation encoding and unusual base URLs.
- `import_map.json`: QA-only mapping to integrated active source, not deployed configuration.

**Supersedes `../backend/integration.patch`: never apply that earlier unversioned hunk.** Both new patches passed read-only `git apply --check --recount` against their respective current-active/app and frozen-helper roots. Actual new runtime count: **0**; expected13 SQL +16 Deno, not accepted yet. Existing SQL fixture models dependencies, not real independent-connection concurrency or new-payment admission.

## Preserved / Release Boundaries

No price, metadata, Stripe key, settlement, refund, Start, auth, shutdown, owner lookup, public-control or secure recovery change. Version1 is literally the original string construction, not URL-normalized. Existing and old-writer rows remain1 even when a new-writer duplicate attempts2. Version2 uses the already-reviewed fragment builder. No provider replay/retrieval or key rotation was added.

Schema must precede the version-aware server writer. Web legacy+fragment reader was integrated first. Old writers continue default1 safely, but rollback to an old *reader* after v2 rows exist is unsafe for replay: retain version-aware reader or obtain a separately reviewed shutdown/drain rollback. No timestamp inference. This version isolates the URL-format cutover; unchanged configured base URL, request selector and other existing Checkout inputs remain the current replay assumptions. It does not freeze every mutable provider input or extend Stripe idempotency retention.

Approved hosted sandbox verification must still establish actual Stripe fragment preservation for the configured domain. Inspected official Stripe docs support return URLs but do not explicitly promise fragment preservation. No provider test performed. Legacy initial-query host/navigation exposure is not retroactively erased. Global distributed rate limiting remains separately open.

## Serial QA Only

Prerequisite: composer integrates the new helper plus helper.patch and current-active integration.patch. The SQL runner reads the candidate SQL directly and existing accepted active migrations; do not apply a remote migration. Retain previously accepted financial/publiccontrols/recovery tests. Run these sequentially from this directory, one process/PG instance at a time:

```sh
PGLITE_MODULE=/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/node_modules/@electric-sql/pglite/dist/index.js /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 checkout_return_version.test.mjs
CLEAN_STREAM_WEB_ORIGIN=https://web.synthetic.invalid /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none --no-prompt --config=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.json --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --import-map=import_map.json --allow-env=CLEAN_STREAM_WEB_ORIGIN supabase/functions/cortina-vend/return_version.test.ts
```

Deno includes typecheck; tests stub pay URL lookup, no live keys/HTTP permission. Node24.19/Deno2.9.6 are the recorded runtimes, not re-probed. No accepted older suites or web47 repetition requested. QA now accepts web47 (retained46 plus named1 exit0/be51ea), scoped typecheck0/1768b1, fixture lint0/3ec492 and retained pure URL7. These accepted scopes are not part of this new13/16 run.
