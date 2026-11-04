# Remaining Cortina/Stripe Rollout

**Current hosted receipts, composer executed:** exact four-SQL assembly4837e950 applied exit0/f835ca; narrowed metadata postflight9a505f accepted. History artifact70cc385a applied exit0/6626c3 with exactly four source hashes matching the manifest; inert history metadata only, no replay/backfill. `nayax-sale-end-sandbox` v26, `nayax-sale-end` v26 and `stripeWebhook` v44 are ACTIVE, all gateway verify_jwt=false, readback689daa. Stripe unsigned empty POST returned400/486b6e, preserving internal signature authentication. Stripe gateway enforcement used the unchanged frozen source with explicit --no-verify-jwt; no speculative config edit. **No new cortina-vend writer deployed.** Published paired web reader must precede that writer. No replay or further checks requested; author0 Node/SQL/runtime/hosted actions, lane idle.

**Current deployment readiness:** composer reports approved C/D18 exactf2788680 applied exit0/bcc2dd, postflight5dc449 containment accepted, and nine paired endpoints ACTIVE/readbackd11da8. All frozen four-SQL/function/web/artifact hashes rechecked unchanged locally. [DEPLOYMENT.md](DEPLOYMENT.md) supplies the exact composer-only first four-SQL command, new narrow metadata-only postflight and completion order: schema -> paired callbacks/webhook; published web reader -> vend writer. Current hosted website is not updated. No author tests/cloud/provider actions; reconciliation queueing excluded. Vercel activation/Google logo are user-owned before go-live, not a development billing blocker.

Frozen 2026-09-30. **Combined rehearsal QA ACCEPT2: exactly new child + parent passed, exit0/6c6ee7, session81104.** Explicit skip5 plus hook return prevented all older cases from running; actual tests2/skipped0. Helper dc0c6f04/assembly4837e950/hook5fab79e9 verified cf0a34. PG17.11 stopped/tempdAIxR9 removed, all processes closed/slot released. No author runtime, active edits, hosted inspection/write, provider call or deployment. Target remains **CleanStream DEVELOPMENT `dnuuhupoxjtwqzaqylvb`**; this separate approval unit is not covered by C/D18 and its nine endpoints. Initial run46460 exit1/fcacd1 retained five prior passes but failed the new child/parent on duplicated fixture hash; only that synthetic hash was corrected, preserving constraints, history and SQL. Dollar-replacement callback retains literal SQL/P0001 rollback assertions. `artifacts.sha256` pins accepted inputs. No repeat requested.

## Evidence And Assembly

Reuse `account-cleanup/activation-current/CD-DEPLOYMENT.md`, its catalog921fdc (`hosted-catalog.json`) and accepted C/D15; paths in `prerequisite-sources.sha256` are relative to that directory. This is recorded hosted evidence, not a fresh deployment receipt. That catalog has Cortina tables/selectors/history, but lacks the four frozen binding columns and `checkout_return_version`; requested binding/ownership functions have null signatures. `Machines.is_out_of_service` is also absent there: C/D's `20260928151021_admin_operations_extensions.sql` supplies it. Capacity was not independently surveyed in that catalog; there is no hosted installation receipt for the new local migration.

**C/D prerequisite now satisfied by composer receipts bcc2dd/5dc449.** C/D supplies `Machines.is_out_of_service`, canonical admission/new-payment control, wallet/claim restrictions and webhook `record_topup_refund_provenance`; installed A/B admission/profile protection is not replayed. The older C/D document's pending wording is superseded by those explicit installation receipts, not inferred from local tests.

`cortina-prerequisites.sql` contains ONLY the following accepted inputs, in one transaction. `migration-sources.sha256` records exact active-app bytes/order. The first source has no outer transaction; only the other three outer `begin;`/`commit;` wrappers were removed. No new migration version, routing assignment, history repair or function implementation was introduced.

1. `20260930154259_freeze_cortina_payment_bindings.sql`: immutable fresh machine/environment/selector snapshot and atomic audited verified-card recording. Historical routing remains NULL.
2. `20260930163919_cortina_callback_provider_ownership.sql`: locked duplicate preflight, scoped unique provider ownership and atomic callback audit/binding. Conflict aborts the entire unit; do not delete/repair history or activate the index around a failed preflight. Unknown-environment evidence remains reserved/manual.
3. `20260930223000_immutable_checkout_return_version.sql`: permanent default1 for existing rows/old writers, explicit2 only on fresh web-card creation; original version1 parameters and Stripe idempotency key remain unchanged on retry. No timestamp inference/version rotation.
4. `20260930225326_cortina_request_capacity.sql`: three private global capacity buckets, service-only RPC. Quote30/card5/status120 burst; refill120/10/1200 per minute. This is downstream cost/capacity protection, not per-client fairness or complete abuse prevention. Missing schema fails closed; **schema must precede the vend function**.

Never replay financial foundations, historical transaction synchronization, dryer/config rewrites or C/D as part of this artifact. Historical unfrozen sessions remain failclosed/support-required; no guessed refund routing. Do not use blanket `db push` to sweep unrelated migrations. Composer must record the exact installation/ledger mechanism under the separate approval; this preparation does not authorize it.

## Named Closures And Order

All paths below are relative to active app `supabase/functions/`; `function-sources.sha256` additionally pins root `deno.json`, root `deno.lock`, and `supabase/config.toml`. Reuse current package resolution (including existing Stripe14/14.25.0 imports, API2023-10-16, Supabase2.97.0), not alternate lane files or dependency updates.

| Named function | Exact transitive local import closure |
| --- | --- |
| `nayax-sale-end` | `nayax-sale-end/index.ts`, `_shared/{cortina_callback,cortina,supabase_keys}.ts` |
| `nayax-sale-end-sandbox` | `nayax-sale-end-sandbox/index.ts`, `_shared/{cortina_callback,cortina,supabase_keys}.ts` |
| `stripeWebhook` | `stripeWebhook/{index,logic}.ts`, `_shared/{cortina,supabase_keys}.ts` |
| `cortina-vend` | `cortina-vend/{index,logic,card_admission,pending_lookup,public_controls,request_limits,return_urls}.ts`, `_shared/{cortina,supabase_keys,wallet_funding_admission,new_payment_control}.ts` |

Deployment sequence, only with separate approval:

1. Require accepted C/D installation/postflight; the four-source combined local rehearsal is now accepted. Under separate hosted approval, install this four-source transaction and verify its new columns, triggers, service-only RPCs/private RLS table. Preserve deletion denial and mail-off containment. Arrange a controlled new-payment pause/window separately; do not disable settlement/refunds. No pause is enacted here.
2. Deploy the explicitly paired `nayax-sale-end-sandbox` and `nayax-sale-end` for the corresponding registered environments before new vends. Ownership SQL requires the new environment-scoped audit keys; this is actual runtime coupling, not merely a shared import. Resolve which registered routes are in use without assuming development means sandbox. Do not change provider registrations/entitlements or equate HwSerial with TerminalId. Old callbacks can fail closed during the mixed-version window; this is not a zero-downtime claim.
3. Deploy `stripeWebhook`: C/D provenance plus frozen card-record RPC must already exist. Raw-body Stripe signature verification, exact intent/checkout/metadata/amount_received/currency/mode, audited paid transition and one-Start CAS remain unchanged. No capacity/admission gate is inserted into settlement.
4. Deploy `cortina-vend` last. Its fresh web writer chooses version2, so the paired accepted web bootstrap/meta/return reader must be published first. `web-prerequisite-sources.sha256` pins the four related current web files; it is not a full website deployment bundle. Genuine guests, captured authenticated caller, secure pending recovery/owner lookup, funded replay, confirm and unknown-outcome protection are preserved. The existing return batch still requires explicitly approved hosted sandbox verification of fragment preservation on the configured return URL; local tests do not certify Stripe/browser behavior. No provider action is authorized here.

All four named functions have local `verify_jwt=false`; preserve their internal signature/token/caller/capability authorization, not a blanket Auth bypass. Check named-key configuration without printing values or rotating keys: `CLEANSTREAM_NAYAX_SANDBOX_SECRET_KEY_NAME`, `CLEANSTREAM_NAYAX_PRODUCTION_SECRET_KEY_NAME`, `CLEANSTREAM_STRIPE_WEBHOOK_SECRET_KEY_NAME`, `CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME`, and caller `CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME`. Explicit-invalid fails closed; absent-only legacy fallback remains. Preserve explicit getUser bearer. Require existing Stripe signing secrets (live/sandbox), callback auth token, environment-specific Start URLs/tokens and configured return/origin values; do not infer credentials or payment-mode entitlement from a project name.

After approved deployment, record each version/gateway/configuration and only separately authorized no-provider rejection checks. Do not smoke create/confirm/Start/refund, call a signed payment event, or replay customer evidence. Missing/ambiguous historical bindings remain support cases. Rollback must not restore unsafe authorization or guess routing; prefer a controlled new-creation hold/forward fix while preserving settlement.

## Independent Reconciliation

Neither `stripeWebhook` nor `cortina-vend` nor the paired callbacks imports `_shared/cortina_reconciliation.ts` or uses reconciliation columns/RPCs. **Exclude `20260930161734_cortina_closed_app_reconciliation.sql` and `cortina-reconcile` from this prerequisite unit.** That separate migration queues historical unresolved rows, so folding it into a no-history assembly is wrong. Its separate closure is `cortina-reconcile/index.ts` plus `_shared/{cortina_reconciliation,cortina,supabase_keys}.ts`, with dedicated auth, disabled-default entrypoint and separately approved scheduling. Existing local reconciliation acceptance is not deployment/activation evidence; closed-app observation remains an independent delivery prerequisite for that feature, not for these import closures.

## Accepted Combined Rehearsal

Retain accepted binding/ownership/history, return SQL13+Deno16, card18, public32/lint3 and capacity PGlite17+Deno24+PG5/lint2 evidence; no older suite repeat. C/D15 deliberately excludes frozen-card recording, and earlier coexistence runs did not combine C/D with return-version/capacity. That missing combined proof is now covered by **one accepted new child plus its runner parent**, exit0/6c6ee7, in the existing C/D fixture.

`cd-rehearsal.patch` is the eight-line hook integrated for QA by composer/QA, not this author. Backend lane remains read-only to this lane. `scripts/cortina-after-cd.mjs` reuses its existing disposable PG harness/fixture with no new cluster framework. Accepted assertions cover exact assembly, late-error rollback, real commit as nonsuperuser owner, unchanged historical financial rows/counter/mail/deletion, NULL historical routing/version1, service-only grants, one idempotent fresh-card audit, version immutability, callback binding and status capacity. No SDK/provider/Start/refund; synthetic callback eligibility is explicitly fixture state. No reconciliation migration is applied.

Executed QA command retained only for provenance. Node24 selected five prior pre-hook children in the original failed run; those passes were retained. The corrected run's explicit skip pattern excluded all five, and the integrated hook returned before later C/D children. One local PG instance, one worker; actual **1 new child + parent = 2 passes**, not a new C/D15 receipt:

```sh
ACTIVATION_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp \
CORTINA_ROLLOUT_REHEARSAL=/Users/jamaki604/CleanStreamProjects/.campaign-work/payments/rollout-current/scripts/cortina-after-cd.mjs \
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin \
/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  --max-old-space-size=1024 --test --test-concurrency=1 \
  --test-name-pattern='^exact C/D install on installed A/B preserves history and final authorization( Cortina four prerequisites preserve installed C/D and record one bound payment)?$' \
  --test-skip-pattern='(18 exact accepted inputs assemble once with only documented wrapper/backfill omission|recorded legacy prerequisites and installed A/B match the bounded rehearsal shape|missing direct counter prerequisite aborts every prior C/D change|late failure after final containment checks rolls back the entire unit|mail enablement or deletion ACL drift cannot commit this artifact)$' \
  /Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/activation-current/scripts/activation-cd.test.mjs
```

**Corrected retry accepted as recorded above; command retained for provenance, not another run.** Required external gates remain explicit hosted approval/schema receipts, named deployment receipts and separately approved fragment/provider-route validation. Nothing here enables reconciliation, cron, voluntary refunds, new charges or machine operations.
