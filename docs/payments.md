# Payments and Refunds

Updated 2026-10-01 UTC, including dirty/untracked work. Historical observations below do not override the current hosted receipts in [operations](operations.md). Physical-machine behavior is not verified here. Active website is `CleanStreamWeb-CortinaQR`; shared backend lives in this app repository.

Current containment: `wakeDevice`, `ping-device`, `verifyPayment`, `changePassword`
and `resetToken` are now deployed credential-free denial handlers. Five empty
POSTs returned410/upgrade_required/no-store; gateway verification stays on. The
supported Cortina, payment status and native/web Auth flows remain unchanged.
This supersedes the legacy simulator's hosted-state observation below, but does
not reverse or settle payments previously initiated by old binaries.

Global wallet administration is approved for Owners only, not location Admins.
The integrated multi-Owner/backend batch reuses existing financial bodies and
adds canonical MFA/session checks, audited role changes and last-Owner guards;
43PG/96Deno cases pass locally. Keyset wallet reads retain integer cents and
reject duplicate/drifting data. Paired write/dialog caller binding passes96,
with clean affected analysis. The Owner migration and admin endpoint are now
installed in development with exact postflight/history; no actual role/balance
change or authenticated financial test occurred. Ledger-only cash redemption
remains bookkeeping, not a Stripe refund or authorization to issue one.

## October 5 Machine Remedies (Local Candidate)

`20261005135004_machine_issue_resolution.sql` and paired admin/Cortina code are
implemented, not deployed. Local machine/mail SQL, paired Edge/UI checks and
synthetic desktop/mobile rendering pass. Sponsored reporting is explicitly
checked for zero collection and zero additional wallet spend. New claims retain
their server receipt even when outside the same-day window, for manual review;
existing `legacy_14_day` receipts keep their prior workflow. The Owner confirmed
same-day reporting while at the location. Same-day resolution while the customer
is still washing is the operating target, not a guaranteed response deadline;
delayed staff response may still reconcile and approve a timely report afterward.
Eligibility uses the original location's verified timezone, never
the device timezone or a universal Indiana default.

The existing Owner-only Refunds page now offers the exact original paid/promo
wallet reversal after another load, or a same-location/same-value sponsored
replacement start when no replacement load has been completed. Staff attest to
on-site notification and the replacement-load circumstances; these are not
claimed as GPS-verified facts. Automatic remedies require a verified original
wallet debit. Card-funded, ambiguous and externally unsettled originals remain
manual review; this does not represent denial of statutory remedies.

The sponsored session uses `funding_source = machine_issue`, no second customer
charge/debit and one durable reservation. Replay cannot dispatch another Start;
unknown/failed outcomes and conflicting original reversals require support.
Only verified server Start confirmation completes the receipt, not physical
cycle completion. Superseded claims cannot also receive another refund.
The existing outbox sends definitive outcomes, never pending-success promises;
see [email](email.md). Deploy migration, admin, Cortina callback/reconciliation
and renderer as a coordinated batch, not the UI alone.

## Source and Units

- `supabase/migrations/20260526010000_wallet_ledger_compliance.sql` defines wallet loads, paid/promo ledger, balances, redemptions, and cash-redemption bookkeeping. `wallet_balances` is ledger-derived; `profiles.balance` is a dollar compatibility cache, not independent money truth.
- Wallet ledger/RPC and Cortina amounts, and Stripe API request amounts, use integer USD cents. Flutter `PaymentService.makePayment(double amount)` currently takes dollars; Stripe implementations convert at the Edge-request boundary. `Refunds.amount`, transaction history, `profiles.balance`, and `profiles.reward_tracker` use dollars. Preserve these boundaries and avoid double conversion.
- Each cumulative 2,000 paid cents currently earns 500 promo cents; reward progress crosses loads. Machine spending consumes promo first. Refunding a load cannot simply delete its row or subtract only a guessed bonus.

## Admin Collections and Device Activity

Source inspection on 2026-09-30, not a deployed-data reconciliation:

- `portal_dataset('transactions')` combines Cortina app/web sessions with unlinked legacy history. A linked legacy transaction is excluded from the second branch, so the session and its ledger row are not two list entries. It labels `card`/`wallet` and app/web, but does not expose an independent direct-Nayax-reader sales feed.
- Cortina sessions retain Stripe intent/checkout/charge references and Nayax transaction/RRN references. The Nayax callback locates an existing Clean Stream session; it is not an importer for all terminal card taps.
- The overview reads `transactions`, not all Stripe settlements or `wallet_loads`. Its exact-description exclusions miss newer `Loyalty payment on Washer - <name>` rows; original amounts also survive late void/refund status updates. Treat these as reporting defects, not evidence of duplicated provider charges or customer loss.
- Required model: collection processor, entry channel, vend provider, stable provider IDs, environment, gross/refunded/net collection amounts and reconciliation state. Stripe collection plus Nayax vend is one collection with linked operational evidence. Direct Nayax collection is separate only when supported by verified provider data. Unknown historical provenance remains explicitly unattributed.
- Keep wallet funding and redemption separate: funding is cash collected, redemption consumes an existing balance, promotional credit is not cash collected. Machine activity totals are a separate operational measure, not a sum added to collection totals. Refund/void outcomes must reconcile without deleting original history.
- Before enabling direct-device reporting, verify the authorized Nayax export/API, fees/quotas and environment. Use idempotent imports, stable IDs and explicit correlation; no amount/time-only deduplication, Supabase Realtime or assumed zero totals when the feed is unavailable.
- September 30 read-only live verification: Nayax DEV reported three USD 4.00 vends; all matched existing Cortina sessions by transaction ID and RRN (two app wallet spends, one Stripe web payment). They are not extra Nayax collections. No direct reader card sample or transaction API entitlement was verified. [Evidence and unsent access request](../NAYAX_AVAILABILITY_RESEARCH.md#access-and-reporting-check---september-30).

## Existing Financial Safeguards
- `stripeWebhook/logic.ts` and `paymentIntentStatus/logic.ts` both reach `record_wallet_load_from_stripe`; the latter verifies payment ownership and successful status. Preserve shared idempotency across both paths.
- The shared status writer now also requires received positive integer USD cents equal to requested cents and exact amount metadata, matching wallet purpose/user and a boolean provider mode. Missing received funds never fall back to requested funds; the endpoint rejects a different returned intent ID. Independent 98 focused/affected checks pass. Existing provider status and retry behavior remain; invalid evidence returns `walletLoadRecorded:false`, not a fictional credit. Both modes remain supported, so this is not separate deployment-environment enforcement.
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
| Failed card vend | Local repair marks `refunded` only for a successful refund matching principal, currency and PaymentIntent; other results retain the provider ID and `support_required`. A bound ID is retrieved, never replaced with another create. Independent 67 callback/orchestration checks pass; durable scheduled/webhook reconciliation remains open. Deployed behavior is unchanged. |
| Failed wallet vend | Reverses the original paid/promo split and marks redemption void; spend history remains |
| Legal cash/redemption bookkeeping | `admin_record_legal_cash_redemption` records negative paid ledger entries; an optional Stripe reference does not issue a payout |
| Voluntary unused-topup refund | Backend and customer/Owner interfaces integrated locally. External-replacement reservation bug is fixed and independently accepted (131 Deno; unchanged 54 PostgreSQL evidence retained). Owner/reporting QA also passed. Hosted/provider verification and operational controls remain; not deployed or activated. |

Flutter `lib/services/supabase/supabase_admin_wallet_service.dart` currently passes a null Stripe refund reference. Do not label that as an implemented cash refund. Existing machine-claim history uses a 14-day request window, not the proposed 48-hour top-up window. Local admin portal resolution adds location scope; do not discard that work.

The customer machine-claim controller preserves a saved request when notification/profile lookup fails, rejects duplicate in-flight submission and missing receipts, and keeps transaction labels paired with IDs when filtering top-ups. Notification uses the captured account and skips a late account switch. The service now replaces three legacy client writes with `request_legacy_loyalty_credit`: the server checks current admission, ownership, stored amount and the 14-day legacy window, atomically records the pending claim, and returns the same receipt on valid replay. Historical legacy rows are not independent proof of payment. Backend 66 runner checks and 19 paired service tests pass locally; old direct-write clients still need coordinated retirement. This is a manual machine claim, not a voluntary top-up refund or Stripe payout.

`refund-email` now enqueues a server-derived alert for the owned pending claim through the existing mail outbox. Permanent event deduplication and verified Owner selection replace caller-supplied amounts/recipients and emailed approval links. Notification failure cannot undo a saved claim; queued does not mean delivered. See [email](email.md); sender/settings and production activation remain gated.

App legal/load copy currently says final sale except legally required remedies. Website copy differs. Do not publish the new policy as available before the workflow works across app, backend, admin, and public terms.

Related machine-claim hardening is integrated locally in `20260930223814_cortina_claim_admission.sql`: Cortina claims require canonical Home admission before work, after the existing session lock and after trigger/counter waits. The original 14-day machine-claim window, server amount and idempotent replay remain unchanged. Direct client INSERT into `transactions` and `Refunds` is revoked at table and column level, with inherited-grant checks and restrictive policies. Trusted service/definer settlement and claim writers remain. Independent QA passes 31 PostgreSQL cases, including wait races and preserved refund exceptions. This is not hosted yet; it requires the accepted legacy atomic-claim migration first and intentionally rejects unsupported old direct-write clients.

## Approved Top-Up Contract

Implemented locally with the verification limits above; not deployed or promised as available in published policy.

- Eligibility uses server-recorded request time and authoritative successful-payment time: `0 <= requested_at - payment_succeeded_at <= 48 hours`. Owner review may occur later. Load insertion time is not necessarily payment-success time.
- Any wallet spending after the top-up disqualifies it, including promo-only spend and a failed vend later fully reversed. Earlier account usage is allowed. Restored balance does not erase usage history.
- Owner-only review/approval is enforced server-side. Refund full paid principal to the original payment method; Clean Stream absorbs original processing fees. No partial voluntary refund initially and no cash value for promo credit.
- Unwind attributable bonus/reward progress, including cumulative thresholds and subsequent loads. Keep statutory remedies, machine claims, and failed-vend compensation distinct.
- Atomically validate eligibility and reserve paid credit plus required reward unwind before provider payout. Every debit path must honor the reservation; a per-vend session lock is not a wallet-wide lock.
- Persist a single auditable business operation/policy version with stable provider idempotency and pending/success/failure/unknown reconciliation. Do not mark pending provider refunds completed, release an uncertain reservation, or blindly retry a possible payout.
- Handle duplicate requests/approvals/webhooks, out-of-order updates, external refunds, and provider success followed by database failure. Preserve completed financial history on account deletion; see [Supabase](supabase.md).

## Vend and Refresh Boundaries

**October 14 owner direction:** combine Stripe reporting and Nayax reporting or
exports to build the financial picture even if Nayax's API is incomplete. Match
periods, currencies, source coverage and verified identifiers before calculating
residuals; retain unexplained differences explicitly. Stripe-funded vends and
wallet redemptions are not additional Nayax collections. Wallet funding is a
collection while later spending consumes that stored value. Per-location banking
and cross-location loyalty allocation are deferred and outside active scope.

Server owns quote/pricing, device mapping, washer settings, six dryer choices, and payment/vend authorization. Check exactly one Start request and strict transaction, terminal, amount, currency, and environment matching. Verify callback authentication; missing configuration must not silently authorize callbacks.

**October 19 verification:** all four physical-reader Lynx GETs and four account
diagnostics return 200 using the existing token. Pulse supplies no vend-failure feedback; SaleEnd therefore
does not independently prove that a washer physically started or finished.
Review customer success wording as well as internal `started` state semantics.
Last Sales appears only after Nayax receives our SaleEnd response, so an absent
row during callback problems cannot prove failure or authorize a refund,
reversal or repeated Start. Actual October19 traffic establishes HTTP Basic authentication. Our
saved-source username transfer error was corrected, then Basic pair parsing was
added. At21:48:36UTC session `f46dad1b-dc66-457d-984f-4306f6c2959c` completed the
$8 sandbox provider flow with one Start, authenticated Sale and SaleEnd, status
`started`, and browser confirmation. Unknown earlier sessions remain intact.
Production credentials remain absent and activation remains off.

`_shared/cortina_callback.ts` checks the routed environment's exact
`NAYAX_{SANDBOX|PRODUCTION}_CALLBACK_USERNAME` and `_PASSWORD` before body/effects.
HTTP Basic is accepted only when both separate headers are absent; partial/wrong
explicit headers cannot be repaired by Basic. Either configured pair field makes
both mandatory and prevents legacy-token fallback. Only neither configured
retains the required legacy token. No credential values are logged.

Observed Pulse SaleEnd omits BasicInfo amount/currency and sends AuthAmount=0,
SettAmount=8. SettAmount is the original Sale/Settlement amount in the
[provider contract](https://devzone.nayax.com/docs/cortina/sale-end-notification);
the documentation nevertheless marks BasicInfo money required, unlike actual
traffic. The narrow compatibility path requires matching exact settlement cents,
an approved/started session with bound provider ID, and its scoped authenticated
Sale audit with matching transaction/environment/device/amount/currency. It
recovers only absent BasicInfo money; present conflicts are rejected. The audit
records `MoneyValidation` provenance. Existing SQL money/ownership/state guards
and closed-state behavior are unchanged. No schema migration or money mutation
was needed. Temporary diagnostic logging was removed after observing the shape.

237 focused tests and both entrypoint typechecks pass. Sandbox v68 and the
production-route adapter v64 in the development project are byte-verified;
production's unauthenticated invalid-body probe is denied. The existing unsent
Cortina reply requests only production credentials and routing confirmation.
Routing/device/selector/environment remain frozen before
funding under configuration/pricing locks; washer price and all six dryer choices
are server-checked. Card confirmation retrieves the exact Stripe
intent/Checkout/charge and verifies principal, currency, mode and metadata.
Funding audit and state recording are atomic. Missing historical snapshots stay
support-required, never guessed or backfilled.

Callbacks now check frozen environment, application transaction, exact amount/currency and any supplied terminal. A new environment/provider-ID unique guard and audit-insert trigger atomically bind the provider ID without leaving a losing audit. All three historical callback kinds reserve their existing owner, including audit-only partial writes and unknown historical environments; a new callback cannot take that evidence. Duplicate evidence must match and Sale rechecks current state after awaited work. Provider failures and recorded terminal states are not optimistic financial success.

Verification is layered, not cumulative: original binding44 PGlite/167 Deno; correction114 Deno including the unchanged independent3; ownership37 checked by author/QA; final historical correction6 and independent2 pass. The prior failed historical regression is closed. The read-only closed-app reconciliation worker is now integrated locally: SQL33, helper48 and final entrypoint20 checks pass. One row per invocation, leases and stored environment/binding evidence protect observations; it never issues Start, charges or refunds. Backoff is capped at six hours, not a finite lifetime retry count. It is disabled by default and requires a dedicated worker bearer and explicit environment; scheduling, gateway/quota review and production activation remain open.

Uncertain-outcome compensation is now corrected locally in the existing helper: 122 focused Deno cases (75 existing, 47 new) pass with typechecking and independent source acceptance. A client timeout, transport failure, unknown response or historical `failed` label cannot authorize a new refund/reversal or second Start. Proven unsent attempts, documented definitive rejections and authenticated Void retain automatic compensation; a bound card refund remains retrieval-only. Callback state/provider binding wins over delayed Start responses. The existing route still writes `timed_out` before calling the helper, so a crash can leave that intermediate state for reconciliation. This is not hosted/provider/device proof. [Nayax Start](https://devzone.nayax.com/docs/cortina/staticqr/static-qr-start) and [Void](https://devzone.nayax.com/docs/cortina/staticqr/static-qr-void) contracts were checked by the author.

Activation requires a current data preflight and coordinated callback/migration rollout. The ownership migration takes table-write locks and rejects old unscoped callback inserts. It is not an online-compatible standalone change; old callback code cannot be restored alone while that trigger remains. Preserve pending settlement and audit evidence, rehearse rollback, and obtain deployment approval. No provider or production operation occurred in these local checks.

The exact four-source post-C/D assembly is now locally accepted (new child plus parent2, exit0/6c6ee7): frozen binding, provider ownership, immutable return version and capacity. It reuses the existing database fixture and proves rollback/preserved history, NULL historical routing/version1, one fresh idempotent card audit, callback binding and service-only capacity. Source hashes and paired callback/webhook/vend order are in `.campaign-work/payments/rollout-current/HANDOFF.md`. Deploy the accepted web return reader before the version-2 vend writer. Reconciliation remains separate because its migration queues historical unresolved records; no hosted/provider/return-fragment validation is implied by this local receipt.

Provider compatibility matters: Nayax's [Sale example](https://devzone.nayax.com/docs/cortina/staticqr/static-qr-sale) has an empty terminal ID but a hardware serial; those identifiers are not automatically interchangeable. [SaleEndNotification](https://devzone.nayax.com/docs/cortina/sale-end-notification) documents transaction/currency fields, not a device object, so requiring a terminal on every callback would reject valid payloads. [Void](https://devzone.nayax.com/docs/cortina/staticqr/static-qr-void) can follow a Sale-response timeout; it cannot require a previously acknowledged Sale. The local binding follows these distinctions; confirm actual inbound authentication and deployment-specific provider identifiers before rollout. Outbound Start credentials do not prove callback authentication.

No Supabase Realtime. Keep cached home/wallet content during background refresh. Payment status must be scoped to the payment/session, not merely the user. Poll only an active pending payment with a deadline and reconciliation/support outcome; a closed app must not prevent backend reconciliation.

## Acceptance

### Local Pending Recovery

Flutter persists unresolved Cortina requests before dispatch using a small dedicated
`CortinaPendingStore`, the existing controller and `flutter_secure_storage: 11.2.0`.
Scope includes project, account and server-quoted machine. Original request IDs and
references are bearer capabilities; they are never logged or put in ordinary
preferences. Android excludes only the plugin's data/key files from backup; iOS
uses device-only Keychain access with no added biometric prompt. Failed readback,
invalid data or uncertain cleanup keeps checkout locked.

Reopening a machine page resumes bounded status observation, never payment
creation, confirmation or Start. A lost creation response can use the existing
status endpoint's read-only owner/request lookup: verified human bearer, exact
machine/request/owner/hash binding, no guest fallback. A missing row is not proof
that payment was unsent and does not unlock another attempt. Account changes,
including A-to-B-to-A, discard stale UI continuation. Guest unresolved requests
without a saved session remain support-only. No cross-device atomicity or
survival of app-data deletion/reinstallation is claimed.

Checkout's initial Auth replay is accepted only for the exact captured, still-
current Session; subsequent sign-ins (including same-user replacements), recovery
and sign-out still invalidate it. Nine real-SDK/fake-HTTP cases cover that boundary.
Actual Android16KB file-camera scanning now opens the hosted washer quote twice
in the rebuilt release, without payment. Source, builds and independent native
evidence review: `.campaign-work/native-scanner-20261002/`. This is not provider
payment success or physical/iOS camera acceptance.

Independent local evidence: corrected secure-store/controller/widget suite89;
then lookup53 Deno with typecheck and affected Flutter50 (49 retained plus one
corrected SDK exception assertion). Counts overlap and are not cumulative.
Current full native release builds pass. The unchanged store now also passes six
native phases on Android16/16KB and iOS26.2 Simulator: attached-record recovery
across three actual process restarts, scope isolation and persistent scoped clear.
Evidence: `.campaign-work/pending-native-probe-20261001/RESULTS.md`. These isolated
checks do not prove full hosted recovery, claim-only restart, crash-during-write,
backup/restore or physical-device security. A prior widget fake-async queue hang
was fixed by releasing the idle serialization future; it was not a demonstrated
ordinary customer refund failure. Current deployment state is in operations.

### Release Checks

- Inclusive 48-hour boundary, delayed webhook/status reconciliation, promo-only spend, reversed failed vend, prior usage, multiple loads/reward thresholds, and Owner-only review.
- Spend/refund and duplicate-approval races; failed, pending, external, and ambiguous Stripe refunds; database failure after provider success; deletion during settlement.
- Invalid QR, disabled machine, changed quote, cancel/return, decline, timeout, refunded/support states, one charge/vend/refund maximum. Verify a physical washer and all six dryer choices separately from sandbox success.
- Follow [operations](operations.md) for exact test/environment gates. Recheck official [Stripe refund behavior](https://docs.stripe.com/refunds) and [refund fees](https://support.stripe.com/questions/understanding-fees-for-refunded-payments) before implementation.
