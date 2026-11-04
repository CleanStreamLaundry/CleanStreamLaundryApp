-- Composer only, after separately approved C/D18 on DEVELOPMENT dnuuhupoxjtwqzaqylvb.
-- Catalog/configuration SELECT only. No customer rows, identities, bodies or secrets.
with api_roles(role) as (values ('anon'),('authenticated'),('service_role')),
targets(signature) as (values
  ('public.request_account_deletion()'), ('public.restore_account()'),
  ('public.admin_portal_request(text,jsonb)'), ('public.admin_resolve_credit(bigint,text,text)'),
  ('public.admin_team_onboarding(text,text,bigint[],uuid,bigint)'),
  ('public.admin_team_invitation_delivered(bigint,uuid)'),
  ('public.customer_mfa_recovery_request(text,uuid,text,boolean,uuid)'),
  ('public.submit_maintenance_request(jsonb)'),
  ('public.request_legacy_loyalty_credit(bigint,text)'),
  ('public.request_cortina_loyalty_credit(bigint,text)'),
  ('public.increment_user_refund_attempts(uuid)'),
  ('public.new_payments_enabled()'),
  ('public.redeem_wallet_for_machine(uuid,bigint,integer,text)'),
  ('public.redeem_wallet_for_cortina(uuid)'),
  ('public.record_wallet_load_from_stripe(uuid,integer,text,text,text,text)'),
  ('public.record_topup_refund_provenance(text,uuid,integer,timestamp with time zone,text,boolean,bigint)'),
  ('public.request_voluntary_topup_refund(bigint)'),
  ('public.prepare_voluntary_topup_refund(uuid)'),
  ('public.reconcile_voluntary_topup_refund(uuid,text,text,text,integer,text,boolean)'),
  ('public.admin_portal_data(uuid,text,jsonb)'),
  ('public.admin_portal_bootstrap_owner(uuid,bigint[])'),
  ('public.resolve_refund_request(bigint,text,text,uuid)'),
  ('public.admin_adjust_wallet(uuid,integer,integer,integer,text)'),
  ('public.admin_record_legal_cash_redemption(uuid,integer,text,text)'),
  ('public.admin_set_wallet_status(uuid,text,text)'),
  ('private.portal_record_access(text,jsonb)'), ('private.current_account_access()')
), functions as (
  select t.signature,p.* from targets t left join pg_proc p on p.oid=to_regprocedure(t.signature)
), tables(name) as (values
  ('private.topup_refund_policy'), ('private.topup_refund_provenance'),
  ('private.topup_refund_spend'), ('private.voluntary_topup_refunds'),
  ('private.new_payment_service_control'), ('private.customer_mfa_recovery'),
  ('public.admin_audit_events'), ('public.admin_maintenance_history'), ('public.admin_invitations')
), financial(name) as (values ('public.transactions'),('public."Refunds"'))
select jsonb_build_object(
  'mail', (select jsonb_build_object('rows',count(*),'all_disabled',bool_and(enabled is false),
    'rollout_set',bool_or(rollout_at is not null),'refund_recipient_set',bool_or(refund_notice_recipient is not null))
    from private.mail_settings),
  'new_payment_control', (select jsonb_build_object('rows',count(*),'enabled',bool_and(enabled is true))
    from private.new_payment_service_control),
  'functions', (select jsonb_agg(jsonb_build_object('signature',f.signature,'exists',f.oid is not null,
    'owner',pg_get_userbyid(f.proowner),'security_definer',f.prosecdef,'settings',f.proconfig,
    'definition_md5',case when f.oid is not null then md5(pg_get_functiondef(f.oid)) end,
    'execute',(select jsonb_object_agg(r.role,case when f.oid is not null
      then has_function_privilege(r.role,f.oid,'EXECUTE') end) from api_roles r)) order by f.signature)
    from functions f),
  'financial_grants', (select jsonb_agg(jsonb_build_object('table',t.name,'role',r.role,
    'insert_table',has_table_privilege(r.role,to_regclass(t.name),'INSERT'),
    'insert_any_column',has_any_column_privilege(r.role,to_regclass(t.name),'INSERT'),
    'update',has_table_privilege(r.role,to_regclass(t.name),'UPDATE'),
    'update_any_column',has_any_column_privilege(r.role,to_regclass(t.name),'UPDATE'),
    'delete',has_table_privilege(r.role,to_regclass(t.name),'DELETE')) order by t.name,r.role)
    from financial t cross join api_roles r),
  'tables', (select jsonb_agg(jsonb_build_object('table',t.name,'exists',c.oid is not null,
    'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity) order by t.name)
    from tables t left join pg_class c on c.oid=to_regclass(t.name)),
  'policies', (select jsonb_agg(jsonb_build_object('table',p.polrelid::regclass::text,'name',p.polname,
    'restrictive',not p.polpermissive,'command',p.polcmd,'using',pg_get_expr(p.polqual,p.polrelid),
    'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname) from pg_policy p where p.polname in (
      'portal_transaction_scope','portal_maintenance_scope','portal_credit_scope','maintenance_record_scope',
      'portal_wallet_direct_self','portal_load_direct_self','portal_ledger_direct_self','portal_redemption_direct_self',
      'wallet_accounts_home_admission','wallet_loads_home_admission','wallet_ledger_home_admission','wallet_redemptions_home_admission',
      'transactions_server_insert_only','refunds_server_insert_only')),
  'triggers', (select jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,
    'enabled',t.tgenabled,'function',t.tgfoid::regprocedure::text) order by t.tgname) from pg_trigger t
    where not t.tgisinternal and t.tgname in ('location_membership_writes_guard','maintenance_writes_guard',
      'capture_topup_refund_provenance','capture_topup_refund_spend','portal_credit_resolution_scope',
      'portal_audit_immutable','portal_maintenance_history_immutable','customer_recovery_role_guard','mail_credit_decision')),
  'wallet_view', (select jsonb_build_object('security_invoker',coalesce('security_invoker=true'=any(reloptions),false))
    from pg_class where oid=to_regclass('public.wallet_balances')),
  'credit_notice_columns', (select jsonb_agg(attname order by attname) from pg_attribute
    where attrelid=to_regclass('private.mail_outbox') and attnum>0 and not attisdropped
      and attname in ('credit_refund_id','credit_resolved_at','credit_notice'))
);
