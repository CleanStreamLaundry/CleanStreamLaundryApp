begin;

do $$ begin
  if not exists(select 1 from pg_catalog.pg_class where oid='public."Machines"'::regclass
    and relkind='r' and relrowsecurity)
    or (select count(*) from pg_catalog.pg_attribute where attrelid='public."Machines"'::regclass
      and attnum>0 and not attisdropped and attname in ('id','Name','Price','Runtime','Status',
        'Location_ID','Machine_type','Weight_kg','washer_size_rate_id','is_out_of_service',
        'service_updated_at','service_reason','service_updated_by'))<>13 then
    raise exception 'Reviewed machine inventory schema required' using errcode='55000';
  end if;
  if exists(select 1 from pg_catalog.pg_roles where rolname in ('anon','authenticated')
      and (rolsuper or rolbypassrls or rolcreaterole))
    or exists(select 1 from pg_catalog.pg_auth_members
      where member in ('anon'::regrole::oid,'authenticated'::regrole::oid)) then
    raise exception 'Client role authority or inheritance requires review' using errcode='42501';
  end if;
end $$;

-- A column REVOKE alone cannot override table-wide or inherited PUBLIC SELECT.
revoke select on public."Machines" from public,anon,authenticated restrict;
do $$ declare columns_list text; begin
  select string_agg(quote_ident(attname),',' order by attnum) into columns_list
    from pg_catalog.pg_attribute where attrelid='public."Machines"'::regclass
      and attnum>0 and not attisdropped;
  execute format('revoke select (%s) on public."Machines" from public,anon,authenticated restrict',columns_list);
end $$;
grant select (id,"Name","Price","Runtime","Status","Location_ID","Machine_type","Weight_kg",
  washer_size_rate_id,is_out_of_service,service_updated_at) on public."Machines" to anon,authenticated;

do $$ begin
  if exists(select 1 from (values ('anon'),('authenticated')) r(name)
    where has_table_privilege(r.name,'public."Machines"','SELECT'))
    or exists(select 1 from pg_catalog.pg_attribute a
      cross join (values ('anon'),('authenticated')) r(name)
      where a.attrelid='public."Machines"'::regclass and a.attnum>0 and not a.attisdropped
        and has_column_privilege(r.name,a.attrelid,a.attnum,'SELECT') is distinct from
          (a.attname in ('id','Name','Price','Runtime','Status','Location_ID','Machine_type',
            'Weight_kg','washer_size_rate_id','is_out_of_service','service_updated_at'))) then
    raise exception 'Unexpected effective machine read grants require review' using errcode='42501';
  end if;
end $$;

commit;
