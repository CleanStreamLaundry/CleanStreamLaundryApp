# Apple Sign-In

## Evidence Boundary

October 5, 2026 source inspection found an existing Apple button and Supabase
browser OAuth flow using `clean-stream://oauth`. That flow may be functional
when the hosted provider is configured; Apple was not entirely absent.
The Privacy draft named Google but omitted Apple. Legal wording is owned by the
legal/composer lane and was not changed by this auth implementation.

Native source now uses `sign_in_with_apple` on iOS/macOS, SHA-256 nonce delivery
to Apple, and the raw nonce for Supabase `signInWithIdToken`. It reuses the
existing isolated Auth client factory and guarded native session adoption.
First-consent names are saved to the isolated Apple user's `full_name` metadata;
missing names on repeat sign-in do not erase existing names. User cancellation
returns to Login; other errors are visible and retryable. Successful native
login navigates through the existing protected Home/admission route. Browser
OAuth and the sole existing deep-link consumer remain unchanged in purpose.

## Local Integration

- Pin `sign_in_with_apple: 7.0.1`. Official pub.dev metadata requires Dart ^3.3
  and Flutter >=3.19, compatible by declaration with pinned Flutter 3.38.10 /
  Dart 3.10.9. Version 8.0/8.1 requires Flutter 3.41 / Dart 3.11; latest 8.2
  requires Flutter 3.44 / Dart 3.12. Do not upgrade the SDK for this feature.
- Composer owns Pub lock/config and generated plugin/Pods integration. The
  plugin adds its platform interface 2.0.0 and web implementation 3.0.0;
  existing `crypto: 3.0.7` supplies SHA-256. No Firebase Auth dependency.
  Composer reports Pub resolution and `pod install --no-repo-update` exit 0
  with 53 Pods including this plugin. The three Pub entries were read back;
  this is dependency integration evidence, not a native build or sign-in test.
- `ios/Runner/Runner.entitlements` has
  `com.apple.developer.applesignin = [Default]`; the Runner project has
  `com.apple.SignInWithApple` enabled. Existing bundle ID remains
  `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp`.
- No new AppDelegate, Info.plist, callback scheme, DI registration, Android
  callback activity, or web JavaScript is needed for native iOS sign-in.
  Android continues showing Google only. macOS code capability is not a
  configured/shipped macOS target.

## Hosted Evidence and Remaining Setup

October 5 composer read-only Chrome inspection of the correct Clean Stream
project `dnuuhupoxjtwqzaqylvb` confirmed Apple **enabled**, the correct Supabase
callback URL, and only this allowed Client ID:
`com.cleanstreamlaundrysolutions.clenaStreamLaundryApp.Auth`.
No provider settings or secrets were changed or disclosed. The existing
browser OAuth Services ID may work; no real sign-in was performed.

1. Apple Developer: enable Sign in with Apple for the exact existing App ID
   `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp` and refresh
   provisioning profiles to include its entitlement. Apple portal capability
   and provisioning status have not been verified. Preserve the actual
   `clena` spelling; do not rename the bundle or identifiers.
2. With approval at action time, append native audience
   `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp` to the hosted Apple
   Client IDs. Preserve existing
   `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp.Auth` as the first
   entry for browser OAuth. The `.Auth` identifier alone does not match the
   native bundle audience. Keep nonce validation enabled. Local
   `supabase/config.toml` has Apple `enabled = false` and empty `client_id`;
   that is local-only configuration, not the enabled hosted provider.
3. Retained browser OAuth additionally requires a configured Services ID,
   Apple return URL `https://dnuuhupoxjtwqzaqylvb.supabase.co/auth/v1/callback`,
   and provider secret rotation. When supporting both flows, Supabase documents
   Services ID first, native App ID also accepted. Native-only ID-token login
   does not require the browser OAuth secret/rotation setup.
4. Verify the existing sending domains with Apple's private email relay before
   claiming delivery to Hide My Email users. No accounts, keys, provider
   settings, or email infrastructure were created or changed in this lane.

## Local Acceptance and Device Gates

Composer's serial QA passed the assigned Apple/Google native, OAuth redirect,
authenticator, Login, social-button and admission checks as part of 553 Flutter
cases, plus 28 router cases. Scoped analysis has existing warnings/infos, not a
clean result. No native build or real Apple account sign-in was run.
The read-only hosted evidence above is not an auth execution; source and synthetic
acceptance do not establish tested device compatibility. The new native test uses the actual plugin method channel and real
Supabase SDK with synthetic HTTP; it does not authenticate a real Apple account.
Receipt: `.campaign-work/review-followup-20261005/QA-RECEIPT.md`.

After dependency/native integration, signed-device acceptance still needs
first and repeat Apple sign-in, cancellation, Hide My Email, session persistence,
and admission completion. Native audience/Apple capability setup, signing, actual
login, relay delivery, and account lifecycle acceptance are separate gates.

## Primary References

- [Supabase Apple provider](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Supabase Dart ID-token and nonce flow](https://supabase.com/docs/reference/dart/auth-signinwithidtoken)
- [Plugin 7.0.1](https://pub.dev/packages/sign_in_with_apple/versions/7.0.1)
- [Plugin version requirements](https://pub.dev/packages/sign_in_with_apple/changelog)
- [Apple capability setup](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple)
- [Apple private relay](https://developer.apple.com/help/account/configure-app-capabilities/configure-private-email-relay-service/)

Current Supabase changelog and the above primary docs were checked during
implementation; no relevant hosted Apple-flow breaking change was identified.
