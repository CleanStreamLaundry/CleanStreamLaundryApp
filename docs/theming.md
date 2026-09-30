# Theming and Refresh UX

Local source reviewed 2026-09-29. Paths below are relative to the named repository. These are implementation references, not a new design system or evidence of visual acceptance.

## Existing Patterns

| Surface | Reuse / source |
| --- | --- |
| Flutter | `lib/core/theme/theme.dart`: Material 3 light/dark, blue `#2073A9`, yellow `#F3C404`, custom getters and gradients |
| Flutter preference | `lib/core/theme/theme_manager.dart`, `lib/root_app.dart`: manual persisted toggle; startup waits for preference restoration before the first app frame, with light fallback on storage failure; not system mode |
| Flutter shell | `lib/features/widgets/base_page.dart`, `custom_app_bar.dart`; feature-local widgets |
| Assets | `assets/Icon.png`, `Logo.png`, `Slogan.png`, `splash-logo.png`; `pubspec.yaml`; native/web generated assets |
| Google sign-in | `assets/Google.png`, bundled `assets/fonts/google_sans/GoogleSans-Medium.ttf` and OFL; font used only by the Google label |
| Website public | `src/components/PublicLayout.tsx`, `src/styles/PublicSite.css`, `.public-*`; 800/520px breakpoints |
| Website pay | `src/components/CortinaPayPage.tsx`, `src/styles/CortinaPay.css`, `--pay-*`; 896/560/370px breakpoints |
| Website admin | `src/admin/AdminApp.tsx`, `admin.css`, `ui.tsx`; `.admin-portal`, `--ap-*`, `.ap-*`, Field/Notice/Badge/Modal/pagination |

Website paths refer to the active `CleanStreamWeb-CortinaQR` checkout, not the older main worktree. Resolve its actual path in isolated worktrees. Public, checkout, and admin styling differ intentionally; do not consolidate them merely for uniformity.

## Local State

- Launcher config now references existing `assets/Icon.png`; generation is not yet accepted. The source is non-square and transparent, so avoid distortion and verify platform mask/safe areas before regeneration. Web icon references and native launch-theme selection still need review.
- Saved-theme startup has focused regression and independent QA coverage. Native light/dark launch transitions still need device verification; widget evidence alone does not establish splash acceptance.
- Official Google mark/font are integrated locally with no runtime font fetch or new SDK. Composer and independent QA pass 29 focused tests and clean scoped analysis; worker render/browser evidence was reviewed. Preserve the supplied mark's aspect ratio and scope Google Sans to its button; do not apply it as the global app font. Follow [Google's current branding guidance](https://developers.google.com/identity/branding-guidelines).
- Flutter `fontPrimary` is white in light mode and black in dark mode; `fontInverted` reverses it. Do not rename globally or assume semantic contrast from names alone.
- App-bar action icons now explicitly use `fontInverted`; the one-line change preserves gradient, navigation and notification behavior. Composer passes all 34 shared-widget tests; independent QA passes 35 including the render harness. Light-action minimum contrast improves from 2.190:1 to 7.744:1 with unchanged dark renders across 12 cases.
- Profile values now wrap within the existing row and the deletion acknowledgement dialog scrolls. Only two runtime layout changes; worker/composer/independent QA pass 49 tests, with 16 worker real-font fixtures. Deletion behavior and acknowledgement requirements are unchanged.
- Navigation dark-label contrast is independently accepted: existing foreground tokens improve minimum rendered contrast from 3.13:1 to 6.01:1. Worker/QA pass 23 tests and verify 28 before/after frame pairs preserving light appearance, icons and safe areas. Route-driven rebuilding remains necessary when using the existing NavBar in a retained shell; the patch adds no route listener.
- Settings contrast and narrow/large-text reflow pass independent 58 tests plus 8 real-font fixtures. Existing theme colors are reused; notification controls move below their labels only when the current two-line layout would truncate. Existing 45 tests, controller behavior and fitting light layouts are preserved, apart from the corrected sign-out button contrast.
- Profile field/danger-text contrast is independently accepted with only three runtime widget edits (net three lines). Existing tokens replace insufficient opacity without changing validation, deletion copy/actions, icons or geometry. Worker/QA pass 49 tests and 24 real-font fixtures; all 128 captures match. Scoped minimum contrast is 5.74:1 dark/4.94:1 light. Existing enlarged hint truncation and 4.47:1 dark validation-error text remain separate known issues.
- Login and Legal action contrast fixes are independently accepted, one runtime line each: existing primary fill/white foreground, no layout or auth/policy behavior change. QA passes 34 Login tests plus 8 real-font fixtures, and 17 Legal plus 4 fixtures; corrected router gate passes 35 and combined app passes 1,832. Contrast is 5.14:1 in both modes; Legal's light renders are unchanged.
- Loading/ErrorView use existing opaque surface/readable tokens, with seven net runtime lines and no controller/animation changes. Independent QA passes 15 tests plus two real-font probes; five sampled frames per mode stay opaque white/#212121. This does not establish native splash-to-Flutter transitions. Login labels independently pass 49 checks: two foreground expressions reuse `fontSecondary`, preserving error text/red cues and geometry; minimum contrast 15.91 light/6.01 dark. The app-bar test's unsupported matcher is replaced with equivalent explicit assertions, independently passing 13 tests and clean scoped analysis on both pinned and installed Flutter; runtime is unchanged.
- Public missing routes now use the existing public document layout with Home/Support links, not an automatic redirect or URL reflection. Footer focus contrast and narrow/enlarged-text wrapping are repaired. Checkout's 896px breakpoint prevents intermediate-width overflow; progress/helper contrast uses existing colors without payment-state changes. Independent QA passes 46 tests, types/scoped lint, and review of 54 browser observations; local acceptance does not change hosting HTTP status behavior.
- Dark card/gradient values remain light in places. Cortina payment surfaces also mix hard-coded white and theme-derived colors. Review actual foreground/background pairs, not only color getters.
- Web `_variables.css` and surface-specific palettes are not one unified token system. No active website dark-mode mechanism was found; app dark-mode fixes do not authorize a website redesign.

## Target and Boundaries

- Reuse existing tokens/components and scoped CSS. Repair incorrect states and references; do not replace the theme system, introduce a styling library, or change working layouts without a concrete defect.
- Fix logo, splash, Google sign-in presentation, both-mode contrast, and saved-theme startup together. Check buttons, dialogs, sheets, forms, maps, auth, home, wallet, and payments.
- Preserve existing content, scroll, and inputs during background refresh. Full initial loading is for no usable data; refresh errors must not erase usable content. Distinguish unknown/empty/stale states.
- Refresh on entry/return, resume when stale, user action, or completed write; ignore old-user/location results. No five-second background refresh loop. Money/machine success remains server-confirmed.
- Keep theme patches separate from payment/auth logic, unrelated dirty controllers, dependency upgrades, and generated asset churn. Regenerate only required platform assets once source/config are verified.

## Verification

- Start with `flutter test test/core/theme`, `flutter test test/features/settings`, and relevant `test/features/widgets` tests. Add saved-theme startup and affected dark payment coverage with the fix.
- Website component tests: `src/components/CortinaPayPage.test.tsx`, `src/admin/AdminWorkspace.test.tsx`. Vitest disables CSS; passing them does not prove layout/contrast.
- Inspect iOS/Android light/dark screens, cold start, narrow screens, large text, focus, keyboard/screen reader, reduced motion, loading/error/empty states, and asset rendering. Use fixture-only screenshots around actual CSS breakpoints for web.
- Record before/after evidence for changed surfaces, not a new screenshot baseline for unrelated screens.
