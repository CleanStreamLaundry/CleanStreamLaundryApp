# Cleanup Activation Inputs

Preparation only: frozen metadata is not purge. No retention, balance treatment,
provider action or deployment is approved here. These are source-backed missing
inputs, not a current deployed catalog or provider inventory.

## Policy Decisions Required

For each class: approve fields to erase/anonymize/retain, retained linkage,
duration/start event, holds/support exceptions and historical-copy treatment.
Thirty days is recovery, not universal retention. Published seven-year financial/
two-year security-support wording in [email.md](docs/email.md) is not design approval.

| Class | Concrete decision and existing source |
| --- | --- |
| Identity and access | Disposition of `profiles` identity/contact fields, role/location assignments, consent-version/timestamps and Auth-managed user/session/MFA/identity data; supported Auth deletion/revocation order and treatment of still-valid JWTs. [Recovery](docs/account-recovery.md), [Supabase baseline/coverage gaps](docs/supabase.md). |
| Financial evidence | Retained columns/linkage for `wallet_accounts`, `wallet_loads`, `wallet_ledger_entries`, `wallet_redemptions`, `transactions`, `Refunds`, `deleted_account_complaints`; include free-text notes and actor attribution, not just `user_id`. [Wallet schema](supabase/migrations/20260526010000_wallet_ledger_compliance.sql), [payments](docs/payments.md). |
| Refund/vend evidence | Retention of top-up provenance/spend/refund operations, Stripe IDs, Cortina access-token hashes, Nayax IDs/RRN, raw event payloads and failure text. Preserve required reconciliation/idempotency evidence. [Top-up refunds](supabase/migrations/20260930125554_voluntary_topup_refunds.sql), [Cortina schema](supabase/migrations/20260803150427_cortina_qr_remote_vend.sql). |
| Support and media | Disposition of `Maintenance` descriptions/contact-related content and attachments independently of complaint/financial retention. Define how legacy `image_data` URLs, structured `attachment_ref`, unreferenced objects and object versions are handled. [Maintenance contract](supabase/migrations/20260930032327_maintenance_authorization.sql), [Storage observations](docs/supabase.md#maintenance-access-check-2026-09-29). |
| Email and suppression | Which email addresses, consent evidence, capability hashes, outbox/provider IDs and webhook records remain for suppression/deduplication; removal must not silently permit resubscription. Decide completion-notice timing and retained delivery evidence. [Newsletter schema](supabase/migrations/20260930125527_newsletter_consent_mail_outbox.sql), [email requirements](docs/email.md). |
| Devices and telemetry | Disposition of installation capabilities/tokens, revoked rows and any linkable provider telemetry, separately for dev/prod. No assumption that all telemetry carries account identity. [Push registration](supabase/migrations/20260930130013_push_token_registration.sql), [Firebase boundaries](docs/firebase.md). |
| Lifecycle and cleanup evidence | Minimum retained request/deadline/suppression and retry/unknown-outcome evidence after completion, without retaining unnecessary PII or falsely signaling deletion. [Existing lifecycle](supabase/migrations/20260930063923_recoverable_account_deletion.sql), [candidate job state](supabase/migrations/20260930154911_account_cleanup_claims.sql). |

## Dependency Decisions Before Auth Deletion

- **SET NULL preserves evidence:** wallet account/load/redemption `user_id`,
  ledger/complaint `created_by`, Cortina session `user_id`, `Refunds.resolved_by`.
  Notes/payment IDs/payloads remain (linked wallet/Cortina migrations).
- **RESTRICT needs policy, not removed constraints:** lifecycle -> profile;
  job -> lifecycle; wallet children -> wallet/load; top-up refund customer/reviewer
  -> profile, provenance -> load, spend -> ledger/wallet, ledger -> refund operation.
- Cortina events cascade with sessions; linked transactions restrict session
  deletion ([history](supabase/migrations/20260928132533_link_cortina_transaction_history.sql)).
  Push cascades with Auth user/session. Newsletter user IDs and recorded deployed
  Maintenance have no Auth FK. Confirm inbound FKs/triggers/grants for legacy
  profiles/transactions/Refunds/membership in a current catalog-only inventory;
  fixtures are not deployed evidence ([baseline gaps](docs/supabase.md#safe-migration-and-verification)).

## Remaining Balance And Settlement Fence

1. Approve remaining **paid cents**, promo/rewards and outstanding claims, including
   money outside voluntary-refund eligibility. No silent forfeiture. The approved
   48-hour Owner-reviewed unused-top-up policy is not deletion payout; legal-cash
   bookkeeping sends no money ([payments](docs/payments.md)).
2. Define settlement evidence for pending loads/vends, open/unknown refunds and
   missing provenance. Authoritative `wallet_balances` can have zero spendable
   funds while a refund reservation is unsettled. Preserve original-method payout,
   unwind and provider IDs ([refund SQL](supabase/migrations/20260930125554_voluntary_topup_refunds.sql),
   [reconciliation](supabase/functions/_shared/voluntary_topup_refund.ts)).
3. Fence new human funding/spending without blocking accepted provider settlement.
   Agree lock order: cleanup holds profile; `sync_profile_wallet_balance` locks
   wallet **then profile**, so appending wallet locks risks deadlock. Recheck after
   waits; deadline/lease is not settlement proof ([writers](supabase/migrations/20260929231120_serialize_wallet_financial_writes.sql),
   [coverage gaps](docs/account-recovery.md#activation-gaps)).
4. Existing `anonymize_wallet_for_deleted_user` only detaches wallet identities;
   it is not balance settlement, provider cleanup or purge completion.

## Storage And Provider Execution Inputs

- Approve `maintenance-images` object/version ownership and byte-deletion scope,
  including unresolved legacy URLs/owners. Use supported Storage operations, never
  metadata-only deletion ([recorded Storage facts](docs/supabase.md#maintenance-access-check-2026-09-29)).
- For Supabase, Stripe, Nayax/Cortina, Resend and Firebase: confirm account/env,
  identifiers, permitted deletion/retention, and observable completion/retry.
  Do not infer customer mappings or erasure APIs from payment/email IDs
  ([payments](docs/payments.md), [email](docs/email.md), [Firebase](docs/firebase.md)).
- Preserve historical provider/environment bindings, not current machine config
  ([bindings](supabase/migrations/20260930154259_freeze_cortina_payment_bindings.sql),
  [Stripe](supabase/functions/stripeWebhook/logic.ts), [Nayax](supabase/functions/_shared/cortina_callback.ts)).
- Require reviewed deletion order, durable unknown-outcome reconciliation and
  actual completion evidence. Seven PG restore/claim/mail-lock cases verify only
  metadata. No destructive executor, retention policy or provider effects verified.
