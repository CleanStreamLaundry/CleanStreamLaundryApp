# Remaining Admission: Anonymous Membership Read

**Frozen source, awaiting serial QA.** Author ran zero tests, databases, cloud/provider actions or active-repository edits. Supabase CLI **2.84.2** created the new migration locally. Owner, financial, availability, push and prior92 evidence are reused, not rerun. Deletion remains held; no purge, retention, grants, rows or Storage changes.

## Confirmed Gap and Fix

Composer's fresh hosted metadata-only preflight **1392c2, exit0** confirms `Location_to_Admin`: postgres owner/RLS=true, anonymous table/all3-column SELECT=true, old PUBLIC permissive SELECT=true, canonical restrictive SELECT applies only to authenticated, and new guard absent. Both authority helpers deny anonymous EXECUTE. All deletion EXECUTE flags remain false. No customer rows were queried.

The candidate adds only `portal_membership_no_anon`, restrictive SELECT TO anon USING(false), after checking the existing canonical policy prerequisite. The authenticated `user_id=auth.uid() AND is_admin_or_owner()` policy and current evaluator remain byte-unchanged. Separate anonymous denial avoids adding helper grants or relying on expression short-circuiting. No table/function/framework is added. Existing service/definer writers and public browsing remain unchanged; old anonymous staff-assignment reads intentionally become empty.

## Bounded Coverage

Historical catalog is used only with accepted installed-source receipts; row4 additionally has fresh1392c2. This is not a whole-API audit or hosted positive acceptance.

| Surface / definition | Status and exact evidence |
| --- | --- |
| `Locations` public address/name/hours/coordinates | Intentionally public, preserved. [Mobile projection](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/lib/services/supabase/supabase_location_service.dart:5); [accepted migration explicitly preserving inventory reads](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260928135006_admin_portal_operations.sql:60); historical PUBLIC true policy at [catalog](/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/activation-current/hosted-catalog.json:2690). No Home/pending gate added. |
| `Machines` public identity/price/count/type/location metadata | Intentionally public, preserved. [Mobile price read](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/lib/services/supabase/supabase_machine_service.dart:82); same inventory contract; historical PUBLIC true at [catalog](/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/activation-current/hosted-catalog.json:2725). |
| `Machines.service_reason/service_updated_by` | **Classification not assumed.** [Admin extension](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260928151021_admin_operations_extensions.sql:12) adds free-text service note and actor UUID to the publicly readable relation; [staff form](/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/src/admin/AvailabilityForm.tsx:62) displays the note. Public price/location intent does not itself approve publishing staff notes/identity. Exact decision: are these fields public, or staff-only? No blanket table denial or speculative column/client change in this batch. |
| Anonymous `Location_to_Admin` SELECT / embedded joins | **Confirmed open; candidate closes.** Fresh1392c2 proves public permissive policy and effective anon SELECT. Existing [authenticated-only restriction](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930142406_admin_canonical_authorization.sql:149) misses anon. Signed-out fallback exposes private staff UUID/location assignments; no public browsing consumer needs these mappings. |
| Authenticated `Location_to_Admin` SELECT | Closed by installed canonical self/staff policy above, using [is_admin_or_owner](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930142406_admin_canonical_authorization.sql:114), which calls the current lifecycle/MFA evaluator. Eligible preterms staff remain allowed; other/pending/MFA-restricted identities denied. Fresh1392c2 confirms deployed policy shape. |
| Membership and inventory direct mutations | Closed installed source, unchanged: [table/column membership revokes and ALWAYS guard](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930024142_protect_location_membership.sql:32), [inventory table/column revokes](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930142406_admin_canonical_authorization.sql:152). C/D receipt reused. |
| `washer_size_rates` / `cortina_machine_config` staff reads | Closed installed source: existing location predicates plus canonical restrictive [rate/config policies](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930142406_admin_canonical_authorization.sql:147). These are not the public `Machines.Price` projection. No grant/policy expansion. |
| `admin_portal_request('locations'/'machines'/...)` and actor-taking helper RPCs | Closed installed source: [captured canonical pre/post context](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930142406_admin_canonical_authorization.sql:40); [inner EXECUTE revokes](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260930142406_admin_canonical_authorization.sql:89). Onboarding and Owner wrappers already accepted/installed; no second review. |
| Availability read/refresh/lease RPCs | Closed within recorded contract: [ordinary-access handoff](/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/ordinary-access/HANDOFF.md:3) records46/ACTIVE13; [availability state and lease functions](/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/supabase/migrations/20260928212227_nayax_machine_availability.sql:17) are service-only. Trigger-returning machine/rate functions are triggers, not standalone human RPC mutation APIs. |
| Public Cortina quote and fresh authenticated card admission | Public quote intent retained; no signed-out price denial. [Post-capacity follow-up](/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/deletion-admission-followup/HANDOFF.md:3) is integrated/QA92 accepted, but new writer remains undeployed pending public return reader. Deployment closure, not new code in this batch. |

Storage policy activation is Composer-owned and excluded. The newer supported `supautils.policy_grants` receipt supersedes the earlier owner-only-path assumption; this batch makes no Storage edits. Existing payment completion/recovery/refund exceptions and deletion hold are unchanged.

## Frozen Inputs

Only two integration files:

- `supabase/migrations/20261001094740_deny_anonymous_location_membership.sql`: `d6ad6839dd6c311d1de436c0189419b6bb26c3a5ec2f1b60ce9a1a01f345cb1b`
- `scripts/location-membership-read-admission.test.mjs`: `fb78d13c9d3dcdbb89696dc8d108229126fabd77fb44ab109b76d66159f8e671`

Supporting catalog query `preflight.sql`: `c0481fad8c55fc3af591ed4b467e84869ba316f79ff3c9ea5a1583051b79c188`; Composer already ran it as1392c2. It includes exact policy qualifications/role targets and table/column grants. No repeat requested. Existing qualified predicate is retained, not regenerated or widened.

## Focused QA

Source-enumerated **16 children + parent =17 expected**, not passes. Uses the existing disposable PG helper with private socket/authorized local bottle relocation and teardown. Prerequisite fixture loads actual accepted canonical admin/lifecycle/MFA SQL; no old suites run. Historical nullable membership is seeded before the existing audit trigger, never by disabling a production guard. Tests cover baseline leak, prerequisite rollback, unchanged table/column ACLs/all other policies/function bodies/audit/rows, anonymous direct/join/regrant denial, eligible Owner/Admin self access without customer terms, pending/expired pending/MFA/stale/cross-session denial, public browsing, canonical location RPC, trusted definer creation and deletion hold.

Run only when QA owns the serial slot, from this root:

```sh
MEMBERSHIP_READ_APP_ROOT=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/location-membership-read-admission.test.mjs
```

No source checks/tests executed by author. QA reports actual PG version/counts/process exit/server stop/temp removal. After acceptance, Composer may install only this single additive policy migration and record its exact source; never replay prerequisite/foundation migrations. No Edge deployment or client integration is required. Removing the guard reopens the confirmed leak and is not a safe privacy rollback; forward repair should keep anonymous denial. This does not authorize enabling deletion.

## Official References

[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) confirms grants and policy applicability are separate, and anon differs from anonymous Auth users. [PostgreSQL17 CREATE POLICY](https://www.postgresql.org/docs/17/sql-createpolicy.html) describes restrictive-policy intersection; the existing authenticated rule stays unchanged. [Current Supabase changelog](https://supabase.com/changelog) checked October1; no relevant policy-role semantic change identified. Markdown changelog endpoint returned unsupported content-type, so the official HTML index was used. Runtime verification remains pending QA.
