# Cortina Distributed Capacity Guard: Frozen Source

**Integrated locally; frozen, not deployed.** Accepted: PGlite17 (exit0/58d580); Deno24 with typecheck (retained23 plus corrected named1, exit0/74a4d7); new2 lint (exit0/2ee54b). Backend's bounded source review found no required fixes to migration9d340979/helperc3c985b4/patch4321ad45.

**Real-PG acceptance closed:** corrected burst child plus parent passed2, exit0/a60abe/session49739; prior3 explicitly skipped and retained (real500ms lock timeout, cancellation/disconnect rollback, clock/refill after lock wait). Final PG count4children+parent=5. Eight distinct connections, exact5allowed/3denied passed; no production change or assertion weakening. Corrected runner SHA25688e9f3f9f92db142ecac5e1ddda33d92d15054b90b13eb5cb8a924d82194050c. PostgreSQL17.11 stopped, owned tempfoF2yq removed, all QA processes closed. No remaining local check in this batch.

Three project-wide route buckets are a downstream cost/capacity guard, **not per-client fairness or complete abuse protection**. No author tests, active edits, provider calls or hosted rollout. No author process/slot held. No repeats of accepted scopes or automatic follow-on work.

## Owned Files

- `supabase/migrations/20260930225326_cortina_request_capacity.sql`: exact approved CLI-generated version, integrated unchanged; hash9d340979. No duplicate unversioned SQL or applied hosted migration.
- `supabase/functions/cortina-vend/request_limits.ts`: one small SDK helper reusing current HttpError, public-error response and privileged client; no new key selector/dependency/framework.
- `integration.patch`: seven added lines only in current-active `cortina-vend/logic.ts` (import plus three two-line guards). Read-only `git apply --check --recount` exited0. No full logic replacement.
- `scripts/cortina-request-capacity.test.mjs`: accepted17, relocated hash32895c03; reversing only its migration-relative-path change reproduces the tested01a5a038 hash. Retain evidence, no repeat.
- `scripts/cortina-request-capacity.pg.test.mjs` and `scripts/test-support/cortina-request-capacity.fixture.sql`: four new independent-connection PostgreSQL children plus parent, using active `scripts/test-support/policy-admission-pg.mjs` unchanged. No copied harness or financial schema. Exact migration runs under a synthetic nonsuperuser, non-bypass owner; real consumers SET ROLE service_role.
- `supabase/functions/cortina-vend/request_limits.test.ts`: accepted24, corrected fixture hashaf04cbf3. Existing SDK/fake HTTP and current handler; no live provider.
- `import_map.json`: QA-only references to the existing active shared helper/public controls and integrated logic. Not deployed configuration.

## Backend Contract

Permanent fixed buckets and approved initial **development** thresholds:

| Trusted route identity | Burst | Refill per minute |
| --- | ---: | ---: |
| quote |30|120|
| card, new provider-create attempts only |5|10|
| status, including authenticated owner recovery |120|1200|

`private.cortina_request_capacity` has RLS enabled, no policies, no direct PUBLIC/anon/authenticated/service_role table grants, and exactly three seeded rows constrained by fixed keys and token maxima. No identity, IP, capability, request history or cleanup job. No request-driven INSERT/upsert. Missing rows fail closed rather than being recreated.

`public.consume_cortina_request_capacity(p_bucket text)` is service-role-only, SECURITY DEFINER for the private-table operation, empty search_path and500ms lock_timeout. No client-set quota/time/refill arguments. It locks the selected row, samples DB clock after the wait, clamps refill to burst capacity, and atomically spends one token. Backward time cannot mint tokens. Denied calls do not update/extend the refill timestamp. Function privilege revocation covers PUBLIC, anon, authenticated and service_role before granting only service_role execution. No financial tables/RPCs, request identity assumptions or historical changes.

The helper uses current SDK `.rpc(...).abortSignal(...)` with a2-second deadline. Strict response validation requires boolean allowed plus integer retry0 when allowed or1..6 when denied. Denial returns sanitized429/code capacity_exceeded, Retry-After and exposed header, existing no-store/no-referrer/CORS. Missing schema/row, lock timeout, transport abort/error or malformed response becomes sanitized503/code capacity_unavailable, never fail-open. An unobserved RPC completion can conservatively consume a token; no automatic retry/refund of quota and no change to payment truth.

Quote/status guard follows bounded body parsing and precedes database/Auth work. Status and owner recovery share their own bucket, isolated from quote/card. New-card guard follows frozen-binding/nonpending replay, new-payment shutdown, stored redirect-version validation and canonical caller admission, but precedes the provider try/catch. Refusal retains the pending draft; it cannot write failed or trigger compensation. Existing retries retain the original Stripe idempotency key and may be temporarily throttled; no new key or financial operation is invented.

Funded/nonpending card replay, wallet, confirm, callbacks, standalone reconciliation, refunds and settlement functions are excluded. Allowed status retains its current timeout/settlement behavior; denied status stops before any state read/change. This is not a change to settlement policy or a throttle inserted into shared financial helpers.

## Verification / Rollout

**Exact rollout dependency:** apply `20260930225326_cortina_request_capacity.sql` before deploying the helper plus seven `cortina-vend/logic.ts` lines. The service-only RPC, private RLS table and all three seeded rows must exist first. Missing schema/row fails closed503 for newly gated work; there is no bypass or automatic repair. Hosted rollout/enablement is not authorized by local acceptance.

Accepted evidence is frozen:17PGlite,24Deno/typecheck,5real-PG (four children plus parent),lint2 and Backend source review. No repeats requested. Existing `policy-admission-pg` harness is unchanged and verified shutdown/removal. Minimal fixture hash2a991c7d; no financial schema. Recorded runtimes Node24.19, Deno2.9.6, PostgreSQL17.11; no author probes/runs or --no-check.

An attacker can exhaust shared capacity and delay legitimate callers, including status. Separate status budget prevents quote/card depletion from spending its tokens, not unfairness among status callers. Development thresholds are not production-load guarantees. Ingress, limiter RPCs and preliminary card quote/Auth/draft work remain outside the downstream cap. No IP/header identity is trusted or stored; any future per-origin control requires independently approved hosted gateway/header evidence, not assumptions.
