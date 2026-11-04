# Paired Return Capability: Versioned Cutover Candidate Ready

**Current receipt:** web47 accepted as retained46 plus corrected named1 (exit0/be51ea,14filtered), scoped typecheck0/1768b1 and fixture lint0/3ec492. Frozen pure URL7 accepted and retained per QA. No full47 repeat. Complete immutable-version compatibility candidate is in [compatibility/HANDOFF.md](compatibility/HANDOFF.md):13 new SQL +16 new Deno authored, zero executed by author. Composer owns integration; QA serial. New versioned hunks supersede the earlier backend/integration.patch below; do not apply the unversioned hunk. Migration ownership was explicitly approved, no migration applied. No slot held.

2026-09-30. Composer-assigned sparse root only. No active source, public-controls inputs, provider, storage, migration, dependency, native or test process was changed/run. Prior publiccontrols32 + new3 lint acceptance is retained unchanged. No test slot held.

## Exact Contract

- New hosted Checkout success URL: `/pay?cortina_return=1#session=<id>&access=<capability>`. Only the nonsecret marker reaches the application's HTTP request target. The configured full redirect URL is still sent to Stripe as an API parameter; this is not secrecy from Stripe.
- Existing query links remain readable. Web captures an exact, single same-source pair into memory, then replaces the address with a nonsecret marker. Partial, duplicate, mixed-source, control-bearing or oversized references stay support-only; no credential guessing/merging. New fragment stripping also leaves the support marker, not another checkout.
- Capture is the first application import, before SDK/application evaluation. An early HTML no-referrer meta protects resource requests during module loading; layout-time cleanup precedes page status effects for in-app navigation. Failed startup scrubbing throws a fixed nonsecret error before app initialization; failed page cleanup invokes no status/payment call. Late cleanup cannot overwrite a newer credential-bearing return.
- Reuses existing pending state, exact status reader, two-minute observation and late-result fencing. Return URLs never prove paid/started/refunded. No confirm/create replay, new payment write, entitlement or provider retrieval was added.
- Active browser source has no durable Cortina pending store. No capability is added to localStorage, sessionStorage, cookies or history state. A reload after successful scrubbing loses the in-memory capability and stays support-only via the marker. This is intentionally NOT durable browser recovery, nor a replacement for accepted secure app recovery/owner lookup.
- Legacy query links already reached the initial host request before JavaScript. Existing server logs/browser navigation records cannot be erased by this patch. New links avoid that exposure; no promise of retroactive removal is made. Other Auth routes/fragments are untouched.

## Owned Files / Proposed Hunks

- `web/src/cortinaReturn.ts`: focused capture/parser/scrubber and one transient initial-return slot, scoped to the initial router entry and released once the page captures it.
- `web/src/cortinaReturn.test.ts`: 15 new parser/bootstrap/privacy cases.
- `web/src/components/CortinaPayPage.return.test.tsx`: 6 new real-BrowserRouter/StrictMode cases with fake service, including scrub-before-status, old links, support lock, failure and stale result handling.
- `web/integration.patch`: current `CortinaPayPage.tsx` reference parsing/layout guard only, first import in `src/main.tsx`, early meta in `index.html`. No full page/App/logic replacement. The entrypoint/meta hunks require composer integration; component-only integration would not meet the early-scrub contract.
- `backend/supabase/functions/cortina-vend/return_urls.ts` and `return_urls.test.ts`: narrow structured success/cancel builder and 7 new cases. Preserves selector precedence, public base query, hosted-development HTTP and HTTPS. Removes stale capability/selector fields from configured base URLs. Invalid scheme/embedded userinfo yields sanitized503.
- `backend/integration.patch`: imports builder and replaces only existing success/cancel construction. Preserves latest public-controls import, owner lookup, shutdown/caller selection, metadata, provider idempotency key, pricing and settlement.
- `backend/import_map.json` and `tsconfig.return.json`: QA-only maps/config extending the existing active configuration, not app dependencies or deployed files.

Both proposed patches pass read-only `git apply --check --recount` against current active files. Neither was applied. Source tests are authored, not executed; actual completed test count is **0**.

## Superseded Hold: Stripe Idempotency

**Do not activate the backend URL hunk over unresolved older Checkout attempts without a reviewed cutover contract.** Active `handleCard` recreates/replays Checkout with `cortina-checkout-<session-id>` even for an existing `payment_pending` session. Changing success/cancel parameters under that key causes Stripe parameter-mismatch errors. The current catch can then mark that draft failed. Rotating the key is NOT a safe fix; it could create a second payment opportunity.

Browser compatibility capture has integrated first. Composer subsequently approved the explicit persisted-version contract and bounded migration ownership: permanent default1 for existing/old writers, explicit2 only for fresh web-card inserts, immutable thereafter. The complete candidate and paired DB/replay tests are in compatibility/. This replaces the proposed drain-only prerequisite, but remains pending serial QA and approved deployment/provider validation. No historical guessing, automatic failure/repair, provider retrieval or key rotation.

## Official Semantics Checked

- [Stripe Checkout create](https://docs.stripe.com/api/checkout/sessions/create): hosted success and cancellation destinations are configurable URLs; cancellation navigation is not financial proof.
- [Stripe hosted success page](https://docs.stripe.com/payments/checkout/custom-success-page?payment-ui=stripe-hosted): return navigation is not guaranteed; backend webhooks remain necessary. This batch does not adopt URL arrival as fulfillment evidence.
- [Stripe idempotency](https://docs.stripe.com/api/idempotent_requests): parameter mismatch on an existing key is rejected; a pruned key can result in a new request. Keys stay unchanged here.
- [RFC3986 section3.5](https://www.rfc-editor.org/rfc/rfc3986#section-3.5): fragments are client-side URI components separated before dereferencing.

The official Stripe pages inspected do not explicitly guarantee fragment preservation. Use of a standard fragment is an implementation inference, not a claimed provider certification. A bounded hosted sandbox return test on the actual configured URL/domain is still required before activation, with explicit provider-test approval. None was performed. Global distributed rate limiting remains separately open.

## Serial QA Commands

Web prerequisites: composer integrates the web helper, six-case test, fifteen-case helper test and web hunks together into current active website. Keep the existing 26-case `CortinaPayPage.test.tsx` unchanged. From `/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR`, QA runs **47 web cases = 21 new + 26 directly affected existing** once, followed by scoped typecheck:

```sh
NODE_OPTIONS=--max-old-space-size=1024 /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 node_modules/vitest/vitest.mjs run src/cortinaReturn.test.ts src/components/CortinaPayPage.return.test.tsx src/components/CortinaPayPage.test.tsx --maxWorkers=1 --no-file-parallelism
/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 node_modules/typescript/bin/tsc -p /Users/jamaki604/CleanStreamProjects/.campaign-work/payments/return-capability/tsconfig.return.json --noEmit
```

The backend pure URL helper's **7 new cases** can run independently without applying the held backend hunk. From this root's `backend` directory:

```sh
CLEAN_STREAM_WEB_ORIGIN=https://web.synthetic.invalid /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none --no-prompt --config=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.json --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --import-map=import_map.json --allow-env=CLEAN_STREAM_WEB_ORIGIN supabase/functions/cortina-vend/return_urls.test.ts
```

Expected new authored cases: **28**. No browser process, provider call, PGlite instance, accepted financial/recovery/publiccontrols rerun, broad typecheck or build is requested. Runtime/typecheck/lint are not yet evidence. Respect QA's serial queue. No automatic follow-on implementation.
