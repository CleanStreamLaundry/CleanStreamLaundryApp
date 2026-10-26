# Supabase Reference

## Current Release (October 5)

Confirmed hosted release for Clean Stream: all seven migrations through
`20261005181711` are applied; policy `2026-10-05.2` is current with 90-day recovery
and `request_account_deletion_with_consent` available. Automatic-inventory
migration `20261005183040` is also applied after a rolled-back hosted rehearsal
and QA 9/9 records (four install, four behavior, one parent); the one Deno check
is retained. All 13 release functions are deployed, including cleanup v2 with
its final worker hash already verified by readback.

Daily cleanup is enabled under the approved prospective 90-day policy;
past acceptances are not applied retroactively, and holds remain preserved.
Activation SQL exited 0; remote readback confirms execution/surrender enabled,
the daily Cron active, and zero pending requests/external cleanup operations.
No actual customer deletion or provider-erasure test was performed.

Website deployment `dpl_2Sxq9oEkTGrZ2JrsFPVDcTUa82P7` is promoted to
cleanstreamlaundry.com. The release handoff confirms `index-CMpgsZxw.js` and HTTP
200 for Terms, Privacy and Account Deletion with an October 5, 2026 effective
date. Android build succeeded and the signed APK is ready; Samsung installation
and device tests are explicitly user-deferred. This is supplied release evidence,
not a new provider test, cleanup execution or legal-enforceability conclusion.
Composer owns [operations](operations.md) and the release receipt.

Earlier dated/local-only and paid-credit-preservation entries below are historical
where superseded by this release. Do not replay their rollout steps or treat
their old policy versions, 30-day deadlines or activation gaps as current status.

Local source includes existing dirty/untracked work. **Not a verified deployed schema snapshot.** The hosted Clean Stream project is development, regardless of the console branch label. Official CLI sign-in now works for `jacob@cleanstreamlaundry.com`; the active app link is verified as `dnuuhupoxjtwqzaqylvb`, and a read-only linked query returned PostgreSQL 17.6. Chrome remains available. The MCP connection still exposes only Gundex; never substitute or replace it. See [operations](operations.md) for current reconciliation evidence.

## Source Map

| Concern | Existing source |
| --- | --- |
| Schema and functions | `supabase/migrations/`, `supabase/functions/`, `supabase/config.toml` |
| Client setup/auth | `lib/core/di/di.dart`, `lib/services/supabase/supabase_auth_service.dart` |
| Wallet ledger | `supabase/migrations/20260526010000_wallet_ledger_compliance.sql` |
| Cortina sessions/reversals | `supabase/migrations/20260803150427_cortina_qr_remote_vend.sql`, `supabase/functions/_shared/cortina.ts` |
| Machine-claim credits | `supabase/migrations/20260807191723_harden_refund_resolution.sql`, `_shared/refund_resolution.ts` |
| Local admin/location scope | `supabase/functions/admin-portal/`, `supabase/migrations/20260928135006_admin_portal_operations.sql` |
| Account deletion | `supabase/functions/delete-account/index.ts`, `logic.ts` |
| Owner-supported customer MFA recovery | [Contract and verification](customer-mfa-recovery.md) |
| Website callers | Active website `src/supabase/client.ts`, `src/admin/api.ts` |

Read only the relevant handlers, shared logic, migration, caller, and tests. Existing [Cortina setup](../CORTINA_SETUP.md) and website `ADMIN_PORTAL_SETUP.md` provide rollout context, not proof of live state. Backend owns shared contracts; client agents do not invent parallel schemas.

## Current Boundaries

- October 3: `20261003115914_readonly_loyalty_admission.sql` is deployed.
  Loyalty status skips its Auth SHARE lock only in read-only transactions;
  financial mutations retain locking and the post-lock access recheck. This
  repairs PostgREST wallet GET failures without changing RLS, grants or money.
  `supabase/ops/20261003_correct_location_coordinates.sql` corrects the swapped
  Madison/Columbus coordinate pairs, preserving location IDs and machine links.
  The guarded operation is not repeatable without inspecting current values.

- Loyalty terms now have a versioned JSON document contract; see
  [publication and acceptance](loyalty-terms.md). Never edit previously accepted
  text in place, bundle the current terms into the app, or backfill consent.
  Deploy/readback evidence is recorded in operations, not inferred from source.

- October 2 native Google setup: existing web client remains first in the hosted
  Google provider list, with approved Android-development and iOS clients added.
  `skip_nonce_check` and allow-without-email remain off; OAuth secret unchanged.
  Flutter uses `google_sign_in` 7.2.0 plus existing `signInWithIdToken`, not Firebase
  Auth. Native setup is not device acceptance; see operations. Public OAuth IDs:
  web `444847125705-mdbtsvhd1ks8n8j061u5gogvi5c1ro54.apps.googleusercontent.com`,
  Android development `444847125705-t4jl9r5a93omuq5959im99ug5fogo8ci.apps.googleusercontent.com`,
  iOS `444847125705-hgq2664pu8sushlgevta6fnt10l07lms.apps.googleusercontent.com`.
  Android registration uses the existing local test certificate SHA-1
  `39:4F:19:6D:EC:C2:88:A6:39:E3:F9:85:B1:A5:B6:9E:1E:F1:AA:A0`;
  Play signing is separate. iOS retains existing bundle ID
  `com.cleanstreamlaundrysolutions.clenaStreamLaundryApp` without renaming it.

- October 1 Owner management: reviewed migration `20261001013709` and paired `admin-portal` are installed in development. Canonical Owner/MFA authority, audited grants/removals, last-Owner protection and Owner-only wallet wrappers have matching source/ACL/guard/history postflight. Flutter caller-binding passes96; website Team UI is published. October 2 explicitly approved operator correction now assigns `jacob@cleanstreamlaundry.com` Owner and `jamaki12345@gmail.com` User; missing business profile created, audit recorded, transaction-only role-removal exception restored before commit. No wallet mutation. Y14 is resolved; authenticated hosted acceptance remains. The last-Owner guard remains active. Authenticated deletion requests were subsequently enabled as recorded below.

- October 1 development containment: `wakeDevice`, `ping-device`, `verifyPayment`, `changePassword`, and `resetToken` now return fixed 410/upgrade_required for non-OPTIONS methods, without body, credential, database or provider access. Independent95 tests and five hosted empty-POST denials pass; gateway JWT checks remain on. Superseded logic/tests were removed locally. Supported Cortina/status/Auth SDK paths remain unchanged. This does not reverse a charge made by an older binary before its wake request.

- App uses `SUPABASE_URL`, `ANON_KEY`, `STRIPE_PUBLISHABLE_KEY`; website uses `VITE_SUPABASE_URL`, `VITE_ANON_KEY`. Both client bundles are public. Inventory names/consumers, never secret values in docs.
- Server/operator credentials include `SUPABASE_SERVICE_ROLE_KEY` and provider secrets. The unused website helper that expected a browser-prefixed service-role key and mutated Auth was removed locally, together with its environment declaration. This does not establish whether a privileged key was ever configured or exposed; deployment/key inventory must still verify that separately.
- `wallet_balances` derives money from the ledger using a security-invoker view; `profiles.balance` is a compatibility cache. Ownership/admin policies and service-only management RPCs exist locally, but old grants/policies are not fully reconstructible here.
- Admin handler verifies the user; management SQL checks roles and location assignments. Client route checks alone are not authorization. Do not use user-editable metadata to authorize privileged actions.
- `verify_jwt=false` is endpoint-specific. Inspect actual authentication: Stripe signatures, user verification, and Nayax callback controls. Local Nayax handlers reject a missing configured token; deployed enforcement and the provider's supported authentication contract still require verification. Never treat an absent setting as permission to accept a callback.
- Current [Edge header guidance](https://supabase.com/docs/guides/functions/auth-headers) permits API keys through the gateway for migration compatibility. A passed gateway check therefore does not prove an authenticated user. Preserve explicit verified caller checks; send user JWTs as Authorization and application keys as apikey. Do not globally disable gateway verification during key migration.
- Sandbox/production Nayax credentials and Stripe webhook settings are separate. A production website URL does not prove production payment mode or isolated backend data.
- Local Auth redirects/password settings do not establish hosted settings. Verify OAuth allowlists, signing, session/MFA behavior, and recovery against the correct environment.

### Key Consumer Inventory (Local Source)

No key values are recorded here. The September30 two-default-key snapshot is
superseded:24 named keys are created,21 Edge selectors and mobile/web/Vercel public
configuration are saved, and the named-key website deployment is READY. Public
policy reads and unauthenticated admission denials pass for both client keys.
Authenticated consumers and release binaries still need acceptance; legacy/default
keys remain active and the operator key is unused. A Firebase environment does not
establish a separate Supabase environment.

The canonical [named-key consumer inventory](supabase-key-migration.md) maps public clients, privileged components, operator scripts and gateway settings to verified source paths. It corrects the earlier broad service-role grouping: current admin/approve/deny, maintenance and account-deletion entrypoints use public keys plus captured user JWTs and authoritative RPCs, not privileged client credentials. Use that inventory for configured assignments, remaining consumer verification and rollback checks; configuration is not authenticated execution proof.

The contained `delete-maintenance` endpoint needs no credential. This source inventory is a starting point, not a verified hosted consumer list. Per-component revocation requires distinct named keys AND deliberate consumer wiring; changing only cloud key names or the shared factory's single default does not isolate callbacks. Keep public keys out of Authorization when a user bearer is required, never accept a request-selected secret name, and preserve callback/reconciliation availability during overlap. Do not disable a legacy key until all deployed clients, functions, operators and old binaries have an approved migration/retirement path.

### Hosted Auth Check (2026-09-29)

Update October 1 UTC: leaked-password protection is enabled in Clean Stream's
Email provider settings, with success notification and checked state verified
after reload. Existing Pro entitlement was used without a plan change. No other
password/OTP/provider settings were changed. Supabase documents rejection on
signup/password change while allowing existing passwords to sign in; confirm
actual client behavior separately. See [password security](https://supabase.com/docs/guides/auth/password-security).
This is a settings receipt, not a real-user sign-in or rejection test.

Read-only inspection of hosted development `dnuuhupoxjtwqzaqylvb` confirmed TOTP enabled, a ten-factor limit, SMS MFA disabled, and the optional 15-minute AAL1 session limit off. This does not establish backend AAL2 enforcement; local `config.toml` differs from hosted settings.

Catalog-only inspection confirms `auth.sessions.id/user_id` UUIDs, nullable `factor_id` UUID, `aal` enum, and `not_after` timestamptz. `refreshed_at` is timestamp without time zone. Factors have nonnull UUID `id/user_id`, `factor_type/status` enums and created/updated timestamptz. No actual users, sessions, factors, or secret values were queried. Check current caller/session ownership and expiry together with verified JWT assurance and current factor state; a session's elevated state must not promote an older AAL1 token.

Follow-up catalog inspection confirms `aal_level` values `aal1/aal2/aal3`, factor status `unverified/verified`, and factor types `totp/webauthn/phone/recovery_code`. Unsupported factor types must fail closed under the planned TOTP contract. Auth users/sessions/factors are owned by `supabase_auth_admin`, with RLS enabled; anon/authenticated lack effective table SELECT, while postgres and the Auth owner have it. Sessions and factors have primary ID indexes and user-ID indexes/FKs with cascading user deletion; sessions has no factor-ID FK, so ownership/current-factor validation cannot be inferred from that column alone. These are catalog facts, not an end-to-end authorization test or permission to change Auth-owned objects.

Hosted session settings: single-session enforcement off; timebox and inactivity timeout both 0 (never); access tokens expire after 3,600 seconds; refresh-token replay detection on with a 10-second reuse interval. No settings were changed. Data API exposes `public` and `graphql_public`, not `private`; extra search path is `public/extensions`, maximum rows 1,000, automatic exposure of new tables on. Explicit grants/revokes in migrations remain required. JWT Keys still reports the legacy JWT secret in use; no secret was opened. Named API-key migration is separate from JWT-signing-key migration, and neither is authorized by these observations.

The Site URL is still `http://localhost:8080`. Its seven redirect entries are the four native callbacks `clean-stream://email-verification`, `clean-stream://oauth`, `clean-stream://change-email`, `clean-stream://reset-protected`, plus `http://localhost:8080/loading`, `http://localhost:8080/email-verification`, and `https://localhost:8080/reset-protected`. No hosted Flutter-web destination is listed. Verify the actual app host/base path before requesting a production allowlist change; the React website is not automatically that destination. Preserve native callbacks. See [redirect configuration](https://supabase.com/docs/guides/auth/redirect-urls).

### Maintenance Access Check (2026-09-29)

- Live `Maintenance` and `Refunds` SELECT policies allow every authenticated caller, without ownership/location scope. Both anon and authenticated have effective table SELECT grants; RLS excludes ordinary anon reads but not cross-customer authenticated reads. The local portal restrictive policies are not deployed.
- `maintenance-images` is a public bucket, limited to 20 MiB and JPEG/PNG/HEIC/HEIF/WebP. Its only Storage policy permits authenticated inserts anywhere in that bucket, without an owner path. Public retrieval does not rely on object SELECT policies. No files/object rows were opened. See [bucket access semantics](https://supabase.com/docs/guides/storage/buckets/fundamentals).
- Deployed `maintenance-request/index.ts` retains the original privileged client, body-supplied `user_id`, no user verification and raw database errors. Gateway legacy-JWT verification is on, but a legacy anon key satisfies that check; it is not user authentication. Local four-file containment now verifies the bearer, derives identity from Auth, rejects mismatched body IDs, bounds/validates input and sanitizes failures while preserving the 200 success shape. Worker/composer/independent QA each pass 94 tests. It is not deployed or full MFA/session/lifecycle/attachment authorization; pair it with honest client response handling before release. See [Edge authentication](https://supabase.com/docs/guides/functions/auth).
- **Containment deployed with explicit approval:** the former `delete-maintenance` handler used the service key to delete `Maintenance` by body-supplied ID without authorization; gateway JWT verification was OFF. It is now replaced by the checked-in 25-line deny-all handler: OPTIONS 200, every other method fixed 403/no-store, no body/credential/database access. Backend/composer/independent QA each passed 19 tests. Reloaded deployed source matched; one credential-free GET at 2026-09-30 00:22:18 UTC confirmed the fixed response. No record IDs or payloads were sent and no records/settings were changed. The unrouted legacy dashboard caller is intentionally disabled. See operations for source hash and approval scope; do not restore vulnerable behavior as rollback.
- App `maintenance_request/controller.dart` uploads a public URL and returns success without checking the nullable `FunctionResponse`. Its service wrapper catches invocation errors and returns null. Backend/client/attachment changes must be coordinated and tested; do not flip bucket privacy or invalidate existing report links as an isolated fix.
- Follow-up catalog-only check (2026-09-30 UTC) confirms Maintenance has a composite primary key `(user_id, created_at)`, unique generated `maint_id`, no foreign key or noninternal trigger, and no timestamp default. Its seven columns do not include the local portal's added location/status fields. Preserve this deployed shape when rehearsing additive changes; a synthetic admin fixture is not the live schema.
- October1 cleanup QA found this key prevents requester nulling. The **unapplied** retained-subject migration now guards the legacy shape, preserves `(user_id,created_at)` uniqueness, changes the primary key to `maint_id`, and preserves the original unique-ID index and dependent support FK. Eight local key/rollback regressions and full migration installation pass; no hosted key change is implied. See the current operations checkpoint for lifecycle evidence and remaining executor checks.
- Further local cleanup QA passes47 unique SQL cases and104 worker cases: all12 populated retained references, late funding/refund arithmetic, restore locks, scoped holds, version-addressed attachment selection and retention expiry. Two query/record alias collisions were fixed without changing guards or policy; final boundary batch39/39 passes. Actual hosted Storage/Auth/scheduler integration and final financial/provider disposition remain separate gates.
- `Location_to_Admin` has public reads and an Admin/Owner INSERT policy with no location restriction, nullable user/location foreign keys and no unique membership pair or guarding trigger. Thus assignments are not independently trusted authorization data. Protect legitimate membership writes before relying on them to scope reports; do not delete or reinterpret existing assignments. `Locations.Address` is nullable/nonunique, so submitted text cannot establish unique location authority.
- Recursive role-membership catalog inspection returns only `anon` and `authenticated` themselves, with no parent grants. Both have inheritance enabled but no superuser, BYPASSRLS or CREATEROLE. This closes the current inherited-grant inventory gap, not the existing direct grants or future-grant risk; no role/ACL was changed.
- The local three-file membership guard is independently accepted; worker/composer/QA each pass 74 real PostgreSQL tests. It transactionally revokes client non-read privileges and adds a statement trigger for accidental regrants, aborts on unreviewed ownership/role/grant drift, and preserves records, SELECT, trusted writers and FK cascades. It does not certify historical membership legitimacy. Existing multi-step direct website writers need coordinated retirement before any approved deployment.
- Storage metadata confirms nullable `owner_id` text (`owner` UUID is deprecated), nullable `version` text and `archived_at` timestamptz, all without defaults. `is_versioned` and `is_delete_marker` are nonnull booleans defaulting false. Names have version-aware uniqueness and a current-version index. Attachment ownership must exclude archived/delete-marker objects and fail closed on absent ownership, without fetching supplied URLs. Storage-managed triggers are outside app ownership. No report, user, session, assignment or object records were queried.
- `storage.objects` remains owned by `supabase_storage_admin`; table grants and BYPASSRLS alone do not authorize policy DDL. October 1 inspection additionally verified the provider's existing `supautils.policy_grants` delegation from `postgres` to `storage.objects`, with `session_preload_libraries=supautils` (bb2e9b/801452). A rollback-only five-policy rehearsal passed (3d6873), followed by unchanged-state readback (10e248). This supported delegation resolves the earlier ownership blocker without assuming a role or changing privileges, ownership or server configuration. The Maintenance identity sequence remains postgres-owned; no report/object data was queried.
- Canonical maintenance authorization and its paired client are locally integrated and independently accepted: 164 Deno/106 reported PostgreSQL checks, 183 client VM/182 Chrome plus eight original form cases. The backend reuses current-session/MFA/account authority; eligible users may request support before loyalty acceptance. New nullable `location_id` and structured `attachment_ref` preserve historical rows without address backfill. The client sends stable bigint ID strings and validates the canonical acknowledgement; it no longer expects new attachment URLs in `image_data`. Unknown outcomes are not retried automatically. No deployment or public Storage byte privacy is implied; older admin paths still need reconciliation.
- Access findings came from read-only configuration/source inspection, not exploit tests or evidence of past access; the separately approved delete-endpoint containment is the only deployed repair above. Repair ownership, verified identity, location/MFA/lifecycle restrictions and attachment delivery together before release.

### Anonymous Assignment Read Closure (2026-10-01)

The earlier inventory above is superseded for anonymous membership reads by
installed `20261001094740_deny_anonymous_location_membership.sql`. Its single
restrictive SELECT policy denies `anon` even while the legacy permissive PUBLIC
policy remains. Existing authenticated canonical restrictions, grants, helper
bodies, trusted writers and records are unchanged. Independent17 passes;
hosted history c1c500 matches exact source `d6ad6839`, and an actual anonymous-role
query returns no assignments (10f00e). This is not proof of all API privacy or
permission to enable deletion; Storage and machine-field gates remain separate.

### Machine Field Privacy (2026-10-01)

Local `20261001095826_machine_public_read_columns.sql` restricts direct client
reads to eleven public inventory fields, excluding staff `service_reason` and
`service_updated_by`. Existing canonical staff/service paths retain both. Paired
app counts now select IDs; the website repository explicitly selects its existing
DTO fields and nested configuration. Independent PG24/Flutter15/web30 pass and
all six sources are integrated. No schema, rows, APIs or dependencies were added.
The migration remains undeployed: supported old wildcard clients must first be
updated or their known failures explicitly accepted. This does not block public
inventory or claim deployed private-field protection.

Separately installed `20261001101347_restrict_machine_client_maintenance_privileges.sql`
removes only client/PUBLIC TRUNCATE, REFERENCES, TRIGGER and MAINTAIN on Machines,
including column REFERENCES. Independent26 passes; metadata383c4b/088326 confirms
exact intended revokes and unchanged reads, trusted authority, schema, policies,
functions, triggers and deletion hold. History2f6072 matches source `172b6edb`.
No data was read/changed, and the separate column-privacy migration remains
undeployed. The subsequent fixed three-table migration
`20261001103350_restrict_inventory_client_maintenance_privileges.sql` applies
the same maintenance/column REFERENCES revokes to Locations, washer_size_rates
and cortina_machine_config. Independent23 passes (66339a); deploymentbeb819,
postflight53822b and exact history895772 close that batch. All read/DML, trusted
rights, policies, functions and deletion hold are preserved. These four tables
are verified, not every table in the project; do not replay either migration.

### Local Attachment Contract (2026-09-30)

`20260930165320_maintenance_attachment_access.sql` adds a caller-bound
`get_maintenance_attachment(p_maint_id text)` RPC returning the exact structured
object reference, not a URL. It reuses canonical account/report/location checks;
owner, object ID, name and version must still match. Missing ownership, historical
URL-only references, archived/deleted/replaced objects and cross-account/location
access fail closed. No existing row, object, policy or client wire is rewritten.

Separate `supabase/storage/maintenance_attachment_policies.sql` contains the
reviewed activation artifact, deliberately outside automatic migrations.
It scopes authenticated reads and current safe uploads, denies client mutation
of existing maintenance objects, and preserves other buckets' policies. It must
not run through a role/ownership workaround. Author and independent composer
each pass 64 scenarios plus parent on PostgreSQL 17.11, including lifecycle,
roles, policy-composition, metadata drift and row-preservation tests. Both owned
test clusters were stopped and removed; these are synthetic metadata tests.
The corrected activation guard permits the existing owner path or the verified
provider delegation, without changing the five policy bodies. Independent QA
passes69 (eb1c6f), including rejected unrelated grants and a local fake setting
that cannot bypass actual PostgreSQL authority. Exact artifact `4ed6c4a3` was
installed in development (778b3c); postflight e00a26 confirms all five names,
commands, modes, roles and predicates, retained helper ACLs/owner/RLS, unchanged
20 MB/MIME bucket settings and deletion hold. The bucket is still public;
authenticated HTTP acceptance and paired public-client rollout precede privacy.

The admin viewer now downloads through the authenticated object endpoint using
the captured caller after the descriptor RPC. It validates report/object paths
and image MIME types, aborts stale attempts and revokes blob URLs on close or
account change. Arbitrary legacy `image_data` links are no longer rendered.
Independent helper16 and page6 checks pass; historical URL-only reports still
need an approved migration/support path, not an unsafe fallback. Hosted Storage
HTTP/signing/cache behavior and an approved private-bucket transition remain.
Public reads bypass these policies, and existing signed URLs/downloaded bytes
are not instantly revoked by new SQL. Do not claim deployed attachment privacy.
Current [Storage access](https://supabase.com/docs/guides/storage/security/access-control),
[ownership](https://supabase.com/docs/guides/storage/security/ownership) and
[bucket semantics](https://supabase.com/docs/guides/storage/buckets/fundamentals)
were rechecked. Provider-managed policy delegation is documented in
[supautils](https://github.com/supabase/supautils#manage-policies) and verified
above; this is not permission to modify its configuration or Storage ownership.

## Local Identity Contracts

Local wallet/claim follow-ons are also integrated, not deployed. Human wallet spending reuses canonical admission with post-lock revalidation (44 PostgreSQL runner checks). `request_legacy_loyalty_credit(bigint,text)` atomically checks the current caller/admission, stored non-Cortina transaction, 14-day window and historical claim consistency, then returns a validated idempotent receipt (66 PostgreSQL runner checks and 19 paired Flutter service tests). It replaces three direct client writes without changing settlement/Stripe routines. Old direct writers require a coordinated rollout. Request-alert enqueue is separate and cannot create/approve a claim or move money; see [payments](payments.md) and [email](email.md).

Four additive restrictive SELECT policies now also require canonical Home admission for ordinary self-owned wallet reads. They compose with existing self restrictions and the security-invoker balance view; they do not regrant global admin wallet operations. Independent 48 PostgreSQL runner checks pass, including current-session waits and preserved pending-deletion refund/service-settlement exceptions. Human funding adapters separately check captured-caller admission before wallet lookup and before provider creation, with an eight-second RPC deadline; 81 initial, 34 compatibility and four timeout checks pass. These local checks cannot retract an external payment object already created.

Complaint recording now rechecks the existing canonical staff context before and after INSERT waits and requires the same actor. Independent 44 scenarios plus parent pass, including FK/trigger waits and rollback. Existing Owner/Admin authority, signature, grants and records are preserved; this does not re-enable global financial RPCs or perform a cash redemption.

- Migration `20260929234955_loyalty_policy_acceptance.sql`, now installed in hosted development, adds protected nullable `profiles.loyalty_policy_version` and `loyalty_policy_accepted_at`. No backfill/default acceptance. `get_loyalty_policy_status()` and `accept_loyalty_policy(p_version text)` return `required_version`, `policy_text`, `policy_sha256`, `accepted_version`, `accepted_at`, `acceptance_required`. Exact-version explicit acceptance uses server time; replay preserves the first timestamp. No supplied user ID/time, newsletter side effects, or automatic acceptance on read.
- Public `get_loyalty_policy_descriptor()` returns only `required_version`, `policy_text`, and `policy_sha256` before login, without Auth/profile reads or writes. It is an invoker with an empty search path and explicit anon/authenticated execution grants; protected status reuses this single source. The original 32-test acceptance is retained in history; the integrated extension passes 37 worker/composer/independent QA PostgreSQL tests.
- Initial version/text remains explicitly review-only existing legal copy, not the final refund/deletion policy. The exact seven-source development rollout installed terms, admission, profile enforcement and dormant recovery/mail contracts. Postflight confirmed protected-field grants, guards and private-table RLS; anonymous HTTP returned the exact descriptor/hash and protected admission returned 401. See [operations](operations.md) for the frozen artifact and receipts. Complete ordinary API admission before enabling deletion.
- Local ProfileService status/accept methods expose the six-key wire, verify the exact UTF-8 policy hash, and preserve SDK errors; their initial slice passed 106 independent tests. The public reader uses shared descriptor parsing and a plain public-key PostgREST transport that does not refresh Auth (167 independent checks). The acceptance controller/page batch independently passes 110 VM/109 Chrome cases: unchecked explicit consent, exact displayed-policy acknowledgement, admission revalidation and guarded late completions. Ten seconds bounds response wait, not HTTP cancellation. The page is now wired through the local admission gate; consent is never automatic and policy copy remains review-only. RPCs are installed in development; final policy approval and actual client/auth flow acceptance remain gates. The already-locked crypto package became direct without a version change.
- Four local AuthService MFA methods use the SDK; verification now has the separate safety gate below. `getMfaAssurance` is local information, not backend authorization. Staff require a current verified TOTP factor plus AAL2; an old AAL2 token after factor removal is insufficient. Customers may choose enrollment, but enrolled customers need AAL2 for protected operations. Unknown roles/access lookup failures fail closed.
- Backend's admission contract must permit only minimal authenticated bootstrap/factor/recovery status before ordinary profile reads; pending deletion denies ordinary access. Recovery cannot implicitly restore an account or bypass verified-factor safeguards. Provider-authenticated settlement/reversal remains independent of human MFA and terms gates. Client UI/routing is integrated locally against the reviewed wire contract.

The admission foundation in `20260930005456_account_admission.sql` is installed in hosted development. One private evaluator checks subject/session binding, JWT/session expiry, account restrictions, known role and current verified TOTP factor binding. `get_admission_status()` projects six keys (`subject_id`, `account_access`, `next_step`, `reason`, `account_state`, `restore_until`); the integrated client gate admits Home only for `home`. `ensure_own_profile(p_full_name)` uses the same authority, inserts only the caller's id/name with database defaults, and never overwrites an existing profile. The installed lifecycle follow-on adds explicit recovery without enabling new deletion requests. The original 109 PostgreSQL and 185 adapter checks remain scoped historical evidence; actual signed-in hosted flows and whole-API coverage remain acceptance gates.

Follow-up `20260930013417_enforce_profile_terms_admission.sql` is also installed in development: two restrictive authenticated profile policies compose with existing ownership rules, deny direct INSERT/upsert, and gate protected terms/admission through the same evaluator. Only three existing RPC bodies are replaced; public descriptor/bootstrap, financial writers, ACLs and Auth schema remain unchanged. Auth SHARE then profile NO KEY UPDATE locking and post-wait checks preserve explicit-version consent/replay timestamps. Errors are sanitized to PT401/PT403/PT503, with 22023 only for explicit stale/null policy version. The accepted 72 PostgreSQL tests include grants and concurrent revocation/acceptance. This is not whole-API/lifecycle/location enforcement or universal immediate revocation; ordinary RLS still uses statement snapshots. Old direct-profile clients may now fail; use the integrated caller-bound bootstrap, not a bypass flag.

The six-file client bootstrap replacement is independently accepted: `createAccount` calls only caller-bound `ensure_own_profile`, with a valid matching session and ten-second response wait; no profile SELECT/upsert fallback or swallowed error. Loading rejects stale account/route completions, including queued A-to-B-to-A events. Owned checks pass 233 VM/53 Chrome; corrected fixture passes 35 router tests and combined app 1,832. The later two-file binding prerequisite captures the matching unexpired bearer for all four protected profile/terms/admission requests; worker/independent QA pass 165. Public descriptor transport is unchanged. Request binding does not repair global SDK refresh races; successful bootstrap still uses existing Home routing. Required RPCs and profile enforcement are now installed in development; signed-in hosted client acceptance remains.

The admission-controller foundation is integrated and independently accepted (124 core plus 238 neighboring tests): one lazy GetIt-owned ChangeNotifier, typed read-only Session/AuthState accessors, bounded/coalesced checks and one expiry-only timer. Later local router/DI work mounts it around protected routes. Same-account unresolved revalidation may retain presentation with actions closed; resolved restrictions show recovery, and hard identity/expiry changes clear it. Eligible support is allowed before loyalty acceptance. No automatic consent, enrollment or restoration is introduced. See operations for current integration evidence; production activation remains separate.

Flutter MFA transport/screens are independently accepted and now wired locally, not deployed. Temporary GoTrue verification was removed because it shares browser BroadcastChannel state even without storage/auto-refresh. Captured-bearer HTTP reuses SDK models and adopts through guarded refresh-token-only `setSession`; no custom session manager, SDK fork or automatic POST retry. Independent checks pass 70 VM, five real-Chrome cases and four neighbors; newer account sessions survive late verification. The feature controller/page passes 85 tests. Enrollment is explicit, secrets clear on invalidation, and verification rechecks server admission rather than navigating directly to Home. Full backend coverage, hosted/device verification and verified lost-factor recovery remain open. React staff MFA is separate: its JS SDK guarantees must be tested independently, not inferred from Dart.

React staff MFA is now locally integrated with the reviewed opt-in Auth 2.103.3 patch and new storage domain, shipped together. Installed SDK/client/UI46, installer9 and full strict types pass. Independent real-browser tests pass five scenarios plus parent using native locks, broadcasts and two tabs: late refresh cannot replace newer accounts or undo sign-out, and old-domain sessions remain separate. A fresh sign-in is intentional; no old-token migration. Build verification refuses unknown SDK bytes. Hosted backend enforcement, recovery and release activation remain separate gates.

## Remaining Campaign Changes

- Finish authenticated acceptance of the configured named publishable/server keys and verify overlap/rollback. Retire legacy keys only after explicit approval. Secret keys still bypass RLS; separate names do not provide least privilege.
- Require TOTP MFA for Owner/Admin and optional customer enrollment. Enforce assurance on the backend for privileged operations, with verified lost-factor recovery; do not reduce MFA to a UI gate.
- Persist required loyalty-policy version/time once before first Home. Optional newsletter consent is separate; see [email](email.md).
- Local client subscriptions and the webhook broadcaster have been removed; worker/independent QA pass 96 tests for the final four-file backend removal. The unchanged webhook entrypoint imports remain unverified locally because they are uncached. Deployed removal still needs old-client migration and coordinated rollout/reconciliation. Keep SDK Auth session listeners, which are not Realtime subscriptions. Use cached reads and meaningful refresh events, with bounded active-payment polling; database triggers alone do not notify clients.
- Backend maintenance/version policy must protect sensitive actions independently of client checks. Preserve in-flight payment callbacks, refunds, and reconciliation. Public app/version keys or headers are not security identities.

## Historical Account Lifecycle Rollout

The earlier recovery-only and preservation rollout below is superseded by the
current release summary: 90-day recovery, policy `2026-10-05.2` and consent-based
deletion. Its 30-day target and no-argument deletion request are not the current
contract; cleanup v2 deployment does not activate cleanup.

The old hard-delete `delete-account` handler has been replaced in hosted development by the reviewed recovery-only handler, with no service key, Auth deletion or financial anonymization. The seven-source rollout installed request/status/restore RPCs and preserved existing account/financial links. The user's later activation approval enabled authenticated `request_account_deletion()` through the existing guarded RPC; anon/service and inner-helper permissions were not broadened. Restoration remains authenticated and requires the server's fresh-session, deadline and admission checks. The client recovery UI is integrated locally. Prior 41 PostgreSQL/62 Edge, 345 client and later 125 race checks cover overlapping scopes and are not summed.

See [Account recovery](account-recovery.md) for exact wire values, lock ordering,
strict post-request fresh-session requirement and persistent marketing suppression.
Request activation does not establish functional acceptance or permanent purge.
October 2: permanent-cleanup/retained-subject migrations and the paid-credit
preservation revision are installed, as are the guarded worker, dedicated
credential and dormant scheduler. Purchased credit is retained separately with
no automatic expiry or forfeiture. Execution remains off for hosted Auth/Storage
and truthful per-request inventory acceptance, not another business-policy
approval. See [retention](retention.md) and the current operations checkpoint.

Target: active -> pending deletion -> restored active before deadline OR final deletion after deadline. The server sets `requested_at + 30 days` in UTC, returns the deadline for localized display, and decides boundaries. Restore requires verified ownership, applicable MFA, and explicit confirmation; a successful login alone does not restore. At/after the deadline restoration is rejected even if cleanup is delayed.

- Preserve account ID and financial links during recovery. Restrict ordinary app reads/writes and spending/funding, revoke applicable sessions, and enforce the pending state in RLS/functions despite stale access tokens. Allow only recovery/status and necessary support/refund/settlement paths.
- Finalization runs server-side independently of app activity, is idempotent, and serializes with restore. Clean up Storage and service-provider personal data; retain only approved financial/security records. Reconcile pending financial operations rather than orphaning them.
- Restore does not reset policy acceptance/refund clocks, duplicate rewards/welcomes, restore revoked roles, or resubscribe marketing. Approval of retention exceptions and paid-balance treatment is required before enabling purge; do not silently zero funds.
- Supabase Auth soft deletion is irreversible and is not this recovery feature. Deletion does not immediately invalidate already-issued JWTs. See [deleteUser](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser) and [user/session caveats](https://supabase.com/docs/guides/auth/managing-user-data).

## Safe Migration and Verification

- Read-only Chrome inspection confirmed 18 public tables with RLS enabled and `wallet_balances` with `security_invoker=true`. This is metadata evidence, not acceptance of policy semantics. `record_wallet_load_from_stripe` is service-role executable only; its live definition has no explicit wallet/profile locking. Unique Stripe identifiers prevent duplicate load rows but do not serialize reward progress across distinct concurrent loads.
- **Closed profile-field finding:** the September 29 inspection found direct client writes to roles/balance/rewards. The approved `20260929223124_protect_profile_authority.sql` containment is now installed; the later seven-source postflight reconfirmed effective anon/authenticated INSERT and UPDATE are false for these and both terms fields. Existing records and trusted writers were preserved. This does not close separate Maintenance/Refunds reads, direct financial inserts or global/location authority findings.
- Live metadata checks found no custom database roles in the 17-role inventory; anon/authenticated cannot CREATE in public. Auth signup and email/name triggers do not accept protected fields. The eight authenticated callable definers are postgres-owned and were read; administrative functions rely on the current profile role helper, not MFA/location enforcement. Existing role legitimacy, shared wallet locks/status checks, and remaining privileged paths are separate release gates, not claims resolved by the new trigger.
- Earliest migrations assume existing `profiles`, `Machines`, `transactions`, `Refunds`, `Location_to_Admin`, `Roles`, and legacy functions. Local config references missing `seed.sql`. Synthetic SQL fixtures are not a complete production baseline.
- September 28 admin/availability/history migrations and functions are currently untracked; untracked does not mean undeployed. Console history confirms the availability/history migrations, but does not list the two admin migrations or August refund hardening. Absence from history does not prove an object's absence. Reconcile deployed definitions, grants, Auth/Storage settings, and environment mapping before changing them.
- Prefer additive, backward-compatible schema changes and small backfills; inspect `--help` before CLI operations. Do not run blanket push/reset, owner bootstrap, or download-overwrite scripts during discovery.
- Test anonymous/customer/other-user/Admin/Owner and cross-location requests, including direct crafted RPC calls, stale sessions, Storage paths, concurrent debits, reservations, duplicate callbacks, and restore/purge races. Inspect grants, function execution privileges, search paths, and RLS together.
- Verify current [API key documentation](https://supabase.com/docs/guides/getting-started/api-keys), [Auth MFA](https://supabase.com/docs/guides/auth/auth-mfa), and [changelog](https://supabase.com/changelog) before implementation. Preserve authoritative database checks rather than duplicating them in multiple clients.
