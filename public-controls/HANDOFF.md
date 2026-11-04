# Cortina Public Controls: Active32 Accepted, Lint-Only Follow-Up Ready

QA receipt: active32 (18 helper + 14 request) and typecheck PASS, exit0/chunk57b834, session48050 closed. Scoped lint found the intentional ASCII-control regex and two async-without-await mocks, plus unchanged baseline logic warnings. This lane now has only a documented regex lint exemption and Promise.resolve mock corrections; assertions are unchanged. Composer integration of these two-file lint-only deltas is pending. No author runtime rerun.

2026-09-30. Composer-assigned lane-only candidate. Active app/website and prior accepted recovery/financial files were not edited. No test, native, provider, database, deployment or dependency-install process was started. No test slot is held.

## Implemented Boundary

The actual requested gap is `CleanStreamLaundryApp/APP_FIX_PRIORITIES.md:90-92`: public quote/card/status abuse controls and capability exposure. Current `cortina-vend/logic.ts` used unbounded `req.json()` and accepted arbitrary-size session credentials; its entrypoint logged raw exceptions and reflected server error messages.

- Body admission is now bounded to 8,192 actual bytes and one five-second receive deadline, including absent/false Content-Length, chunked input, aborts and stalled cancellation. Invalid JSON/object errors retain their existing HTTP/code contract. Oversize is 413; deadline is 408. No content-type tightening.
- Status/confirm validate a session UUID and bound the opaque capability to 128 characters with no ASCII controls before hashing/querying. Current UUID and historical 32-character/opaque tokens remain usable. No secret trimming, case folding, JWT decoding or client-asserted identity.
- Success/error responses are `no-store`; API responses also carry `Referrer-Policy: no-referrer`. Raw entrypoint exception logging is replaced by a fixed message plus HTTP status. Server diagnostics are sanitized without changing 500/503 status or existing error codes. Known client errors, including unconfirmed-payment 409, survive.
- Owner lookup still dispatches before capability/status timeout handling, with the original captured bearer and exact owner/machine/request/hash checks. Shared financial helpers, creation shutdown/caller-key logic, all prices/dryer choices, provider calls, settlement, refunds and secure pending recovery are unchanged. No retry/re-Start/refund policy is added.

## Exact Files

Within this root:

- `supabase/functions/cortina-vend/public_controls.ts`: one narrow helper, reusing existing `HttpError` and `errorResponse`.
- `supabase/functions/cortina-vend/public_controls.test.ts`: 18 new helper cases.
- `supabase/functions/cortina-vend/public_controls.request.test.ts`: 14 new adapter/request cases, including route matrix, owner recovery and no financial side effects.
- `integration.patch`: tiny current-source hunks only; `logic.ts` +3/-26, `index.ts` +5/-4. Removes old unbounded parser and duplicate credential extraction. No full logic copy.
- `import_map.json`: read-only mapping to active shared code/entrypoints for QA; not a deployed application file.

Composer integration prerequisite: add the new helper at its corresponding active path and apply/review the patch against current source. Tests can remain in this lane, using the mapping below. Do not run request tests against unpatched active source and call that candidate verification.

Read-only `git apply --check --recount integration.patch` against the active app exited 0. Initial check found formatted index imports; the patch was corrected against those actual bytes. No patch was applied. Baselines:

```
93990e64895c8fddd5ef7233a3d9a19c64059da57097c17316f458ba8569a6cf  logic.ts
7f9bb9b7acbc588c26e4540600c107ce5c8af3cd2ab52bf18f4e8810b8075103  index.ts
```

## QA Command

Expected **32 new tests: 18 helper + 14 request**. Actual completed count **0**; typecheck/runtime remain unrun. No accepted financial/recovery suite rerun requested. After composer integration, from this `public-controls` root, QA alone runs:

```sh
CLEAN_STREAM_WEB_ORIGIN=https://web.synthetic.invalid CORTINA_VEND_TIMEOUT_SECONDS=45 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none --no-prompt --config=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.json --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --import-map=import_map.json --allow-env=CLEAN_STREAM_WEB_ORIGIN,CORTINA_VEND_TIMEOUT_SECONDS supabase/functions/cortina-vend/public_controls.test.ts supabase/functions/cortina-vend/public_controls.request.test.ts
```

Deno 2.9.6 is the already-verified surviving runtime; not re-queried. Tests use synthetic requests/fakes and no network permission, provider calls, database or native processes. The request module uses active entrypoints so later composer edits are not silently replaced by old lane copies. Check the integrated helper matches the frozen candidate before runtime.

## Remaining Requested Gates (Not Claimed Closed)

- **Request-frequency limiting:** a byte/deadline bound is not a distributed rate limit. Targeted shared-helper/migration inspection found no reusable public limiter. Complete cross-isolate enforcement requires a composer/backend-approved atomic shared limiter or trusted ingress rate policy, with an explicit trusted client-address/key contract for guest traffic and configured quotas. A local Map or client-supplied forwarded-IP header would not close this boundary. No counter table/framework or pretend limiter was added.
- **Browser URL capability removal:** current Checkout success URL still contains `session`/`access`. The API response's no-referrer header does not protect the browser return document or remove that URL. This needs a paired website return-handler/backend URL change under composer ownership; changing only the backend would strand existing return/recovery behavior. Existing secure app storage is unaffected.
- **Provider callback/network enforcement:** current accepted callback auth remains frozen; actual ingress credentials/network restrictions and hosted activation are external release gates, not proven by local tests.

This is a complete bounded-request/capability-input and entrypoint-disclosure guard candidate, not acceptance of the entire public-payment security checklist. No automatic follow-on scope.
