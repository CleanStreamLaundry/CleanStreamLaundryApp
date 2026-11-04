-- Read configuration and authorization metadata only; never customer records.
select jsonb_build_object(
  'policy', (select jsonb_build_object('version', d->>'required_version', 'sha256', d->>'policy_sha256')
    from (select public.get_loyalty_policy_descriptor() d) x),
  'mail', (select jsonb_build_object('enabled', enabled, 'rollout_set', rollout_at is not null,
    'refund_recipient_set', refund_notice_recipient is not null) from private.mail_settings),
  'deletion_execute', (select jsonb_object_agg(role, has_function_privilege(role,
    'public.request_account_deletion()', 'EXECUTE'))
    from (values ('anon'), ('authenticated'), ('service_role')) r(role)),
  'restore_execute', (select jsonb_object_agg(role, has_function_privilege(role,
    'public.restore_account()', 'EXECUTE'))
    from (values ('anon'), ('authenticated'), ('service_role')) r(role)),
  'protected_profile_writes', (select jsonb_agg(jsonb_build_object('role', role, 'column', col,
    'insert', has_column_privilege(role, 'public.profiles', col, 'INSERT'),
    'update', has_column_privilege(role, 'public.profiles', col, 'UPDATE')) order by role, col)
    from (values ('anon'), ('authenticated')) r(role)
    cross join (values ('roles'), ('balance'), ('reward_tracker'),
      ('loyalty_policy_version'), ('loyalty_policy_accepted_at')) c(col)),
  'enabled_triggers', (select jsonb_agg(tgname order by tgname) from pg_trigger
    where not tgisinternal and tgenabled='O' and tgname in
      ('profiles_protected_fields_guard','profiles_policy_acceptance_guard',
       'mail_verified_account','mail_identity_changed','mail_account_suppression')),
  'private_tables', (select jsonb_agg(jsonb_build_object('table',c.relname,'rls',c.relrowsecurity)
    order by c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind='r')
);
