# Public-Payment Capacity: Remaining Function Rollout

Source/evidence only, October 1. No tests, installs, service launches, remote queries, deployments or active app/web edits by this lane. Artifacts are under `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/public-payment-capacity-rollout`.

## Actual Status

**Capacity SQL is already installed and recorded; do not replay it.** Active `docs/operations.md:219` and `.campaign-work/payments/rollout-current/HANDOFF.md:3` record four-source assembly `4837e950` installed `f835ca`, postflight `9a505f` confirming service-only capacity RPC and three buckets, and exact four-source history `6626c3`. The fourth source is `20260930225326_cortina_request_capacity.sql`. The Remaining Work statement at operations line374 that neither schema nor function is deployed is stale.

Composer reconfirmed that this schema/history batch is closed; no duplicate cloud verification or schema artifact remains in this lane. The current receipts explicitly say **no new `cortina-vend` writer deployed**. This is the remaining deployment. The seven additions were seven lines in one handler file (import plus two lines in each quote/card/status branch), not seven functions/endpoints. Paired callbacks and Stripe webhook are already deployed; do not redeploy those for capacity.

## Exact Inputs and QA

Active app root: `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp`. Exact current hashes are in `source-hashes.sha256`, relative to that root. Runtime closure is eleven files:

- `supabase/functions/cortina-vend/{index,logic,request_limits,card_admission,pending_lookup,public_controls,return_urls}.ts`
- `supabase/functions/_shared/{cortina,supabase_keys,wallet_funding_admission,new_payment_control}.ts`
- Existing root `deno.json`, `deno.lock` and `supabase/config.toml` are also pinned; no SDK/dependency/config change.

Key full SHA256 values:

| Source | SHA256 |
| --- | --- |
| Already-installed `supabase/migrations/20260930225326_cortina_request_capacity.sql` | `9d340979f40d9633e9beddaef6b86ae3d7029f10b07cf78db436d61580d8e54b` |
| `supabase/functions/cortina-vend/request_limits.ts` | `c3c985b4aeeed8a4452ccf6df35d04e7c6a45d23b4d64b3a2fd6d1aa59502899` |
| Current `supabase/functions/cortina-vend/logic.ts` | `9357f7aa2bf89ab29fefd186caf26cd7beae65c06c37fac3c5ba518035c756fe` |
| `supabase/functions/cortina-vend/index.ts` | `6ec451142e0f5f22818badd4fdcdaba0b419abd9de25f43d4e4702943102fe6c` |

SQL/helper and all remaining runtime closure hashes match the accepted payment rollout manifest. The old logic hash `591d19dc` was superseded only by the accepted post-capacity captured-caller admission correction; current `9357f7aa` and request-limit test `322f9152` match this lane's `deletion-admission-followup/HANDOFF.md` and independent receipt `1140e2`. Do not redeploy the old logic to match an obsolete manifest.

Retained acceptance, no rerun: original SQL17 (`58d580`), Deno24/typecheck (retained23 plus corrected1 `74a4d7`), lint2 (`2ee54b`), real PG5 (retained3 plus corrected burst/parent2 `a60abe`), and Backend source acceptance. The current post-wait handler additionally has capacity27/typecheck in `1140e2` (24 existing +3 new), not 24+27 distinct tests. The combined four-SQL/C-D coexistence child+parent2 is accepted `6c6ee7`. PG harness cleanup/all processes exited are recorded in those receipts. Current SQL/test/fixture hashes match the accepted paths; see `.campaign-work/payments/distributed-controls/HANDOFF.md` and `.campaign-work/payments/rollout-current/HANDOFF.md`.

## Handler Scope and Gate

| Branch in `cortina-vend/logic.ts` | Capacity behavior | Version2 dependency |
| --- | --- | --- |
| `handleQuote`, lines61-65 | Fixed quote bucket after bounded body parse, before quote read | None in branch; shares function bundle |
| `handleCard`, lines105-124 | Fixed card bucket only for payment_pending provider-create path; funded/nonpending replay exits first; captured admission repeated after capacity wait | Current web writer chooses version2 through `_shared/cortina.ts:353-354` |
| `handleStatus`, lines292-298 | Fixed status bucket before capability read or authenticated pending lookup | None in branch; shares function bundle |

Missing/invalid quota result is sanitized503; exhausted bucket is429 + Retry-After. Budgets are quote burst30/refill120/min, card5/10/min, status120/1200/min. Helper uses existing service client and 2s abort; RPC uses a row lock and500ms lock timeout. No per-client fairness claim. Wallet, confirm, callbacks, refunds and reconciliation have no added capacity call. Allowed status retains its existing settlement/timeout behavior, so it is not a read-only smoke endpoint.

**Public-reader gate remains for this exact complete function bundle.** `logic.ts:147` uses the stored return version; fresh web-card sessions explicitly choose2, producing marker plus fragment credentials. All four accepted website prerequisites still match `web-reader-hashes.sha256`, relative to `/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR`: `src/cortinaReturn.ts`, `src/main.tsx`, `src/components/CortinaPayPage.tsx`, `index.html`. Source equality is not public delivery.

Latest Composer-provided Preview `dpl_2n5oi4FrRJdJUJuTwo91WF2TirxW` is READY (`dc32aa`), protected, productionURL null. It does not establish anonymously reachable version2 handling at the configured `CLEAN_STREAM_PAY_URL` (source fallback `https://cleanstreamlaundry.com/pay`). No public publication, environment change, provider test or partial-handler rewrite is authorized here. Quote/status alone do not logically require version2, but they cannot be independently deployed from this single accepted entrypoint without a separately scoped code batch. Do not silently deploy the whole current writer to close just capacity.

## Minimal Completion Order

1. Retain closed schema/history receipts `f835ca / 9a505f / 6626c3`; do not rerun, reverify, reseed or repair this schema. No callback, refund/reconciliation or mail rollout is a new prerequisite for these capacity calls.
2. Establish the already-required public-reader receipt for the actual configured return URL. Current protected Preview alone is insufficient.
3. Only after that gate, Composer deploys exactly **`cortina-vend`** on development `dnuuhupoxjtwqzaqylvb` with the eleven-file current closure, preserving `verify_jwt=false` (`supabase/config.toml:383-385`), named-key/caller bearer contracts and existing environment values. No other endpoint/key/schedule or migration/history write is needed for this deliverable.
4. Composer records the named function's deployment/version/gateway/source receipt under a later explicit execution assignment. No backend/QA runtime is currently assigned. Do not invoke quote/card/status/confirm/wallet or the capacity RPC as a read-only smoke; those can spend quota, mutate state or reach providers. Return/provider proof remains separately scoped, not inferred from deployment.

The initially drafted read-only verification script was withdrawn after Composer reconfirmed the closed four-source receipt; no duplicate schema check is prepared or requested. If the public-reader gate is not satisfied, the precise remaining deliverable is the single function deployment, not an unimplemented limiter or missing SQL. Source/evidence mapping is complete; author idle, no further audit or runtime assigned.
