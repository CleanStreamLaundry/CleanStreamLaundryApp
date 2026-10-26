# Clean Stream Legal Review
Revised October 5, 2026. Draft for user review only. Not approved, effective, or published.

## October 5 Revision

The reading copy below now matches the 90-day recovery, same-day machine-remedy,
prepaid-service, Apple sign-in and resolution-email edits in both applications.
The older verification and editorial history below describes October 4 only.
October 5 now has separate local app/web, SQL/Edge and new-admin-form acceptance
in `.campaign-work/review-followup-20261005/QA-RECEIPT.md`; neither receipt publishes
or legally approves the draft. Current legal
classification findings: [prepaid-credit research](prepaid-credit-law-review-20261005.md).
Latest Owner direction: voluntary deletion surrenders remaining credit at the
90-day recovery deadline, subject to nonwaivable law. The drafts now reflect
that rule and no general cash withdrawal or post-deletion refund right. Existing
48-hour refunds, timely machine claims and dispute procedures remain separate.
This copy revision does not change the ledger, active loyalty terms or cleanup
worker. Earlier verification receipts do not cover this latest wording.

## Composer Verification

Completed after the source handoff below:25 Flutter legal widget cases and
225 focused website cases passed across the legal/admin batch. The website's
8 desktop/mobile Playwright legal/role cases and production build also passed.
Legal screenshots show readable numbered sections, decoded logos, reachable
contact links and no content overlap. No native rebuild or hosted publication.

The `Redesign Clean Stream website` task copied these exact drafts into its
saved preview. Headless desktop1440px, mobile390px, and720px reflow inspections
passed for both documents, including last sections and support links.
Screenshots: `.campaign-work/legal-roles-20261004/` in the shared project root.
An artificial CSS-root zoom probe overflowed the redesign's existing header;
normal responsive reflow passed, not actual-browser zoom verification. The
redesign preview servers remain closed. Current React screenshots are in the
website's `test-results/legal-roles-*` directories.

Scoped admin TypeScript passes. Whole-site typecheck retains one unrelated
pre-existing test error: invalid Testing Library `exact` option in
`src/components/CortinaPayPage.test.tsx:96`. No Analytics runtime changed.

## Ready Handoff

The author's initial handoff was source-only; the Composer Verification above
records the subsequent checks. No Supabase publication, acceptance mutation,
Analytics setting change, deployment, or cleanup activation occurred.

Source freeze: composer-requested prose polish is complete. The two application copies and full reading copy use matching wording. Technical Analytics/control/cleanup details remain only in these editorial notes; financial and account-lifecycle safeguards are unchanged. Focused test assertions were updated but not executed. No further edits are planned in this lane.

The full Terms and Privacy drafts below match the copy embedded in both applications. The app uses its existing selectable LoyaltyPolicyText letterhead and section renderer with a separate draft constructor, not a fabricated publication descriptor or effective date. The loyalty page still reads and verifies its server-managed descriptor; acceptance behavior is untouched. The website uses its existing logo and legal-only selectors for modest typography. Neither deployment needs the sibling repository; no assets or pubspec wiring are needed.

Dirty files were read in place and preserved outside the assigned legal edits. Git's diff against HEAD includes pre-existing work and is not this lane's complete authorship record.

### Exact Files Changed

- [App draft text](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/lib/features/legal/legal_drafts.dart)
- [App legal renderer](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/lib/features/legal/legal_page.dart)
- [App focused tests](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/test/features/legal/legal_page_test.dart)
- [Website legal page and matching draft text](/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/src/components/PublicLegalPage.tsx)
- [Website focused tests](/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/src/components/PublicLegalPage.test.tsx)
- [Website stylesheet, new legal-document selectors only](/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/src/styles/PublicSite.css)
- [This review artifact](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/docs/legal-review-20261004.md)

### Source Basis

Read both repository AGENTS.md files; current legal pages and tests; app docs/loyalty-terms.md, docs/retention.md, docs/firebase.md and relevant theming/payment/email references; the original stored JSON in migration 20261002211015_server_managed_loyalty_terms.sql and the section-5 revision in 20261003111631_simplify_loyalty_payment_terms.sql. Local Google sign-in requests email/profile and authenticates with Supabase; the map uses tile.openstreetmap.org and external directions. These are source observations, not new hosted verification.

The October 5 instruction extends explicit restoration to 90 days. The latest Owner clarification replaces the earlier paid-credit-preservation proposal with voluntary-deletion forfeiture at that deadline, subject to nonwaivable law. No general cash redemption or refund right is created by deletion. The inclusive 48-hour unused-load policy, timely machine remedies and dispute procedures remain. The timeout-refund promise is corrected. There is no new reward formula, liability cap, arbitration requirement, age restriction, promotional-email program, or statutory retention mandate. The Owner confirmed same-day reporting while at the location, with same-day resolution as the operating target. A delayed staff response may still reconcile and approve a timely report afterward.

### Verification Queue

These were the initial queued commands; focused Flutter/web checks have now
completed as recorded above, using the pinned SDK and existing dependencies.

Source-only git diff --check completed with exit 0 in both repositories for the owned tracked files. This is whitespace evidence, not compilation, tests, or visual acceptance.

From the app root, using the composer-confirmed pinned Flutter executable:

```sh
FLUTTER_TOOL_ARGS=--old_gen_heap_size=512 flutter test test/features/legal/legal_page_test.dart
```

From the website root, serially:

```sh
npm test -- src/components/PublicLegalPage.test.tsx src/components/PublicLayout.test.tsx --maxWorkers=1 --no-file-parallelism
npm run typecheck
```

Before broader integration checks, composer must update the existing copy assertions in website src/App.public.test.tsx: the tests beginning at lines 38, 49 and 68 assert replaced paragraphs, old unnumbered headings, and excluded newsletter/mailing-address language. That broader, already-dirty integration file was not edited in this lane. Its account-deletion-resource assertions must remain scoped to that separate page. Then run:

```sh
npm test -- src/App.public.test.tsx --maxWorkers=1 --no-file-parallelism
```

App tests cover selectable full copy, explicit draft status, no acceptance control or policy fetch for static drafts, 320px large-text light/dark rendering, and unchanged server descriptor behavior. Website focused tests cover numbering, draft metadata, contact/deletion links, refund boundaries, post-deletion credit, provider roles, and truthful automatic Analytics disclosure. Authored tests are not passing evidence.

In the runtime slot, inspect app light/dark at normal and enlarged text and website mobile/desktop at normal and 200% zoom. Confirm selectable paragraphs, uncropped existing logos, modest heading hierarchy, no cards/hero, no overflow, and reachable last paragraph/resources. Verify source-copy parity again after any editorial change. No rendered-quality claim is made yet.

## Editorial Review Notes

These are review notes, not part of either policy.

### Analytics Clarification

The user's clarified purpose is operational reliability only, not general customer-behavior analysis, advertising, or profiling. Privacy sections 5 and 6 now state that limit, exclude customer identity, wallet/funds/payment information and support content from Analytics events, and preserve the disclosure of automatic Firebase identifiers, device/app information and events. Both app and website copies and this full reading copy were updated together. No runtime change is needed or made for this clarification.

Local evidence confirmed by the user and source reading: flutterfire_driver.dart logs only settings_opened and update_opened, with no event parameters, customer user ID, user properties or screen observer; its ad-storage, ad-user-data and ad-personalization consent flags are false. Android removes AD_ID/adservices permissions and disables advertising-ID collection and automatic screen reporting. iOS disables IDFV collection and automatic screen reporting; the Podfile selects Analytics without advertising-ID support.

Control and cleanup details retained for editorial review only: Analytics is automatically enabled when Firebase is configured, subject to platform restrictions and account-deletion privacy controls. There is no in-app Analytics switch or separate Analytics opt-in. Optional messaging choices are not an Analytics opt-out. Confirmed account deletion pauses Analytics and in-app messaging; pending privacy cleanup must complete before Analytics resumes. Disabling push or changing accounts starts token cleanup, which can require connectivity and retry. Remote Config operates independently of Analytics and optional messaging choices. These implementation details were removed from the customer-facing policy, not changed in code.

The precise remaining distinction is purpose versus collection: these two custom events describe navigation actions, not just faults, and Firebase's automatic identifiers/device/events still exist. No inspected custom event sends customer identity, funds, payment or support content, and no advertising-setting mismatch was found in the inspected local configuration. Do not describe the implementation as collecting only errors, collecting no user data, or being fully anonymous. This is not independent verification of hosted Analytics property settings or every SDK-emitted event. [Google Analytics data collection](https://support.google.com/analytics/answer/11593727?hl=en), [Firebase collection configuration](https://firebase.google.com/docs/analytics/android/configure-data-collection).

### Decisions Before Approval

1. **Apple usage-data consent remains unresolved.** The current app automatically enables Analytics and has no in-app Analytics switch or separate opt-in. The policy discloses automatic collection; control and consent details are recorded here for editorial review. This lane does not change them or claim compliance. Apple App Review Guideline 5.1.1(ii) requires consent for collection of user or usage data and an accessible way to withdraw it. Resolve the app's collection/consent design and store disclosures in a separately authorized implementation before claiming Apple readiness. This is distinct from whether App Tracking Transparency applies. [Apple guidelines](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
2. **Minimum age remains an owner/counsel decision.** The former adults/under-13 sentence was not an established eligibility decision. No new minimum age, parental-consent mechanism, or assertion about children's data was invented. Decide the actual audience and necessary safeguards before approval.
3. **Retention implementation is not a deletion guarantee.** The approved business policy is not being reopened. The retention reference describes dormant execution and outstanding provider/backup/hold verification. Confirm operational readiness and actual provider schedules before making any bounded-erasure promise. The draft intentionally gives no universal 90-day backup guarantee and does not convert financial retention floors into paid-credit expiry.
4. **Legal applicability remains for qualified review.** Confirm governing law, applicable privacy-request rights and appeals, wallet classification, any mandatory redemption/remittance obligations, and record-class exceptions for the actual business. Conditional wording does not assert a statutory obligation or blanket deadline. Section 10 uses balanced responsibility language rather than the earlier blanket consequential-loss exclusion; no fixed cap or new waiver is introduced.
5. **Publication is separate.** The user must review and approve wording before any effective date or release. Keep current Supabase loyalty version and customer acceptances unchanged. Reconcile any final editorial change with the immutable published Loyalty Program Terms before separately authorized publication.
6. **Provider disclosures must stay factual.** Google/Firebase identifiers are not described as anonymous, and optional messaging is not presented as Analytics consent. Confirm actual hosted data settings and provider agreements during release review; this document does not certify them. [Firebase privacy information](https://firebase.google.com/support/privacy), [Analytics data collection](https://support.google.com/analytics/answer/11593727?hl=en).

---

# Terms of Service

Draft for user review | Revised October 5, 2026 | Not approved or effective

This document is a draft for review. It does not replace current terms or policies, require new acceptance, or change your existing rights.

## 1. About these terms

These terms describe use of the websites, mobile applications, payments, wallet, and connected laundry services provided by Clean Stream Laundry Solutions LLC (Clean Stream, we, us, or our). References to you mean the person using those services.

Prices and purchase details are shown before payment. Posted facility and machine instructions also apply to use of the equipment. The separately presented Loyalty Program Terms govern the wallet and rewards; the wallet provisions below are intended to reflect those terms, not replace the version you accepted.

## 2. Accounts and responsible use

Provide accurate account information, use only accounts and payment methods you are authorized to use, and protect your sign-in credentials. Tell us promptly if you suspect unauthorized access or an incorrect charge.

Follow posted machine instructions and facility rules. Do not misuse equipment, interfere with the service, bypass security or payment controls, manipulate rewards, or submit fraudulent claims. We may restrict access to address misuse or security concerns. A restriction does not automatically confiscate purchased credit or eliminate valid refund or claim rights.

## 3. Purchases and machine operation

Submitting a payment authorizes the displayed charge using your selected card or wallet. Washer charges relate to the selected machine and service; dryer purchases add the time shown before payment. Check the location, machine, amount, and selected service before confirming.

Stripe processes card payments and refunds made through the Clean Stream app and website. Nayax supports payments at participating machines and helps start connected washers and dryers. Clean Stream remains your contact for laundry-service, payment, and wallet issues. The original payment method and processor determine the available refund route.

Payment confirmation and machine-start confirmation are different. An unconfirmed or timed-out request does not by itself establish that the payment or machine start failed, or that a refund is due. We reconcile available payment and machine records to determine the outcome. Check the machine and payment status and contact support before paying again when the outcome is unclear.

For a confirmed failed or voided vend with a collected payment or wallet debit, we arrange the applicable card refund or wallet reversal. A pending refund or reversal is not proof it has completed. Processing and bank posting times can vary.

## 4. Purchased wallet credit

Loading your wallet is a purchase of prepaid laundry-service credit for use only at participating Clean Stream-operated locations in Indiana. It is not a deposit into a bank or savings account, does not earn interest, and is not available for cash withdrawal. Credit cannot be gifted, transferred to another customer, or used outside Clean Stream. Purchases are nonrefundable except under the refund and claim policies in sections 6 and 7 or where required by law.

Credit does not expire solely through inactivity and carries no inactivity fee. Voluntary account deletion results in forfeiture after the 90-day recovery period as described in section 9, except where applicable law prohibits forfeiture. Purchased and promotional credit are tracked separately. Neither deletion nor restoration creates a right to withdraw the balance or receive a refund outside the policies below.

## 5. Promotional rewards

The applicable reward offer is displayed when you load your wallet. Promotional credit has no cash value and is applied before purchased credit when paying from the wallet. Spending credit does not earn the load reward again.

Refunding a load reverses promotional credit and reward progress attributable to that load. Unrelated earlier rewards are not canceled merely because a later load is refunded. Remaining promotional credit and unissued reward progress are forfeited with the account balance under section 9.

## 6. Voluntary refunds of unused wallet loads

You may request a voluntary refund of the full paid principal of a wallet load if our server receives the request no later than 48 hours after successful funding, including exactly 48 hours. Eligibility uses the server-recorded successful-payment and request times.

No wallet spending may have occurred after that load. Spending only promotional credit or a failed machine vend that was later reversed still disqualifies that load from this voluntary refund. Earlier wallet use does not disqualify a later load.

An Owner reviews timely requests and may approve them after the 48-hour deadline. Approved refunds return the full paid principal to the original payment method; Clean Stream absorbs the original processing fees. Partial voluntary refunds and cash refunds of promotional credit are not offered. Associated bonus credit and reward progress are reversed as described in section 5.

Deleting or restoring an account does not restart or extend the refund window. These voluntary conditions do not limit rights required by law or replace remedies for machine failures, duplicate charges, or other payment errors.

## 7. Machine and payment claims

For our same-day machine-failure remedy, notify us through the app, on-site staff, or support@cleanstreamlaundry.com while you are at the affected location and on the same calendar day as the affected use, measured in that location's local time. Include the location, machine, approximate time, payment reference, and problem. We aim to respond and resolve eligible issues that same day while you are still doing your laundry, subject to staff availability. If our response is delayed, we may review, reconcile, and approve a timely report afterward. Our delay does not make your report late.

For an approved same-day machine-failure claim, if you have already completed another load to replace the affected service, we credit the affected service amount to your wallet. Otherwise, we arrange an available replacement machine at the same location for the same amount, without an additional charge. Staff verify the circumstances and record the remedy. If a suitable machine or immediate remedy is unavailable, the claim remains open for support review.

Machine-failure claims, duplicate or unauthorized charges, and confirmed failed-payment or vend reversals are separate from voluntary unused-load refunds. The 48-hour unused-load restriction does not apply to those claims. The same-day procedure governs our voluntary machine remedy; it does not eliminate remedies or payment-dispute rights required by law. We review records before determining any other remedy. An approved wallet reversal preserves the purchased and promotional portions of the original payment; an approved card refund returns to the original payment method. We send a nonpromotional follow-up when a refund decision or reported issue is resolved.

## 8. Account deletion and restoration

A deletion request places your account in pending deletion and restricts ordinary access. You may explicitly restore the original account and its wallet links after verifying ownership and completing any required multi-factor authentication, before the exact server-set deadline 90 days after the request. The recovery screen shows the deadline and timezone. Signing in alone does not restore the account. At or after the deadline, restoration is unavailable even if cleanup has not occurred.

After the restoration deadline, we delete the login and ordinary profile through our cleanup process, subject to necessary, limited retention described in the Privacy Policy. The restoration deadline is not a promise that all copies are erased at that moment. Restoration does not reset refund deadlines, duplicate rewards, or automatically restore revoked messaging or push permissions.

## 9. Credit forfeiture and claims after deletion

By voluntarily requesting account deletion, you agree to surrender any remaining purchased and promotional laundry credit and unissued reward progress if you do not explicitly restore the account before the server-set 90-day recovery deadline. At that deadline, the remaining credit and reward progress are forfeited, except where applicable law prohibits forfeiture. Deletion does not convert credit into cash or entitle you to a refund. Creating a new account does not restore forfeited credit.

Use remaining credit before requesting deletion, or submit an eligible refund request within the applicable policy deadline. Deletion does not restart or extend the 48-hour unused-load refund window or the same-day machine-reporting requirement. A timely refund request or claim remains subject to the same eligibility rules and review after deletion; deletion itself is not a reason for approval.

Pending payments, approved refunds, reversals, and timely claims are reconciled under the applicable payment and claim policies. Disputes follow section 11 and any applicable payment-provider process; submitting a dispute does not automatically establish entitlement to a refund. We retain only records needed for those matters and applicable legal obligations. Nothing in this section waives rights that cannot lawfully be waived.

## 10. Availability and responsibility

Equipment, networks, and payment services may be unavailable or interrupted. Availability information may change before you reach a machine. We cannot promise uninterrupted access or a particular laundry result, but interruptions do not remove responsibility for valid payment or service claims.

Each party remains responsible for its conduct to the extent provided by applicable law. Nothing in these terms excludes liability or consumer remedies that cannot lawfully be excluded, excuses fraud or willful misconduct, or imposes a fixed monetary cap on your claim.

## 11. Changes and disputes

Machine prices and future reward offers may change; the applicable price or offer is shown before a purchase. Material revisions requiring agreement will be presented under a new version for acceptance. Changes do not retroactively erase purchased credit or override rights required by law.

Contact support first so we can try to resolve a concern. We aim to work toward a resolution within 30 days; this does not prevent urgent relief or require you to miss a legal deadline.

Indiana law governs these terms, without overriding mandatory consumer protections that apply to you. Unresolved disputes may be brought in an appropriate court, including small claims court when eligible. These terms do not require arbitration, waive a jury trial, or waive class-action rights. Mediation or arbitration may be used only if both sides separately agree in writing after a dispute arises.

## 12. Contact

Contact Clean Stream Laundry Solutions LLC at support@cleanstreamlaundry.com for service, payment, wallet, or privacy questions. Please do not send passwords, authentication codes, or full payment-card numbers.

# Privacy Policy

Draft for user review | Revised October 5, 2026 | Not approved or effective

This document is a draft for review. It does not replace current terms or policies, require new acceptance, or change your existing rights.

## 1. Scope

This policy describes how Clean Stream Laundry Solutions LLC (Clean Stream, we, us, or our) handles personal information in its website, iOS and Android apps, accounts, payments, wallet, and connected laundry services. It covers information you provide, information generated by use of the service, and relevant information received from service providers.

## 2. Account and sign-in information

We process your name, email address, account identifier, profile details and photo if supplied, authentication and verification records, and account preferences. Authentication services process credentials and session information needed to sign you in, protect the account, and support recovery.

If you choose Google sign-in or Sign in with Apple where offered, that provider authenticates you and shares the identity information authorized by the sign-in. Google may share an account identifier, email address, name, and profile image. Apple shares an account identifier and email address, which may be a private relay address if you choose Hide My Email, and may provide your name when you first authorize sign-in. Supabase uses the resulting credentials or tokens to establish your Clean Stream session. Clean Stream does not receive your Google or Apple password.

## 3. Payments, wallet, machines, and support

We process wallet balances, purchased and promotional credit, loads, spending, rewards, payment amounts and status, processor references, machine and location identifiers, vend outcomes, refunds, and claims. These records help connect a purchase to the correct account, machine, and payment outcome.

Stripe processes app and website card payments and refunds. Nayax supports payments at participating machines and connected-machine operation. Payment providers receive payment information through their payment services; Clean Stream receives the references and results needed to operate and reconcile the service, not your complete payment-card number for storage in our application.

Support and maintenance records include your contact details, messages, descriptions of problems, related payment and machine records, and photos or other attachments you submit. Avoid including unrelated personal information in messages or images.

## 4. Location, maps, camera, and uploads

With device permission, the app uses your location to help identify nearby laundry locations. Location access is separate from your ability to contact support. You can change location permission in device settings.

The app loads map tiles from OpenStreetMap. Tile requests disclose your IP address and the map area requested to the tile service; the area may relate to your location when the map centers on you. Opening directions sends the selected destination to the external map service, such as Google Maps, which handles the request under its own privacy practices.

Camera access supports machine QR scanning and taking photos where offered. Photos you choose to upload for a profile or support request are sent to our application storage and may contain personal information or embedded metadata. You can control camera and photo access in device settings; denying access can make the corresponding feature unavailable.

## 5. Technical information and purposes

Our application, hosting, authentication, and payment providers process technical information such as IP addresses, request and access logs, browser or device information, app version, session identifiers, and security events. The website and app use local storage or similar technologies to maintain sessions and preferences and recover pending payment status.

We use information to provide accounts and laundry services, process and reconcile payments, maintain wallet and reward records, resolve refunds and machine claims, respond to support, secure the service, prevent fraud, and meet applicable recordkeeping and legal requirements. Analytics has a separate, limited purpose: checking that the app functions properly and identifying operational reliability problems.

## 6. Mobile Analytics

We use Google Analytics for Firebase only for operational reliability, to check that the app functions properly and identify operational problems. Analytics collection is automatic.

Analytics data includes app-instance and installation identifiers, device and app information, and events associated with app operation. We do not include customer names, email addresses, account identifiers, wallet balances, funds or payment information, or support content in Analytics events.

We do not use Analytics for advertising or customer profiling, and we do not share Analytics information for advertising. Analytics and in-app messaging are paused when you confirm an account-deletion request.

## 7. Notifications, configuration, and nonpromotional messages

Firebase In-App Messaging is optional and starts off. Push notifications use Firebase Cloud Messaging and require a separate opt-in and device permission. A push registration token is linked to your signed-in account and session to direct notices to the intended device. Device settings also control notification permission.

Firebase Remote Config provides app-version and maintenance information. Firebase installation identifiers support configuration and messaging services. Turning off optional messages does not erase information already held by providers, and restoring an account does not restore messaging or push opt-ins.

We use Resend to send nonpromotional account, security, payment, refund, support, and account-lifecycle messages, including a welcome after verified account creation. Resend processes recipient addresses and message content. We retain delivery references and delivery, bounce, complaint, failure, and suppression information to manage reliable delivery. Delivery suppression may prevent even necessary notices. Optional informational messages remain separate from necessary service communications.

## 8. Service providers and disclosures

We share information needed for the relevant service with Supabase for authentication, database and file storage; Stripe for app and web payments and refunds; Nayax for machine payments and operation; Google for sign-in and Firebase services; Apple for Sign in with Apple and its private email relay when used; Resend for email; OpenStreetMap for map tiles; and our website hosting provider for serving and securing the website. For example, payment references and machine identifiers help reconcile a vend, while recipient addresses and message content enable email delivery.

Authorized personnel use account, financial, and support information as needed to operate the service and resolve requests. Providers may also handle information under their own privacy policies and legal responsibilities. Processing may occur outside your state or country.

We do not sell personal information or use third-party advertising SDKs in the app. We may disclose relevant records when required by law, to address fraud or security incidents, to protect legal rights or safety, or in a business transfer subject to applicable privacy obligations.

## 9. Retention and account deletion

A deletion request places your account in pending deletion and restricts ordinary access. You may explicitly restore the original account and its wallet links after verifying ownership and completing any required multi-factor authentication, before the exact server-set deadline 90 days after the request. The recovery screen shows the deadline and timezone. Signing in alone does not restore the account. At or after the deadline, restoration is unavailable even if cleanup has not occurred.

After that deadline, the login and ordinary profile are removed through our cleanup process. Necessary financial, claim, security, and legal records are handled separately. The deadline ends restoration rights; it is not a guarantee of immediate deletion from all systems or backups.

By voluntarily requesting account deletion, you agree to surrender any remaining purchased and promotional laundry credit and unissued reward progress if you do not explicitly restore the account before the server-set 90-day recovery deadline. At that deadline, the remaining credit and reward progress are forfeited, except where applicable law prohibits forfeiture. Deletion does not convert credit into cash or entitle you to a refund. Creating a new account does not restore forfeited credit.

Routine account, support, attachment, delivery, and security information is retained for the purpose it serves and the applicable retention schedule. An unresolved refund, dispute, security incident, or legal obligation can require longer retention of specific records, not indefinite retention of an entire usable account. Records linked through identifiers may still be personal information.

Deletion from active systems, provider systems, and backups may occur at different times. We do not promise immediate physical erasure or a universal backup-erasure deadline. Contact us about the status of a deletion request or the reason particular records remain necessary.

## 10. Your choices and requests

You can update available profile details and preferences in the app and change location, camera, photo, and notification permissions in your device settings. You can initiate account deletion in the app or use the account-deletion instructions on our website. Deletion and restoration do not extend refund deadlines.

Contact support@cleanstreamlaundry.com to request access, correction, or deletion of your personal information, ask for a copy, or raise a privacy concern. You may also request portability, restrict or object to certain processing, or appeal a request decision where applicable law provides these rights.

We may need to verify your identity or an authorized representative's authority before acting, using information proportionate to the request. We will explain when a request cannot be fulfilled in whole or in part. Records retained for a legal obligation or unresolved claim do not create permission to use them for unrelated purposes.

## 11. Security and policy changes

We use access controls, authentication, and other technical and organizational measures to protect information. No internet service, device, or storage system can be guaranteed completely secure. Protect your account and contact us promptly about suspected unauthorized activity.

We may revise this policy to reflect changes to services, data practices, or applicable requirements. A published revision will identify its date, with additional notice or consent where required.

## 12. Contact

Contact Clean Stream Laundry Solutions LLC at support@cleanstreamlaundry.com for service, payment, wallet, or privacy questions. Please do not send passwords, authentication codes, or full payment-card numbers.
