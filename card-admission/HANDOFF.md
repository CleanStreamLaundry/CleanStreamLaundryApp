# New Card Caller Admission: Source Ready

**Integrated QA accepted:** corrected18 all passed with typechecking, exit0/aecb58; tested lane fixture matches active, comparison4b0319. Fake Auth/HTTP with current active handler, no no-check/provider calls. All QA processes closed and slot released. The earlier runtime0/typecheck failure below is resolved; commands are retained evidence, not a repeat request.

Separate follow-on after the immutable return batch was completed/frozen. Composer assigned this narrow admission gap; Kant received the exact contract. No active edits, author runtime, test process, remote/provider operation, dependency or migration. No test slot held.

Kant independently read the exact helper/integration patch and reported no additional source-contract blocker. Runtime remains pending: current fixtures fake Auth and HTTP; they do not constitute real-SDK transport evidence. Any required real-SDK case belongs to composer's serial QA scope, not an implied pass here.

Integrated QA receipt: card18 completed zero runtime cases; typecheck stopped with six TS2339 errors (exit1/038bfb). The pre-admission `assert.deepEqual(f.calls, [])` narrowed the mutable list to never[]. Lane correction changes that single assertion to `assert.equal(f.calls.length, 0, ...)`, retaining the exact zero-call requirement and every transport assertion, without casts or no-check. Composer integration and queued18/typecheck remain pending; no author check.

## Candidate

- `supabase/functions/cortina-vend/card_admission.ts`: resolve the original caller and reuse the accepted shared `captureFundingAdmission` RPC implementation, unchanged. No JWT-role decoding, alternate RPC, new financial architecture or shared-helper edit.
- `integration.patch`: current-active `cortina-vend/logic.ts` only. Capture Authorization before body await; replace only handleCard's optional-user lookup; admission immediately before the provider try/catch, after funded replay/shutdown/return-version validation. Apply alongside/after the frozen return-version patch, never copy full logic.ts. Read-only `git apply --check --recount` current active exited0.
- `supabase/functions/cortina-vend/card_admission.test.ts`: 18 new authored cases (12 helper,6 request-handler); exact original-bearer transport, trusted component selector, guest compatibility, invalid/Auth/transient/admission failures, caller mutation during body read, pending preservation, funded replay and shutdown. Fake Auth/HTTP/Stripe only; no actual payment or Start.
- `import_map.json`: QA-only references to current active shared dependencies and integrated handler.

## Exact Boundary

Guest means no Authorization header, or a Bearer token exactly equal to the configured current VEND caller-public key. Named selection remains trusted `CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME`; absent alone permits legacy SUPABASE_ANON_KEY. Invalid explicit selector returns sanitized503 before SDK/HTTP. An arbitrary publishable-looking token is no longer a guest bypass; it must verify via getUser or fail401. Malformed explicit Authorization401, returned retryable/429/5xx Auth errors or thrown transport503. No decoded role or request-body user is trusted.

Verified getUser identity is bound into both the session user and the admission closure. Shared admission uses the original bearer, selected public apikey, exact verified subject and canonical eligible/home result. Its existing8s abort, redirect refusal, error sanitization and read-only RPC are reused. The FUNDING selector argument is mapped to the fixed VEND selector, not a new environment setting or an accidental other-component key.

Only NEW provider creation is admission-gated. Existing non-payment_pending replay returns before admission and does not charge/Start/refund. Quote, wallet, status, recovery, confirm, settlement and callbacks are unchanged. A valid but restricted caller may insert an unfunded pending draft before admission denies; this preserves existing duplicate/funded replay ordering and is explicitly not a DB-level draft-creation gate. No failed status or automatic compensation is written by admission refusal. Canonical admission is a point-in-time server check, not a claim of atomic exclusion with a later account restriction/Stripe operation.

Guest checkout remains intentionally public; global distributed rate limiting is still separately open. This does not claim whole public-payment abuse closure.

## Serial QA

Prerequisites: composer review and integration of helper plus tiny hunk in current active app. Frozen return compatibility13/16 remains a separate preceding queue scope. Do not rerun accepted recovery/publiccontrols/financial suites. Source count18, actual completed0; runtime/typecheck/lint not claimed.

From `/Users/jamaki604/CleanStreamProjects/.campaign-work/payments/card-admission`:

```sh
CLEAN_STREAM_WEB_ORIGIN=https://web.synthetic.invalid /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none --no-prompt --config=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.json --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --import-map=import_map.json --allow-env=CLEAN_STREAM_WEB_ORIGIN supabase/functions/cortina-vend/card_admission.test.ts
```

Uses recorded Deno2.9.6, typechecking enabled, env lookups replaced with synthetic fixture after module import, no network permission. No native/browser/PG process required. Await QA result, not another author run.
