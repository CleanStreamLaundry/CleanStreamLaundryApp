# Retention Schedule and Implementation State

Updated October 5, 2026 from the confirmed release handoff. Business implementation reference, not legal advice, a compliance guarantee or authority to enable deletion/purge jobs. This document does not activate any hosted setting.

## Latest Owner Direction: October 5

The Owner now expressly requires purchased/promotional credit and unissued reward
progress to be forfeited upon voluntary deletion if the account is not explicitly
restored before the 90-day recovery deadline, except where law prohibits it.
Credit purchases are restricted-use laundry prepayments, not deposits or cash
withdrawals. Deletion grants no new refund right. Existing 48-hour unused-load
refunds, timely machine claims, payment corrections and dispute rights remain.
The current published policy is `2026-10-05.2`, with 90-day recovery and deletion
consent available through `request_account_deletion_with_consent`. Terms, Privacy
and Account Deletion pages are published at cleanstreamlaundry.com with an
October 5, 2026 effective date. See [loyalty terms](loyalty-terms.md).

Daily cleanup is enabled under the approved prospective 90-day policy;
past acceptances are not applied retroactively, and holds remain preserved.
Activation SQL exited 0; remote readback confirms execution/surrender enabled,
the daily Cron active, and zero pending requests/external cleanup operations.
No actual customer deletion or provider-erasure test was performed. This does
not establish legal enforceability or completed erasure. The older
preservation contract and rollout notes below are historical where superseded;
their policy versions, hashes and local-only statements are not current release
instructions. See [operations](operations.md) for Composer's release receipt.

## Existing Implementation Context
Scope: iOS and Android mobile apps only; no Flutter web release now. Existing public website, web checkout and admin remain in scope for their collected data.
Reuse [account lifecycle](supabase.md), [recovery contract](account-recovery.md), [email](email.md) and [operations](operations.md). These references describe existing contracts, not proof of cleanup activation.
Existing recovery contracts/local acceptance do not establish permanent cleanup. Older published seven-year financial/two-year support wording is not approval of this schedule.

## Hosted Setup Status

Confirmed October 5 release: all seven migrations through `20261005181711` are
applied, current policy is `2026-10-05.2`, recovery is 90 days, and the deletion
consent RPC is available. Automatic-inventory migration `20261005183040` is also
applied after a rolled-back hosted rehearsal and QA 9/9 records (four install,
four behavior, one parent); the one Deno check is retained. All 13 release
functions are deployed, including cleanup v2 with its final worker hash already
verified by readback. Daily cleanup activation SQL exited 0; final remote
readback confirms the schedule and execution/surrender controls enabled. The
signed Android APK is ready after a successful build; Samsung
installation and device tests are explicitly deferred by the user. These are
supplied release facts, not new runtime or provider tests in this docs update.

Historical October 2 receipt: the four scoped migrations listed below are deployed to Clean Stream
`dnuuhupoxjtwqzaqylvb`; retained financial references report ready. Worker v1,
the matching dedicated Vault/Edge credential and the dormant daily scheduler are
installed. Execution and credit forfeiture remain false; Cron is inactive.
The new terms are published as version `2026-10-02.1` and displayed by the
updated Samsung build. No account was permanently deleted during setup.
Hosted Auth/Storage behavior and truthful per-request inventory/hold/processor/
backup evidence remain before operational purge. This supersedes historical
local-only setup descriptions, not the documented execution prerequisites.

## Historical October 2 Preservation Contract

On October 2, 2026, the Owner explicitly approved the per-class schedule below
as the business implementation policy, with the stated legal/processor exceptions.
Do not request this business approval again. Approval does not establish legal
classification or certify compliance. The irreversible executor remains unactivated;
implementation follow-through is agent work, not a pending Owner decision.
This October 2 preservation decision superseded earlier forfeiture instructions
at that time. Its no-forfeiture provisions are superseded by the published
October 5 policy above; the following preserves the earlier decision record,
not current publication or activation instructions.

- Recovery lasts exactly 90 days from each new accepted request. Existing pending,
  non-purged accounts receive at least request date + 90 days, preserving any later
  existing deadline; completed purges are never resurrected. Store deadlines in
  UTC and display the exact deadline with the customer's local timezone.
- Run eligible cleanup daily after expiry, targeting completion within seven
  days; apply any shorter mandatory deadline. Delete identity/profile/photos
  without erasing needed settlement or claim records.
- An Owner is the retention/hold custodian. Holds name the affected records,
  purpose and next quarterly review; they do not preserve an entire usable account.
- Use the existing schedule's tax clocks, not years since account deletion.
  If a required date or disposition is unknown, hold only the affected records
  for Owner/accountant resolution. Missing dates do not restart known clocks.
- Purchased credit never automatically expires or is forfeited, including after
  voluntary account deletion. Retain minimal ownership and ledger records until
  it is used, refunded or legally remitted; tax/cleanup retention windows cannot
  erase outstanding principal or its claim linkage. Do not retain ordinary login
  credentials/profile solely because credit remains. Free promotional credits
  and reward progress cancel at final deletion, not merely at the deadline.
  Pending payments, reversals, disputes and timely refunds remain preserved.
- Provider deletion/backup verification is agent work. Disclose verified limits;
  do not promise a universal 90-day erasure deadline when a provider cannot meet it.

Email scope is separate from retention approval. October 2: the Owner has excluded
promotional email and will not provide a mailing address. Do not ask again, invent
one or buy a mailbox. Necessary transactional messages remain enabled; rare
opted-in informational messages must be classified by their actual content.
Preserve existing consent/withdrawal evidence without silently broadening consent.

## Historical Recovery and Balance Policy

- Let D be the verified server-accepted deletion-request timestamp and E the server deadline D + 90 days for new requests, displayed with timezone. For existing pending, non-purged requests, use the later of the existing deadline and D + 90 days, not migration time + 90 days. Approved disposal target: next daily job after E, completed within seven days unless a documented exception or shorter legal deadline applies; this is not current behavior.
- Before E, explicit verified restoration restores the original account and wallet links. Login alone does not restore; restoration does not reset a refund clock or resubscribe newsletters. Preserve current fresh-session/admission checks.
- After E, restoration is rejected even if cleanup is delayed. Delete Auth/login and the ordinary profile through the existing fenced cleanup; outstanding paid credit is not an identity-retention blocker. Keep its minimal restricted liability/ownership record, with no automatic expiry, forfeiture, re-registration transfer or historical money rewrite.
- Deletion acknowledgement must distinguish the 90-day explicit account restoration deadline from continuing paid-credit ownership. Signing in alone does not cancel deletion. Free promo/reward progress cancel at final deletion; paid credit and unresolved financial obligations survive. Show the server-set deadline and timezone on the recovery screen. No waiver of mandatory rights and no new general refund promise.
- The retention policy is not an authorization to write off paid balances, even after a tax record minimum or cleanup-metadata window passes. Retain necessary claimant mapping until the paid obligation is discharged by use, refund or lawful remittance, and longer only where the remaining record-class obligations require it.
- Existing voluntary-refund draft stays separate: full paid principal requested at the server within 48 hours inclusive of payment success; no wallet spend since that load, including bonus spend or reversed failed vend; later Owner review, original payment method, no partial refund or bonus cash, statutory rights preserved.

## Approved Per-Class Schedule

The schedule below retains the October 2 record. Its paid-credit preservation
wording is historical and superseded by `2026-10-05.2`; it is not the current
balance policy or evidence that cleanup is active.

All periods below are approved business operational limits, subject to the stated legal/processor exceptions; none is a deployed cleanup promise. Delete sooner when no purpose remains, subject to documented obligations.

| Data class | Approved clock and disposition | Required confirmation / exception |
| --- | --- | --- |
| Auth, profile and account links | Restrict ordinary access at D; retain only restoration-needed identity/profile until E. At finalization remove Auth credentials/factors, profile and redundant identifiers; retain only separately justified financial/hold mappings. | Backend must prove access revocation, processor deletion and no settlement cascade. A financial hold does not automatically justify retaining login credentials. |
| Profile photos | Restrict access at D; delete original, thumbnails and orphaned copies at finalization. | Verify storage/CDN deletion, not just database reference removal. |
| Device/push tokens | Disable use at D; delete server tokens within 24 hours. Re-register explicitly on a restored device. Remove invalid tokens when detected. | Approved target behavior, not an assertion about current cleanup. Do not retain usable tokens for accounting. |
| Financial ledger, settlement, receipts and refunds | Keep minimum transaction/provider references and necessary claimant mapping until paid credit is used, refunded or legally remitted and open payments/refunds/claims are resolved. No automatic paid-credit expiry or forfeiture, and no fixed-year ledger purge over these obligations. Approved policy tax floor: later of 3 years after applicable return filing (early filing treated as due date) and 3 years after Indiana final tax-payment due date, extended for applicable exceptions. Delete/anonymize unnecessary profile/contact fields at finalization. | Tax floors are not balance expiry or disposal authorization. Accountant assigns each record's tax year/clock and federal/state exceptions; counsel/processor confirms dispute, contract and unclaimed-property needs. Pseudonymous linked records remain personal data. |
| Routine security/access logs | 90 days from event; minimize IP/device identifiers and never store credentials/capabilities. | Documented incident evidence: retain until incident/claim closes plus 12 months, reviewed quarterly; counsel may set a different necessary period. Do not retain all routine logs under one incident hold. |
| Support and maintenance records | While open; after closure keep a de-identified operational summary for 12 months. At account finalization remove requester/contact/free-text identifiers unless needed for an unresolved case or documented claim. | Security, safety, insurance or refund evidence moves to its justified class/hold; ordinary support is not automatically a legal exception. |
| Support/maintenance attachments | Delete at the earlier of account finalization or 90 days after case closure, unless specific evidence is still necessary. | Preserve only scoped dispute/incident evidence; strip metadata where feasible. Delete object copies, not only links. |
| Newsletter consent evidence | Suppress marketing at D immediately. Retain minimal consent source/version/time and withdrawal evidence for 3 years after withdrawal/last marketing use, whichever is later; then delete unless justified. | Three years is an approved operational limit, not a CAN-SPAM prescribed term; counsel confirms evidence needs. Restore never reinstates consent. |
| Suppression list | Retain only address or compatible keyed matching identifier, reason and date while that address could otherwise be mailed; annual necessity review, delete when all relevant sender/import/replay sources are retired. | No fixed expiry that silently re-enables sending. Hard-bounce/complaint safeguards remain; keyed identifiers are not anonymous. Processor matching/deletion feasibility must be confirmed. |
| Email/outbox/provider events | Strip message bodies and unnecessary recipient payloads within 30 days of terminal delivery/failure; minimal event/dedup evidence 90 days. Financial/lifecycle evidence follows its own class. | Do not expire replay protection while a retry/callback can still act; backend must establish that window. Promotional email and the mailing-address request are excluded by the October 2 decision; support@cleanstreamlaundry.com is the approved controlled-test recipient. |
| Cleanup metadata | Keep minimal request ID, policy version, D/E, disposition/hold reference and completion results for 12 months after finalization; no photos, tokens or full profile payloads. | Preserve financial replay/claim linkage for its longer required period. Review whether subject mapping is still necessary; deletion receipts must not reconstruct the profile. |
| Backups and processor copies | Approved backup expiry target within 90 days after primary deletion, inaccessible to ordinary use; reapply deletion/suppression before any restored backup serves traffic. | Firebase documents up to180 days for installation-linked live/backup erasure after its deletion API; the 90-day target cannot be promised there. Analytics history is separate. Verify other provider schedules/contracts and disclose residual retention. Request processor deletion; no claim of instant physical erasure. |

## Authoritative Boundaries

- [IRS record guidance](https://www.irs.gov/businesses/small-businesses-self-employed/how-long-should-i-keep-records): usual income-tax support period is three years, with six-year, seven-year and indefinite exceptions; employment-tax records have a separate four-year minimum. These clocks are not measured from account deletion. Accountant must map actual records, not apply seven years to every class.
- [Indiana DOR legislative explanation of IC 6-8.1-5-4](https://www.in.gov/dor/files/legislative-synopsis-2019.pdf): at least three years after final tax-payment due date, with assessment/proceeding and other exceptions. This is an agency explanation of the amendment, not a fresh opinion on every current tax obligation; confirm applicable current law with the accountant. [Indiana private-business guidance](https://faqs.in.gov/hc/en-us/articles/360036013331-How-long-do-I-need-to-keep-the-records-of-my-private-business) warns against borrowing government retention schedules.
- [CFPB Regulation E, 1005.20](https://www.consumerfinance.gov/rules-policy/regulations/1005/20/): covered gift-card funds generally cannot expire before the applicable five-year minimum; reloadable/non-gift and promotional exclusions require classification. [Indiana holder FAQ](https://www.indianaunclaimed.gov/app/faq-report) says gift cards are exempt from unclaimed-property reporting; that does not establish that this paid wallet qualifies, or that balances may be forfeited. Counsel must apply [Indiana's actual property classifications](https://www.indianaunclaimed.gov/app/ucp-law).
- [Indiana AG CDPA guidance](https://www.in.gov/attorneygeneral/files/Consumer-Data-Bill-of-Rights.pdf): effective January 1, 2026, with applicability thresholds/exemptions; covered requests generally require a response within 45 days, with conditional extension. Counsel must assess applicability and other states, and whether the recovery delay is appropriate; the business's 90-day recovery window is not a legal safe harbor or an extension of a mandatory response/deletion deadline.
- [Apple deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) requires an in-app deletion initiation path, not merely deactivation, and disclosure of necessary retention. [Google Play guidance](https://support.google.com/googleplay/android-developer/answer/13327111) requires in-app and web request paths, associated-data deletion and transparency about legitimate retention. Mobile-only scope does not remove the public deletion resource requirement; neither store guarantees approval of this policy.
- [FTC CAN-SPAM guidance](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business) requires honoring marketing opt-outs within 10 business days and a valid physical postal address in commercial messages. Approved immediate suppression is stricter; consent/suppression periods above are not FTC-mandated durations. No sending readiness is inferred.

## Holds and Implementation Follow-Through

The published October 5 policy supersedes the earlier preservation direction.
Publication does not establish legal classification or enforceability. The
follow-through and setup notes below retain historical implementation context;
current cleanup work is limited to automatic-inventory SQL QA and activation,
as recorded above, without claiming completed provider tests.

Holds override disposal only for identified records and a documented purpose (tax audit, dispute, investigation, litigation/preservation duty). Record owner, authority, scope and review date; review quarterly, release promptly, then apply the original clock. Do not restart all retention periods or hold an entire account indefinitely. Preserve necessary settlement processing while blocking new ordinary wallet activity.

1. Counsel: classify paid principal, promo bonus and refunds under federal gift/prepaid rules and Indiana property law; identify required remedies, remittance and notices. Review the October 5 voluntary-deletion forfeiture clause without treating its business approval as legal clearance or waiving mandatory rights.
2. Accountant/counsel: approve exact tax clocks, exceptions, processor/insurance dispute windows and minimum retained claimant mapping; identify any required longer period by record class.
3. Agents: implement the October 2 approved operational durations, Owner hold-custodian requirement, D/E timezone and strict before-expiry restoration wording. Business approval is complete; do not reassign it to the user.
4. Backend/processor owners: confirm feasible deletion/backup/token schedules, retry/dedup windows and hold isolation; separately authorize and verify an executor only after approved terms, access guards and settlement safeguards. No cleanup activation is granted here.
5. Align iOS/Android disclosures and public policies with the approved schedule. The email-scope decision is resolved: no promotional campaigns or mailing-address request. The approved controlled-test recipient remains support@cleanstreamlaundry.com. No Flutter web hosting task is implied.

## Minimal Claim Path

Retain the existing `private.account_retained_subjects.user_id`, its wallet UUID,
paid/promo ledger split, load/provider references and unresolved refund records.
Do not add an email/name/profile snapshot or treat pseudonymous records as anonymous.
The financial retention reference identifies the restricted support/claim evidence;
it must survive the twelve-month cleanup-metadata expiry. No financial record purge
is implemented by this cleanup path, even when those records are very old.

After final deletion, contact support@cleanstreamlaundry.com with the original
payment receipt/reference (or wallet/old user UUID). The existing Owner wallet
search, `admin_wallet_read('search', {query: ...})`, finds wallet/user UUIDs and
Stripe PaymentIntent, Checkout Session or charge references without a profile
join. Its detail view retains loads and ledger evidence. A receipt/reference is
a lookup key, not authentication: the Owner must verify the claimant against the
original processor receipt/payment ownership and record the support case/evidence
reference before any remedy. Never collect full card numbers, passwords or tokens.

Use existing Owner-only, canonically authenticated/MFA-checked tools and existing
refund rules. Outstanding refund reconciliation continues against the original
subject/provider IDs. Legal-cash-redemption bookkeeping does not itself send money.
Any permitted manual use/refund/remittance needs verified authority and an explicit
audited entry; neither account deletion nor this migration creates broad refund
rights. Do not change old user IDs, transfer a wallet automatically to a new login,
restore deleted credentials, or infer ownership from a newly registered matching
email. Unproven ownership stays an unresolved claim, not forfeiture. A dedicated
self-service post-deletion claim UI or automatic rebinding is not implemented.

## Implementation Handoff - October 2

Historical pre-setup handoff below; its absent/uninstalled observations were
superseded by Hosted Setup Status. They are not fresh October 5 remote evidence.

Source authored and focused PG/Deno checks completed; no Flutter/build ran in this
lane. Nothing was deployed, executed against hosted data, or scheduled. Composer's read-only
hosted report found only `20261001140307` among migrations at/after
`20261001130137`; treat permanent cleanup and retained subjects as **not installed**.
Composer additionally confirmed `claim_account_cleanup(uuid,timestamptz,uuid)`
absent, Owner wallet lookup present, postgres Auth TRIGGER/REFERENCES and Storage
SELECT available, and no cleanup execution table, retained-subject table, executor
or `cleanstream_account_cleanup%` Vault names. Lifecycle exists. Hosted Edge worker
deployment is still unconfirmed; local source/config is not proof it exists there.

Install dependencies only after catalog/permissions preflight and focused QA, in
this order (do not use a broad pending-migrations push):

1. Existing foundation `20260930154911_account_cleanup_claims.sql`, with its
   lifecycle `20260930063923_recoverable_account_deletion.sql`, wallet/refund,
   canonical admission, newsletter/mail, push and support prerequisites. Confirm
   deployed versions rather than reapplying them. Claims do not delete accounts.
2. `20261001013709_owner_management.sql` and its existing canonical onboarding/staff
   prerequisites must already be installed for the Owner claim path. Its migration
   intentionally requires the deletion RPC ACL to remain held. This update does
   not regrant that ACL or change Owner permissions.
3. `20261001130137_permanent_account_cleanup.sql`: installs the disabled executor,
   private retained-subject/hold/inventory structures, scoped retention and Auth
   deletion fences. Installation does not dispatch deletion or seed approvals.
   It requires the actual Auth/Storage catalog and reviewed migration-role grants;
   do not add ownership/bypass privileges to force installation.
4. `20261001130950_retained_financial_subjects.sql`: projects existing referenced
   UUIDs, validates twelve replacement FKs before dropping the old ones, and moves
   financial references off Auth/profile cascades. It preserves amounts and ledger
   history. It takes table locks and changes the Maintenance primary key to its
   existing report ID while retaining `(user_id,created_at)` uniqueness. Unexpected
   FK/key dependencies must fail and roll back, never be dropped with CASCADE.
5. `20261002211306_bounded_deletion_preserve_paid_credit.sql`: requires the retained
   reference protocol and Owner wallet lookup; invalidates the old draft approval
   and leaves execution disabled. On fenced final Auth deletion it cancels free
   promo by a new paid-zero ledger entry, clears reward progress and marks the
   wallet deleted without dropping ownership/principal. It retains late paid
   funding and refund releases, with no new retired-account promo accrual. Active
   reward rates and refund eligibility are unchanged. No financial backfill/purge
   or bulk cleanup is executed during installation.

Current local policy identity: `retention-paid-credit-2026-10-05`; SHA-256
`0e63c08fc2b695533295635a4c2db4902898b639c902f6633430aa91d9b0ab04`.
The exact hash input is recorded in the new migration, not the mutable whole guide.
The worker, database and `supabase/ops/account-cleanup-setup.sql` now pin this same
identity. The setup script still creates only a dormant schedule and requires
database execution/forfeiture disabled; no activation behavior was changed.
Do not blindly reauthorize old in-flight dispatches under the new identity.
The October 5 candidate requires execution already disabled and refuses unresolved
destructive work before extending deadlines; its transaction invalidates earlier
approvals. Future authorized rollout must coordinate the migration, worker/settings,
dormant tick, legal/email copy and new descriptor. Existing users must explicitly
accept loyalty version `2026-10-05.1`; restoration never grants acceptance. No
blanket pending-migration push or remote publication is authorized by these notes.

Remaining gates: hosted Auth/Storage compatibility and owned-object deletion,
inventory/holds and processor backup evidence, actual Owner support verification,
policy/terms alignment and separately authorized scheduling. No guarantee of
bounded erasure is implied while those execution prerequisites remain unmet.

### Focused Validation Results

October 2, composer-assigned serial runtime slot: PG17.11 **54 child checks plus
one parent passed (55 reported), exit 0**; cached Deno **105 passed, 0 failed,
exit 0**, with typechecking. First PG attempt stopped after 39 passes at SQLSTATE
42601: a CASE expression inside the provenance IF needed parentheses. That exact
syntax correction is included; the second run above passed. No repeated audit.
All psql sessions exited, PG stopped and its disposable directory was removed.
Heavy slot released immediately after Deno exited. No hosted financial mutation.

```sh
cd /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp
PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --test scripts/account-cleanup-execution.test.mjs
DENO_DIR=/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/.deno-cache /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env=ACCOUNT_CLEANUP_ENABLED,ACCOUNT_CLEANUP_WORKER_SECRET,ACCOUNT_CLEANUP_EXECUTION_ENABLED,ACCOUNT_CLEANUP_POLICY_VERSION,ACCOUNT_CLEANUP_POLICY_SHA256,SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,CLEANSTREAM_CLEANUP_SECRET_KEY_NAME,SUPABASE_SECRET_KEYS supabase/functions/account-cleanup
```

The SQL suite reuses the catalog-matched disposable PostgreSQL harness; it retains
historical dependency tests, then installs the Owner prerequisites and new policy
for fifteen focused checks including exact function OID/owner/ACL preservation.
It tests century-old cleanup-metadata expiry with
outstanding paid credit and an unknown refund, Auth/profile removal with promo-only
cancellation, idempotency, late settlements/reversals, refund success/failure,
unchanged active rewards, Owner lookup/security, same-email non-rebinding and
restoration/funding races. Auth/profile/lifecycle are absent during successful Owner
lookup by payment reference, wallet UUID and old subject UUID. A rollback-only
test exercises actual Owner legal-redemption bookkeeping on the deleted wallet:
paid-only debit, actor/note attribution, old history unchanged, Admin/customer
denied, and no account restoration/rebinding. This does not simulate a payout.
The existing app Cash/Refund control calls that RPC with a null Stripe reference;
it does not issue a Stripe refund. Manual fulfillment/payment is an operator step,
not an automatic transfer or newly granted refund right. Explicit Owner adjustment
authority is unchanged. Composer owns combined Flutter/profile checks.

### Setup Versus User Work

Composer can complete already-authorized setup without asking for policy approval
or a new user-supplied credential:

1. Preflight the existing prerequisite catalog, then install only these four
   migrations in order: `20260930154911_account_cleanup_claims.sql`,
   `20261001130137_permanent_account_cleanup.sql`,
   `20261001130950_retained_financial_subjects.sql`,
   `20261002211306_bounded_deletion_preserve_paid_credit.sql`. Keep the existing
   deletion-request ACL hold unchanged. No executor, Auth-delete or financial
   mutation call belongs in this install. Do not bulk-push unrelated migrations.
2. Read the hosted function inventory/config; deploy the owned `account-cleanup`
   worker if absent/outdated. Retain dedicated-header authentication and the local
   `verify_jwt=false` gateway contract, and verify the deployed gateway. Keep
   `ACCOUNT_CLEANUP_ENABLED=false` and `ACCOUNT_CLEANUP_EXECUTION_ENABLED=false`
   during setup; configure the matching policy version/hash without enabling it.
3. Generate/configure the already-authorized dedicated worker credential through
   the protected operator path, without logging it. Configure its same value as
   Edge `ACCOUNT_CLEANUP_WORKER_SECRET` and Vault
   `cleanstream_account_cleanup_worker_secret`; Vault
   `cleanstream_account_cleanup_project_url` is
   `https://dnuuhupoxjtwqzaqylvb.supabase.co`. Use the approved existing server-key
   mechanism for the worker; no client key or guessed named-key fallback.
4. Verify existing Cron/pg_net/Vault availability and privileges, then run the
   dormant setup script. Missing extensions/Vault names, duplicate/conflicting
   jobs, enabled execution, wrong operator or unsafe tick ownership fail setup.
   The job stays inactive (`0 3 * * *`); an inactive job or disabled database
   execution makes the tick return NULL before decrypting credentials/HTTP.
   Wrong policy or invalid credential/URL fails closed. Creating dormant setup
   is distinct from activating deletion; do not invoke the executor this turn.

Before operational purge, the composer must verify hosted Auth/Storage behavior
and populate truthful per-request inventory references for holds, processors,
media, backups and financial retention. Missing inventory parks the request;
scoped identity/processor/media holds and unresolved external outcomes block the
affected disposition. Financial holds preserve money evidence without retaining
login. Request mismatch, restoration, unexpired recovery, stale lease or policy
drift blocks Auth deletion; paid balance alone does not. No fixed-year financial
purge exists. These are agent setup/verification tasks, not reasons to ask the
user to implement infrastructure or approve paid forfeiture again.

Only real-world facts/authority still require the Owner or their advisers when
applicable: claimant ownership proof and the actual permitted remedy/fulfillment,
truthful unresolved dispute/hold information, and legal/accounting classification
or required remittance that cannot be established from existing records. Existing
Owner identity is sufficient as custodian; no new claim UI or automatic identity
rebinding is required. Unverified claims remain preserved, not written off.
