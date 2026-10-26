# Named Supabase Key Migration Inventory

Original read-only inventory: 2026-09-30. Current-status corrections below use accepted source and scoped development-deployment receipts, not a fresh or complete hosted configuration inventory.
App: `/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp`, HEAD `e65ade63523f2d563dfb41b0670fa03231d4f4cb` plus current local edits.
Web: `/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR`, HEAD `367a7b425cf44a9643c40d11b82e36a0bede212a` plus current local edits.
The original inventory was read-only. Reviewed mail and caller-bound public selectors are now integrated locally as described below; no key values, env-file contents, private downloads, hosted account inspection or credential mutations were needed.
Frontend variable names do not establish configured key format: `ANON_KEY`/`VITE_ANON_KEY` could already contain publishable keys. Values were deliberately not inspected. The standard hosted Edge legacy variables, by contrast, have the documented legacy contract below.

October 1 approved setup: project `dnuuhupoxjtwqzaqylvb` now has 24 individually
named `cleanstream_dev_*` keys (9 publishable, 15 secret), alongside unchanged
defaults. The browser lane's reloaded catalog confirms creation. Composer saved
21 Edge component selectors (80a5ae). Local app `.env` and web `.env.local` now
use their respective named publishable keys; Vercel Production and Preview use
the web key as public Config (f22f86). Same-source website redeployment
`dpl_Dw4sqZERapTD88w7yziC2QEPBpZq` is READY on the public domain (26f909);
the native rebuild remains in stage 3. No reserved runtime dictionary was overwritten
or legacy key retired. The operator key is reserved and undistributed: the old
service-key bootstrap helper has been replaced by offline guarded SQL generation.
It no longer reads keys, connects, invites users or resets passwords. No new API
privilege was granted to justify the reserved key; initial Owner still needs Y14.
Source mapping and receipt: `.campaign-work/named-key-setup/HANDOFF.md` and
`edge-selectors.env`. Hosted transport/dictionary acceptance remains stage 3.

## Current Official Contracts

- `sb_publishable_...` replaces public `anon`; `sb_secret_...` replaces backend `service_role`. Neither is a JWT. Secret keys still bypass RLS; separate names isolate rotation, not database permissions. Named API-key migration is separate from user JWT signing-key rotation. [API keys](https://supabase.com/docs/guides/api/api-keys)
- Send application keys in `apikey`, user JWTs in `Authorization: Bearer`. Current docs explicitly say `verify_jwt` accepts new API keys on either header for migration compatibility, but that is **not user authentication**. Keep user-only gateway checks and explicit handler authorization; do not globally set `verify_jwt=false`. Provider webhooks and dedicated worker secrets need endpoint-specific contracts. [Authorization headers](https://supabase.com/docs/guides/functions/auth-headers)
- Edge runtime exposes JSON dictionaries `SUPABASE_PUBLISHABLE_KEYS` and `SUPABASE_SECRET_KEYS`, indexed by key name. Existing `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` remain legacy. Custom Edge secret names cannot start with reserved `SUPABASE_`. [Environment variables](https://supabase.com/docs/guides/functions/secrets)
- Official `@supabase/server` supports `auth: 'secret:<name>'` and `'publishable:<name>'`; this repo does not use it. It is a supported option, not a recommendation to rewrite handlers during cutover. [Edge authentication](https://supabase.com/docs/guides/functions/auth)
- Legacy and new keys can overlap. Retire only after consumer verification; legacy deactivation can be reversed, deleted new secret keys cannot. Retain old mobile-client compatibility until explicitly retired. [Migration guide](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)

Docs checked today; changelog markdown fetch unsupported, [HTML reviewed](https://supabase.com/changelog). No relevant key-contract change inferred from the database-only breaking-change entry.

## Public Consumers

| Actual source / variable | Use and cutover gap |
| --- | --- |
| [App DI](../lib/core/di/di.dart:43), `SUPABASE_URL`, `ANON_KEY` at 65/66, 83/84, 105/106, 168/169 | One bundled key feeds SDK Auth/data/storage/functions, apikey-only public policy reader, MFA HTTP and Firebase push-token REST. No named selector or separate public config exists. A publishable value can remain under the old variable name initially; changing names requires all four DI reads plus CI. |
| [MFA HTTP](../lib/services/supabase/mfa_verification_client.dart:19), [push bootstrap](../lib/services/firebase/firebase_bootstrap.dart:45), [push store](../lib/services/firebase/push_token_store.dart:46) | Already separate public `apikey` from captured user bearer. Preserve exact caller binding and session-independent policy transport. |
| [App service consumers](../lib/services/supabase): `supabase_auth_service.dart`, `supabase_profile_service.dart`, `supabase_edge_function_service.dart`, `supabase_cortina_vend_service.dart`, `supabase_machine_service.dart`, `supabase_location_service.dart`, `supabase_transaction_service.dart`, `supabase_wallet_service.dart`, `supabase_admin_wallet_service.dart` | Share DI client, not separate credentials. Profile includes newsletter/restore/admission RPCs; machine service calls availability. [Mobile Stripe](../lib/services/stripe/stripe_service_mobile.dart:118) calls `paymentIntent`/`paymentIntentStatus`; [web Stripe](../lib/services/stripe/stripe_service_web.dart:68) calls `createCheckoutSession`/`checkPaymentResult`. |
| [App manifest](../pubspec.yaml:103), [CI](../.github/workflows/dart.yml:30) | `.env` is an app asset; CI writes `SUPABASE_URL`/`ANON_KEY`. Contents not inspected. Never place a server secret in this configuration. |
| [Web client](../../CleanStreamWeb-CortinaQR/src/supabase/client.ts:3), [types](../../CleanStreamWeb-CortinaQR/src/global.d.ts:3), `VITE_SUPABASE_URL`, `VITE_ANON_KEY` | Shared public/checkout/staff SDK identity; `/admin` is not a separate secret-bearing deployment. No named selector. Missing config returns null; preserve that behavior. |
| [Web newsletter](../../CleanStreamWeb-CortinaQR/src/components/NewsletterPage.tsx:48) | Independent raw fetch reads the same two variables and sends `apikey` only, no stored-session bearer. Must migrate along with the singleton, not just client.ts. |
| [Web DI](../../CleanStreamWeb-CortinaQR/src/di/container.ts), [repositories](../../CleanStreamWeb-CortinaQR/src/supabase/repositories), [admin API](../../CleanStreamWeb-CortinaQR/src/admin/api.ts), [admin provider](../../CleanStreamWeb-CortinaQR/src/admin/AdminProvider.tsx), [auth pages](../../CleanStreamWeb-CortinaQR/src/admin/AuthPages.tsx) | Repository consumers: Auth, Employee, Location, Maintenance, Transcation (existing spelling), Traffic, Refund, EdgeFunction, CortinaVend. Admin invokes `admin-portal`; mutations pin the initiating user bearer; Cortina invokes quote/card/wallet/status. All remain public-key + user/capability authority, never service keys. |

Source locks: app `supabase_flutter` 2.17.2 / `supabase` 2.16.1; web manifest and lock pin 2.103.3 with the reviewed Auth patch. Edge imports vary: admin backend 2.99.3, Cortina/availability 2.97.0, deletion 2.14.0, several floating `@2`. Inventory is not SDK transport compatibility evidence.

Pinned Flutter transport verification now passes eight synthetic HTTP cases in `test/services/supabase/publishable_key_transport_test.dart`. Signed-in REST/RPC/Storage/Edge preserve the exact user bearer and public apikey; signed-out Edge omits Authorization, while signed-out SDK REST/RPC/Storage retain a publishable-key fallback bearer. The actual public-policy factory sends apikey only without refreshing Auth. No Realtime channel connects. This is local wire evidence, not hosted gateway/RLS compatibility or permission to retire keys; test the observed fallback explicitly during staging cutover.
The inspected [web CI](../../CleanStreamWeb-CortinaQR/.github/workflows/test.yaml) contains no Supabase/VITE key mapping; actual hosting/build-time injection remains an operator inventory gap.

## Backend And Operator Consumers

Paths below are under [app Edge functions](../supabase/functions). All also read `SUPABASE_URL`.

| Consumer | Actual key use / named-key gap |
| --- | --- |
| [admin-portal/index.ts](../supabase/functions/admin-portal/index.ts), `approveRefund/index.ts`, `denyRefund/index.ts` | Optional `CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME` now selects an exact public-dictionary entry; absent selector preserves legacy. Shared [backend.ts](../supabase/functions/admin-portal/backend.ts) retains captured-token `accessToken` and authoritative RPCs. Caller/credit RPCs use no service key. Separate Owner invite/resend now uses `CLEANSTREAM_ADMIN_SECRET_KEY_NAME` with `SUPABASE_SECRET_KEYS` (absent-only legacy), canonical caller authorization and Auth-admin transport; provider/delivery acceptance is separate. |
| [maintenance-request/index.ts](../supabase/functions/maintenance-request/index.ts) | Optional `CLEANSTREAM_MAINTENANCE_PUBLISHABLE_KEY_NAME` with exact caller bearer; absent-only legacy and guarded failures. Integrated after 12 new/20 existing adapter checks and source QA. |
| [delete-account/index.ts](../supabase/functions/delete-account/index.ts) | Optional `CLEANSTREAM_ACCOUNT_PUBLISHABLE_KEY_NAME`; same caller JWT/getUser and pending-deletion RPC. No service key, Auth deletion or wallet anonymization. |
| [shared Cortina factory](../supabase/functions/_shared/cortina.ts) | Fixed component identities select `CLEANSTREAM_CORTINA_VEND_SECRET_KEY_NAME`, `CLEANSTREAM_STRIPE_WEBHOOK_SECRET_KEY_NAME`, `CLEANSTREAM_NAYAX_PRODUCTION_SECRET_KEY_NAME`, `CLEANSTREAM_NAYAX_SANDBOX_SECRET_KEY_NAME` or `CLEANSTREAM_TOPUP_REFUND_SECRET_KEY_NAME`. Integrated after 80 independent checks. Modern keys use apikey while explicit human bearers remain intact; only an absent selector retains legacy. Caller clients separately use `CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME` and `CLEANSTREAM_TOPUP_REFUND_PUBLISHABLE_KEY_NAME`, with captured bearer and absent-only legacy. Their 23 new plus 18 retained checks pass; the retained vend helpers are not provider-flow coverage. |
| [createCheckoutSession/index.ts](../supabase/functions/createCheckoutSession/index.ts) | Optional server `CLEANSTREAM_CHECKOUT_SECRET_KEY_NAME`; caller Auth and canonical funding checks use `CLEANSTREAM_FUNDING_PUBLISHABLE_KEY_NAME`. Modern privileged requests use apikey only; captured human admission is separate. |
| [paymentIntent/index.ts](../supabase/functions/paymentIntent/index.ts) | Optional `CLEANSTREAM_PAYMENT_INTENT_SECRET_KEY_NAME`, modern privileged apikey only and exact getUser caller bearer. Funding admission retains its separate captured caller/public key. Both creation adapters are integrated after independent47/typechecking, with absent-only legacy and invalid-explicit 503 before HTTP. |
| [paymentIntentStatus/index.ts](../supabase/functions/paymentIntentStatus/index.ts), [checkPaymentResult/index.ts](../supabase/functions/checkPaymentResult/index.ts) | Optional `CLEANSTREAM_PAYMENT_INTENT_STATUS_SECRET_KEY_NAME` and `CLEANSTREAM_CHECK_PAYMENT_RESULT_SECRET_KEY_NAME`, respectively. Integrated after 13 intent and 18 checkout checks with typechecking. Fixed-project REST uses modern apikey only; explicit getUser retains the caller bearer. Invalid explicit selection fails closed; absence alone retains legacy. |
| [machine-availability/index.ts](../supabase/functions/machine-availability/index.ts) | Optional `CLEANSTREAM_AVAILABILITY_SECRET_KEY_NAME`, resolved per request; modern REST uses apikey only, explicit getUser retains the caller bearer. Integrated after 12 real-SDK adapter/5 logic checks and source QA. No provider call or hosted key activation. |
| [mail RPC adapter](../supabase/functions/_shared/mail.ts) used by `newsletter`, `mail-delivery`, `mail-webhook`, `refund-email` | Optional `CLEANSTREAM_MAIL_SECRET_KEY_NAME` chooses one exact secret entry, apikey only; caller branch uses `CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME` plus the unchanged user bearer. Both preserve legacy only when their selector is absent, never on invalid explicit selection. Public32+compat8 pass with independent source review. Project equality and sending gates remain; hosted cutover is not done. |
| [account-cleanup/index.ts](../supabase/functions/account-cleanup/index.ts) | Optional `CLEANSTREAM_CLEANUP_SECRET_KEY_NAME`, modern apikey only and absent-only legacy. Draft-supported executor/scheduler source is integrated, untested and unapplied; final disposition remains Y5. Preparatory adapter checks do not verify the new executor. |
| [cortina-reconcile/index.ts](../supabase/functions/cortina-reconcile/index.ts) | Disabled by default. Optional `CLEANSTREAM_CORTINA_RECONCILIATION_SECRET_KEY_NAME` selects one exact secret-dictionary entry, apikey only. Absent selector preserves legacy; invalid explicit selection fails before HTTP. Dedicated worker bearer is separate from database authority. |
| [changePassword/index.ts](../supabase/functions/changePassword/index.ts), [resetToken/index.ts](../supabase/functions/resetToken/index.ts), `wakeDevice/index.ts`, `verifyPayment/index.ts` | Retired October 1: credential-free fixed denial handlers integrated and deployed after caller review/95 tests. No key migration needed for these handlers; never restore privileged wrappers or simulator success. |
| [ping-device/index.ts](../supabase/functions/ping-device/index.ts) | Also replaced/deployed with credential-free denial. MachineCommunicator's remaining caller belongs to the unwired legacy scanner path; supported scanner uses Cortina. No anonymous-to-secret credential promotion. |
| [operator bootstrap](../../CleanStreamWeb-CortinaQR/scripts/bootstrap-admin-owner.mjs) | Offline SQL generator only. No API key, network call, account creation or email; `--apply` is rejected. SQL requires the explicitly approved existing account and trusted database operator, preserving the installed bootstrap authority and audit record. Old transport tests do not establish acceptance of this replacement. |

`refund-email` uses the shared mail caller-RPC adapter, not direct provider delivery.
`delete-maintenance` remains credential-free deny-all containment; never restore
its unauthenticated privileged implementation. The existing dedicated Edge/Vault
mail scheduler is now enabled for transactional events from the current rollout.
Postal-dependent newsletter delivery remains unavailable. See [email](email.md)
for activation receipts and unverified delivery; do not duplicate keys/jobs/webhooks.

PaymentIntent creation and status now explicitly request Stripe API `2023-10-16`, matching the already-locked Stripe 14.25 SDK and the other payment adapters. Fake-HTTP assertions verify the actual headers. This fixes prior type mismatches without a dependency upgrade and changes adapter create/retrieve request versions, not the Stripe account or webhook version. C/D deployed `paymentIntent`39 and `createCheckoutSession`41; positive provider acceptance and any status-adapter deployment not explicitly recorded remain separate. Existing Edge import-policy lint findings remain recorded in operations.

## Gateway Matrix

Local [config.toml](../supabase/config.toml:371), with only the recorded hosted readbacks distinguished below:

| Local setting | Functions / authority to preserve |
| --- | --- |
| Explicit `false` | `stripeWebhook` (Stripe signature); `nayax-sale-end`, `nayax-sale-end-sandbox` (required `NAYAX_CALLBACK_AUTH_TOKEN`, not Supabase API key); `cortina-vend` (public quote/card + verified wallet user + hashed status capability); `admin-portal` (captured bearer into authoritative RPC); `machine-availability` (getUser); `cortina-reconcile` (disabled unless configured, dedicated worker bearer); `newsletter`, `mail-delivery`, `mail-webhook` (caller/capability, dedicated worker bearer and raw-body provider signature, respectively). |
| Explicit `true` | `approveRefund`, `denyRefund`, `customer-mfa-recovery`; still require current caller/role/location/MFA authority as applicable, not API-key possession. |
| No per-function stanza: default `true` unless deployment overrides | `paymentIntent`, `paymentIntentStatus`, `createCheckoutSession`, `checkPaymentResult`, `maintenance-request`, `delete-account`, `voluntary-topup-refund`, `wakeDevice`, `ping-device`, `verifyPayment`, `changePassword`, `resetToken`, `refund-email`, `delete-maintenance`. Default is not proof of hosted state. |

Recorded readbacks: mail3 ACTIVE v6/false (465728); C/D9 off only for admin-portal, other eight on (d11da8); Stripe/Nayax callbacks false (689daa); machine-availability13 false; retired legacy5 true (62e390). The earlier delete-maintenance containment retains its recorded hosted false setting. These scoped receipts in [operations](operations.md) do not establish every deployed override or named-key cutover.

Mail gateway settings are deployed; signed-event/delivery and no-login one-click unsubscribe acceptance remain separate. The four rejection smokes are not positive capability/provider evidence. A publishable-key browser POST passing migration compatibility does not prove a credential-free mailbox/provider POST reaches the handler. Never replace the worker, webhook or callback secret with a publishable key. Cortina already excludes `sb_publishable_` from optional user-token lookup at [cortina.ts:197](../supabase/functions/_shared/cortina.ts:197); this alone is not complete key migration.

## Minimal Cutover And Rollback Evidence

1. **Selection:** use trusted, fixed component-name mappings for Edge dictionary lookup; reject missing/malformed/wrong-kind keys without logging values or silently choosing `default`. Candidate names per environment: app, web, caller-RPC; separate server names for vend, Stripe callback, each Nayax environment, top-up refund, checkout, intent/status, availability, mail, cleanup and operator bootstrap. These are proposed allocations, not existing key names. Shared factories must accept trusted component selection, never request-selected names. Mail/admin/account selectors are integrated; no hosted key cutover is verified.
2. **Public transport:** use real pinned SDK + fake HTTP with synthetic publishable strings. Assert apikey on Auth/REST/Storage/Edge, exact user JWT when signed in, no credential promotion, and no session refresh for public policy/newsletter. Extend [public-policy test](../test/core/di/public_policy_test.dart), [MFA HTTP test](../test/services/supabase/authentication/mfa_http_test.dart), [push-token test](../test/services/firebase/push_token_store_test.dart), [newsletter page test](../../CleanStreamWeb-CortinaQR/src/components/NewsletterPage.test.tsx), [web Auth test](../../CleanStreamWeb-CortinaQR/src/supabase/repositories/AuthRepositoryTests.test.ts).
3. **Backend authority:** synthetic named dictionaries + fake transport for mail/admin/maintenance/deletion adapters; valid user, expired/wrong user, publishable-only and secret-as-user-bearer cases. Keep staff AAL/location and lifecycle checks. Start at [admin backend tests](../supabase/functions/admin-portal/backend.test.ts), [mail tests](../supabase/functions/_shared/mail.test.ts), [maintenance tests](../supabase/functions/maintenance-request/index.test.ts), [deletion tests](../supabase/functions/delete-account/index.test.ts). Subsequent source changes need scoped review; this inventory does not establish their acceptance.
4. **Callbacks and money:** gateway contract matrix in approved staging later: user JWT + publishable, key-only, no keys + valid/invalid provider signature, worker secret and unsubscribe form. Preserve callback idempotency and pending reconciliation across overlap; reuse [Cortina tests](../supabase/functions/_shared/cortina_orchestration.test.ts), [callback tests](../supabase/functions/_shared/cortina_callback_auth.test.ts), [checkout status tests](../supabase/functions/checkPaymentResult/index.test.ts), [top-up tests](../supabase/functions/voluntary-topup-refund/index.test.ts). SDK mocks alone cannot prove hosted gateway behavior.
5. **Rollback:** keep approved legacy credentials active during staged consumer rollout; test restoring prior non-secret configuration/code mapping and previous client artifact without changing event keys or replaying payments/email. Before revocation, inventory deployed functions, build-time web env, shipped app versions and operator jobs using names/usage metadata only. Confirm one component's replacement does not break other callbacks. No auto-retirement, broad fallback, permission widening, or rollback to contained unsafe endpoints.

## Mail Component Cutover

Local selector/adapter evidence: author 33 new plus eight existing cases pass;
independent QA reruns the 33 new cases with typecheck and finds no required fix.
Existing fetch transport, timeout, payload, project binding and no-retry policy stay.
This is code acceptance, not hosted provisioning or delivery evidence.

- Optional server variable `CLEANSTREAM_MAIL_SECRET_KEY_NAME` contains a key name,
  not its value. Select the exact own entry in runtime `SUPABASE_SECRET_KEYS` on
  every privileged RPC. Missing/malformed/wrong-kind entries fail before HTTP;
  rejected HTTP credentials never fall back or retry another key.
- Absent selector preserves legacy mode. An empty selector is invalid, not an
  opt-out. User-bearing newsletter calls do not consult the secret selector.
- After explicit provisioning/rollout approval, verify dictionary and header
  behavior in the correct environment. Do not overwrite reserved dictionaries.
  Separate names still provide revocation, not least privilege.
- Rollback requires an explicit operator action: remove the selector entirely or
  restore the accepted prior adapter, only while the legacy key is authorized.
  Never restore a compromised key or clear mail event keys/payload fingerprints.

## Caller-Bound Public Cutover

The shared `supabase_keys.ts` now serves mail plus four caller-bound endpoints;
the superseded mail-only helper is removed. `CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME`
is for admin-portal/approveRefund/denyRefund; `CLEANSTREAM_ACCOUNT_PUBLISHABLE_KEY_NAME`
is for delete-account. Each trusted name selects the exact own entry from
`SUPABASE_PUBLISHABLE_KEYS`, allowing only `sb_publishable_` values. No server
secret or request-selected name can be substituted. Absent selectors alone retain
legacy mode; empty/missing/malformed named configuration fails closed.

The existing credit adapter lazily creates one caller client inside its guarded
error boundary, preserving bearer capture, 503 sanitization, CORS and preflight
ordering without duplicate response handlers. Deletion preserves its existing
two-client flow; no request-wide key snapshot is claimed there. In-flight clients
retain their selected key; subsequent client construction uses current config.

Author109 distinct cases and independent26 real-SDK caller cases pass with
typechecking. Eleven checksum entries for already-imported pinned std0.182.0
modules close the frozen-lock loader gap; no version pins changed. Four existing
URL-import lint findings remain. That selector-only batch changed no gateway,
live key, environment variable or provider; later scoped setup/deployment receipts
are recorded above. Rollback follows the explicit absent-selector rule above and
must not restore compromised credentials or replay business operations.

Remaining gaps: unverified deployed overrides, runtime dictionary availability
and hosted transport acceptance. Align the obsolete
operator helper in stage 2; do not distribute an unnecessary server secret. Older builds
explicitly need no support, but existing keys must remain active until separate
retirement approval. Saved selectors do not prove end-to-end named-key cutover.
Current scoped commands and review boundaries are in [operations](operations.md).
