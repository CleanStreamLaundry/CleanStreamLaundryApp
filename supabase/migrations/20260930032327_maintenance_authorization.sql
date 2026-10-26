-- LOCAL ONLY: coordinated readers, trusted roles/memberships, approved admission
-- foundations and separate Storage/admin reconciliation are release gates.
begin;

do $$
declare
  location_column smallint;
begin
  if current_user <> 'postgres' or not exists (
    select 1 from pg_catalog.pg_class where oid = 'public."Maintenance"'::regclass
      and relkind = 'r' and relrowsecurity and not relforcerowsecurity
      and pg_get_userbyid(relowner) = 'postgres'
  ) or to_regprocedure('private.account_access_allowed()') is null
    or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public.profiles'::regclass
        and tgname = 'profiles_protected_fields_guard' and tgenabled in ('O','A')
        and tgfoid = to_regprocedure('public.guard_profile_protected_fields()'))
    or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public."Location_to_Admin"'::regclass
        and tgname = 'location_membership_writes_guard' and tgenabled = 'A'
        and tgfoid = to_regprocedure('public.guard_location_membership_writes()')) then
    raise exception 'Reviewed maintenance authority prerequisites required' using errcode = '55000';
  end if;
  if exists (select 1 from pg_catalog.pg_roles
      where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls or rolcreaterole))
    or exists (select 1 from pg_catalog.pg_auth_members m
      join pg_catalog.pg_roles r on r.oid = m.member
      where r.rolname in ('anon','authenticated')) then
    raise exception 'Client authority or inheritance requires review' using errcode = '42501';
  end if;

  -- The unshipped portal may already declare this column, but never infer its
  -- correctness from IF NOT EXISTS, nor infer report attribution from an address.
  select attnum into location_column from pg_catalog.pg_attribute
    where attrelid = 'public."Maintenance"'::regclass and attname = 'location_id' and not attisdropped;
  if found then
    if not exists (select 1 from pg_catalog.pg_attribute
        where attrelid = 'public."Maintenance"'::regclass and attnum = location_column
          and atttypid = 'bigint'::regtype and not attnotnull and not atthasdef
          and attidentity = '' and attgenerated = '')
      or (select count(*) from pg_catalog.pg_constraint
        where conrelid = 'public."Maintenance"'::regclass and contype = 'f'
          and location_column = any(conkey)) <> 1
      or not exists (select 1 from pg_catalog.pg_constraint
        where conrelid = 'public."Maintenance"'::regclass and contype = 'f'
          and conkey = array[location_column] and confrelid = 'public."Locations"'::regclass
          and confkey = array[(select attnum from pg_catalog.pg_attribute
            where attrelid = 'public."Locations"'::regclass and attname = 'id')]
          and confupdtype = 'a' and confdeltype = 'a' and confmatchtype = 's'
          and convalidated and not condeferrable) then
      raise exception 'Existing maintenance location definition requires review' using errcode = '55000';
    end if;
  else
    alter table public."Maintenance" add column location_id bigint references public."Locations"(id);
  end if;
end;
$$;

alter table public."Maintenance" add column attachment_ref jsonb;

revoke insert, update, delete, truncate, references, trigger, maintain
  on public."Maintenance" from public, anon, authenticated restrict;
do $$
declare columns_list text;
begin
  select string_agg(format('%I',attname), ', ' order by attnum) into columns_list
    from pg_catalog.pg_attribute where attrelid = 'public."Maintenance"'::regclass
      and attnum > 0 and not attisdropped;
  execute format('revoke insert (%1$s), update (%1$s), references (%1$s) on public."Maintenance" from public, anon, authenticated restrict', columns_list);
  if exists (select 1 from (values ('anon'),('authenticated')) r(name)
      cross join (values ('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) p(privilege)
      where has_table_privilege(r.name,'public."Maintenance"',p.privilege))
    or exists (select 1 from (values ('anon'),('authenticated')) r(name)
      cross join (values ('INSERT'),('UPDATE'),('REFERENCES')) p(privilege)
      where has_any_column_privilege(r.name,'public."Maintenance"',p.privilege)) then
    raise exception 'Remaining effective maintenance writes require review' using errcode = '42501';
  end if;
end;
$$;

create function public.guard_maintenance_writes()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') then
    raise exception 'Maintenance writes require a trusted server writer' using errcode = '42501';
  end if;
  return null;
end;
$$;
create trigger maintenance_writes_guard
before insert or update or delete or truncate on public."Maintenance"
for each statement execute function public.guard_maintenance_writes();
alter table public."Maintenance" enable always trigger maintenance_writes_guard;
revoke all on function public.guard_maintenance_writes() from public, anon, authenticated, service_role;

create function private.maintenance_record_access(report_user_id uuid, report_location_id bigint)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid; caller_role public."Roles";
begin
  if not private.account_access_allowed() then return false; end if;
  caller_id := auth.uid();
  if report_user_id = caller_id then return true; end if;
  select roles into caller_role from public.profiles where id = caller_id;
  return coalesce((caller_role = 'Owner' and report_location_id is null)
    or (caller_role in ('Admin','Owner') and report_location_id is not null and exists (
      select 1 from public."Location_to_Admin" m
      where m.user_id = caller_id and m.location_id = report_location_id
    )), false);
exception
  when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;
revoke all on function private.maintenance_record_access(uuid,bigint) from public, anon, authenticated, service_role;
grant execute on function private.maintenance_record_access(uuid,bigint) to authenticated;
create policy maintenance_record_scope on public."Maintenance"
as restrictive for select to authenticated
using (private.maintenance_record_access(user_id,location_id));

create function public.submit_maintenance_request(p_request jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  caller_id uuid;
  report public."Maintenance"%rowtype;
  target_location bigint;
  attachment_name text;
  attachment jsonb;
  object_count bigint;
  field_name text;
  field_limit integer;
  field_value text;
  utf16_length integer;
begin
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  caller_id := auth.uid();
  perform 1 from auth.users where id = caller_id for share;
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  if jsonb_typeof(p_request) is distinct from 'object' then
    raise exception 'invalid_request' using errcode = 'PT400';
  end if;
  if p_request ? 'user_id' then
    if jsonb_typeof(p_request->'user_id') is distinct from 'string'
      or (p_request->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    if (p_request->>'user_id')::uuid <> caller_id then
      raise exception 'user_mismatch' using errcode = 'PT403';
    end if;
  end if;
  -- Match JavaScript string limits and trim whitespace without changing text.
  for field_name, field_limit in values ('category',64),('description',4000),('location',1000) loop
    field_value := p_request->>field_name;
    if jsonb_typeof(p_request->field_name) is distinct from 'string'
      or length(field_value) > field_limit
      or btrim(field_value, E' \t\n\r\f' || chr(11) || chr(160) || chr(5760) ||
        chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||
        chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279)) = '' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    select coalesce(sum(case when ascii(c) > 65535 then 2 else 1 end),0)
      into utf16_length from regexp_split_to_table(field_value,'') c;
    if utf16_length > field_limit then raise exception 'invalid_request' using errcode = 'PT400'; end if;
  end loop;
  if p_request->>'category' not in ('Other','Washer/Dryer Maintenance','App Maintenance','Location Maintenance')
    or coalesce(p_request->'image','null'::jsonb) <> 'null'::jsonb then
    raise exception 'invalid_request' using errcode = 'PT400';
  end if;
  if coalesce(p_request->'location_id','null'::jsonb) <> 'null'::jsonb then
    if jsonb_typeof(p_request->'location_id') <> 'string'
      or (p_request->>'location_id') !~ '^[1-9][0-9]{0,18}$' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    if (p_request->>'location_id')::numeric > 9223372036854775807 then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    target_location := (p_request->>'location_id')::bigint;
    if not exists (select 1 from public."Locations" where id = target_location) then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
  end if;
  if coalesce(p_request->'attachment','null'::jsonb) <> 'null'::jsonb then
    if jsonb_typeof(p_request->'attachment') <> 'object'
      or ((p_request->'attachment') - 'name') <> '{}'::jsonb
      or jsonb_typeof(p_request->'attachment'->'name') is distinct from 'string' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    attachment_name := p_request->'attachment'->>'name';
    if length(attachment_name) = 0 or octet_length(attachment_name) > 2048
      or attachment_name ~ '(^/|/$|//|\\|[[:cntrl:]]|(^|/)\.\.?(/|$))' then
      raise exception 'invalid_request' using errcode = 'PT400';
    end if;
    select count(*), (jsonb_agg(jsonb_build_object('bucket','maintenance-images',
      'id',o.id,'name',o.name,'version',o.version)) filter (where o.owner_id = caller_id::text))->0
      into object_count, attachment
    from storage.objects o where o.bucket_id = 'maintenance-images' and o.name = attachment_name
      and o.archived_at is null and not o.is_delete_marker;
    if object_count <> 1 or attachment is null then raise exception 'invalid_request' using errcode = 'PT400'; end if;
  end if;

  -- Storage is read-only metadata; no service insertion fallback or URL fetch.
  begin
    insert into public."Maintenance"(user_id,category,description,location,created_at,location_id,attachment_ref,image_data)
    values(caller_id,p_request->>'category',p_request->>'description',p_request->>'location',
      clock_timestamp(),target_location,attachment,null) returning * into report;
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    if attachment is not null and not exists (
      select 1 from storage.objects o where o.id = (attachment->>'id')::uuid
        and o.bucket_id = 'maintenance-images' and o.name = attachment_name
        and o.version is not distinct from attachment->>'version'
        and o.archived_at is null and not o.is_delete_marker and o.owner_id = caller_id::text
    ) then raise exception 'invalid_request' using errcode = 'PT400'; end if;
    return jsonb_build_object('success',true,'message','Request logged','record',jsonb_build_array(to_jsonb(report)));
  exception
    when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
    when sqlstate 'PT403' then raise exception 'account_restricted' using errcode = 'PT403';
    when sqlstate 'PT400' then raise exception 'invalid_request' using errcode = 'PT400';
    when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
  end;
exception
  when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
  when sqlstate 'PT403' then
    if sqlerrm = 'user_mismatch' then raise exception 'user_mismatch' using errcode = 'PT403'; end if;
    raise exception 'account_restricted' using errcode = 'PT403';
  when sqlstate 'PT400' then raise exception 'invalid_request' using errcode = 'PT400';
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;
revoke all on function public.submit_maintenance_request(jsonb) from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.submit_maintenance_request(jsonb) to authenticated;

commit;
