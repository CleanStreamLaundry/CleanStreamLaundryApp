# Hosted Admission/Lifecycle/Mail Slice

## Activation Hold

Minimal dependencies do NOT mean approved terms or readiness to activate. Composer
integrated the exact two-file descriptor/test update and Avicenna's five text/test
files locally. The seven-paragraph review draft now aligns the approved 48-hour
refund and 30-day restoration mechanics, explicitly leaving retention and
remaining-balance treatment unresolved. Nearest37 and presentation QA are queued
after geocoding; no new pass or legal approval is claimed. Guard1 is installed;
HOLD remaining migrations 2-6 pending QA, policy approval and whole-API lifecycle
coverage. The legacy delete endpoint has been replaced as recorded below.
Do not reuse a policy version for different text or manufacture consent.
Development enablement does not authorize purge or binding draft terms.

Composer installed the first guard as standalone containment:
`20260929223124_protect_profile_authority.sql`, SHA256
`1286837332961990a19d986e5112720ae50efa1b03677b8fb49bd9b5dfe4dcfb`.
Its only schema dependency is existing profiles/roles/catalog grants, verified
by the completed catalog checks. Independent local38 receipt is recorded in
docs/supabase.md. It creates no terms, mail or lifecycle objects, changes no
application rows and invokes no external operation. Use the complete file's own
BEGIN/COMMIT, one transaction. It intentionally rejects legacy client role/
balance/reward writes while preserving nonprotected edits and trusted server
privileges; it does not fix every profile/API privilege or unsafe delete endpoint.
Hosted receipt: exact reviewed file applied through SQL --linked, exit0/chunk
`922886`, no DML. Trigger metadata enabled=O confirmed, exit0/chunk `d5cbcc`.
Effective-grant verification subsequently returned all six INSERT/UPDATE results
false, exit0/chunk `452ac6`. Official CLI migration repair recorded ONLY
`20260929223124` as applied, exit0/chunk `0a5789`; other history was preserved.
Exclude guard1 from every later bundle: its CREATE FUNCTION/TRIGGER are not
replayable. File2's updated local source receipt is frozen below, not activated.

Composer also deployed the reviewed recovery-only delete-account code/helpers
with --use-api, exit0/chunk `ba4c52`. This replaces an existing function; inventory
remains23. No Auth deletions occurred. Missing lifecycle RPCs fail closed until
their held prerequisites are installed. Never roll back to the hard-delete
handler. These receipts do not establish whole-API lifecycle coverage.

## Scope And Evidence

Read-only mapping for composer-controlled DEVELOPMENT activation, 2026-09-30.
Verified project is CleanStream (DEVELOPMENT), reference `dnuuhupoxjtwqzaqylvb`.
Final local-only check of `CleanStreamLaundryApp/supabase/.temp/project-ref`
matches that reference; no repeat database query. Existing official CLI login works with authorized host
access; no token copied/logged, link changed, application rows read, or SQL writes.
Two catalog SELECTs passed: exit0/chunks `b856c2` and `fde77a`, executor postgres,
PostgreSQL17.6. A sandbox-only attempt could not access login; it ran no query.
No test reruns. Composer is the only remote writer.

The catalog rows below are the PRE-CHANGE baseline, not a claim that guard1 is
still absent. The installation/trigger receipts above supersede that baseline;
effective grants are now verified by the separate receipt above.

| Exact pre-change catalog result | Consequence |
| --- | --- |
| private schema absent; lifecycle and all five mail tables absent; all selected admission/terms/lifecycle/mail routines absent | Clean six-file dependency slice below, not a replay of all migrations. |
| public.wallet_ledger_entries EXISTS | Earlier wallet_ledger lookup used a different name. Do NOT run the wallet foundation or paid-balance backfill. |
| profiles is postgres-owned, RLS on/force off; UUID PK and validated Auth FK; default User, zero balances; no extra required insert columns | Existing bootstrap/profile assumptions match this slice. |
| Two loyalty columns and profile triggers absent; protected fields effectively INSERT/UPDATE-granted to anon/authenticated | Baseline justified guard1, now installed. Loyalty columns remain absent; all six post-change INSERT/UPDATE results false. |
| Required Auth users/sessions/factors columns and enum labels present; postgres can SELECT them, lock Auth id, create Auth triggers, bypass RLS, create public objects/schema | Needed owner/DDL/lookup permissions present. Auth rows/secrets not inspected. |
| anon/authenticated have no superuser, bypass-RLS, create-role or membership authority | No discovered inheritance blocker to the migration guards. |
| pg_net0.19.5, supabase_vault0.3.1, pgcrypto1.3; net.http_post and Vault view present; cron.schedule absent | Mail schema/Edge can be staged without Cron; scheduler cannot yet install. |

Hosted legacy Auth triggers remain `on_auth_user_created`,
`on_auth_user_updated`, `on_auth_users_full_name_updated`; this slice preserves
their functions. Metadata fingerprints were recorded, not secret-bearing bodies.
Latest composer receipt supersedes the initial20 inventory:20 legacy +3 new mail
functions =23. mail-webhook, mail-delivery and newsletter were deployed individually
with --use-api; no existing function replaced or DB mutation. Empty anonymous
smokes returned webhook503/webhook_disabled, delivery401/unauthorized and
newsletter401/session_required. Initial secret-name inventory found no component
mail variables; legacy RESEND_API_KEY exists but is not a supported fallback.
Latest composer receipt supersedes that baseline: the user approved and created
the restricted Resend key; composer saved it as CLEANSTREAM_RESEND_API_KEY on
exact project dnuuhupoxjtwqzaqylvb and verified persistence after reload. Temporary
copy cleared; no key in logs/files, no old key retired and no sends. Do not create
a duplicate key. Other mail secrets and scheduling remain missing; this is partial
configuration, not mail activation. MFA/cleanup/admin/reconcile remain absent
per composer inventory; mail transport deployment is NOT schema/feature activation.

## Dependency Order, Not Activation Approval

All paths relative to active app `supabase/migrations/`; do not use older lane
copies. The six files below form one prerequisite chain, with no financial or
Cortina migration dependency. Migration1 is already installed and must be excluded
from future execution. Descriptor alignment is integrated locally; QA, policy
approval and whole-API lifecycle coverage hold the remaining five. The deletion
Edge replacement is deployed fail-closed.

| Order | Exact migration | Installation effect |
| --- | --- | --- |
| 1, INSTALLED | 20260929223124_protect_profile_authority.sql | Preserve server/nonprotected writes; close client role/balance/reward writes. Do not replay. |
| 2, UNAPPLIED | 20260929234955_loyalty_policy_acceptance.sql | Updated review draft integrated locally; nullable protected consent pair, descriptor/status/explicit acceptance; no consent backfill. |
| 3 | 20260930005456_account_admission.sql | Private canonical evaluator, minimal self-bootstrap and admission RPC. |
| 4 | 20260930013417_enforce_profile_terms_admission.sql | Restrictive profile policies and same canonical terms/admission locking. |
| 5 | 20260930063923_recoverable_account_deletion.sql | Empty lifecycle table, request/status/restore, exact 720-hour deadline and post-wait restore checks. |
| 6 | 20260930125527_newsletter_consent_mail_outbox.sql | Empty consent/outbox/suppression/event tables, disabled settings singleton, Auth/lifecycle triggers, scoped RPCs. |

Freeze receipt (file SHA256 in the same order; guard1 already applied, files2-6 held):

```text
1286837332961990a19d986e5112720ae50efa1b03677b8fb49bd9b5dfe4dcfb
259d42771722c6a51f84c9688624db3553fa377d770acedfb41d7f230c9c4c6a
50f6a4cf08e9bd76d3bde0956d43db79b6fa1cb391191f641e5ea25f5a0f49e0
6a74d173592bb71cf0a314712b40a91c22648359947359d8f1697d98c7660595
bc960d7af1dc61078e1eb849dd2c4e5127867bdba39283ec9dd7f22821bf3315
b1dbb1ef6cd8e673cbcb1e5104d24df7bec7138f784714b3f3883b612390b3ca
```

File2's active local source was checked against the integrated receipt. Descriptor
version is `review-only-loyalty-d08c2c970e4fb2f7`; policy-text SHA256 is
`d08c2c970e4fb2f7255034ee643f6148454f7aca3c09e595c5eb94d10106e748`.
This replaces the obsolete file2 source hash and old review-only version, not an
existing hosted acceptance. File2 was confirmed unapplied; no migration history
or hosted descriptor was changed by this source update.

### Transaction Boundary

The remaining five can execute atomically as one PostgreSQL transaction. Source
inspection found exactly one outer `begin;` and final `commit;` per file,
no other transaction control, concurrent index operation, enum-value addition,
extension installation or external call during installation. The function/trigger
bodies are transactional definitions, not invoked mail/provider work.

Technical atomicity does NOT clear the activation hold. Guard1 has already committed
separately; assemble only migrations 2-6 after their source/activation approval.

Composer must assemble the reviewed payload by removing ONLY those five outer
BEGIN/COMMIT pairs, preserving every intervening byte/order, and wrapping once
with BEGIN and COMMIT. Do NOT concatenate unchanged files inside an outer BEGIN:
their COMMITs would commit intermediate stages. Do not modify the source migrations
or suppress errors. Any SQL error must abort the entire assembled transaction.
Use one reviewed CLI query/file execution, not five auto-committing invocations.

The only top-level INSERT is the mail settings singleton: enabled=false,
rollout_at=NULL. No profile-balance/consent/history backfill, finance operation,
Auth/user deletion, permanent purge, factor removal, network send or scheduler
installation occurs. Added profile columns start NULL. No existing user state is
converted into consent or pending deletion.

### Behavior And Rollback Limits

Old direct profile INSERT/upsert clients will fail; they must use the integrated
ensure_own_profile path. Direct protected-field writes stop. Restricted/session/
MFA states lose ordinary authenticated profile access. Terms reads/acceptance use
canonical identity, while Home uses explicit consent. The updated descriptor
remains review-only under the new version/hash above. Source integration does not
clear policy/QA/activation gates or unresolved retention treatment; deployment is
not legal-policy approval or automatic acceptance.

Lifecycle RPCs become callable at commit; this is not merely inert table setup.
Do not describe it as whole-API deletion protection: older funding/spend/admin/
Storage entrypoints need their separately reviewed gates. The accepted recovery-only
delete-account Edge replacement is now deployed; its missing lifecycle RPC fails
closed. This covers the identified legacy handler, not all API surfaces or a
working recovery flow yet. Do not invoke deletion as a smoke test. Old callers
must not regain an irreversible deletion path alongside advertised 30-day recovery.
No new boundary bypass or secret flag is proposed; never restore the hard-delete
handler as rollback.

Mail stays disabled until BOTH database enable/reached rollout and all Edge
mail configuration/approval gates pass. No historical welcome or newsletter
backfill. The three accepted mail bundles are deployed; CLEANSTREAM_RESEND_API_KEY
is saved/configured, but other mail secrets/scheduling remain missing and mail
remains disabled with schema absent per the last database receipt. Keep sending
disabled until the held prerequisites and remaining sender/configuration/rollout
checks are satisfied. Refund notices
(20260930175136_refund_request_notice_outbox.sql) are a separate optional extension;
they are not a prerequisite of this base slice. Do not set recipient/rollout here.

Before commit, rollback removes the attempted remaining-five installation, not
the already committed guard1 or independently deployed Edge functions.
After clients use the new contracts, dropping guards/consent/lifecycle/outbox or
restoring broad legacy writes is NOT a safe rollback. Preserve recorded consent,
deadlines, suppression and idempotency evidence; fix forward or pause the affected
surface. Never fall back to hard-delete-account. Disabling mail/scheduler cannot
retract an HTTP/provider request already dispatched. Preserve unfinished outcomes.

## Separate Later Stages, Not This Mutation

- Mail scheduling: existing supabase/ops/mail-worker-setup.sql depends on this
  mail schema, deployed worker/custom bearer, exact Vault entry setup and missing
  Cron integration. Setup itself installs no extension. No scheduling or sends in
  this slice; existing disable SQL is the narrow scheduler rollback.
- New-payment control: existing wallet schema/serialization + human-spend
  admission, then 20260930193130_new_payment_service_control.sql and three creation
  Edge consumers. No wallet foundation/backfill. Preserve settlement/refunds.
- Owner recovery: admin operations/extensions + canonical staff authorization
  + 20260930202731_customer_mfa_recovery.sql, then dedicated Edge/UI. Admin reporting
  additionally needs voluntary-topup provenance and must preserve source wrapper/
  rename order; it is NOT needed for base mail. MFA endpoint verify_jwt=true and
  named-key/asymmetric-token smoke remain separate deployment checks.
- Cortina binding/callback/reconciliation, maintenance/Storage and push each keep
  their own paired rollout. Existing Cortina objects prohibit blind historical
  CREATE replay. Cleanup metadata is not a mail dependency; executor remains
  disabled, retention/settlement policy unresolved, no purge or cleanup schedule.

## Existing QA, Not A New Campaign Run

Recorded local evidence: profile guard38; terms descriptor37; admission109
INCLUDING those37 (72 admission); profile/terms enforcement72; lifecycle41 plus
62 Edge cases; newsletter52 PG plus73 Deno. Later restore/mail-trigger rollback
checkpoint125 is documented in docs/supabase.md. These counts overlap and older
runtime/temp paths are historical, not fresh execution here. Current slice source
includes the post-trigger restore recheck. No hosted signature, email-delivery,
full financial or production-data result is inferred from synthetic QA.

Current checks completed here are ONLY verified project link, source boundary/
dependency inspection, six hashes and the two read-only catalog SELECTs below.
No SQL compile/apply test or mutation was performed. After composer commits, check
these same catalog deltas and restricted grants before deploying/enabling callers;
state/flag inspection or development end-to-end sends need the separate approved
composer scope.

## Exact Read-Only Preflight SQL

Executed with the existing CLI login and explicit active workdir:

```sh
supabase db query --linked --workdir /Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp --output json '<catalog SELECT>'
```

No application row, Vault value, network queue, provider log or token query.

```sql
with objects(name) as (values
('public.profiles'),('auth.users'),('auth.sessions'),('auth.mfa_factors'),
('private.account_lifecycle'),('private.mail_settings'),('private.newsletter_consent'),
('private.mail_suppression'),('private.mail_outbox'),('private.mail_webhook_event'),
('public."Refunds"'),('public.transactions'),('public.wallet_ledger_entries'),
('supabase_migrations.schema_migrations')),
needed(rel,cols) as (values
('public.profiles',array['id','full_name','email','roles','balance','reward_tracker','created_at','loyalty_policy_version','loyalty_policy_accepted_at']),
('auth.users',array['id','email','created_at','email_confirmed_at','is_anonymous','deleted_at','banned_until']),
('auth.sessions',array['id','user_id','aal','factor_id','not_after','created_at']),
('auth.mfa_factors',array['id','user_id','factor_type','status','created_at']),
('public."Refunds"',array['refund_id','user_id','transaction_id','status','amount']),
('public.transactions',array['id','user_id','amount','type','description','requested_refund'])),
cols as (select rel,unnest(cols) col from needed)
select jsonb_build_object(
'server',jsonb_build_object('database',current_database(),'executor',current_user,'version',current_setting('server_version')),
'extensions',(select jsonb_object_agg(extname,extversion) from pg_extension where extname in ('pg_net','supabase_vault','vault','pg_cron','pgcrypto')),
'objects',(select jsonb_object_agg(name,to_regclass(name) is not null) from objects),
'columns',(select jsonb_agg(jsonb_build_object('relation',rel,'column',col,'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull,'postgres_select',case when a.attnum is not null then has_column_privilege('postgres',a.attrelid,a.attnum,'SELECT') end) order by rel,col) from cols left join pg_attribute a on a.attrelid=to_regclass(rel) and a.attname=col and a.attnum>0 and not a.attisdropped),
'owners_rls',(select jsonb_agg(jsonb_build_object('relation',name,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl)) from objects join pg_class c on c.oid=to_regclass(name) where name in ('public.profiles','auth.users','auth.sessions','auth.mfa_factors')),
'types',(select jsonb_object_agg(t.typname,x.labels) from pg_type t join pg_namespace n on n.oid=t.typnamespace cross join lateral(select jsonb_agg(e.enumlabel order by e.enumsortorder) labels from pg_enum e where e.enumtypid=t.oid) x where (n.nspname,t.typname) in (('public','Roles'),('auth','aal_level'),('auth','factor_type'),('auth','factor_status'))),
'routines',(select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig,'acl',p.proacl,'definition_md5',md5(pg_get_functiondef(p.oid)))),'[]'::jsonb) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname in ('guard_profile_protected_fields','guard_profile_policy_acceptance','get_loyalty_policy_descriptor','get_loyalty_policy_status','accept_loyalty_policy','current_account_access','account_access_allowed','get_admission_status','ensure_own_profile','request_account_deletion','restore_account','newsletter_request','mail_claim','mail_finish','enqueue_refund_request_notice')),
'triggers',(select coalesce(jsonb_agg(jsonb_build_object('relation',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,'function',t.tgfoid::regprocedure::text,'definition_md5',md5(pg_get_triggerdef(t.oid)))),'[]'::jsonb) from pg_trigger t where not t.tgisinternal and t.tgrelid in (to_regclass('public.profiles'),to_regclass('auth.users'),to_regclass('private.account_lifecycle'))),
'profile_policies',(select coalesce(jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))),'[]'::jsonb) from pg_policy p where p.polrelid=to_regclass('public.profiles')),
'protected_client_writes',(select jsonb_agg(jsonb_build_object('role',r.rolname,'column',a.attname,'insert',has_column_privilege(r.oid,a.attrelid,a.attnum,'INSERT'),'update',has_column_privilege(r.oid,a.attrelid,a.attnum,'UPDATE'))) from pg_roles r cross join pg_attribute a where r.rolname in ('anon','authenticated') and a.attrelid=to_regclass('public.profiles') and a.attname in ('roles','balance','reward_tracker')),
'private_schema',(select jsonb_build_object('owner',pg_get_userbyid(n.nspowner),'acl',n.nspacl) from pg_namespace n where n.nspname='private'),
'client_role_flags',(select jsonb_agg(jsonb_build_object('role',r.rolname,'super',r.rolsuper,'bypassrls',r.rolbypassrls,'createrole',r.rolcreaterole,'memberships',(select coalesce(jsonb_agg(pg_get_userbyid(m.roleid)),'[]'::jsonb) from pg_auth_members m where m.member=r.oid))) from pg_roles r where r.rolname in ('anon','authenticated'))
) as preflight;
```

Second bounded constraints/privileges/extension check:

```sql
select jsonb_build_object(
'profile_constraints',(select jsonb_agg(jsonb_build_object('name',conname,'type',contype,'validated',convalidated,'definition',pg_get_constraintdef(oid))) from pg_constraint where conrelid='public.profiles'::regclass),
'profile_defaults',(select jsonb_object_agg(a.attname,pg_get_expr(d.adbin,d.adrelid)) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid='public.profiles'::regclass and a.attname in ('id','roles','balance','reward_tracker','created_at')),
'additional_required_profile_columns',(select coalesce(jsonb_agg(a.attname),'[]'::jsonb) from pg_attribute a where a.attrelid='public.profiles'::regclass and a.attnum>0 and not a.attisdropped and a.attnotnull and not a.atthasdef and a.attidentity='' and a.attgenerated='' and a.attname not in ('id','full_name')),
'postgres_capabilities',jsonb_build_object('database_create',has_database_privilege('postgres',current_database(),'CREATE'),'public_create',has_schema_privilege('postgres','public','CREATE'),'auth_usage',has_schema_privilege('postgres','auth','USAGE'),'auth_user_trigger',has_table_privilege('postgres','auth.users','TRIGGER'),'auth_user_share_lock',has_column_privilege('postgres','auth.users','id','UPDATE'),'bypass_rls',(select rolbypassrls from pg_roles where rolname='postgres')),
'scheduler_metadata',jsonb_build_object('cron_schedule',to_regprocedure('cron.schedule(text,text,text)') is not null,'http_post',to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null,'vault_view',to_regclass('vault.decrypted_secrets') is not null),
'legacy_auth_trigger_functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig,'definition_md5',md5(pg_get_functiondef(p.oid)))) from pg_proc p where p.oid in (select tgfoid from pg_trigger where tgrelid='auth.users'::regclass and not tgisinternal))
) as prerequisites;
```
