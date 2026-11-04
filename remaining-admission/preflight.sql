-- Catalog only. Composer verifies linked development dnuuhupoxjtwqzaqylvb.
-- No customer rows, authority RPC execution, DDL or DML.
with target as (
  select c.* from pg_catalog.pg_class c
  where c.oid=to_regclass('public."Location_to_Admin"')
), policies as (
  select p.* from pg_catalog.pg_policy p join target t on t.oid=p.polrelid
), api_roles(name) as (values ('anon'),('authenticated'),('service_role'))
select jsonb_build_object(
  'table',(select jsonb_build_object('owner',pg_get_userbyid(relowner),
    'rls',relrowsecurity,'force_rls',relforcerowsecurity,'acl',relacl) from target),
  'select_grants',(select jsonb_agg(jsonb_build_object('role',r.name,
    'table',has_table_privilege(r.name,t.oid,'SELECT'),
    'columns',(select jsonb_object_agg(a.attname,has_column_privilege(r.name,t.oid,a.attnum,'SELECT'))
      from pg_catalog.pg_attribute a where a.attrelid=t.oid and a.attnum>0 and not a.attisdropped))
    order by r.name) from target t cross join api_roles r),
  'policies',(select jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,
    'permissive',p.polpermissive,'roles',(select jsonb_agg(case when id=0 then 'PUBLIC'
      else pg_get_userbyid(id) end order by id) from unnest(p.polroles) id),
    'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
    order by p.polname) from policies p),
  'anonymous_public_read',exists(select 1 from policies p where p.polcmd in ('r','*')
    and p.polpermissive and (0::oid=any(p.polroles) or 'anon'::regrole::oid=any(p.polroles))
    and pg_get_expr(p.polqual,p.polrelid)='true'),
  'authenticated_canonical_restriction',exists(select 1 from policies p
    where p.polname='portal_membership_direct_self' and p.polcmd='r' and not p.polpermissive
      and p.polroles=array['authenticated'::regrole::oid]),
  'new_guard_absent',not exists(select 1 from policies where polname='portal_membership_no_anon'),
  'helpers',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
    'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'settings',p.proconfig,
    'source_md5',md5(p.prosrc),'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
    'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')) order by p.oid)
    from pg_catalog.pg_proc p where p.oid in (to_regprocedure('public.is_admin_or_owner()'),
      to_regprocedure('private.current_account_access()'))),
  'deletion_execute',(select jsonb_object_agg(r.name,case when p.oid is not null
    then has_function_privilege(r.name,p.oid,'EXECUTE') end) from api_roles r
    left join pg_catalog.pg_proc p on p.oid=to_regprocedure('public.request_account_deletion()'))
) as membership_read_preflight;
