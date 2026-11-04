-- Metadata only after the one reviewed migration; compare with saved preflight.
-- Expected: all source/owner/settings/ACL matches true; deletion and bootstrap
-- held; wallet policy fingerprint unchanged; history absent until receipt step.
with expected(signature,source_sha256,auth_execute) as (values
  ('private.admin_adjust_wallet(uuid,integer,integer,integer,text)','35259762165fcebd24dea72afa64295c92475b520719b8b52479ce20a34532a4',false),
  ('private.admin_record_legal_cash_redemption(uuid,integer,text,text)','d0898698392caf71c2c5c2734fdf9f3ab2fc913201999458bd7d075db33fcd8e',false),
  ('private.admin_set_wallet_status(uuid,text,text)','459567e140934c87375a795c740a7d00d0ff909d3ca30ec091d5829e4bee42be',false),
  ('private.request_account_deletion()','8c485e52342832b5b22e3d1a6cdc7abda3f186751ae29fff3126b6e4cc31a597',false),
  ('public.admin_adjust_wallet(uuid,integer,integer,integer,text)','a692bf9963549e98e2049bb37f334b71f2ea9e3f7025e954216190d2b9ea0909',true),
  ('public.admin_record_legal_cash_redemption(uuid,integer,text,text)','085bcfac688cbfaa1646c5b494bb6542f0ee4b4fe89ee60d8a2695c7a1ab8c56',true),
  ('public.admin_set_wallet_status(uuid,text,text)','8563809bcd48341dfa82f431ef40e8cfb19678fe54dd7868a0102a92de723f84',true),
  ('public.request_account_deletion()','8d1a7764a846bfcc31bb4586291165761bd45f641b9084e0d9b7a14e1b905bf8',false),
  ('private.owner_target_restriction(uuid)','fd3f4e5d984531441014056b86304d42343e276a2939abbe2102655ce35aeeff',false),
  ('private.require_other_owner(uuid)','5669f7bb89358f69430e4ea660590b4402a80f34627d8dabf2c7e24b7ef08d5a',false),
  ('private.guard_last_owner()','e3147568c0540daf50b9f25f438c0f684b5bd48a4b6f1a0417b31f627872e909',false),
  ('private.portal_owner_context()','6eb879a8b8a64862284c59b7a1dc6de2eacea4f232134fa10a7d12940f4d283f',false),
  ('public.admin_owner_management(text,jsonb)','caee2af1104f2c765228da9f31caeaedc7c2cc4af9a1294f3d937b0ea990e922',true),
  ('public.admin_wallet_read(text,jsonb)','a3907f0118acc55e26f00dc4b0cbb8b770d6e1abe72500febb0f16a16b503cef',true)
)
select jsonb_build_object(
  'functions',(select jsonb_agg(jsonb_build_object('signature',e.signature,'exists',p.oid is not null,
    'owner',pg_get_userbyid(p.proowner),'owner_matches',pg_get_userbyid(p.proowner)='postgres',
    'security_definer',p.prosecdef,'settings',p.proconfig,'settings_match',p.proconfig=array['search_path=""']::text[],
    'body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),
    'body_matches_source',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=e.source_sha256,
    'acl_matches',case when p.oid is not null then not has_function_privilege('anon',p.oid,'execute')
      and has_function_privilege('authenticated',p.oid,'execute')=e.auth_execute
      and not has_function_privilege('service_role',p.oid,'execute')
      and not has_function_privilege('supabase_auth_admin',p.oid,'execute')
      and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
        where a.grantee=0 and a.privilege_type='EXECUTE') end,
    'acl',p.proacl) order by e.signature) from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature)),
  'deletion_held',not (has_function_privilege('anon','public.request_account_deletion()','execute')
    or has_function_privilege('authenticated','public.request_account_deletion()','execute')
    or has_function_privilege('service_role','public.request_account_deletion()','execute')),
  'bootstrap_held',not (has_function_privilege('anon','public.admin_portal_bootstrap_owner(uuid,bigint[])','execute')
    or has_function_privilege('authenticated','public.admin_portal_bootstrap_owner(uuid,bigint[])','execute')
    or has_function_privilege('service_role','public.admin_portal_bootstrap_owner(uuid,bigint[])','execute')),
  'owner_trigger',(select jsonb_build_object('enabled',tgenabled,'function',tgfoid::regprocedure::text,'definition',pg_get_triggerdef(oid))
    from pg_trigger where tgrelid=to_regclass('public.profiles') and tgname='owner_role_removal_guard'),
  'receipt_index',(select jsonb_build_object('unique',indisunique,'valid',indisvalid,'definition',pg_get_indexdef(indexrelid))
    from pg_index where indexrelid=to_regclass('public.admin_owner_request_receipt')),
  'wallet_view',(select jsonb_build_object('owner',pg_get_userbyid(relowner),'options',reloptions) from pg_class where oid=to_regclass('public.wallet_balances')),
  'wallet_policy_sha256',(select encode(sha256(convert_to(coalesce(string_agg(polname||':'||polcmd::text||':'||coalesce(pg_get_expr(polqual,polrelid),'')||':'||
    coalesce(pg_get_expr(polwithcheck,polrelid),'')||':'||polpermissive::text||':'||polroles::text, E'\n' order by polrelid,polname),''),'UTF8')),'hex')
    from pg_policy where polrelid in(to_regclass('public.profiles'),to_regclass('public.wallet_accounts'),to_regclass('public.wallet_loads'),
      to_regclass('public.wallet_ledger_entries'),to_regclass('public.wallet_redemptions'))),
  'history',(select jsonb_agg(jsonb_build_object('version',version,'name',name,'stored_source_files',cardinality(statements),
    'source_sha256',encode(sha256(convert_to(statements[1],'UTF8')),'hex'))) from supabase_migrations.schema_migrations where version='20261001013709')
);
