begin;

do $$ declare
  table_name text; target regclass; columns_list text;
  service_before boolean[]; service_after boolean[];
begin
  if exists(select 1 from pg_catalog.pg_roles where rolname in ('anon','authenticated')
      and (rolsuper or rolbypassrls or rolcreaterole))
    or exists(select 1 from pg_catalog.pg_auth_members
      where member in ('anon'::regrole::oid,'authenticated'::regrole::oid)) then
    raise exception 'Client role authority or inheritance requires review' using errcode='42501';
  end if;

  -- Fixed reviewed inventory tables only; Machines is deliberately excluded.
  foreach table_name in array array['Locations','washer_size_rates','cortina_machine_config'] loop
    target:=to_regclass(format('public.%I',table_name));
    if not exists(select 1 from pg_catalog.pg_class where oid=target
      and relkind='r' and relrowsecurity and relowner='postgres'::regrole) then
      raise exception 'Reviewed inventory owner and RLS required: %',table_name using errcode='55000';
    end if;
    select array(select has_table_privilege('service_role',target,p)
      from unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p order by p)
      || array(select has_column_privilege('service_role',attrelid,attnum,'REFERENCES')
        from pg_catalog.pg_attribute where attrelid=target
          and attnum>0 and not attisdropped order by attnum) into service_before;

    -- Refuse dependent grant chains rather than changing another role's grants.
    execute format('revoke truncate,references,trigger,maintain on public.%I from public,anon,authenticated restrict',table_name);
    select string_agg(quote_ident(attname),',' order by attnum) into columns_list
      from pg_catalog.pg_attribute where attrelid=target and attnum>0 and not attisdropped;
    execute format('revoke references (%s) on public.%I from public,anon,authenticated restrict',columns_list,table_name);

    if exists(select 1 from (values ('anon'),('authenticated')) r(name)
        cross join unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
        where has_table_privilege(r.name,target,p))
      or exists(select 1 from pg_catalog.pg_attribute a
        cross join (values ('anon'),('authenticated')) r(name)
        where a.attrelid=target and a.attnum>0 and not a.attisdropped
          and has_column_privilege(r.name,a.attrelid,a.attnum,'REFERENCES')) then
      raise exception 'Unexpected effective inventory maintenance grants: %',table_name using errcode='42501';
    end if;
    select array(select has_table_privilege('service_role',target,p)
      from unnest(array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p order by p)
      || array(select has_column_privilege('service_role',attrelid,attnum,'REFERENCES')
        from pg_catalog.pg_attribute where attrelid=target
          and attnum>0 and not attisdropped order by attnum) into service_after;
    if service_after is distinct from service_before then
      raise exception 'Trusted inventory privileges would change: %',table_name using errcode='42501';
    end if;
  end loop;
end $$;

commit;
