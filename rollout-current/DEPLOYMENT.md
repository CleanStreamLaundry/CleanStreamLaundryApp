# Composer Deployment Steps

Source-only readiness refresh. Composer reports C/D18 exact `f2788680` applied exit0/bcc2dd, metadata5dc449 accepted containment; nine paired functions ACTIVE/version readbackd11da8. These supersede the earlier pending C/D documentation. No C/D rerun. User approved deployments; only composer performs cloud mutations, and only on DEVELOPMENT `dnuuhupoxjtwqzaqylvb`. This lane performed hashes/local CLI-help reads only, no runtime tests or remote actions.

## Verified Inputs

All frozen manifests matched current source: four migrations; 16 function files plus root Deno config/lock and Supabase config; three assembly/rehearsal artifacts; four paired web-reader files. Assembly SHA256 remains `4837e95074c0de61ef9a97f13131b3b247f093ea05d3d7e7815783e1a8cb6990`. Combined QA new child+parent2 exit0/6c6ee7 remains accepted, no repeat. Exact closure/order and retained receipts are in HANDOFF.md. This local match is not evidence that the website has been published.

## First Four-SQL Command

Local `supabase/.temp/project-ref` in the active app was read as `dnuuhupoxjtwqzaqylvb`; CLI `db query --help` confirms `--linked`, `--file`, `--workdir`. Composer must retain that target binding at execution. Do not use another linked checkout, `db push`, migration-history replay or the independently historical-queuing reconciliation migration.

```sh
/opt/homebrew/bin/supabase db query --linked \
  --workdir /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp \
  --file /Users/jamaki604/CleanStreamProjects/.campaign-work/payments/rollout-current/cortina-prerequisites.sql \
  --output json
```

This executes exactly one accepted transaction: binding154259 -> ownership163919 -> immutable-return223000 -> capacity225326. It does not replay C/D or create a migration-history receipt automatically. Record exact file hash/result through the composer's existing installation process; do not add guessed ledger entries. Duplicate ownership preflight or any other error aborts the unit: stop, retain evidence, no repair/backfill or repeated partial install. Existing historical routing stays NULL/manual; no implicit cleanup, payment replay, Start or refund.

After successful commit, composer may execute the new metadata-only postflight:

```sh
/opt/homebrew/bin/supabase db query --linked \
  --workdir /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp \
  --file /Users/jamaki604/CleanStreamProjects/.campaign-work/payments/rollout-current/postflight-cortina.sql \
  --output json
```

Postflight SHA256 `0e3e2da9928b1dc7cba1413b2354b9daedb8e5d13c2329d49a83f613e7fed4b8` is source-reviewed, not executed by this lane. It returns no customer/payment/session/event rows, secrets or function bodies and invokes no financial/capacity RPC. It reads only catalog metadata and the three quota names/mail containment configuration. Expected:

- Five session columns: three nullable text routing fields, nullable boolean `stripe_livemode`, smallint `checkout_return_version` NOT NULL DEFAULT1. No routing defaults or historical value inference.
- Both service RPCs exist: `record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)` invoker, and `consume_cortina_request_capacity(text)` definer; owner postgres, empty search_path, API EXECUTE only service_role. Capacity also has lock_timeout500ms.
- Three new trigger functions exist with invoker/empty search_path; binding BEFORE INSERT OR UPDATE, immutable return BEFORE UPDATE, callback ownership AFTER INSERT, all enabled O. Existing `cortina_transaction_history` remains enabled O; no trigger removal/history resync. Callback function grants service-only; return guard denies all three API roles. Binding trigger function's service EXECUTE may reflect existing default privileges and is not a new callable RPC requirement.
- Provider index unique/valid/ready, on `(nayax_environment,nayax_transaction_id)` with both non-NULL predicate; no missing-index workaround. Return CHECK validated, only1/2 and version2 only web/card.
- Session/event RLS retained; new private capacity table exists, RLS true, direct SELECT/INSERT/UPDATE/DELETE false for anon/authenticated/service_role. Exactly bucket names `[card,quote,status]`; no token consumption smoke.
- Deletion EXECUTE false for all three API roles; restore only authenticated. Mail exactly one row, all_disabled=true, rollout_set=false, refund_recipient_set=false. Broader C/D containment already accepted in5dc449; do not run its entire postflight again for this batch.

## Separate Completion Order

### Exact History Metadata

After composer confirms the exact four-SQL commit AND accepts its metadata postflight, record only those four sources with `record-cortina-history.sql` (SHA256 `70cc385abd1a01983d3b33dc3c5f5b0b34a0368e9515b59980c1c80d6a235618`). It follows the established C/D history generator pattern; reproducible generator `scripts/build-cortina-history.mjs` pins assembly4837e950, manifest91dcfe3f and every source SHA. Source assembly/checksums only were performed here; Node generator, SQL and runtime tests were NOT executed. No new migration or installed-schema change is contained in the executable history wrapper.

One transaction takes a history-table SHARE ROW EXCLUSIVE lock with 5s lock/30s statement bounds, validates text version/name and text[] statements plus unique version index, rejects every existing target version, checks each stored source SHA256 and requires exactly four inserts. No upsert/delete/overwrite. Whole original reviewed sources, including their outer wrappers, are stored as ONE inert statements array element each; there is no EXECUTE of their SQL. No C/D, historical routing, reconciliation queue, customer data, provider or gate mutation. Post-COMMIT readback returns only these four versions/names/cardinalities/digests.

Composer-only command, after the installation/postflight prerequisite:

```sh
/opt/homebrew/bin/supabase db query --linked \
  --workdir /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp \
  --file /Users/jamaki604/CleanStreamProjects/.campaign-work/payments/rollout-current/record-cortina-history.sql \
  --output json
```

Expected exact versions: `20260930154259`, `20260930163919`, `20260930223000`, `20260930225326`; each stored_source_files=1 and source_sha256 equals migration-sources.sha256. Target-history emptiness has not been assumed or queried by this lane. Collision/error aborts all inserts. If command outcome is uncertain, composer uses ONLY the final metadata SELECT from the artifact before any retry; never replay schema or delete/overwrite history to force completion. Existing accepted source/rehearsal artifacts are unchanged.

### Named Function And Website Completion

1. Commit four SQL and accept narrowed metadata above. New schema before current vend writer is mandatory; missing quota/schema fails closed.
2. Deploy paired `nayax-sale-end-sandbox`, `nayax-sale-end`, then `stripeWebhook` with the exact frozen local closures. Their completion does not depend on publishing the new web reader; preserve funded settlement. Do not blanket deploy shared-import consumers or `cortina-reconcile`.
3. Publish the accepted development website reader/bootstrap/meta before the fresh version2 `cortina-vend` writer. Current hosted website has not been updated per composer; this step remains open. Local four-file web manifest identifies the required reader inputs, not a full deployment bundle. User will handle Vercel activation and Google logo before go-live; development website work is not blocked on billing. No hosting-account action is assigned to this lane.
4. After the deployed reader receipt, deploy `cortina-vend` and record function version/gateway/source match. Default1 legacy returns retain exact original Stripe parameters; fresh writer explicitly chooses2. Do not rotate keys or mutate versions to overcome retries. Separately approved sandbox verification must establish actual fragment preservation before claiming the return path end-to-end proven; this document authorizes no financial-provider action.

All four functions must remain enabled with gateway `verify_jwt=false`, matching the pinned local config. Read back these named versions/settings after deployment. External webhook/callback authentication is internal; the vend route must continue genuine-guest/capability flows and verified captured-user admission. No blanket verification toggle, live financial smoke or signed event replay.

## Callback And Secret Settings

- `nayax-sale-end` dispatches production; `nayax-sale-end-sandbox` dispatches sandbox. Existing handler dispatches POST suffixes `sale`, `void`, `saleendnotification`. Confirm registered environment-to-route settings without modifying subscriptions/entitlements or sending a device request. Each endpoint uses its frozen session environment, not current config or project-name inference.
- Required callback secret `NAYAX_CALLBACK_AUTH_TOKEN`; accepted header is `x-nayax-auth`, or Bearer authorization when that header is absent. Missing/wrong auth returns a Nayax Declined envelope (do not require HTTP401 as the success criterion). Environment/transaction/amount/currency/provider evidence must still match; SaleEnd can omit device data and HwSerial is not TerminalId.
- Preserve production/sandbox `NAYAX_*_START_URL` and `NAYAX_*_SECRET_TOKEN`; checking configured names/presence is not permission to call them. Preserve `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_SANDBOX_WEBHOOK_SECRET`, raw-body Stripe signatures and expected live/test ownership. No value logging or account/mode changes.
- Optional trusted secret selectors: `CLEANSTREAM_NAYAX_PRODUCTION_SECRET_KEY_NAME`, `CLEANSTREAM_NAYAX_SANDBOX_SECRET_KEY_NAME`, `CLEANSTREAM_STRIPE_WEBHOOK_SECRET_KEY_NAME`, `CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME`; caller `CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME`. Explicit invalid fails closed, absence only retains legacy. Preserve explicit user bearer and named-secret apikey-only use.
- Preserve configured `CLEAN_STREAM_PAY_URL` and `CLEAN_STREAM_WEB_ORIGIN` with the intended development website. Provider callback path suffixes remain the existing registered contract, not a new guessed Nayax API. No changes to timeout compensation, payment amounts, one-Start behavior or automatic refund policy.

Remaining completion evidence: four-SQL commit/postflight, four named function deployment/readbacks, published paired web-reader receipt before vend writer, separately approved return/provider-contract validation. Reconciliation scheduling/historical queueing remains excluded, as do any provider Start/refund and production actions. No tests or new preflight requested.
