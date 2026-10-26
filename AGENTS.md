# Agent Guide

Be warm, direct, repo-aware, and verification-minded. This guide governs this repository; it does not authorize deployments or queued features.

## Smallest Safe Change

- Read related implementation/tests first; reuse working controllers, services, helpers, components and theme tokens. Write the least new code necessary; preserve behavior/public contracts unless assigned otherwise.
- No speculative frameworks, parallel implementations or hypothetical abstractions. Refactor only for the task or demonstrably lower duplication/dependencies/complexity without regressions; keep optional refactors separate. Use clear names, focused responsibilities and consistent errors, not clever compression.
- Remove verified replaced/unused code and dependencies, including competing refresh/payment paths. No unrelated renaming, formatting, generated-file or dependency churn. Justify additions by complexity removed; report reuse/removal/additions, why simpler was insufficient and compatibility evidence.

## Product and UI Acceptance

- A request to remove one control or polish a screen does not authorize removing
  other actions, changing defaults, or replacing the workflow. Preserve the
  owner's choices; ask before an additional product change. Agent implementation
  notes are not owner approval.
  Requested corrections and routine behavior-preserving fixes need no additional
  approval.
- Apply the [finished-UI checklist](docs/theming.md#finished-ui-checklist) before
  calling UI work done. Tests/build success prove function, not visual quality.
  Inspect every changed screen's actual rendered states, including headers,
  against the request and existing brand; do not
  accept visibly awkward wrapping, oversized copy, misalignment or lost controls.
- Review real-font renders before the expensive native build, then inspect the
  installed result. Show a final screenshot for a requested visual refinement;
  distinguish functional checks from owner design approval.
- For before/after requests, freeze the current source before editing and use
  matching data, dimensions, fonts and accessibility settings. Label fixture
  captures separately from device screenshots. A screen-specific color request
  must not silently restyle other tabs through shared theme tokens.
- Before adding a cache for navigation flashes, trace page/controller disposal
  through the actual router. Retain existing account-scoped state where possible;
  test first-return frames, not just settled screens or isolated page fixtures.

## Order, Ownership and Resources

- Honor explicit stage order: implementation/setup, known fixes, testing/verification. No early QA, analysis, builds, simulator/browser checks or broad audits; necessary source reading is implementation. Announce each stage complete. Record the current stage, evidence, assignments, gates and blockers in [operations](docs/operations.md), not here. Assign unavailable approvals/access/devices to the user with dependent work; park unsafe activation, never remove safeguards or call blocked work done.
- Runtime waits for the documentation gate's recorded evidence, not inferred approval. Provider production labels are not release status. After approved development activation, do not hold completed features off solely for testing; retain authorization and concrete missing-input/destructive guards, recording each disable reason.
- Check `git status --short` before/after edits; preserve dirty/untracked user/other-task work. Composer verifies isolated writable roots and assigns an absolute root, owned files and one writer per file. Read-only inputs are not edit targets; use reviewed baselines, not unreviewed dirty copies/other lanes.
- Backend owns migrations, RLS, Storage, functions and shared financial/Auth contracts. Composer coordinates router/startup/DI, manifests, native configuration, dependencies and integration.
- Finish each requested deliverable/acceptance check before another audit/refactor loop; deliver coherent batches. Separate local gaps, external setup and rollout. Default to one critical-path implementation lane plus independent QA; additional requested lanes need disjoint ownership and useful benefit.
- Serialize memory-intensive checks in one composer-assigned slot; no parallel browsers/native builds. Prefer one QA-owned queue: authors freeze batches and supply exact commands/prerequisites; QA writes only test outputs. Preauthorized transfer names the next owner; release with terminal results immediately after all owned processes exit, before hashes/handoffs.
- Delegate `medium` for routine implementation/docs/styling/tests; `high` for Auth/payments/database/concurrency/difficult QA. Extra-high needs a concrete unresolved problem. Keep inherited model unless requested otherwise; effort follows risk, not composer settings. Escalate with evidence; finish bounded work before replacing an agent whose effort cannot change.
- After the Mac restart, one bounded check at a time; no automatic pool/simulator/native-build/preview restart. Reuse caches without full copies; keep isolated work/handoffs in workspace `.campaign-work/`. Verify surviving files/process handles after interruptions; past receipts are not reproducible evidence.
- Keep `FLUTTER_TOOL_ARGS=--old_gen_heap_size=512` across pinned Flutter tests, analysis and native wrappers, including indirect Gradle invocations. Match the verified cache; toggling the value rebuilds Flutter/resolves SDK dependencies. Do not delete/rebootstrap it.
- Freeze dependency discovery per batch; record compatibility/scope deferrals. Reuse unchanged accepted evidence, not repeated discovery, whole-workspace fingerprints or author/QA/composer reruns. One focused QA run suffices after source-only author review; rerun changed inputs/concrete failures. After two failed attempts, record blocker and change approach or do unblocked work. Never save usage by weakening financial/authorization/data-integrity checks.
- Search the named source/evidence directory, not all of `.campaign-work`; SDK, Pub, Pods, Gradle and DerivedData copies overwhelm unrelated searches. Request only the status fields or log lines needed for the next decision.

## Project and References

- Flutter delivery is iOS/Android only; browser app/hosting is deferred. Preserve cross-platform code without expanding scope. Sibling `CleanStreamWeb-CortinaQR` owns React public pages, browser checkout and administration, not separate `CleanStreamWeb` main.
- `lib/main.dart` starts; GetIt: `lib/core/di/di.dart`; GoRouter: `lib/core/router/app_router.dart`; startup `/loading` then normally `/homePage` or `/login`.
- Features: `lib/features/<feature>/` pages/controllers/widgets; models/interfaces: `lib/logic/`; implementations: `lib/services/`. Reuse DI; update affected test constructors with contracts. Shared widgets: `lib/features/widgets/`; theme: `lib/core/theme/`; persistence: `lib/core/storage/`; assets: `assets/`, `pubspec.yaml`, `web/`, `android/`, `ios/`.
- Auth spans router, loading controller, auth service and `clean-stream://` links: inspect all four. Financial changes span interfaces, implementations, Edge Functions and SQL; read payments first. Backend endpoints/functions and migrations remain app-owned; website consumes shared contracts.
- Terms/Privacy review drafts live in `lib/features/legal/legal_drafts.dart` and
  website `PublicLegalPage.tsx`; keep the wording aligned without a runtime
  sibling-repository dependency. Draft approval is separate from publication or
  changing the immutable Supabase loyalty agreement and acceptance version.
- A lifecycle/policy change must include the public deletion page, current
  acceptance document, customer notices and server deadline, not just the draft.
  Preserve historical policy/receipts; identify local candidates versus deployed
  versions. Sign-in provider disclosure must match both the existing browser
  flow and native setup, not merely an installed package or an enabled console toggle.
- Per-action legal acknowledgement must use the displayed server policy snapshot,
  not local draft copy. Bind receipts to caller/action/amount or displayed balances;
  retain unknown-outcome reconciliation. Unpublished surrender wording does not
  authorize changing balances or erasing historical acceptances.

Read the relevant reference for the boundary being changed. **Before Auth/admission, async/account, database/payment, native/dependency/tool or fixture work, read the matching focused sections of [Engineering Lessons](docs/engineering-lessons.md).** These required lessons do not grant approvals.

| Work | Reference |
| --- | --- |
| Backend, Auth, RLS, keys, lifecycle | [Supabase](docs/supabase.md) |
| Portal roles, financial privacy, staff scope | [Admin Permissions](docs/admin-permissions.md) |
| Branding, themes, components/loading | [Theming](docs/theming.md) |
| Wallet, Stripe, Cortina, refunds | [Payments](docs/payments.md) |
| Loyalty terms, publication and consent | [Loyalty Terms](docs/loyalty-terms.md) |
| Consent, lifecycle email, newsletter | [Email](docs/email.md) |
| Firebase, notifications, release controls | [Firebase](docs/firebase.md) |
| Security, toolchains, upgrades | [Dependencies](docs/dependencies.md) |
| Assignments, gates, commands, rollout | [Operations](docs/operations.md) |

[APP_FIX_PRIORITIES.md](APP_FIX_PRIORITIES.md) is the user's return-to list, not instructions/automatic work. Do not duplicate it or implement unassigned items. Keep one current operations record; replace stale entries, link superseded evidence, consult history only as needed. Keep handoffs/log excerpts concise; link full inventories.

On resume, read only operations' Current Checkpoint and Remaining Work first. Open a named historical receipt only for the boundary being changed; do not reread Evidence History or restart its superseded pending items.

## Safety

- Verify actual Clean Stream project before remote action; inspect deployed state before risky changes. Never substitute Gundex/another accessible project or replace unrelated connector accounts. When authorized, use the correct signed-in browser console.
- Before calling a scheduled workflow complete, trace its prerequisite records to
  their actual writer and verify activation separately from installation. Derive
  factual inventory from existing data; never manufacture human review or
  provider-erasure evidence to bypass a missing prerequisite.
- Bundled Flutter `.env` is public client configuration. No privileged Supabase/Stripe/provider credentials in assets, logs or docs.
- No paid services, production deployment, destructive migration or legacy-key retirement without explicit approval. Rehearse recovery and reconcile pending payments before release. Access/development approval does not imply billing or destructive approval.
- No new Supabase Realtime, general timers, another database or live infrastructure by default. Quiet event-driven refresh; polling only for pending payments. Keep SDK Auth session listeners (not database subscriptions); public policy reads must not require signed-in refresh. Verify transport, not headers alone.
- Account/payment truth stays server-side. Duplicate events require matching stored owner/binding; recheck current state after awaits before vend approval. Protect historical partial-write audit evidence too. Never weaken authorization, financial checks or recovery. Distinguish collection, wallet spending and machine activity; join verified provider IDs before counting money. Cached diagnostics/portal access do not prove API entitlement.
- Bind mutations to intended caller before dispatch; guard late completion against account/route changes, including A-to-B-to-A. Cleanup/timeouts cannot undo dispatched side effects. Read guards must not add money-write deadlines/retries.
- Start Auth transport work with real-SDK/fake-HTTP happy path before mocked races. Test actual shared router/admission, including open protected modals/payment pages inside its navigator. Invalidate cached admission after lifecycle mutations; unresolved presentation may persist, resolved restrictions must expose recovery. New startup privacy choices outrank saved snapshots.
- Verify current official vendor docs before SDK/API changes. Failed/skipped checks are not passes.

## Verification and Handoff

- In the authorized stage, nearest `flutter test test/<area>`, then related integration; Flutter toolchain and actual repository analysis configuration/pins. Honor `dart_test.yaml`/CI partitions and synthetic `firebase-configured` notification fixtures. Shared contracts need `flutter analyze`/broader tests; native builds/full suites/broad security checks belong to shared-contract or release gates. Reduced harnesses are not integrated acceptance; separate baseline diagnostics.
- Read completed output, exact case counts and exit status. Interrupted loaders, zero cases and running commands are not passes; correct inaccurate receipts. Verify intended contracts before changing behavior/assertions to make tests green.
- Docs-only work: source/link/consistency checks, no builds or remote mutation. Distinguish local/deployed evidence and unrun/blocked checks.
- Handoff promptly: owned/frozen exact paths/bytes, behavior preserved/changed, reuse/removal, commands/counts/exit/cleanup, risks/blockers and docs. Send before next batch; inspect named active paths after READY, not stale queued messages. Do not idle disjoint work for pending checks.
- Stop at docs, baseline/contracts, waves, significant failure, pre-release and key-retirement checkpoints; resolve failures before dependent work. Update guides only with durable verified lessons, references with detail and operations with evidence; remove repetition, not safeguards.
