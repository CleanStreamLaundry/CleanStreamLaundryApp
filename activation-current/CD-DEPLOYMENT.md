# C/D Paired Deployment

**CleanStream DEVELOPMENT, dnuuhupoxjtwqzaqylvb**. User approved development deployments; Composer applied exact C/D18 artifact `f2788680676ac4021dadd594bc435723dac148e5833a1b00ce4d03a3910a4348`, exit0/bcc2dd. History artifact `fb9873d16` applied with exact18 source-hash readback, exit0/d55c49. All nine paired endpoints ACTIVE d11da8; all nine unauthenticated smokes returned401, receipt66eedf. Independent QA postflight66eb15 accepted controls reported by5dc449: expected functions/tables, RLS9, mail=false/rollout=null/recipient=null, deletion ACL allfalse, restore authenticated-only, new-payment enabled. Combined C/D **all15 accepted** remains valid (f6dcab plus retained11, clean PG teardown). Input order is `cd-sources.sha256`. No remote action by this lane; no schema replay or further rehearsal. Separate payment four-SQL/callback/web-reader ordering remains outside this nine-endpoint closure.

Already installed: A/B seven and profile guard; mail endpoints ACTIVE v6 receipt465728, sending/rollout/recipient offc32f90, four rejection smokes951be8. Do not repeat them. Deletion request remains denied to anon/authenticated/service, restoration stays authenticated-only. Preserve those states through this slice.

## SQL Postflight

`postflight-cd.sql` is one configuration/catalog SELECT, no customer rows, function bodies, secrets or mutations. Completed after approved installation; independent QA receipt66eb15 accepted. No rerun requested. Existing catalog921fdc, installed A/B receipts and narrow invoker-counter receiptcaef1b are reused.

Expected results:

- Mail: exactly one settings row, all_disabled=true, rollout_set=false, refund_recipient_set=false. New-payment control: one row, enabled=true (approved behavior-preserving installation default).
- All listed functions/tables exist. Deletion EXECUTE false for all API roles; restore true only authenticated. Canonical human admin/legacy-claim/MFA/maintenance RPCs are authenticated-only. Human Cortina claim `request_cortina_loyalty_credit(bigint,text)` preserves EXECUTE for authenticated AND service_role, not anon; the broader authenticated-only description was incorrect. Onboarding delivery, provenance/prepare/reconcile are service-only. Actor-taking admin internals, raw resolver and global wallet adjustment/status/cash-redemption RPCs stay denied to all three API roles. These are role-metadata findings, not customer-data reads.
- Preserve the counter's existing invoker/search_path=public/ACL contract, including its existing public EXECUTE; trusted definer wrappers perform its protected profile write. Do not "repair" this helper as part of postflight.
- Direct transaction/Refunds table INSERT and any-column INSERT false for anon/authenticated, true service table INSERT. UPDATE/DELETE metadata is returned for comparison with catalog921fdc, not permission to widen it. Both restrictive INSERT policies have false checks. Four Home wallet SELECT policies and four original self-only wallet policies coexist; portal/maintenance SELECT policies remain restrictive.
- New private/admin tables have RLS. Location/maintenance write guards enabled ALWAYS; provenance/spend/credit notice/audit/recovery triggers enabled. Wallet view remains security_invoker=true; the three credit-notice columns exist. No query counts financial/customer rows or claims that hosted historical balances were inspected.

## Exact Function Order

Completed after C/D SQL commit and metadata acceptance: **these nine named functions**, ACTIVE d11da8 with unauthenticated401 each66eedf. The order and accepted local closure below are deployment provenance, not a request to redeploy. Positive provider/customer actions and separate payment/Storage coverage are not proved by rejection smokes.

1. `admin-portal`: canonical caller-bound admin, invite/resend, geocoding and credit decisions.
2. `approveRefund`: retained legacy URL, now the caller-bound canonical credit adapter.
3. `denyRefund`: same preservation for denial; no direct email sender.
4. `maintenance-request`: caller-bound canonical submission, not a service bypass.
5. `paymentIntent`: canonical Home and new-payment switch before new funding creation.
6. `createCheckoutSession`: same gate, original bearer preserved across awaits.
7. `refund-email`: enqueue existing claim notice only; no second financial write or direct sender.
8. `voluntary-topup-refund`: C's caller-bound refund/review and trusted provider reconciliation contract.
9. `customer-mfa-recovery`: Owner-only externally verified support case, current AAL2/session and mandatory reenrollment; no action in a deployment smoke.

**Excluded from this approval request: `stripeWebhook`.** Its current wallet branch records C's verified payment-success provenance, so the 48-hour automated refund workflow is incomplete until that writer is separately deployed. Its current Cortina branch requires frozen binding/provider-ownership prerequisites absent from catalog921fdc: `20260930154259_freeze_cortina_payment_bindings.sql` and `20260930163919_cortina_callback_provider_ownership.sql`. These are not added to C/D18. Preserve the current hosted settlement endpoint while that separate pairing is held; historical routing is never guessed/backfilled.

`cortina-vend` is also a separately coordinated Dalton closure (binding/provider ownership, return version and newly accepted capacity RPC), not one of these nine. Its deployment remains necessary for complete ordinary card admission. Do not blanket replace Nayax callbacks, confirm/status routes or reconcile merely because they import common code. No new quota migration is added here.

## Local Import Closure

All paths below are relative to active `supabase/functions/`. Bundle transitive local imports, not just `index.ts`; preserve pinned `deno.json`/`deno.lock` resolution. No SDK upgrades or copied alternate helpers.

| Named deployment | Exact local files |
| --- | --- |
| `admin-portal` | `admin-portal/{index,handler,backend,logic,geocoding,onboarding}.ts`, `_shared/{refund_resolution,supabase_keys}.ts` |
| `approveRefund` | `approveRefund/index.ts`, `admin-portal/{backend,logic,geocoding,onboarding}.ts`, `_shared/{refund_resolution,supabase_keys}.ts` |
| `denyRefund` | `denyRefund/index.ts`, `admin-portal/{backend,logic,geocoding,onboarding}.ts`, `_shared/{refund_resolution,supabase_keys}.ts` |
| `maintenance-request` | `maintenance-request/{index,logic}.ts`, `_shared/supabase_keys.ts` |
| `paymentIntent` | `paymentIntent/{index,logic}.ts`, `_shared/{wallet_funding_admission,new_payment_control,supabase_keys}.ts` |
| `createCheckoutSession` | `createCheckoutSession/{index,logic}.ts`, `_shared/{wallet_funding_admission,new_payment_control,supabase_keys}.ts` |
| `refund-email` | `refund-email/{index,logic}.ts`, `_shared/{mail,supabase_keys}.ts` |
| `voluntary-topup-refund` | `voluntary-topup-refund/index.ts`, `_shared/{voluntary_topup_refund,cortina,supabase_keys}.ts` |
| `customer-mfa-recovery` | `customer-mfa-recovery/index.ts`, `admin-portal/{backend,logic,geocoding,onboarding}.ts`, `_shared/{refund_resolution,supabase_keys}.ts` (actual capturedBearer import closure, no refactor) |
| Conditional `stripeWebhook` | `stripeWebhook/{index,logic}.ts`, `_shared/{cortina,supabase_keys}.ts` |

Current config explicitly keeps admin-portal verify_jwt=false with canonical caller authorization, approveRefund/denyRefund/customer-mfa-recovery=true, stripeWebhook=false with raw-body Stripe signature verification. Other listed endpoints have no explicit local override: preserve/record their existing gateway settings, do not silently disable verification. Named-key/asymmetric-JWT human gateway compatibility must be proved, especially MFA; do not deploy a password-only workaround. Funding's accepted Stripe API literal is 2023-10-16, not permission to change a remote Stripe account or webhook version.

Use existing optional selectors only: funding public `CLEANSTREAM_FUNDING_PUBLISHABLE_KEY_NAME` and per-endpoint secret selectors; admin `CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME`/`CLEANSTREAM_ADMIN_SECRET_KEY_NAME`; maintenance public selector; MFA public/secret selectors; top-up refund public/secret selectors; mail public/secret selectors; webhook component secret selector. Explicit invalid configuration fails closed; absent-only legacy fallback is unchanged. Verify names/configuration without printing values or creating/retiring keys. Preserve admin origin/redirect binding and server-only GEOCODEMAPS_KEY. Auth invitation delivery uses existing Auth SMTP, not the mail outbox.

## Impact And Boundaries

Old direct financial INSERT clients intentionally lose access even if Home-eligible; current accepted app claims use the two authoritative RPCs. Existing records, UPDATE/DELETE grants and service/definer writers are preserved by that denial batch. Old raw maintenance writers and service-identity staff adapters fail rather than bypass canonical admission. Owner/Admin global wallet authority is not granted; legacy unknown top-up provenance remains manual support, never retroactively inferred. Already-funded completion, settlement, reversals and dedicated pending-account refunds must remain available.

After each named deployment, record its version/gateway and only no-provider rejection/configuration smokes. Missing/invalid human bearer and staff AAL1 must deny before external work; unsigned webhook must deny before funding. No invite/resend, geocoding, Stripe create/refund, factor removal, real claim or deletion smoke is authorized by this preparation. A positive test requires a separately approved disposable identity and action receipt.

Storage E remains separate: app public-URL-shaped image value is a compatible parser reference, not displayed public media. Require hosted authorized upload/download and cross-account/location/pending-account denial proof before privacy activation; no forced app signed-URL redesign, file repath/delete or bucket mutation here. Deletion stays held until complete ordinary API/Storage coverage. Mail stays off; SMTP/Cron/delivery proof and any actual sends are separately authorized. Rollback must not restore hard deletion, unsafe client financial INSERT, global wallet grants or old service bypasses; prefer a forward fix and controlled service pause.
