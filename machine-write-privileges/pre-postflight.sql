-- Same SELECT before/after this one migration. Catalog metadata only; no row reads or RPC execution.
-- Composer verifies development project dnuuhupoxjtwqzaqylvb before any remote use.
with target as (
  select * from pg_catalog.pg_class where oid=to_regclass('public."Machines"')
), api_roles(name) as (values ('anon'),('authenticated'),('service_role')),
attributes as (
  select a.* from pg_catalog.pg_attribute a join target t on t.oid=a.attrelid
  where a.attnum>0 and not a.attisdropped
), named_functions(signature) as (values
  ('public.admin_portal_request(text,jsonb)'),
  ('public.admin_portal_data(uuid,text,jsonb)'),
  ('public.admin_portal_data_before_reporting(uuid,text,jsonb)'),
  ('public.admin_portal_data_v1(uuid,text,jsonb)'),
  ('private.portal_staff_context()'),
  ('private.current_account_access()'),
  ('private.portal_capture_audit()')
), relevant_functions as (
  select to_regprocedure(signature)::oid as oid from named_functions
  union
  select g.tgfoid from pg_catalog.pg_trigger g join target t on t.oid=g.tgrelid
)
select jsonb_build_object(
  'target_present',exists(select 1 from target),
  'preserve',jsonb_build_object(
    'table',(select jsonb_build_object('name',t.oid::regclass::text,
      'owner',pg_get_userbyid(t.relowner),'kind',t.relkind,'rls',t.relrowsecurity,
      'force_rls',t.relforcerowsecurity,'persistence',t.relpersistence,
      'replica_identity',t.relreplident,'options',t.reloptions) from target t),
    'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'ordinal',a.attnum,
      'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
      'identity',a.attidentity,'generated',a.attgenerated,
      'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
      from attributes a left join pg_catalog.pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum),
    'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',c.conname,
      'definition',pg_get_constraintdef(c.oid),'validated',c.convalidated) order by c.conname),'[]')
      from pg_catalog.pg_constraint c join target t on t.oid=c.conrelid),
    'indexes',(select coalesce(jsonb_agg(jsonb_build_object('name',i.indexrelid::regclass::text,
      'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid,'ready',i.indisready)
      order by i.indexrelid::regclass::text),'[]') from pg_catalog.pg_index i join target t on t.oid=i.indrelid),
    'policies',(select coalesce(jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,
      'permissive',p.polpermissive,'roles',(select jsonb_agg(case when r=0 then 'PUBLIC'
        else pg_get_userbyid(r)::text end order by r) from unnest(p.polroles) r),
      'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
      order by p.polname),'[]') from pg_catalog.pg_policy p join target t on t.oid=p.polrelid),
    'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',g.tgname,
      'enabled',g.tgenabled,'internal',g.tgisinternal,'definition',pg_get_triggerdef(g.oid),
      'function',g.tgfoid::regprocedure::text) order by g.tgname),'[]')
      from pg_catalog.pg_trigger g join target t on t.oid=g.tgrelid),
    'functions',(select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
      'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'volatility',p.provolatile,
      'settings',p.proconfig,'definition_md5',md5(pg_get_functiondef(p.oid)),
      'acl',(select jsonb_agg(jsonb_build_object('grantor',pg_get_userbyid(a.grantor),
        'grantee',case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end,
        'privilege',a.privilege_type,'grantable',a.is_grantable) order by a.grantor,a.grantee,a.privilege_type)
        from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)) order by p.oid::regprocedure::text),'[]')
      from pg_catalog.pg_proc p join relevant_functions f on f.oid=p.oid),
    'missing_named_functions',(select coalesce(jsonb_agg(signature order by signature),'[]')
      from named_functions where to_regprocedure(signature) is null),
    'roles',(select jsonb_agg(jsonb_build_object('role',rolname,'superuser',rolsuper,
      'bypassrls',rolbypassrls,'createrole',rolcreaterole,'inherit',rolinherit) order by rolname)
      from pg_catalog.pg_roles where rolname in ('anon','authenticated','service_role')),
    'client_parents',(select coalesce(jsonb_agg(jsonb_build_object('member',pg_get_userbyid(m.member),
      'parent',pg_get_userbyid(m.roleid),'inherit',m.inherit_option,'set',m.set_option)
      order by m.member,m.roleid),'[]') from pg_catalog.pg_auth_members m
      where m.member in ('anon'::regrole,'authenticated'::regrole)),
    'unchanged_effective_table',(select jsonb_agg(jsonb_build_object('role',r.name,'privilege',p,
      'allowed',has_table_privilege(r.name,t.oid,p)) order by r.name,p)
      from api_roles r cross join target t
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
      where r.name='service_role' or p in ('SELECT','INSERT','UPDATE','DELETE')),
    'unchanged_effective_columns',(select jsonb_agg(jsonb_build_object('role',r.name,'column',a.attname,
      'privilege',p,'allowed',has_column_privilege(r.name,a.attrelid,a.attnum,p)) order by r.name,a.attnum,p)
      from api_roles r cross join attributes a cross join unnest(array['SELECT','INSERT','UPDATE','REFERENCES']) p
      where r.name='service_role' or p<>'REFERENCES'),
    'deletion_execute',(select jsonb_object_agg(r.name,case when p.oid is not null
      then has_function_privilege(r.name,p.oid,'EXECUTE') end) from api_roles r
      left join pg_catalog.pg_proc p on p.oid=to_regprocedure('public.request_account_deletion()'))
  ),
  'expected_acl_delta',jsonb_build_object(
    'effective_client_table',(select jsonb_agg(jsonb_build_object('role',r.name,'privilege',p,
      'allowed',has_table_privilege(r.name,t.oid,p)) order by r.name,p)
      from api_roles r cross join target t cross join unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
      where r.name<>'service_role'),
    'effective_client_column_references',(select jsonb_agg(jsonb_build_object('role',r.name,'column',a.attname,
      'allowed',has_column_privilege(r.name,a.attrelid,a.attnum,'REFERENCES')) order by r.name,a.attnum)
      from api_roles r cross join attributes a where r.name<>'service_role'),
    'explicit_table_acl',(select jsonb_agg(jsonb_build_object('grantor',pg_get_userbyid(a.grantor),
      'grantee',case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end,
      'privilege',a.privilege_type,'grantable',a.is_grantable) order by a.grantor,a.grantee,a.privilege_type)
      from target t cross join lateral aclexplode(coalesce(t.relacl,acldefault('r',t.relowner))) a),
    'explicit_column_acl',(select coalesce(jsonb_agg(jsonb_build_object('column',c.attname,
      'grantor',pg_get_userbyid(a.grantor),'grantee',case when a.grantee=0 then 'PUBLIC'
        else pg_get_userbyid(a.grantee)::text end,'privilege',a.privilege_type,'grantable',a.is_grantable)
      order by c.attnum,a.grantor,a.grantee,a.privilege_type),'[]')
      from attributes c cross join lateral aclexplode(c.attacl) a)
  )
) as machines_maintenance_privileges_catalog;
