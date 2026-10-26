# Mobile Store Data-Disclosure Inventory (Draft)

Updated 2026-10-01 for iOS/Android release documentation. Source and vendor-documentation inventory: not approved policy, completed store forms, device/binary acceptance or store readiness. SDK documentation and installed iOS manifests were inspected in stage 3; no new build, device session or provider mutation was performed for this inventory.

Scope: active mobile source and its backend; companion website only for relevant support/deletion context. Existing dirty source is input, not a claim that every implementation is deployed. This closes the missing **draft data-flow/category inventory**, not the privacy/store release gate in [platform preflight](../docs/platform-release-check.md#L58).

October 3 source-only alignment: the current Analytics rows reflect automatic
operational collection, superseding the earlier optional opt-in policy. New runtime
acceptance remains deferred; this update does not change other inventory findings.

## Reading the Inventory

- Off-device means a first-party backend or external recipient receives data. Supabase hosts first-party Auth/database/Storage/Edge processing; SDK recipients are listed separately.
- Required means necessary for the named flow, not necessarily required for every app user. Optional feature use still belongs in store answers when collection occurs.
- Account IDs, session/payment references and installation tokens are linkable identifiers, not anonymous data. Treat account-associated rows as linked; SDK-only linkage needs confirmation.
- Retention periods, provider copies, logs and backups are **unconfirmed for every row** unless explicitly stated otherwise below. No blanket no-sharing, no-tracking, encryption or deletion claim is made.

## Observed Flows and Candidate Store Categories

Category names below are draft mappings to [Apple data types/purposes](https://developer.apple.com/app-store/app-privacy-details/#data-type) and [Google Data safety types/purposes](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en). Their official pages were consulted during initial authoring, before the instruction to defer verification. These mappings are guidance, not finalized form selections.

| Flow / source | Local vs off-device; linkage and choice | Purpose / recipients | Apple / Google candidate categories |
| --- | --- | --- | --- |
| Identity and profile [S1] | Email/password/name sent to Supabase Auth; profile name, role, balance/reward state and notification lead time stored server-side under account ID. Google/Apple OAuth alternatives are wired. Identity is required for account flows; edits/preferences are user initiated. | Authentication, account management, functional preferences; Supabase and selected sign-in provider. Credentials are not merely local. | Apple: Name, Email Address, User ID; credentials/other profile fields need classification. Google: Name, Email address, User IDs, Other personal info as applicable. |
| Stripe mobile payment [S2] | PaymentSheet handles payment entry off-device with Stripe; app/backend exchange amount, currency, intent/status and purpose. Backend attaches user ID and, for top-ups, wallet account ID. Required if paying by this route; do not infer first-party raw card storage. Google Pay configured; Apple Pay code commented out here. | Payment processing, settlement, fraud prevention pending processor confirmation; Stripe and Supabase. | Apple: Payment Info, Purchase History, User ID. Google: User payment info, Purchase history, User IDs. Exact billing fields and SDK telemetry unresolved. |
| Stored wallet / rewards / claims [S3] | Server-side balance, ledger, paid/promo credit and refund/transaction references linked to account; wallet load invokes Stripe. Redemption spends existing value, not a second card collection. Required for wallet use; claims optional. | Balances, rewards, transaction history, reconciliation and support; Supabase; Stripe where a real funding/refund operation occurs. | Apple: Other Financial Info, Purchase History, User ID; Customer Support for claims. Google: Other financial info, Purchase history, User IDs; Other user-generated content for claim content. |
| Nayax / Cortina vend [S4] | Backend sends AppUserId, transaction ID, price/product and terminal or QR selector to Nayax. Sessions bind machine, account, payment method and provider references. Required for this vend route; a terminal identifier identifies a machine, not automatically the customer's device. | Machine activation and reconciliation; Nayax plus Supabase. Vend evidence can describe the same Stripe/wallet purchase, not another collection. Direct-reader card collection is not established by this mobile flow. | Apple: User ID, Purchase History. Google: User IDs, Purchase history. Machine/site association may reveal location context; store owner to classify, not automatically precise GPS. |
| Nearest site / map [S5] | Permission-gated coordinates are compared with site coordinates locally; no GPS upload appears in this parser. Map tiles are fetched from OpenStreetMap with requested tile coordinates and network metadata. Location permission is optional; tile traffic is separate from GPS permission. | Nearest-site selection and map display; local geolocator processing, OSM tile service. Selected site also accompanies maintenance/vend activity. | No collection category solely for local GPS processing. Apple Coarse/Precise Location and Google Approximate/Precise location remain conditional on actual off-device derivation/retention; IP/tiles must not be ignored. |
| Camera / photos / maintenance [S6] | QR scanner consumes camera input; no image upload is shown in scanner references. Maintenance photo selection is initially local, then optional upload to Supabase Storage on submit. Category, description, selected site/address, image URL and user ID go to Edge. Photo not required; description/category/site choice required for a request. | Machine selection and customer support; Supabase. Uploaded image contents and possible embedded metadata need retention/access decisions. No profile-photo upload identified in the reviewed profile service; do not invent one from retention proposals. | Apple: Photos or Videos, Customer Support, User ID. Google: Photos, Other user-generated content, User IDs. QR camera access alone is not photo collection. |
| Push / local notifications [S7] | Push defaults off; opt-in, OS permission and account admission gate token acquisition. FCM/APNs tokens and a generated installation ID enable delivery; token, platform/environment and installation registration go to Supabase with authenticated account/session linkage. Local notification presentation alone is not off-device collection. | Functional notifications; Google Firebase, Apple APNs and Supabase. Required only when using push. Revocation code is not proof of eventual provider erasure. | Apple: Device ID, User ID. Google: Device or other IDs, User IDs. Provider delivery/diagnostic metadata remains unconfirmed. |
| Analytics [S8] | Native startup default off; automatically enabled after configured startup by application policy, subject to platform/privacy restrictions and deletion cleanup. No in-app switch. Custom events are settings_opened/update_opened without PII, free-text parameters or app-set user ID. Automatic collection includes app-use, technical app/device information, installation-based usage and derived geography; see vendor evidence below. Advertising storage, advertising user data and ad personalization consent remain denied. | Operational usage measurement; Google Analytics for Firebase. Application-policy collection, not optional local opt-in. | Apple: Product Interaction, Device ID, Coarse Location as applicable; Google: App interactions, Device or other IDs, Approximate location. Reconcile actual release settings and linkage, not just custom events. |
| In-App Messaging [S8] | Default off; collection/messages controlled by a separate opt-in and paused during deletion privacy cleanup. Restoration does not restore messaging consent. SDK can collect campaign interactions/installation data when enabled; exact shipped SDK behavior not established here. | In-app communications; Firebase. Optional. Actual campaign content determines functionality versus marketing/personalization purposes. No active campaign or sending claim. | Candidate Apple: Product Interaction, Device ID. Google: App interactions, Device or other IDs. SDK/campaign owner must settle categories/purposes. |
| Remote Config [S8] | Configured Firebase initialization/fetch is independent of Analytics collection state. fetchAndActivate retrieves release_policy_v1; 12-hour minimum interval, eight-second timeout, local defaults/cache. SDK request/installation metadata needs inventory; do not claim zero Firebase collection while Analytics is paused. | Release compatibility/availability controls; Firebase. Functional startup/resume path, independent of optional messaging choices. | Candidate Apple: Device ID; Google: Device or other IDs. SDK owner must confirm installation/app/device metadata, retention and any additional categories. |
| Newsletter / lifecycle / support email [S9] | Mobile newsletter action sends opt-in, policy version and source with authenticated identity. Backend consent/outbox/suppression and lifecycle records are account-linked. New transactional delivery is enabled; newsletter delivery lacks its postal address. Companion support/deletion mailto links initiate user email outside the app. | Consent management and service communication; Supabase and configured Resend delivery. Enabled delivery is not proof of receipt. Newsletter marketing optional; account notices tied to lifecycle actions. | Apple: Email Address, User ID, Customer Support as applicable. Google: Email address, User IDs, Other user-generated content. Marketing purpose only where newsletter/campaign use actually applies. |

Ordinary account, payment, support, push and release-control uses map principally to Apple **App Functionality**; Google **App functionality**, **Account management**, **Developer communications**, and **Fraud prevention, security, and compliance** only where the actual use supports each selection. Analytics maps to **Analytics**. Marketing maps to Apple **Developer's Advertising or Marketing** / Google **Advertising or marketing**. Do not select every purpose for every category. [Apple purposes](https://developer.apple.com/app-store/app-privacy-details/#data-use), [Google purposes](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).

## Local Handling and Disclosure Boundaries

### Verified SDK Inputs

`pubspec.lock` pins FlutterFire core4.15.0, Analytics12.6.0, FCM16.7.0,
FIAM0.9.4, Remote Config6.7.0 and Installations0.4.4; `ios/Podfile.lock` resolves Firebase12.19.0
and Stripe25.15.0 (`flutter_stripe`13.0.0). These are source dependencies, not a
signed-release inventory. The installed25.15.0 StripeCore/PaymentSheet privacy
manifests were re-read after the October1 pod refresh; their declarations still
match the table below. Earlier unsigned artifacts pass their recorded checks;
the final dependency graph's native release checks remain separate.

| SDK | Vendor declaration and current source consequence |
| --- | --- |
| Analytics | Google documents an app-instance identifier plus automatic lifecycle/session/device/geography data. On iOS, general location is derived from masked IP addresses. Inspect these alongside custom events, even without an app-set user ID. [Collection](https://support.google.com/firebase/answer/6318039?hl=en), [iOS disclosure](https://support.google.com/analytics/answer/10285841?hl=en). |
| FCM and Installations | iOS associates APNs tokens with installation IDs. Android FCM includes app-version/user-agent data and the Installations dependency; Installations generates an FID. Token registration is account-linked in this app, even though FID alone is installation-scoped. [iOS](https://firebase.google.com/docs/ios/app-store-data-collection#firebasemessaging), [Android](https://firebase.google.com/docs/android/play-data-disclosure#cloud_messaging). |
| FIAM | Both platform guides describe message impressions, clicks and dismissals; Android also includes Installations. Optional messages are not collection-free. [iOS](https://firebase.google.com/docs/ios/app-store-data-collection#firebaseinappmessaging), [Android](https://firebase.google.com/docs/android/play-data-disclosure#in-app_messaging). |
| Remote Config | Both platforms send locale/time-zone, OS and app metadata; Android also declares SDK/platform versions and Installations. Treat release-control fetching as functional Firebase processing independent of Analytics collection state. [iOS](https://firebase.google.com/docs/ios/app-store-data-collection#firebaseremoteconfig), [Android](https://firebase.google.com/docs/android/play-data-disclosure#remote_config). |
| Stripe | Installed StripeCore and StripePaymentSheet `PrivacyInfo.xcprivacy` declare linked Product Interaction for Analytics/App Functionality; PaymentSheet additionally declares linked Payment Info for App Functionality. These entries declare tracking false. This is SDK manifest evidence, not a blanket declaration for every processor, payment method or optional feature. |

Native source defaults Analytics, automatic screen reporting, FCM auto-init and
FIAM collection off. iOS also disables IDFV collection; Android disables Analytics
advertising-ID collection. The current Android release also excludes inherited
AD_ID, ACCESS_ADSERVICES_AD_ID and ACCESS_ADSERVICES_ATTRIBUTION permissions;
install-referrer and functional permissions remain. The driver denies ad consent;
the service automatically enables operational Analytics without an in-app switch,
keeps FIAM/push optional, and pauses Analytics/FIAM collection for confirmed account deletion
and pending privacy cleanup. Remote Config is fetched manually. These controls do not
mean all Firebase traffic or SDK metadata is absent. See `ios/Runner/Info.plist`,
`android/app/src/main/AndroidManifest.xml` and `flutterfire_driver.dart`.

Firebase's published policy retains FIDs used by FCM/FIAM/Remote Config until an
installation-deletion API call, then removes live/backup data within180 days.
This is a documented provider limit, not an unknown owner preference or a
90-day guarantee. The new local installation-deletion call passes focused independent
QA and native plugin compilation; it complements token deletion and local Analytics reset, not historical
Analytics erasure or other-device cleanup. Include those remaining processor
requirements in the final lifecycle contract. [Firebase retention](https://firebase.google.com/support/privacy),
[installation deletion boundaries](https://firebase.google.com/docs/projects/manage-installations#delete_a_firebase_installation).

- A local permission prompt, camera frame, draft image or distance calculation alone does not establish collection. Uploads and derived off-device data must be assessed separately. Google form treatment of ephemeral transmission differs from Apple's retained-collection definition. [Apple guidance](https://developer.apple.com/app-store/app-privacy-details/#additional-guidance), [Google collection guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).
- Names/IDs/payment/maintenance records shown above are account-linked. Treat push as account/device-linked. For Analytics/FIAM/Remote Config, obtain SDK identifier/linkage facts rather than claiming anonymous operation.
- Google sharing exceptions for service providers/user-initiated transfers require facts about the recipient relationship and use. Apple tracking is a separate question concerning cross-company advertising linkage/data brokers; neither a manifest flag nor disabled ad consent proves the answer for all processors. [Apple tracking](https://developer.apple.com/app-store/app-privacy-details/#tracking), [Google sharing](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).
- Network IP addresses, SDK automatic telemetry, server logs, OAuth attributes and photo metadata remain bounded disclosure inputs, not asserted absent. No new broad security audit is requested.

## Retention and Deletion Status

[retention.md](../docs/retention.md#L1) is an **unapproved proposal**, not an effective schedule. Do not copy its periods into store/policy answers as implemented guarantees. Draft-supported permanent-cleanup source is integrated but unapplied and not accepted; financial/provider disposition remains incomplete. Server lifecycle/deletion-request and restoration RPCs do not prove full account/data deletion. Financial history, attachments, tokens, logs, backups and provider copies need approved disposition and verified implementation.

[Email reference](../docs/email.md#L3) records new transactional delivery enabled on October1, with no backfill; newsletters still require the actual postal address. [Companion deletion draft](../../CleanStreamWeb-CortinaQR/src/components/AccountDeletionPage.tsx#L28) leaves post-deadline retention/balance treatment unresolved. Website publication is recorded in operations; functional deletion-path acceptance remains separate. No new rights, retention promises or policy language are established by this inventory.

## Remaining Store-Form Decisions

| Owner | Blocking input / deferred decision |
| --- | --- |
| Privacy/store owner | Select final per-platform categories, required/optional answers, linkage and purposes for the actual release; assess narrow optional-disclosure exceptions, not blanket omission of optional features. Approve policy URLs/copy and reconcile mobile/companion scope. |
| Mobile/SDK owner | Reconcile the vendor/manifest facts above with the actual signed iOS and resolved Android releases, consent behavior and OAuth scopes. Resolve final diagnostic/location/linkage categories; do not defer obtainable public SDK facts as user input. Binary/device verification remains. |
| Payments/provider owner | Confirm Stripe billing/fraud fields and retention; Nayax retained identifiers and use; Google Pay scope. Supply processor/controller and onward-use facts for sharing/tracking answers. Do not treat wallet bookkeeping as raw card processing. |
| Backend/account owner | Identify deployed versus local flows and actual data/log/storage/backup retention; implement approved permanent cleanup and processor disposition. Confirm account request, restoration and public deletion paths when verification is authorized. |
| Business/privacy owner | Approve retention, financial-record exceptions and remaining-balance policy; settle processor terms and marketing purposes. This draft supplies no legal approval. |
| Communications owner | Confirm actual delivery configuration at release, approved newsletter/campaign purposes and Resend retention/suppression handling. Transactional delivery is enabled; newsletters require the postal address. Include manual support mailbox processing. |
| Release/composer owner | Integrate this draft, assign unresolved answers and defer formal store/provider/security declarations, including encryption-in-transit and tracking/sharing assertions, until supporting evidence is authorized and available. |

## Code Evidence Index

Anchors refer to the current local source read for authoring; no test or QA result is implied.

- **S1:** [Auth signup](../lib/services/supabase/supabase_auth_service.dart#L77), [OAuth](../lib/services/supabase/supabase_auth_service.dart#L222), [profile creation](../lib/services/supabase/supabase_profile_service.dart#L175).
- **S2:** [PaymentSheet](../lib/services/stripe/stripe_service_mobile.dart#L42), [intent payload/status](../lib/services/stripe/stripe_service_mobile.dart#L110), [server metadata](../supabase/functions/paymentIntent/logic.ts#L36).
- **S3:** [wallet load/spend](../lib/services/supabase/supabase_wallet_service.dart#L156), [transaction history/claims](../lib/services/supabase/supabase_transaction_service.dart#L14), [financial distinctions](../docs/payments.md#L28).
- **S4:** [session linkage](../supabase/functions/_shared/cortina.ts#L346), [Nayax outbound fields](../supabase/functions/_shared/cortina.ts#L565), [Stripe/session binding](../supabase/functions/_shared/cortina.ts#L691).
- **S5:** [local nearest-site calculation](../lib/logic/parsing/location_parser.dart#L65), [network tiles](../lib/features/home/widgets/map.dart#L49).
- **S6:** [scanner](../lib/features/scanner/controller.dart#L14), [photo selection](../lib/features/maintenance_request/controller.dart#L136), [upload/request fields](../lib/features/maintenance_request/controller.dart#L267).
- **S7:** [token registration](../lib/services/firebase/push_token_store.dart#L32), [permission/token](../lib/services/firebase/flutterfire_driver.dart#L84), [revocation/admission](../lib/services/firebase/firebase_service.dart#L251), [local presentation](../lib/services/notification_service.dart#L111).
- **S8:** [consent defaults](../lib/services/firebase/firebase_service.dart#L133), [Analytics/FIAM coupling](../lib/services/firebase/firebase_service.dart#L184), [SDK consent/events](../lib/services/firebase/flutterfire_driver.dart#L40), [Remote Config setup](../lib/services/firebase/flutterfire_driver.dart#L30), [fetch](../lib/services/firebase/flutterfire_driver.dart#L113).
- **S9:** [newsletter request](../lib/services/supabase/supabase_profile_service.dart#L46), [lifecycle methods](../lib/services/supabase/supabase_profile_service.dart#L99), [email implementation/status](../docs/email.md#L35), [support email link](../../CleanStreamWeb-CortinaQR/src/components/SupportPage.tsx#L11).
