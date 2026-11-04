-- Metadata only; Composer verifies linked development dnuuhupoxjtwqzaqylvb.
with target as (
  select * from pg_catalog.pg_class where oid=to_regclass('public."Machines"')
), api_roles(name) as (values ('anon'),('authenticated'),('service_role'))
select jsonb_build_object(
  'table',(select jsonb_build_object('owner',pg_get_userbyid(relowner),
    'rls',relrowsecurity,'force_rls',relforcerowsecurity,'acl',relacl) from target),
  'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,
    'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl,
    'select',(select jsonb_object_agg(r.name,has_column_privilege(r.name,a.attrelid,a.attnum,'SELECT'))
      from api_roles r)) order by a.attnum)
    from pg_catalog.pg_attribute a join target t on t.oid=a.attrelid where a.attnum>0 and not a.attisdropped),
  'table_grants',(select jsonb_object_agg(r.name,jsonb_build_object(
    'select',has_table_privilege(r.name,t.oid,'SELECT'),
    'insert',has_table_privilege(r.name,t.oid,'INSERT'),
    'update',has_table_privilege(r.name,t.oid,'UPDATE'),
    'delete',has_table_privilege(r.name,t.oid,'DELETE'))) from api_roles r cross join target t),
  'client_roles',(select jsonb_agg(jsonb_build_object('role',rolname,'superuser',rolsuper,
    'bypassrls',rolbypassrls,'createrole',rolcreaterole) order by rolname)
    from pg_catalog.pg_roles where rolname in ('anon','authenticated')),
  'client_parents',(select coalesce(jsonb_agg(jsonb_build_object('member',pg_get_userbyid(m.member),
    'parent',pg_get_userbyid(m.roleid),'inherit',m.inherit_option,'set',m.set_option)), '[]')
    from pg_catalog.pg_auth_members m where m.member in ('anon'::regrole,'authenticated'::regrole)),
  'policies',(select jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,
    'permissive',p.polpermissive,'roles',p.polroles,'using',pg_get_expr(p.polqual,p.polrelid),
    'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname)
    from pg_catalog.pg_policy p join target t on t.oid=p.polrelid),
  'public_columns',jsonb_build_array('id','Name','Price','Runtime','Status','Location_ID',
    'Machine_type','Weight_kg','washer_size_rate_id','is_out_of_service','service_updated_at'),
  'private_columns',jsonb_build_array('service_reason','service_updated_by'),
  'deletion_execute',(select jsonb_object_agg(r.name,case when p.oid is not null
    then has_function_privilege(r.name,p.oid,'EXECUTE') end) from api_roles r
    left join pg_catalog.pg_proc p on p.oid=to_regprocedure('public.request_account_deletion()'))
) as machine_columns_preflight;
