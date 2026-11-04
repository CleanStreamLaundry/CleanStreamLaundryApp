begin;

do $$ declare columns_list text; service_before boolean[]; service_after boolean[]; begin
  if not exists(select 1 from pg_catalog.pg_class where oid='public."Machines"'::regclass
    and relkind='r' and relrowsecurity and relowner='postgres'::regrole) then
    raise exception 'Reviewed Machines owner and RLS required' using errcode='55000';
  end if;
  if exists(select 1 from pg_catalog.pg_roles where rolname in ('anon','authenticated')
      and (rolsuper or rolbypassrls or rolcreaterole))
    or exists(select 1 from pg_catalog.pg_auth_members
      where member in ('anon'::regrole::oid,'authenticated'::regrole::oid)) then
    raise exception 'Client role authority or inheritance requires review' using errcode='42501';
  end if;
  select array(select has_table_privilege('service_role','public."Machines"',p)
    from unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p order by p)
    || array(select has_column_privilege('service_role',attrelid,attnum,'REFERENCES')
      from pg_catalog.pg_attribute where attrelid='public."Machines"'::regclass
        and attnum>0 and not attisdropped order by attnum) into service_before;

  -- RESTRICT refuses dependent grant chains; never cascade into another role.
  revoke truncate,references,trigger,maintain on public."Machines" from public,anon,authenticated restrict;
  select string_agg(quote_ident(attname),',' order by attnum) into columns_list
    from pg_catalog.pg_attribute where attrelid='public."Machines"'::regclass
      and attnum>0 and not attisdropped;
  execute format('revoke references (%s) on public."Machines" from public,anon,authenticated restrict',columns_list);

  if exists(select 1 from (values ('anon'),('authenticated')) r(name)
      cross join unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
      where has_table_privilege(r.name,'public."Machines"',p))
    or exists(select 1 from pg_catalog.pg_attribute a
      cross join (values ('anon'),('authenticated')) r(name)
      where a.attrelid='public."Machines"'::regclass and a.attnum>0 and not a.attisdropped
        and has_column_privilege(r.name,a.attrelid,a.attnum,'REFERENCES')) then
    raise exception 'Unexpected effective Machines maintenance grants' using errcode='42501';
  end if;
  select array(select has_table_privilege('service_role','public."Machines"',p)
    from unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p order by p)
    || array(select has_column_privilege('service_role',attrelid,attnum,'REFERENCES')
      from pg_catalog.pg_attribute where attrelid='public."Machines"'::regclass
        and attnum>0 and not attisdropped order by attnum) into service_after;
  if service_after is distinct from service_before then
    raise exception 'Trusted Machines privileges would change' using errcode='42501';
  end if;
end $$;

commit;
