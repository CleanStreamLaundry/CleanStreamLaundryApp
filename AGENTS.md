# Agent Guide

Be warm, direct, repo-aware, and verification-minded. Leave the project easier to work on, not larger by default. This guide governs this repository; it does not authorize deployments or queued features.

## Smallest Safe Change

- Read related implementation and tests before editing. Identify what works and reuse it.
- Write the least new code necessary for the requested behavior. Preserve working behavior and public contracts unless the task explicitly changes them.
- Prefer existing controllers, services, helpers, components, and theme tokens. No speculative frameworks, parallel implementations, or abstractions for hypothetical requirements.
- Refactor only when required by the task or when it demonstrably reduces duplication, dependencies, or complexity without regressions. Keep optional refactors separate.
- Use clear names, focused functions, explicit responsibilities, and consistent error handling. Fewer lines are evidence, not a reason for clever compression or weaker safety.
- Remove replaced code and unused dependencies after verification. Do not retain competing refresh/payment paths.
- Keep diffs focused: no unrelated renaming, formatting, generated files, or dependency churn. Justify new abstractions/packages by the complexity they remove.
- Report what was reused, removed, and added; why a simpler solution was insufficient; and what proves compatibility.

## Work Efficiently

- Deliver coherent feature batches, not repeated proposal/review cycles for tiny edits. Once scope and contracts are clear, implement and verify.
- Keep only critical-path agents active. Default to one implementation lane plus independent QA; add parallel work only when its benefit exceeds coordination cost.
- Set delegated reasoning effort explicitly: `medium` for routine implementation, docs, styling, and straightforward tests; `high` for auth, payments, database changes, concurrency, and difficult QA. Reserve extra-high for a concrete unresolved problem, not the default. Keep the inherited model unless the user requests another.
- Assign effort by task risk, not the composer's setting. Escalate only when evidence warrants it. If an agent's effort cannot be changed in place, finish its bounded batch and set the next agent appropriately rather than restarting completed work.
- Run focused checks once during implementation and once independently in QA. Composer reviews the diff and evidence instead of routinely running a third copy. Rerun only after a relevant change or to investigate a concrete failure.
- Reserve full suites, native builds, and broad security checks for shared-contract changes or release checkpoints. Never weaken financial, authorization, or data-integrity verification to save usage.
- Reuse accepted evidence while its inputs are unchanged. Check owned files and relevant dependencies, not repeated whole-workspace fingerprint inventories.
- Read targeted sections, keep handoffs concise, and maintain one current status record. Do not duplicate long logs, historical narratives, or complete context across agents.
- After two unsuccessful attempts at the same check, record the blocker and change approach or move to unblocked work. Do not spend repeated runs proving the same environment failure.

## Read Only What You Need

| Work | Reference |
| --- | --- |
| Backend, auth, RLS, keys, account lifecycle | [Supabase](docs/supabase.md) |
| Branding, dark mode, components, loading states | [Theming](docs/theming.md) |
| Wallet, Stripe, Cortina, refunds | [Payments](docs/payments.md) |
| Consent, welcome/lifecycle email, newsletter | [Email](docs/email.md) |
| Firebase environments, notifications, release controls | [Firebase](docs/firebase.md) |
| Package security, toolchains, upgrade batches | [Dependencies](docs/dependencies.md) |
| Assignments, gates, commands, blockers, rollout | [Operations](docs/operations.md) |

[APP_FIX_PRIORITIES.md](APP_FIX_PRIORITIES.md) is the user's return-to list, not agent instructions or an automatic work queue. Do not duplicate it here or implement unassigned items merely because they are listed.

Keep operations focused on current assignments, approvals and evidence summaries. Preserve superseded detail in a linked verification record; consult that history only when the current task needs it.

## Project Map

- Flutter mobile/web client. Support iOS and Android; preserve Flutter web compatibility. The companion React website owns browser checkout and administration.
- `lib/main.dart` starts the app; `lib/core/di/di.dart` uses GetIt; `lib/core/router/app_router.dart` uses GoRouter. Startup currently enters `/loading`, then normally `/homePage` or `/login`.
- Features use `lib/features/<feature>/` pages, controllers, and widgets. Read the existing feature before introducing structure.
- Models/interfaces: `lib/logic/`; implementations: `lib/services/`. Reuse DI and update affected test constructors when changing a contract.
- Shared shell/widgets: `lib/features/widgets/`; themes: `lib/core/theme/`; small local persistence: `lib/core/storage/`.
- Assets: `assets/`; icon/splash configuration: `pubspec.yaml`; generated/platform assets: `web/`, `android/`, `ios/`.
- Auth entry spans the router, loading controller, auth service, and `clean-stream://` deep links. Check all four before changing OAuth, verification, reset, or post-login redirects.
- For web callbacks, verify the actual document URL, base path, and Flutter URL strategy as well as the router URI. Hash routes and top-level OAuth parameters are different inputs. Keep one callback consumer and test exchange, cleanup, reload, and failure without relying only on mocked route strings.
- Financial changes cross interfaces, implementations, Edge Functions, and SQL. Read the payments reference first; never infer success from UI state.

## Safety and Coordination

- Check `git status --short` before/after edits. Preserve dirty and untracked user/other-task work; never reset or overwrite it.
- Composer assigns one writer per file and verifies the isolated writable root before dispatch. Every assignment names that absolute root and owned files; read-only input paths are not edit targets. Use a reviewed baseline, never unreviewed dirty copies or another lane's changes.
- Backend owns migrations, RLS, Storage, functions, and shared financial/auth contracts. Composer coordinates router/startup/DI, manifests, native configuration, dependencies, and integration.
- Runtime work waits for the documentation gate in [operations.md](docs/operations.md). A gate passes only with recorded evidence, not inferred approval.
- Verify the actual Supabase project before any remote action. Docs orient you; deployed state must be inspected before risky changes. Never substitute another accessible project.
- Preserve unrelated cloud projects and connector accounts. When authorized, use the correct signed-in browser console instead of replacing another project's connection.
- Flutter `.env` is bundled as an asset. Its values are public client configuration, not secrets. Never put privileged Supabase, Stripe, or provider credentials there, in logs, or in docs.
- No paid services, production deployment, destructive migration, or legacy-key retirement without explicit approval. Rehearse recovery and reconcile pending payments before release.
- No new Supabase Realtime. Refresh content quietly on meaningful events; bound polling to pending payments. Do not add general timers, another database, or live infrastructure by default.
- Keep SDK Auth session-change listeners; they are not Realtime database subscriptions. Public policy reads must not depend on refreshing a signed-in session. Verify transport behavior, not just request headers.
- Nonpersistent Auth clients can still share browser broadcast state. Disabling storage or token refresh does not establish isolation; verify cross-client effects in a browser before relying on temporary clients.
- Keep account/payment truth server-side. Do not weaken authorization, idempotency, financial checks, or recovery to reduce code.
- Bind asynchronous mutations to the intended caller before dispatch and guard late completion against account/route changes, including A-to-B-to-A. UI cleanup or a response timeout cannot undo SDK/server side effects already started.
- Audit effective table/column grants, policies, triggers, and executable functions together. RLS being enabled or a column-level revoke alone does not prove sensitive fields are protected; check inherited/table-wide privileges and trusted-function paths.
- Verify current official vendor docs before SDK/API changes. Prefer narrow MCP inspection where useful, then local tools. A failed/skipped check is not a pass.

## Verification and Handoff

- Start with the nearest `flutter test test/<area>`, then related integration tests. Use Flutter's toolchain for Flutter code.
- Run `flutter analyze` and broader tests for shared contracts; native builds belong to release gates. Environment caveats and backend/web commands are in operations.
- Isolated checks must use the repository's actual analysis configuration and pinned toolchain. Compare existing diagnostics separately; a clean reduced harness is not a clean integrated repository.
- Verify completed test-case counts, not only exit status or runner summaries. An interrupted loader or zero-case run is not a passing regression check.
- Check newly used framework APIs against the pinned CI/minimum SDK source, not only a newer installed SDK or current API documentation. Do not raise requirements or hide diagnostics just to make a candidate pass.
- When tests disagree with current behavior, verify the intended contract before editing either. Do not change working behavior or weaken assertions just to obtain a green run. For async findings, test delayed completion/failure through public behavior; a diagnostic alone is not proof of a user-visible bug.
- Docs-only edits need source/link/consistency checks, not app builds. Never mutate a remote service to validate docs.
- Handoff: owned files, changed/preserved behavior, reuse/removal, commands/results, unrun checks, risks/blockers, and doc updates. Distinguish local from deployed evidence.
- Hand off each independently verified batch promptly; do not hold an urgent fix behind unrelated queued checks. Freeze accepted artifacts and identify exact bytes before deployment.
- Stop at checkpoints: docs, baseline/contracts, each wave, significant verification failure, pre-release, and key retirement. Resolve failures before dependent work.
- Update this guide only with durable verified lessons. Put transient evidence in operations and details in the relevant reference. Remove stale/repeated guidance instead of appending a diary.
