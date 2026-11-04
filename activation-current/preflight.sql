-- Composer only, verified DEVELOPMENT ref dnuuhupoxjtwqzaqylvb.
-- One SELECT/result. No application rows, function bodies, secrets or mutations.
with wanted_rel(name) as (values
  ('public.wallet_accounts'), ('public.wallet_loads'), ('public.wallet_ledger_entries'),
  ('public.wallet_redemptions'), ('public.wallet_balances'),
  ('public.deleted_account_complaints'), ('public.transactions'), ('public."Refunds"'),
  ('public."Maintenance"'), ('public."Locations"'), ('public."Location_to_Admin"'),
  ('public."Machines"'), ('public.washer_size_rates'), ('public.cortina_machine_config'),
  ('public.cortina_vend_sessions'), ('public.cortina_vend_events'),
  ('public.admin_maintenance_history'), ('public.admin_invitations'), ('public.admin_audit_events'),
  ('storage.objects')
), rel as (
  select w.name, c.* from wanted_rel w left join pg_class c on c.oid=to_regclass(w.name)
), wanted_fn(name) as (values
  ('get_or_create_wallet_account'), ('sync_profile_wallet_balance'),
  ('record_wallet_load_from_stripe'), ('redeem_wallet_for_machine'), ('redeem_wallet_for_cortina'),
  ('reverse_cortina_wallet_redemption'), ('resolve_refund_request'),
  ('admin_adjust_wallet'), ('admin_record_legal_cash_redemption'), ('admin_set_wallet_status'),
  ('record_deleted_account_complaint'), ('update_user_balance'),
  ('sync_cortina_transaction'), ('validate_cortina_credit_request'), ('request_cortina_loyalty_credit'),
  ('guard_cortina_payment_binding'), ('bind_cortina_callback_provider'),
  ('admin_portal_data'), ('admin_portal_data_v1'), ('admin_portal_rows'),
  ('admin_portal_records'), ('admin_portal_assign_member'), ('admin_portal_bootstrap_owner'),
  ('portal_record_access'), ('portal_record_access_before_authorization'), ('is_admin_or_owner')
), fn as (
  select w.name, p.* from wanted_fn w left join pg_proc p on p.proname=w.name
    and p.pronamespace in (select oid from pg_namespace where nspname in ('public','private'))
    and p.prokind='f'
)
select jsonb_build_object(
  'relations', (select jsonb_agg(jsonb_build_object('name',name,'exists',oid is not null,
    'owner',pg_get_userbyid(relowner),'kind',relkind,'rls',relrowsecurity,
    'force_rls',relforcerowsecurity,'options',reloptions,'acl',relacl) order by name) from rel),
  'columns', (select jsonb_agg(jsonb_build_object('table',r.name,'column',a.attname,
    'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'identity',a.attidentity,
    'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl) order by r.name,a.attnum)
    from rel r join pg_attribute a on a.attrelid=r.oid and a.attnum>0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum),
  'constraints', (select jsonb_agg(jsonb_build_object('table',r.name,'name',c.conname,
    'validated',c.convalidated,'definition',pg_get_constraintdef(c.oid)) order by r.name,c.conname)
    from rel r join pg_constraint c on c.conrelid=r.oid),
  'policies', (select jsonb_agg(jsonb_build_object('table',r.name,'name',p.polname,
    'permissive',p.polpermissive,'cmd',p.polcmd,'roles',p.polroles,
    'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
    order by r.name,p.polname) from rel r join pg_policy p on p.polrelid=r.oid),
  'triggers', (select jsonb_agg(jsonb_build_object('table',r.name,'name',t.tgname,
    'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) order by r.name,t.tgname)
    from rel r join pg_trigger t on t.tgrelid=r.oid and not t.tgisinternal),
  'functions', (select jsonb_agg(jsonb_build_object('name',name,'signature',oid::regprocedure::text,
    'owner',pg_get_userbyid(proowner),'security_definer',prosecdef,'config',proconfig,
    'acl',proacl,'definition_md5',case when oid is not null then md5(pg_get_functiondef(oid)) end,
    'anon_execute',case when oid is not null then has_function_privilege('anon',oid,'execute') end,
    'authenticated_execute',case when oid is not null then has_function_privilege('authenticated',oid,'execute') end,
    'service_execute',case when oid is not null then has_function_privilege('service_role',oid,'execute') end)
    order by name,oid) from fn),
  'direct_writes', (select jsonb_agg(jsonb_build_object('table',r.name,'role',u.role,
    'insert',has_table_privilege(u.role,r.oid,'insert') or has_any_column_privilege(u.role,r.oid,'insert'),
    'update',has_table_privilege(u.role,r.oid,'update') or has_any_column_privilege(u.role,r.oid,'update'),
    'delete',has_table_privilege(u.role,r.oid,'delete')) order by r.name,u.role)
    from rel r cross join (values ('anon'),('authenticated')) u(role)
    where r.oid is not null and r.name in ('public.transactions','public."Refunds"','public."Maintenance"'))
);
