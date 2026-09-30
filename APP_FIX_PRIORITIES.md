# App and Website Fix Priorities

User return-to list for the approved minimal-change campaign. This is not an agent instruction file or automatic work queue. Status, owners, evidence, and blockers live in [operations](docs/operations.md); implementation rules live in [AGENTS.md](AGENTS.md).

## Delivery Order

Dependencies and production safety take precedence over easiest-first ordering. Branding is the easiest independent work; lifecycle, money, and release changes need backend contracts and wider verification. All items below are planned unless operations records verified completion.

| Order | Work together | Scope |
| --- | --- | --- |
| 0 | Documentation gate | App/web agent guides; Supabase, theming, payments, email references; ownership, checkpoints, and minimal-change review |
| 1 | Baseline + safeguards + dependency audit | Preserve existing work; correct backend access; local/deployed reconciliation; reproducible checks; authorization, wallet concurrency, callbacks, CI/toolchain risks |
| 2 | Branding + dark mode + public presentation | App logo, splash, Google auth branding, assets, saved-theme startup, contrast, public website content and accessibility |
| 3 | Login + MFA + first-run terms | No post-login 404; OAuth/deep links/protected routes; required Owner/Admin TOTP, optional customer MFA/recovery; one-time versioned loyalty acceptance before Home |
| 4 | Account lifecycle + consent + email | 30-day recoverable deletion and explicit restore; optional newsletter double opt-in; separate verified-account and newsletter welcomes; retries/unsubscribe/suppression |
| 5 | Home/wallet loading + Realtime removal | Keep cached content visible, deduplicate, ignore stale responses, paginate; entry/return/resume-if-stale/manual/write refresh; remove all Supabase subscriptions |
| 6 | Payments + loyalty refund correctness | Browser/app pay UI and status; authoritative pricing; one vend; secure callbacks; machine/failed-vend/top-up flows; Owner refund review |
| 7 | Firebase + notifications + version controls | Create dev/prod projects on free plan; Analytics, FCM, In-App Messaging; consent/routing/tokens; Remote Config build blocks/update/maintenance |
| 8 | Website/admin completion | Hosting/links/pay UI; account/role/location security; privileged operations; reporting, maintenance/Storage, responsive/accessibility, routing and monitoring |
| 9 | Final hardening + dependencies + policies + release | Compatible package/platform updates; fix audit findings; aligned privacy/terms; device/end-to-end/security checks; Apple/Google standards; controlled rollout/rollback |

## Required Outcomes

- **Smallest safe changes:** preserve working behavior, reuse established code, remove verified obsolete code, and refactor only for demonstrated simplification or task necessity. No speculative frameworks, broad formatting, or dependency churn.
- **Branding/theme:** verify app icons, native/web splash, manifests, Google sign-in buttons/text, and light/dark buttons, dialogs, sheets, forms, maps, auth, home, wallet, and payment surfaces.
- **Auth/terms:** persist accepted loyalty version/time once across password/social signup before Home; reaccept only for an explicit required revision. MFA must include backend enforcement, recovery, and error handling.
- **Deletion:** server-controlled 30-day recovery period preserving original account/wallet links; explicit verified restore before deadline; normal access/marketing restricted immediately. Scheduled retry-safe cleanup must serialize with restore. No reset of refund clocks, duplicate rewards/welcomes, revoked-role restoration, or automatic newsletter resubscription.
- **Retention/legal:** approve data-class retention exceptions and remaining paid-balance treatment before permanent deletion. Update app/web privacy, terms, support/deletion pages, and lifecycle emails together; never promise unimplemented recovery.
- **Newsletter/email:** optional unchecked consent separate from terms; double opt-in; one nonpromotional welcome after verified account creation plus one newsletter welcome after subscription confirmation. Reuse Resend; no-login unsubscribe, delivery dedup/retry, bounce/complaint suppression, no automatic enrollment of existing users.
- **Refresh/cost:** no Supabase Realtime and no general five-second timer. Trigger background pulls while cached content stays visible; bounded polling only for pending payments. Do not display optimistic successful charges or machine starts.
- **Firebase:** dev/prod separation, free plans, token registration/cleanup, foreground/background routing and consent/privacy. Dev/prod Spark projects, separate Analytics properties, and Android/iOS app registrations were provisioned with approved terms on 2026-09-29; environment-safe SDK wiring, consent, iOS support-floor approval, and device verification remain pending (see [Firebase setup](docs/firebase.md)). Infrastructure/test delivery first, no automatic campaigns. No Firestore/Realtime Database/WebSocket/SSE replacement without separate need/cost approval; quota-reviewed Remote Config invalidation may serve urgent release controls.
- **Version control:** minimum/recommended versions, specific blocked builds, store links, maintenance messaging, staged rollout, and emergency override. Honor cached known blocks offline; otherwise permit safe cached browsing. Backend shutdown/authorization is independent of client flags and preserves settlement/refunds.
- **Top-up refunds:** server receipt within 48 hours inclusive of successful funding; no later wallet spend, including bonus-only or subsequently reversed failed-vend spend. Earlier account use is allowed. Owner review, full principal to original payment method, business absorbs fees, no partial voluntary refund initially, no bonus cash. Reserve atomically, unwind reward progress, and reconcile provider uncertainty without duplicate money effects.
- **Separate refund flows:** do not conflate the new top-up policy with machine-claim promo credits, failed-vend reversals, legal remedies, or ledger-only cash bookkeeping. Details: [payments](docs/payments.md).
- **Security/keys:** audit Auth/sessions, RLS/Storage, endpoint authorization, local storage, deep links, payments, logging, abuse controls, and permissions. Named publishable keys per client/environment and named server secrets per component; migrate all consumers before approved legacy-key retirement. Secret keys still bypass RLS.
- **Dependencies:** current compatible supported Flutter/Dart, Firebase/Supabase, Android Gradle/Kotlin, iOS, and web packages; remove unused packages, address vulnerabilities/deprecations, review breaking changes, isolate major upgrades, and verify lockfiles. No blanket automatic upgrade/fix.
- **Release:** align privacy labels/Data Safety with actual SDKs/consent, check current Apple/Google requirements, permissions, reviewer access, policy/deletion links, release builds, physical-machine operation, support/monitoring, rollback, and legal/business signoff.

## Website Detail

Retain the website review below as the detailed checklist; it shares auth, payments, privacy, and backend contracts with the app. Existing local admin work must be reconciled, not rebuilt.

1. Complete production hosting and domain setup.
   - Scope: connect the Vercel project to `cleanstreamlaundry.com`, configure DNS and SSL, redirect `www`, and verify SPA rewrites.
   - Include: `/pay`, `/admin`, legal pages, support, account deletion, Apple association, and Android association routes.

2. Review the public website and content.
   - Scope: verify navigation, location information, contact details, support hours, branding, images, calls to action, and mobile presentation.
   - Include: confirm the correct support email and remove inaccurate or unfinished scaffold copy.

3. Review legal and store-facing pages.
   - Scope: verify Privacy Policy, Terms, account deletion, support, retention language, wallet terms, refund language, and payment disclosures.
   - Include: confirm that the URLs and wording meet Apple, Google Play, Stripe, and business requirements.

4. Finish the browser payment experience.
   - Scope: review machine lookup, washer pricing, the six configured dryer choices, card checkout, wallet availability, cancellation, return routing, and status polling.
   - Include: clear states for invalid QR, disabled machine, changed price, declined payment, starting, started, timed out, refunded, and support required.

5. Review Cortina web and backend integration.
   - Scope: verify server-authoritative pricing, one Nayax Start request, device mapping, dryer product or pulse selection, callbacks, duplicate handling, timeout compensation, and live-device testing.
   - Include: strict transaction, terminal, amount, currency, and environment matching.

6. Harden public payment security.
   - Scope: add rate limiting and abuse protection to public quote, card, and status endpoints.
   - Include: require supported Nayax callback authentication or network controls and remove session access tokens from browser URLs and logs.

7. Fix admin authentication and authorization.
   - Scope: review session restoration, sign-out, token refresh, invalid-role handling, protected-route redirects, MFA, and multi-tab session changes.
   - Include: test Owner, Admin, customer, and anonymous access with crafted Supabase requests and cross-location attempts.

8. Review privileged admin operations.
   - Scope: verify employee assignment, role changes, location creation, machine configuration, washer rates, machine deletion, refunds, and maintenance deletion.
   - Include: transactional updates, server-side authorization, audit records, duplicate-submit prevention, and accurate failure messages.

9. Fix refund processing correctness.
   - Scope: ensure Edge Function errors are thrown instead of returned as successful data.
   - Include: update the displayed refund status only after confirmed success and prevent duplicate approvals, denials, refunds, or notifications.

10. Review reporting and data access.
    - Scope: verify revenue totals, transaction categories, integer-cent handling, location time zones, date boundaries, and location filtering.
    - Include: replace unrestricted `select("*")`, full-table browser aggregation, and unpaginated transaction queries with scoped server queries.

11. Review privacy and maintenance data.
    - Scope: verify location-based access to maintenance records, customer information, descriptions, and attachments.
    - Include: secure Storage policies, image validation, retention, removal of unnecessary raw user IDs, and safe attachment links.

12. Complete responsive and accessibility review.
    - Scope: test all public and admin pages on phone, tablet, and desktop.
    - Include: table overflow, form labels, keyboard navigation, modal focus management, icon-button names, screen-reader announcements, contrast, and reduced-motion behavior.

13. Review routing, assets, and failure states.
    - Scope: test direct URLs, refreshes, browser history, unknown routes, expired sessions, and Stripe return links.
    - Include: add a deliberate 404 page and replace remaining development `/src` image paths with production-bundled imports.

14. Complete security and dependency review.
    - Scope: upgrade vulnerable React Router packages, run `npm audit`, review third-party packages, and verify that no service-role secret can enter a browser build.
    - Include: restrict or proxy the geocoding API key, add appropriate security headers, and run Supabase security and performance advisors.

15. Strengthen testing and deployment checks.
    - Scope: add required TypeScript checking, lint, tests, build, dependency audit, and browser end-to-end tests to CI.
    - Include: test real route wiring and dependency injection currently excluded from coverage, not only mocked components.

16. Add production monitoring and support operations.
    - Scope: monitor browser errors, Edge Function failures, failed vends, callback rejection, refunds, and `support_required` sessions.
    - Include: documented machine disablement, manual refund review, deployment rollback, database restore, and incident response.

## Website Release Acceptance

- All public and admin routes load directly from the production domain.
- Apple and Android association files return valid JSON without redirects.
- Owner and Admin access is proven to be location-scoped at the database level.
- Browser washer payments and all six dryer options pass live-device testing.
- Duplicate and failed payment scenarios cannot vend, charge, or refund twice.
- Type checking, lint, tests, build, dependency audit, accessibility checks, and end-to-end tests pass before deployment.

## Shared Boundary

This is a combined app and website campaign. Shared backend changes live in the app repository and have one Backend owner. The website owns browser checkout/admin/public pages and association files; Flutter owns mobile UX. Preserve existing local work and use explicit deployment gates rather than publishing the entire dirty workspace.
