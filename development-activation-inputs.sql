begin read only;
set local statement_timeout='10s';
select jsonb_build_object(
  'deletion_request_available',has_function_privilege('authenticated','public.request_account_deletion()','execute'),
  'mail_settings',(select to_jsonb(s)-'consent_text' from private.mail_settings s where singleton),
  'payment_routing',(select coalesce(jsonb_agg(r),'[]'::jsonb) from (
    select environment,count(*) as machines from public.cortina_machine_config group by environment
  ) r),
  'reconciliation_routes',(select coalesce(jsonb_agg(r),'[]'::jsonb) from (
    select nayax_environment,stripe_livemode,count(*) as sessions
    from public.cortina_vend_sessions group by nayax_environment,stripe_livemode
  ) r),
  'reconciliation_job',(select coalesce(jsonb_agg(jsonb_build_object('name',jobname,'active',active)),'[]'::jsonb)
    from cron.job where jobname='cleanstream-cortina-reconcile')
) as development_activation;
rollback;
