-- Schema input for authoring approved cleanup. No application rows or secrets.
begin transaction read only;
set local statement_timeout = '10s';
select jsonb_build_object(
  'foreign_keys', (select coalesce(jsonb_agg(jsonb_build_object(
    'table', c.conrelid::regclass::text,
    'referenced_table', c.confrelid::regclass::text,
    'name', c.conname, 'definition', pg_get_constraintdef(c.oid),
    'delete_action', c.confdeltype, 'update_action', c.confupdtype,
    'deferrable', c.condeferrable, 'deferred', c.condeferred,
    'validated', c.convalidated) order by c.conrelid::regclass::text,c.conname), '[]')
    from pg_constraint c where c.contype='f' and c.confrelid = any(array[
      to_regclass('auth.users'),to_regclass('public.profiles'),
      to_regclass('private.account_lifecycle'),to_regclass('private.account_cleanup_jobs'),
      to_regclass('public."Maintenance"'),to_regclass('public.wallet_accounts')])),
  'columns', (select coalesce(jsonb_agg(jsonb_build_object(
    'schema', table_schema, 'table', table_name, 'column', column_name,
    'type', data_type, 'udt', udt_name, 'nullable', is_nullable,
    'default', column_default) order by table_schema,table_name,ordinal_position), '[]')
    from information_schema.columns where
      (table_schema='public' and table_name in ('profiles','Maintenance','Refunds','transactions'))
      or (table_schema='storage' and table_name='objects')),
  'triggers', (select coalesce(jsonb_agg(jsonb_build_object(
    'table',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,
    'type_flags',t.tgtype,'internal',t.tgisinternal,'function',t.tgfoid::regprocedure::text)
    order by t.tgrelid::regclass::text,t.tgname), '[]') from pg_trigger t
    where t.tgrelid = any(array[to_regclass('auth.users'),to_regclass('public.profiles'),
      to_regclass('private.account_lifecycle'),to_regclass('private.account_cleanup_jobs')]))
) as cleanup_schema_input;
rollback;
