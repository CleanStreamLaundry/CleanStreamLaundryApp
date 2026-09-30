# Firebase Reference

Updated 2026-09-29. Separate verified setup from planned SDK behavior. Current work and verification belong in [operations](operations.md), not in this guide.

## Access and Environments

- Use the Clean Stream business Google account. The user explicitly authorized its signed-in Chrome console; connector authentication is not a prerequisite for that workflow.
- Do not sign out, replace, disconnect, or modify Gundex's Firebase project or connector setup. Verify the displayed account and project before every remote change.
- Separate development and production projects were created through Chrome and each console confirmed Spark, no-cost ($0/month). Keep one codebase with explicit build configuration and test analytics/messages/release controls away from customers. No billing account or paid service activation is authorized.
- Firebase Terms and the separate Google Analytics Terms were accepted with explicit user approval. Analytics is enabled with separate properties in both projects, and Android/iOS apps are registered. No database, SDK configuration, campaign, or release policy has been added. Console registration does not connect the app or enable customer telemetry.
- Optional Gemini, Google Developer Program enrollment, and optional Analytics sharing are not required. Keep them off. Do not replace Supabase Auth with Firebase Auth or provision another database.

| Environment | Verified project | Analytics property ID | Console |
| --- | --- | --- | --- |
| Development | `clean-stream-dev` (Clean Stream Dev) | `556688774` | [Overview](https://console.firebase.google.com/u/2/project/clean-stream-dev/overview) |
| Production | `clean-stream-production` (Clean Stream Production) | `556696345` | [Overview](https://console.firebase.google.com/u/2/project/clean-stream-production/overview) |

Both properties use the Clean Stream account's `Default Account for Firebase` Analytics account (`410162599`). Google Products and Services, Benchmarking, Technical support, and Account specialists sharing were all deselected during account setup. Do not merge development and production properties or enable optional sharing as an SDK prerequisite.

The `/u/2/` account index is specific to the observed Chrome session. Recheck the displayed account rather than assuming that index on another machine/session.

## Existing App Identity

| Platform | Verified local identity |
| --- | --- |
| Android | `com.cleanstreamlaundrysolutions.clean_stream_laundry_app` |
| iOS | `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp` |

These come from `android/app/build.gradle.kts` and `ios/Runner.xcodeproj/project.pbxproj`. Preserve the existing iOS spelling; changing an installed application's bundle ID is not cosmetic cleanup. Both environments use these existing platform identities. No development flavors or Firebase SDK/config files are currently added. Resolve environment selection before configuring builds; never silently connect debug builds to production.

| Environment | Platform | Verified Firebase app ID |
| --- | --- | --- |
| Development | Android | `1:83380736317:android:7b074a257825c9670af554` |
| Development | iOS | `1:83380736317:ios:3fe930785b224eb30af554` |
| Production | Android | `1:863183154828:android:3c15f3dbc067244de615a9` |
| Production | iOS | `1:863183154828:ios:1f263e0ea3df94bde615a9` |

Project numbers are `83380736317` (development) and `863183154828` (production). Registrations were verified in the console on 2026-09-29. The production iOS configuration was subsequently downloaded through Chrome, but macOS denied access to Downloads; it has not been read, verified, copied or integrated. The other three configurations remain undownloaded. No APNs material, signing fingerprints, App Store ID, or Team ID were added.

## Planned Integration Boundaries

- Reuse the existing notification service and settings. Add only necessary SDK/configuration and focused service methods, not a parallel notification framework.
- Initial scope is infrastructure and approved test delivery. No customer campaign, automatic newsletter enrollment, or production message sending during setup.
- Analytics and In-App Messaging need deliberate consent and collection defaults before SDK initialization. Do not send names, email addresses, payment details, secrets, or raw deep links as event data.
- FCM registration/cleanup must account for permission denial, account changes, sign-out, and account deletion. Review foreground/background routes and require normal authorization at the destination; a notification is not proof of permission.
- Remote Config release controls must have safe defaults, cached known blocks, explicit environment targeting, and offline behavior. Backend authorization/shutdown remains independent of client version claims. Reuse existing configuration boundaries.
- Current Spark pricing lists 100,000 Remote Config fetches per day per project, not unlimited fetches. Use deliberate fetch intervals and verify the current quota before rollout. Functional release checks must not require optional Analytics consent.
- Current Firebase Flutter setup requires iOS 15 or later; the app currently declares iOS 13. Raising the supported floor requires an explicit product decision before adding current SDKs.
- No Supabase Realtime. Do not add Firestore, Realtime Database, WebSockets, or SSE. A quota-reviewed Remote Config realtime listener requires the approved urgent-invalidation use case, not general data refresh.
- Client Firebase configuration is public identification, not server authorization. Never bundle Admin SDK/service-account credentials. APNs signing material stays private and requires a reviewed setup path.
- A development Firebase project does not isolate Supabase, Stripe, email or machine providers. Verify the whole environment before connected testing; use mocks/local backends until a separate staging environment is reviewed. Do not bypass filesystem/privacy controls to obtain a downloaded configuration.

Before rollout, verify dev/prod isolation, consent, no sensitive event payloads, token cleanup, denial/offline behavior, signed-out notification navigation, release-policy fallback, costs/quotas, and both native platforms. Console provisioning alone is not SDK integration or production readiness.

Official references: [environment separation](https://firebase.google.com/docs/projects/dev-workflows/general-best-practices), [pricing](https://firebase.google.com/pricing). Verify current product/SDK documentation before implementation.
