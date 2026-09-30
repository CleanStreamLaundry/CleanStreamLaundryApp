# Newsletter Backend Contract

LOCAL ONLY, DISABLED, NOT DEPLOYED. Integrated into the app source on September 30; independent QA and client integration remain open. Original worker baseline: `66b1d8267a24f208b7bd9b21fc605b4598ed6086`.

## Delivered / Preserved

- New CLI-generated `20260930125527_newsletter_consent_mail_outbox.sql`: private consent history, settings, address suppression, three-purpose outbox, webhook receipt deduplication; RLS and explicit function/table grant boundaries.
- New Edge handlers: `newsletter`, `mail-delivery`, `mail-webhook`; `_shared/mail.ts` and its tests. No packages, lockfile, app manifests, router, DI, client, existing migration, refund, or financial callback edits.
- Reuses canonical `private.current_account_access()`, existing lifecycle suppression, Auth verification, and Resend's HTTP API. Composer integration uses the existing disposable PostgreSQL harness instead of adding a second copy; no production behavior changes from that test-only consolidation.
- No existing-user enrollment/backfill. Explicit verified-user request only; terms/signup metadata cannot grant consent. Confirmation expires 24 hours after request, is single-use, and is stored only as SHA-256. Source, purpose, exact consent text/version and server timestamps persist per request. One request/minute and three/rolling 24 hours per user OR email; fresh request invalidates previous pending consent.
- Account welcome has a permanent unique event key per Auth user, only for accounts created at/after an explicitly configured rollout and verified while capture is enabled, including social insert. Newsletter welcome is a separate event after confirmation. Login, verification replay, email changes and restoration cannot duplicate account welcome.
- Email change invalidates consent permanently, even when changed back. Deletion atomically suppresses queued mail and marketing; restore never clears it. This release deliberately rejects post-deletion re-opt-in pending separate resubscription approval.

## Frontend Contract

Types: `NewsletterRequest` and `NewsletterStatus` in `supabase/functions/_shared/mail.ts`.
POST `/functions/v1/newsletter`, JSON:

| Body | Authentication / response |
| --- | --- |
| `{ "action": "status" }` | Exact user bearer; `NewsletterStatus` |
| `{ "action": "request", "opt_in": true, "version": "newsletter-v1", "source": "signup" }` | Exact user bearer; status becomes `pending`; `source` also accepts `settings` |
| `{ "action": "withdraw" }` | Exact user bearer; idempotent caller-bound withdrawal; status |
| `{ "action": "confirm", "token": "<64 lowercase hex>" }` | No login; `{ "state": "subscribed" }` |
| `{ "action": "unsubscribe", "token": "<64 lowercase hex>" }` | No login; idempotent `{ "state": "unsubscribed" }`, including unknown well-formed tokens |

Status keys: `subject_id`, `state`, nullable UTC `requested_at`/`confirmed_at`/`unsubscribed_at`, current `consent_version`/`consent_text`, database `enabled`.
States: `not_subscribed | pending | expired | subscribed | unsubscribed | suppressed`.
Authenticated RPC equivalents: `newsletter_status()`, `newsletter_request(p_opt_in,p_version,p_source)`, `newsletter_withdraw()`; never pass a subject/email/date. Edge forwards the original user bearer through the public API key, not a service impersonation.
Keep the optional checkbox unchecked and separate from terms. Render the current status text/version. Call request only after explicit intent and verified admission; false is a no-op, not withdrawal. Do not persist intent in editable Auth metadata or auto-replay it after login/restore/account switching. Anonymous newsletter signup is intentionally unsupported.
Errors: 400 invalid consent/token, 401 session, 403 restriction/suppression, 429 request limit, 503 disabled/unknown outcome. After an uncertain request/withdraw response read status; do not retry signup, terms, deletion or other business operations. A 200 request means consent work is stored, not that email was delivered.
Human email links target the approved frontend page with `#action=confirm|unsubscribe&token=...`. Composer must implement that no-login page, remove the fragment from browser history after capturing it, and POST the token only after explicit confirmation/withdrawal. Never auto-confirm on page load. Backend GET links only 303-redirect to that approved page; no HTML is served by Edge because default Supabase domains rewrite it. One-click unsubscribe POST remains directly on the backend. Redact one-click capability query URLs from gateway/access logs before launch.

## Delivery / Recovery

- `mail-delivery` POST takes a dedicated worker bearer and processes one job; no scheduler is installed. Durable event keys outlive Resend's 24-hour idempotency window. Rendering is fingerprinted; changed retry payloads fail closed.
- Explicit 429 rejection alone gets bounded independent backoff (maximum five attempts, under 23 hours). Other definite 4xx failures are terminal. Network errors, 5xx, 409, malformed success, and post-dispatch worker loss are `uncertain`, never blindly replayed. Pre-dispatch expired leases alone are reclaimable.
- Signed raw-body Resend events reconcile by provider ID or the `outbox_id` tag. Svix HMAC verification includes a five-minute timestamp tolerance and receipt deduplication. Bounce/complaint/suppressed events suppress transactional AND marketing mail in this new outbox; reordered sent/delivered events never remove suppression. Unmatched events return 503 for provider retry.
- Inspect private outbox `state`, `attempts`, `last_error`, `first_attempt_at`, and `provider_id` as an approved DB operator. Recover uncertain outcomes using provider delivery evidence and signed webhook replay. If evidence is unavailable, retain quarantine; do not reset to `ready`, change event keys, or retry a business action. No provider polling/sends were performed here.
- Exactly-once refers to durable welcome event creation/deduplication, not a mathematically guaranteed delivery across PostgreSQL and HTTP. Suppression wins before the final dispatch authorization transaction; a request already authorized/in flight cannot be recalled. Never hold a business transaction open over HTTP.
- Existing refund mail is deliberately unchanged and is NOT migrated into this outbox. Its historical delivery/suppression gaps remain a separate launch review. No deletion/restore/purge email promises or lifecycle-notice worker were added.
- Confirmation/unsubscribe capabilities are deterministic HMACs derived in memory from a dedicated secret and consent UUID; only hashes are persisted. Preserve old unsubscribe hashes. Secret rotation blocks pending newsletter welcomes with mismatched hashes rather than sending broken links; coordinate pending work before rotation. There is no automatic consent/audit purge.

## Activation Gates

No environment values, DNS, sender, provider account, webhook subscription, SMTP/Auth template, scheduler, or remote deployment was changed. Never use the Gundex connector/account/key/sender.
Approve the account owning Clean Stream's existing Resend infrastructure, sender/domain, SPF/DKIM/DMARC (including the previously documented duplicate DMARC policy), content, actual postal address, reply-to, privacy/retention wording, quotas and test recipients first.
Runtime requires `CLEANSTREAM_MAIL_ENABLED=true`, `CLEANSTREAM_RESEND_API_KEY`, `CLEANSTREAM_MAIL_FROM`, identical `CLEANSTREAM_MAIL_VERIFIED_FROM`, `CLEANSTREAM_MAIL_REPLY_TO`, `CLEANSTREAM_MAIL_POSTAL_ADDRESS`, `CLEANSTREAM_MAIL_CONTENT_APPROVED=true`, and a random >=256-bit `CLEANSTREAM_MAIL_TOKEN_SECRET` (base64 text >=43 chars). No default/shared `RESEND_API_KEY` fallback exists; sender/reply-to must be plain Clean Stream domain addresses.
Also require `CLEANSTREAM_MAIL_PROJECT_URL` equal to `SUPABASE_URL`, `CLEANSTREAM_NEWSLETTER_URL` equal to that origin plus `/functions/v1/newsletter`, approved comma-separated `CLEANSTREAM_MAIL_CORS_ORIGINS`, random `CLEANSTREAM_MAIL_WORKER_SECRET` (>=32 chars), dedicated `CLEANSTREAM_RESEND_WEBHOOK_SECRET`, and server-only standard Supabase keys. `CLEANSTREAM_NEWSLETTER_PAGE_URL` must be an HTTPS Clean Stream domain page without query/fragment, with its origin in the CORS list; `CLEANSTREAM_MAIL_LINKS_APPROVED=true` must be set only after composer verifies the no-login page. The DB settings row starts disabled with NULL rollout; an approved operator must set actual go-live cutoff, approved text/version and enable explicitly. Do not backdate rollout or backfill users.
Composer must later configure only these three Edge gateways for `verify_jwt=false` (public capability links, dedicated worker auth, signed webhook auth); handlers retain their own authority. Do not globally change JWT verification or expose private tables. Pair with reviewed existing lifecycle/admission migrations and deployed Auth-owner privileges. Hosted gateway/browser form behavior, SMTP/deliverability, full financial schema compatibility and scheduling remain launch gates, not claims of these synthetic tests.

## Verification

- Deno 2.9.7: **73 passed, 0 failed**, frozen existing repository lock/config, no network or environment permissions; fake provider only. `deno fmt --check` and `deno lint`: all five new TS files clean.
- PostgreSQL 17.11: **52 passed, 0 failed** = 51 scenarios plus parent. Includes real lock waits, post-wait session expiry, Auth-owner trigger execution, RLS/effective grants, DOI/rates/replay, suppression/restoration, out-of-order callbacks, leases/uncertainty, and unchanged representative financial rows. Private Unix socket, no network listeners, all disposable files removed.
- `supabase db advisors` was attempted against that socket: CLI URI handling failed locally. **Unavailable, not passed**; direct SQL security assertions passed. Sandbox shared memory required an approved unsandboxed local test run. No hosted advisors or full app/financial suite was run.

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin node --test scripts/newsletter.test.mjs
DENO_DIR=/private/tmp/cleanstream-delivery-email/.deno-cache /tmp/cleanstream-backend-tooling/deno-2.9.7/deno test --frozen --node-modules-dir=none supabase/functions/_shared/mail.test.ts
```

Official references checked: [Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys), [raw webhook verification](https://resend.com/docs/webhooks/verify-webhooks-requests), [Svix algorithm/test vector](https://docs.svix.com/receiving/verifying-payloads/how-manual), [event types](https://resend.com/docs/webhooks/event-types), [webhook tags](https://resend.com/changelog/message-id-for-sent-emails), [Supabase Edge auth](https://supabase.com/docs/guides/functions/auth), [Edge HTML limits](https://supabase.com/docs/guides/functions/limits). [Supabase changelog](https://supabase.com/changelog) HTML reviewed after markdown fetch failed; this code uses none of the flagged legacy pgcrypto/ltree/operator features.
