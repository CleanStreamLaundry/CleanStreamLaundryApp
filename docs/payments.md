# Payments and Refunds

Local source reviewed 2026-09-29, including dirty/untracked work. Deployment and physical-machine behavior are not verified here. Active website is `CleanStreamWeb-CortinaQR`; shared backend lives in this app repository.

## Source and Units

- `supabase/migrations/20260526010000_wallet_ledger_compliance.sql` defines wallet loads, paid/promo ledger, balances, redemptions, and cash-redemption bookkeeping. `wallet_balances` is ledger-derived; `profiles.balance` is a dollar compatibility cache, not independent money truth.
- Wallet ledger/RPC and Cortina amounts, and Stripe API request amounts, use integer USD cents. Flutter `PaymentService.makePayment(double amount)` currently takes dollars; Stripe implementations convert at the Edge-request boundary. `Refunds.amount`, transaction history, `profiles.balance`, and `profiles.reward_tracker` use dollars. Preserve these boundaries and avoid double conversion.
- Each cumulative 2,000 paid cents currently earns 500 promo cents; reward progress crosses loads. Machine spending consumes promo first. Refunding a load cannot simply delete its row or subtract only a guessed bonus.
- `stripeWebhook/logic.ts` and `paymentIntentStatus/logic.ts` both reach `record_wallet_load_from_stripe`; the latter verifies payment ownership and successful status. Preserve shared idempotency across both paths.
- Read-only production inspection found unique load indexes for Stripe intent, Checkout session, charge, and event IDs, but no explicit locking in the recording RPC's reward-tracker read/update. Distinct concurrent loads can race reward progress; the new Checkout-status caller must not be treated as production-ready until this shared financial contract is hardened and verified.
- Live `redeem_wallet_for_machine` also reads the ledger balance without a wallet-level lock or wallet-status check. Cortina's per-session lock does not serialize spending from different sessions against the same wallet. Coordinate all financial writers and lock order before refunds/reservations or account restrictions rely on that state.
- Local `20260929231120_serialize_wallet_financial_writes.sql` repairs wallet-wide serialization and duplicate-load rechecks across nine existing routines. Worker/composer/QA pass 28 real PostgreSQL 17.11 tests after correcting the review finding: first-resolution `notificationSent` remains false, replay retains the timestamp check. Local acceptance passed; deployment is not approved. Production still has the behavior described above. A busy session fails with `55P03` before credit; a fresh transaction may retry. This is not MFA/location hardening, server pricing, voluntary refunds, or a historic-balance repair.
- Local `checkPaymentResult` now authenticates the caller, matches session/intent ownership, purpose, integer cents, USD, and provider mode, and reports wallet success only after the existing ledger RPC succeeds. The web Stripe client uses bounded polling and no Supabase subscription. The webhook broadcaster is removed locally too; its four-file removal passes 96 worker/independent QA tests. Financial recording/signature checks are unchanged; uncached webhook entrypoint imports remain unverified. These changes are not deployed; old-client compatibility, pending-payment reconciliation and coordinated rollout remain gates before production Realtime shutdown.
- Mobile Stripe's per-instance guard remains held through server verification, then releases even for a `pending` result. It prevents overlapping calls, not duplicate charges across clients or through settlement; backend idempotency and reconciliation remain required.
- `_shared/cortina.ts` handles vend/compensation and Nayax money conversion; `20260803150427_cortina_qr_remote_vend.sql` owns sessions/reversal. Read related handlers/tests before changes.
- **Legacy route release blocker:** read-only Chrome inspection confirmed deployed `wakeDevice/index.ts` calls the same simulated `logic.ts` as local: random 95% success, short delay, no machine/provider transport. The legacy direct-card controller charges before trusting this result; its wallet path calls it before recording a client-priced debit. Local `/paymentPage` now mounts an inert `MachinePayment` support notice, never constructing that controller or initiating payment. Composer/independent QA pass 161 containment/unchanged payment/scanner tests; QA also passes 19 Chrome containment cases and clean scoped analysis. This client-only fix does not contain older deployed binaries or retire the backend. Current `handleQRCode` routes supported codes through Cortina `/pay`, not this legacy method. Do not claim scanner default flow uses the simulator or infer past customer impact. No endpoint invocation/payment/device operation was performed. Coordinate remaining retirement and captured-payment reconciliation; a remote wake toggle alone would leave charge-before-failure behavior.

## Distinct Workflows

| Workflow | Current local behavior |
| --- | --- |
| Machine-issue claim | `Refunds` approval adds promo-only credit, not a Stripe payout; hardened resolution locks/deduplicates the request |
| Failed card vend | Requests a Stripe refund with session-based idempotency, then marks the vend `refunded` without checking provider refund status. Thrown errors attempt `support_required`. Pending/failed refund reconciliation is a baseline risk; local `refunded` is not completed repayment. |
| Failed wallet vend | Reverses the original paid/promo split and marks redemption void; spend history remains |
| Legal cash/redemption bookkeeping | `admin_record_legal_cash_redemption` records negative paid ledger entries; an optional Stripe reference does not issue a payout |
| Voluntary unused-topup refund | Proposed only; no dedicated request/reservation/provider reconciliation workflow found |

Flutter `lib/services/supabase/supabase_admin_wallet_service.dart` currently passes a null Stripe refund reference. Do not label that as an implemented cash refund. Existing machine-claim history uses a 14-day request window, not the proposed 48-hour top-up window. Local admin portal resolution adds location scope; do not discard that work.

App legal/load copy currently says final sale except legally required remedies. Website copy differs. Do not publish the new policy as available before the workflow works across app, backend, admin, and public terms.

## Approved Top-Up Policy, Not Implemented

- Eligibility uses server-recorded request time and authoritative successful-payment time: `0 <= requested_at - payment_succeeded_at <= 48 hours`. Owner review may occur later. Load insertion time is not necessarily payment-success time.
- Any wallet spending after the top-up disqualifies it, including promo-only spend and a failed vend later fully reversed. Earlier account usage is allowed. Restored balance does not erase usage history.
- Owner-only review/approval is enforced server-side. Refund full paid principal to the original payment method; Clean Stream absorbs original processing fees. No partial voluntary refund initially and no cash value for promo credit.
- Unwind attributable bonus/reward progress, including cumulative thresholds and subsequent loads. Keep statutory remedies, machine claims, and failed-vend compensation distinct.
- Atomically validate eligibility and reserve paid credit plus required reward unwind before provider payout. Every debit path must honor the reservation; a per-vend session lock is not a wallet-wide lock.
- Persist a single auditable business operation/policy version with stable provider idempotency and pending/success/failure/unknown reconciliation. Do not mark pending provider refunds completed, release an uncertain reservation, or blindly retry a possible payout.
- Handle duplicate requests/approvals/webhooks, out-of-order updates, external refunds, and provider success followed by database failure. Preserve completed financial history on account deletion; see [Supabase](supabase.md).

## Vend and Refresh Boundaries

Server owns quote/pricing, device mapping, washer settings, six dryer choices, and payment/vend authorization. Check exactly one Start request and strict transaction, terminal, amount, currency, and environment matching. Verify callback authentication; missing configuration must not silently authorize callbacks.

Current local `_shared/cortina_callback.ts` is not yet strict: missing `NAYAX_CALLBACK_AUTH_TOKEN` allows the request; absent currency or missing callback/configured terminal passes matching. Environment is checked against mutable machine configuration, not an immutable session snapshot. These are source findings, not fresh provider/deployment tests. Review actual documented provider payloads and deployment compatibility before tightening them; preserve captured-payment reconciliation rather than silently rejecting settlement in production.

Provider compatibility matters: Nayax's [Sale example](https://devzone.nayax.com/docs/cortina/staticqr/static-qr-sale) has an empty terminal ID but a hardware serial; those identifiers are not automatically interchangeable. [SaleEndNotification](https://devzone.nayax.com/docs/cortina/sale-end-notification) documents transaction/currency fields, not a device object, so requiring a terminal on every callback would reject valid payloads. [Void](https://devzone.nayax.com/docs/cortina/staticqr/static-qr-void) can follow a Sale-response timeout; it cannot require a previously acknowledged Sale. Proposed validation must freeze environment/device identity before funding and use route-specific transaction binding. Confirm the actual inbound authentication arrangement with Nayax before implementation; outbound Start credentials do not prove callback authentication. No provider call or financial-source implementation is authorized by this review.

No Supabase Realtime. Keep cached home/wallet content during background refresh. Payment status must be scoped to the payment/session, not merely the user. Poll only an active pending payment with a deadline and reconciliation/support outcome; a closed app must not prevent backend reconciliation.

## Acceptance

- Inclusive 48-hour boundary, delayed webhook/status reconciliation, promo-only spend, reversed failed vend, prior usage, multiple loads/reward thresholds, and Owner-only review.
- Spend/refund and duplicate-approval races; failed, pending, external, and ambiguous Stripe refunds; database failure after provider success; deletion during settlement.
- Invalid QR, disabled machine, changed quote, cancel/return, decline, timeout, refunded/support states, one charge/vend/refund maximum. Verify a physical washer and all six dryer choices separately from sandbox success.
- Follow [operations](operations.md) for exact test/environment gates. Recheck official [Stripe refund behavior](https://docs.stripe.com/refunds) and [refund fees](https://support.stripe.com/questions/understanding-fees-for-refunded-payments) before implementation.
