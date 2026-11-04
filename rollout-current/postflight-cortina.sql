-- Composer only, after the exact four-source transaction on DEVELOPMENT dnuuhupoxjtwqzaqylvb.
-- Catalog/configuration only: no payment/session/event rows, secrets, function bodies or RPC execution.
with api_roles(role) as (values ('anon'), ('authenticated'), ('service_role')),
targets(signature) as (values
  ('public.guard_cortina_payment_binding()'),
  ('public.record_cortina_card_payment(uuid,text,text,text,text,integer,text,boolean)'),
  ('public.bind_cortina_callback_provider()'),
  ('public.guard_cortina_checkout_return_version()'),
  ('public.consume_cortina_request_capacity(text)'),
  ('public.request_account_deletion()'), ('public.restore_account()')
), functions as (
  select t.signature,p.* from targets t left join pg_proc p on p.oid=to_regprocedure(t.signature)
), relations(name) as (values
  ('public.cortina_vend_sessions'), ('public.cortina_vend_events'), ('private.cortina_request_capacity')
)
select jsonb_build_object(
  'columns', (select jsonb_agg(jsonb_build_object('name',a.attname,
    'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
    'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attname)
    from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid=to_regclass('public.cortina_vend_sessions') and a.attnum>0 and not a.attisdropped
      and a.attname in ('nayax_environment','nayax_terminal_id','nayax_uniqr','stripe_livemode','checkout_return_version')),
  'functions', (select jsonb_agg(jsonb_build_object('signature',f.signature,'exists',f.oid is not null,
    'owner',pg_get_userbyid(f.proowner),'security_definer',f.prosecdef,'settings',f.proconfig,
    'execute',(select jsonb_object_agg(r.role,case when f.oid is not null
      then has_function_privilege(r.role,f.oid,'EXECUTE') end) from api_roles r)) order by f.signature)
    from functions f),
  'triggers', (select jsonb_agg(jsonb_build_object('name',t.tgname,'table',t.tgrelid::regclass::text,
    'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) order by t.tgname)
    from pg_trigger t where not t.tgisinternal
      and t.tgrelid in (to_regclass('public.cortina_vend_sessions'),to_regclass('public.cortina_vend_events'))
      and t.tgname in ('guard_cortina_payment_binding','guard_cortina_checkout_return_version',
        'bind_cortina_callback_provider','cortina_transaction_history')),
  'provider_index', (select jsonb_build_object('unique',i.indisunique,'valid',i.indisvalid,
    'ready',i.indisready,'definition',pg_get_indexdef(i.indexrelid),'predicate',pg_get_expr(i.indpred,i.indrelid))
    from pg_index i where i.indexrelid=to_regclass('public.cortina_nayax_environment_transaction_key')),
  'return_constraint', (select jsonb_build_object('valid',c.convalidated,'definition',pg_get_constraintdef(c.oid))
    from pg_constraint c where c.conrelid=to_regclass('public.cortina_vend_sessions')
      and c.conname='cortina_checkout_return_version_valid'),
  'relations', (select jsonb_agg(jsonb_build_object('name',r.name,'exists',c.oid is not null,
    'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity) order by r.name)
    from relations r left join pg_class c on c.oid=to_regclass(r.name)),
  'capacity_direct_grants', (select jsonb_object_agg(r.role,jsonb_build_object(
    'select',has_table_privilege(r.role,to_regclass('private.cortina_request_capacity'),'SELECT'),
    'insert',has_table_privilege(r.role,to_regclass('private.cortina_request_capacity'),'INSERT'),
    'update',has_table_privilege(r.role,to_regclass('private.cortina_request_capacity'),'UPDATE'),
    'delete',has_table_privilege(r.role,to_regclass('private.cortina_request_capacity'),'DELETE'))) from api_roles r),
  'capacity_buckets', (select jsonb_agg(bucket order by bucket) from private.cortina_request_capacity),
  'mail', (select jsonb_build_object('rows',count(*),'all_disabled',bool_and(enabled is false),
    'rollout_set',bool_or(rollout_at is not null),'refund_recipient_set',bool_or(refund_notice_recipient is not null))
    from private.mail_settings)
);
