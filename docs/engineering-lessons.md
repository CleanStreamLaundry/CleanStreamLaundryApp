# Engineering Lessons

Required boundary reading under both AGENTS guides: read the matching sections before changing Auth/admission, async/account, database/payment, native/dependency/tool or fixtures. These are retained verified lessons, not deployment permissions. Current assignments, approvals, commands and evidence remain in [operations](operations.md); backend contracts in [Supabase](supabase.md), money contracts in [payments](payments.md), toolchain pins in [dependencies](dependencies.md).

## Auth Transport and Admission

- Diagnose required MFA using the exact account's server role/factors/recovery
  state; do not infer that a personal Google login is a customer or management
  account. Correct roles only for explicitly identified identities, preserving
  audited grants and last-Owner safeguards.
- Browser OAuth and native Google sign-in are different integrations, not a
  logo/package-version setting. Native sign-in needs platform clients, matching
  Android signing certificates/iOS callback schemes, accepted Supabase audiences
  and explicit session-completion navigation. Reuse another app's pattern, never
  its client IDs, credentials or project configuration.

- An in-place install preserves existing sessions; do not confuse a retained
  account's MFA gate with signed-out customer onboarding. Required verification
  must identify the active account and offer a public Login escape without
  granting protected access, enrolling factors or changing roles.
- Match Auth copy to the configured email and actual app consumer, not vendor
  default examples. Code verification and credential-bearing link acceptance
  are different checks; neither proves final password submission.
- Start new Auth transport work with one real-SDK, fake-HTTP happy path before expanding mocked races. Catch replay/cleanup assumptions early. For SDK error mapping, include a result different from generic-error fallback; matching server output alone does not prove exception decoding.
- Supabase Dart replays the latest Auth event to new subscribers. A session-bound
  page must distinguish the initial captured-session replay from a new sign-in;
  do not blindly skip the first event or ignore every same-user sign-in. Cover
  restored sessions, recovery and replacement sessions with real-SDK transport
  fixtures; broadcast-only mocks can hide a checkout that never loads.
- Verify session adoption itself: an SDK lock or pre-call guard does not prove safety across password login, account replacement or awaited user lookup. Do not assume Dart and JavaScript SDK guarantees match.
- Native Google exchange uses an isolated Auth client before guarded adoption.
  Pinned gotrue fresh `recoverSession` commits synchronously but omits same-user
  events; use guarded refresh for that case. Require explicit expiry headroom,
  invalidate abandoned attempts, and test delayed exchange against replacement
  login/sign-out plus same-user persistence. Never reuse native isolation on web
  without checking its broadcast behavior.
- Nonpersistent clients can share browser broadcast state. Disabling storage/token refresh does not establish isolation; verify cross-client browser effects before relying on temporary clients. Keep Auth session-change listeners; public policy reads must not depend on signed-in refresh. Verify transport, not headers alone.
- For web callbacks, verify actual document URL, base path and Flutter URL strategy as well as router URI. Hash routes and top-level OAuth parameters differ. Keep one callback consumer; test exchange, cleanup, reload and failure, not only mocked route strings.
- Keep single-use Auth-payload deduplication separate from reusable plain recovery navigation. Test reopening the same recovery link after leaving its page; a first-delivery pass misses lifetime suppression. Native warm-link evidence needs a distinct starting screen, not Login remaining on Login.
- Distinguish route freshness from global Auth lifecycle. Discard late page effects and prevent stale verification/adoption starts. An already-dispatched same-session refresh may complete after navigation; never restore old tokens to undo it. Account replacement/sign-out must win; refreshed credentials do not replace server admission. Tests must state this boundary, not demand unsupported SDK cancellation.
- Website Auth 2.103.3 requires the reviewed `scripts/auth-refresh/` patch and new storage domain together. `npm ci` applies it; build verifies exact installed bytes. No bypass, old-token import or upgrade without replacing/verifying the patch. Installer fixtures use `npm run test:auth-sdk`, separately from UI tests.
- Protected dialogs/pushed payment pages belong inside the admission-controlled navigator. Root overlays can remain actionable above blocked shells: test changes while the real modal is open. Invalidate cached admission after lifecycle mutations before recovery navigation; route changes alone can reuse Home permission. Test actual shared router/gate.
- Preserve protected presentation only while admission is unresolved; resolved restrictions must expose recovery, not an inert screen. New startup privacy choices outrank saved consent snapshots.
- Inspect individual frames for admission transitions. A listening recovery child can redraw before its deferred parent and briefly expose a ready-account recovery screen; settled assertions miss it. Schedule safe parent updates in the same frame while retaining deferral for build-time SDK notifications.

## Async Mutations and Account Cleanup

- Auth events can dispose a protected page before logout completes. Capture its existing router before awaiting; redirect only if still signed out, without stealing navigation from a newer session. Reproduce this with the real admission gate, not a standalone page mock.
- Bind caller/attempt before dispatch; guard late completion and URL cleanup against newer account/route state, including A-to-B-to-A. Test delayed completion/failure and departure/return through public behavior; diagnostics alone do not prove user-visible bugs.
- Cleanup or response timeout cannot undo SDK/server effects already started. Reusing read guards must not silently add deadlines/retries to money writes.
- Preserve unresolved privileged-mutation request IDs before dispatch so remount/reload cannot permit blind retries. Use server receipts for status-only recovery; persist minimum caller-bound references, never credentials/notes. State tab-scoped limits honestly.
- Distinguish push-token revocation, installation deletion, local Analytics reset and historical provider erasure. Client cleanup does not prove closed-device/backup deletion. Keep cached release restrictions during privacy cleanup.
- Preference caches may reflect failed writes. Persist retry acknowledgements explicitly; verify disk after restart, not just cached getters.
- A cleanup helper that catches failures has not acknowledged success. Aggregate
  deletion must explicitly require each prerequisite to complete before removing
  its durable pending marker; test failures across restoration and restart.

## Database, Financial and Hosted Boundaries

- Before broadening money input, trace its existing dollars-to-cents conversion
  before freezing/building. A correct UI callback can still lose a cent through
  floating-point truncation; check the actual outbound integer amount too.

- Exercise RLS-backed reads in a `READ ONLY` transaction, matching PostgREST
  GET semantics. A shared admission helper's row lock can work in RPC/payment
  fixtures but reject every balance GET. Preserve mutation locking/rechecks
  while using snapshot reads on the read-only path; never weaken admission.
- Published agreement content is immutable: add a version and switch the current
  pointer atomically, preserving old wording. After waiting on a publication-row
  lock, require that a row was actually locked and its version still matches the
  submitted consent. Test both publication-wins and acceptance-wins races.
- Account erasure and financial-liability retention are separate operations.
  Preserve purchased principal/claim linkage independently of Auth/profile
  deletion; retention-clock expiry must not silently erase outstanding credit.

- Feature availability must include runtime configuration, not only a database enable flag. Reuse the authoritative capability check for reads and mutation responses; an unsubscribe response must not accidentally re-enable enrollment when sending is unavailable.
- Duplicate provider events are idempotent only after stored owner/binding match. Recheck current state after awaited work before vend approval. New uniqueness guards must protect historical audit evidence from partial writes, not only new rows/populated bindings.
- Revalidate time-sensitive authority after lock waits, including trigger waits. Keep prechecks for stable errors; post-wait failure must roll back mutation.
- Recheck creation-only shutdown after Edge admission/capacity awaits, before provider dispatch. Keep refusal outside failure-marking compensation and leave already-funded recovery/settlement ungated. Reuse current composed fixtures; old stubs can fail before the changed branch.
- Audit effective table/column grants, policies, triggers and executable functions together. Enabled RLS/column revokes alone do not prove protection; inspect inherited/table-wide privileges and trusted-function paths.
- Pair column-read restrictions with explicit client projections and actual supported-client rollout. Older wildcard reads may fail despite passing new source; inspect fallbacks before deployed grant changes.
- Check provider-managed DDL delegation before claiming ownership blockers. Supabase can delegate Storage policies without table ownership; verify configuration and rollback-only rehearsal. Never add privileges, change ownership or enable bypasses to make deployment work.
- Fixtures need current reviewed guards and actual constraints; synthetic old schemas are not integration evidence. Check primary/unique keys/dependent FKs before identity changes. Invoke idle and populated PL/pgSQL paths: installation does not exercise lazy SQL planning.
- Trace the current public/private function chain before a duration migration.
  An earlier security migration may have moved the implementation behind an
  Owner guard; preserve that wrapper and both ACLs while changing the inner body.
- Seed historical legacy records before installing guards prohibiting their creation; preserve historical assertions and current guards. Match hosted-owner fixture privileges, including FK REFERENCES. Fix fixture privileges only after verifying real capability; never switch to superuser to hide deployment failures.
- Hosted Save disabled may mean pending request: wait, reload, verify persistence. Use rendered UI if accessibility exposes stale/partial editor values.
- Monaco's accessible textarea may expose only part of its model: `fill` alone can append instead of replacing SQL. Select All/clear first and inspect the complete rendered query before Run; never infer execution from an old result or pending control.
- Read back deployed gateway settings; local `verify_jwt` is not hosted proof. Provider callbacks retain internal signature/token validation with reviewed gateway exemptions.
- Collection, wallet spending and machine activity are distinct. A Nayax vend may describe existing Stripe/wallet payment: join verified provider IDs before counting money. Portal access/cached diagnostics do not establish current entitlement.
- Recheck volatile provider access immediately before clearing a support escalation
  for sending. Historical denials remain dated evidence, not proof that a reported
  permission grant is still ineffective; verify Sent Items before preparing a
  correction or duplicate reply.

## Dependencies, Native and Tooling

- Consent persistence does not prove native opt-in activation or in-memory message
  suppression. Inspect runtime-only properties in the actual SDK, tied to the
  exact binary; do not add a product debug API solely for QA. Inspect the pinned
  SDK's registration lifecycle when defaults disable auto-init; exercise the real
  adapter across the method-channel boundary, including first opt-in and teardown.
- Narrow firebase_core imports when using the app's FirebaseService; the pinned
  SDK also exports that name. For stalled method-channel timeout fixtures, prefer
  a bounded real-clock check over repeated fake-clock retries or weaker assertions.

- Resolve a missing dependency's complete pinned static import graph once within approved public-cache/network scope. Do not repeat loaders/permissions per file of that approved version; stop for pin changes, unexpected providers or secret access.
- Cached dependencies still need lock entries: include exact newly used import closure in reviewed lock delta before frozen QA. No unpinned/no-lock acceptance substitute.
- Sparse Deno dynamic imports need scoped read permission for the lane and reviewed source symlink targets. Supply exact paths in handoff commands; never fix loaders with unrestricted filesystem/environment/network permissions.
- Declare first-party build/check script imports in `dev_dependencies`, not unrelated transitives. Distinguish version updates, node reclassification and graph growth. Inspect reverse constraints before upgrade lanes; integrate coupled graphs atomically, no overrides/unresolvable combinations.
- Freeze discovery per delivery batch, record concrete deferral reasons and retain accepted versions/evidence while inputs are unchanged.
- Preflight optional artifacts: offline Pub resolution does not prevent missing Flutter Web SDK downloads. Check effective emulator RAM/actual kernel page size, not flags/image labels; disable compatibility fallback for native page-size acceptance.
- Before direct native release builds, generate release-mode plugin registration through Flutter's supported path. Pinned `--no-pub` also skips registration refresh; stale debug registrants can reference excluded development plugins. Do not move tooling into runtime dependencies to repair generated metadata.
- Check framework APIs against pinned CI/minimum SDK source, not just newer installed SDK/current docs. Never raise requirements/hide diagnostics to pass a candidate. After package integration refresh active generated dependency metadata/native plugin locks; sparse harness acceptance does not update active checkout.
- Inspect actual packaged native-library inventory; dependency ABIs may exceed build targets. Linking success is not page-size/device/store acceptance.
- Match Flutter hook output to Xcode's native-asset embedding path. In pinned Flutter, a custom `FLUTTER_BUILD_DIR` can change the lookup without relocating assemble's hook output: compilation/signature checks may pass while a manifest-referenced framework is absent. Prefer the verified standard path and inspect the packaged manifest targets.
- Native storage checks require process restarts/platform entitlements, not unsigned builds alone. Isolated iOS Simulator Keychain uses Xcode-managed ad-hoc signing with only QA identity, never customer credentials/production entitlement edits. Require expected UI and actual process evidence even when launch tools report success.
- Separate provider delivery from native resource acceptance. After bounded delivery retries, a pinned actual-SDK fixture can verify a resource-only correction without more sends; label synthetic content and temporary state explicitly. Use real input outside the old hit area, not `performClick`, and restore each temporary setting independently even if another cleanup step fails.
- Separate simulator boot, OS launch snapshots, retained native splash and Flutter frames when diagnosing startup flashes. Manual app themes cannot rewrite the earlier OS-owned snapshot. Verify a native preference bridge with cold-start window state and actual Settings toggles/persistence in both directions; a debug preference write alone does not prove Flutter integration. Preserve the engine's intentional handoff unless a concrete defect requires changing it.
- Freeze source only after independent findings are resolved, then build. Reviewers send actionable findings before long receipts and consolidate superseded verdicts. A first-load presentation change must also preserve already-displayed content during later retries; a new loading screen is not a background-refresh solution.
- For direct simulator preference fixtures, stop the owning simulator before key-scoped edits; its preference daemon can overwrite file changes after the app stops. Preserve exact selected values and a recovery journal, verify actual UI plus post-launch cache, and reuse valid parser fixtures. Keep stored timestamp precision; formatted CLI output may round it. Cached UI acceptance is not offline/network proof.
- Keep `FLUTTER_TOOL_ARGS=--old_gen_heap_size=512` across pinned Flutter checks/native wrappers, including indirect Gradle tasks. It participates in launcher cache identity; do not toggle/delete caches or repeat bootstrap.
- Diagnose build timeouts with task progress and owned-process CPU/GC/memory evidence before retrying. Use bounded invocation-only adjustments, not weaker checks or global settings. A detached Gradle JVM can have a different process group from its launcher; verify both have exited before releasing the runtime slot. Record deliberate termination separately from a crash.
- Reuse the last successful build invocation, not a wrapper's older defaults. A smaller JVM heap can spend most runtime in full GC; inspect the existing receipt before changing a verified resource setting. Keep exact current flags in operations, not duplicated across guides.
- Check the current debugger backend before assuming expression support: a DAP attach may work while arbitrary LLDB commands do not. Reuse a bounded known-working CLI command when needed; unavailable module imports and unsupported persistent-variable captures are tooling failures, not app defects. Keep getter output scoped and detach on completion.

## Test Fixtures and Actual Surfaces

- A48dp layout box is not proof of a48dp touch target. Transparent gesture
  padding needs an explicit hit-test behavior. Preserve center/edge activation
  tests instead of narrowing taps to the text just to make a UI regression pass.

- Retained map controllers keep their camera when responsive layouts remount
  the map. Synchronize selection after mounting as well as on widget updates;
  test remounting with the same controller, not only selection changes in place.
  With flutter_map8.3.2, wait until its post-frame resize event finishes before
  moving the camera; a late old-camera event can prune the newly selected tiles.
  Assert the final event camera too. Dispose retained map subscriptions/controllers
  in the widget fixture's real-clock zone if fake-clock stream cleanup stalls.
- BottomNavigationBar already reserves viewPadding.bottom. Prefer its natural
  height to a second fixed-height wrapper; test gesture and three-button insets,
  usable touch targets and the last content edge, not just absence of overflow.
  Use real SDK fonts for phone-height assertions and retain enlarged-text scrolling.
- Fixed legal footers reserve layout space rather than overlaying scrollable
  text. Check the last line and persistent scroll affordance at large text sizes.
  For typography geometry, load SDK fonts using the generated package config;
  square test glyphs can inflate wrapping and machine-specific font paths drift.
- Verify the actual browser viewport, not just a requested emulation setting.
  If resizing does not apply, use an isolated configured test profile; preserve
  signed-in user profiles. On hosted checkout, allow only the intended public
  quote transport and deny payment/status/Auth calls unless separately assigned.
- Filter Node nested tests using positive full-child-name patterns. A negative
  lookahead can match the runner's unnamed root and silently select zero real
  cases. Prove selection with a tiny inline fixture, then require the intended
  child names and teardown output; a fast file-level pass is not acceptance.
- Flutter checks honor `dart_test.yaml`/CI partitions/build defines. Notification-router fixtures need separate synthetic `firebase-configured` invocation, not unconfigured default.
- Sparse JS/TS harnesses must resolve shared exception classes to one canonical module URL; duplicate imports invalidate `instanceof` behavior.
- In `tester.runAsync`, create controlled error-producing futures in the consumers' error zone. Crossing zones can strand rejected futures and resemble startup deadlock; preserve real failure/reporting assertions.
- Restore test-wide platform overrides and dispose explicit semantics handles in widget-test `finally`, before binding invariants; `addTearDown` may be too late. Check pinned framework semantic field (`tooltip`/`label`); verify native accessibility bridge separately for reported native defects.
- Test global UI at its real placement around the Navigator, not only inside a page. Route barriers can suppress earlier sibling semantics; isolate the Navigator's semantic boundary. Do not supply a test-only Overlay to hide a missing production ancestor. Preserve tooltips where supported and use explicit icon labels where no overlay exists.
- Verify intended contract before changing tests or behavior; never weaken assertions for green runs. Use actual repository analysis/lint/type/test config and pins; separate existing diagnostics from new ones. Reduced clean harnesses are not integrated acceptance.
- Website critical route failures need real DI/missing public configuration, not only mocked pages. Contain checkout render/download failures without automatic payment replay or error/query disclosure. Check fallback typography/spacing outside normal layout; reuse theme shell, no fallback-only styles.
- Website Vitest excludes scripts/disables CSS: independently verify backend harnesses, routing/DI and visuals. `test:admin:db`, `test:admin:edge` and Edge types assume sibling app: resolve reviewed checkout before isolated validation.
- Serial synthetic browser tests with external HTTP/WebSocket blocking do not prove hosted rewrites/provider flows. Discovery, interrupted loaders, zero cases and running commands are not passes. Read completed output/exact case counts/exit; distinguish local, mocked and deployed evidence and correct inaccurate receipts.
