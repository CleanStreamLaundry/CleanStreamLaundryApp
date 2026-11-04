-- Metadata only, DEVELOPMENT dnuuhupoxjtwqzaqylvb. Never invokes account RPCs.
-- Stop on any body/owner/ACL mismatch or pre-existing new object/history row.
with expected(signature,source_sha256) as (values
  ('public.admin_adjust_wallet(uuid,integer,integer,integer,text)','35259762165fcebd24dea72afa64295c92475b520719b8b52479ce20a34532a4'),
  ('public.admin_record_legal_cash_redemption(uuid,integer,text,text)','d0898698392caf71c2c5c2734fdf9f3ab2fc913201999458bd7d075db33fcd8e'),
  ('public.admin_set_wallet_status(uuid,text,text)','459567e140934c87375a795c740a7d00d0ff909d3ca30ec091d5829e4bee42be'),
  ('public.request_account_deletion()','8c485e52342832b5b22e3d1a6cdc7abda3f186751ae29fff3126b6e4cc31a597')
), prerequisites(signature) as (values
  ('private.current_account_access()'),('private.portal_staff_context()'),
  ('public.get_account_lifecycle_status()'),('public.restore_account()'),
  ('public.is_admin_or_owner()'),('public.sync_profile_wallet_balance(uuid)'),
  ('public.admin_portal_request(text,jsonb)'),
  ('public.admin_team_onboarding(text,text,bigint[],uuid,bigint)'),
  ('public.admin_portal_bootstrap_owner(uuid,bigint[])')
), new_functions(signature) as (values
  ('private.owner_target_restriction(uuid)'),('private.require_other_owner(uuid)'),
  ('private.guard_last_owner()'),('private.portal_owner_context()'),
  ('public.admin_owner_management(text,jsonb)'),('public.admin_wallet_read(text,jsonb)'),
  ('private.admin_adjust_wallet(uuid,integer,integer,integer,text)'),
  ('private.admin_record_legal_cash_redemption(uuid,integer,text,text)'),
  ('private.admin_set_wallet_status(uuid,text,text)'),('private.request_account_deletion()')
)
select jsonb_build_object(
  'moving_bodies',(select jsonb_agg(jsonb_build_object('signature',e.signature,'exists',p.oid is not null,
    'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'settings',p.proconfig,
    'body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),
    'body_matches_source',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=e.source_sha256,
    'expected_owner',pg_get_userbyid(p.proowner)='postgres',
    'held_api_acl',case when p.oid is not null then not (has_function_privilege('anon',p.oid,'execute') or
      has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('service_role',p.oid,'execute')) end,
    'acl',p.proacl) order by e.signature) from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature)),
  'prerequisites',(select jsonb_agg(jsonb_build_object('signature',r.signature,'exists',p.oid is not null,
    'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'settings',p.proconfig,'acl',p.proacl,
    'body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),
    'execute',case when p.oid is not null then jsonb_build_object('anon',has_function_privilege('anon',p.oid,'execute'),
      'authenticated',has_function_privilege('authenticated',p.oid,'execute'),'service_role',has_function_privilege('service_role',p.oid,'execute')) end)
    order by r.signature) from prerequisites r left join pg_proc p on p.oid=to_regprocedure(r.signature)),
  'new_functions_absent',(select jsonb_object_agg(signature,to_regprocedure(signature) is null) from new_functions),
  'new_trigger_absent',not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.profiles') and tgname='owner_role_removal_guard'),
  'new_index_absent',to_regclass('public.admin_owner_request_receipt') is null,
  'history_absent',not exists(select 1 from supabase_migrations.schema_migrations where version='20261001013709'),
  'relations',(select jsonb_agg(jsonb_build_object('name',name,'exists',c.oid is not null,'owner',pg_get_userbyid(c.relowner),
    'rls',c.relrowsecurity,'options',c.reloptions) order by name) from unnest(array[
      'public.profiles','public."Location_to_Admin"','public.admin_audit_events','private.account_lifecycle',
      'private.customer_mfa_recovery','public.wallet_accounts','public.wallet_balances','public.wallet_loads',
      'public.wallet_ledger_entries','public.wallet_redemptions','auth.users','auth.mfa_factors']) name
    left join pg_class c on c.oid=to_regclass(name)),
  'membership_location_nullable',(select not attnotnull from pg_attribute where attrelid=to_regclass('public."Location_to_Admin"') and attname='location_id'),
  'existing_guards',(select jsonb_agg(jsonb_build_object('relation',tgrelid::regclass::text,'name',tgname,'enabled',tgenabled,
    'function',tgfoid::regprocedure::text) order by tgrelid,tgname) from pg_trigger where not tgisinternal
    and tgrelid in(to_regclass('public.profiles'),to_regclass('private.account_lifecycle'),to_regclass('public.admin_audit_events'))),
  'wallet_policy_sha256',(select encode(sha256(convert_to(coalesce(string_agg(polname||':'||polcmd::text||':'||coalesce(pg_get_expr(polqual,polrelid),'')||':'||
    coalesce(pg_get_expr(polwithcheck,polrelid),'')||':'||polpermissive::text||':'||polroles::text, E'\n' order by polrelid,polname),''),'UTF8')),'hex')
    from pg_policy where polrelid in(to_regclass('public.profiles'),to_regclass('public.wallet_accounts'),to_regclass('public.wallet_loads'),
      to_regclass('public.wallet_ledger_entries'),to_regclass('public.wallet_redemptions')))
);
