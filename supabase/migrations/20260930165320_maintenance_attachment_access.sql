-- Additive contract only. Storage policies have a different owner; see
-- supabase/storage/maintenance_attachment_policies.sql. No bucket/object writes.
begin;

do $$
begin
  if current_user <> 'postgres'
    or to_regprocedure('private.maintenance_record_access(uuid,bigint)') is null
    or to_regclass('private.account_lifecycle') is null
    or not exists (select 1 from pg_catalog.pg_class
      where oid = 'storage.objects'::regclass and relrowsecurity)
    or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public."Location_to_Admin"'::regclass
        and tgname = 'location_membership_writes_guard' and tgenabled = 'A') then
    raise exception 'Reviewed maintenance, lifecycle and Storage prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

-- The Storage service supplies owner_id from the verified JWT. Keep existing
-- safe names (including requests/<filename>); do not repath historical objects.
create function private.maintenance_upload_allowed(
  p_name text, p_owner_id text, p_archived_at timestamptz, p_delete_marker boolean
)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null or p_owner_id is distinct from auth.uid()::text
    or p_archived_at is not null or p_delete_marker is distinct from false
    or p_name is null or octet_length(p_name) not between 1 and 2048
    or p_name ~ '(^/|/$|//|\\|[[:cntrl:]])'
    or exists (select 1 from unnest(string_to_array(p_name, '/')) part
      where part in ('.', '..')) then
    return false;
  end if;
  return private.account_access_allowed();
exception when sqlstate 'PT401' then return false;
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;

-- Exact current metadata and report ownership bind the object to the existing
-- report ACL. Never authorize a legacy URL or a replacement at the same name.
create function private.maintenance_attachment_allowed(p_object_id uuid)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare
  object_row storage.objects%rowtype;
begin
  if auth.uid() is null or not private.account_access_allowed() then return false; end if;
  select * into object_row from storage.objects where id = p_object_id;
  if not found or object_row.bucket_id is distinct from 'maintenance-images'
    or object_row.owner_id is null or object_row.name is null
    or object_row.archived_at is not null or object_row.is_delete_marker is distinct from false
    or (select count(*) from storage.objects o
      where o.bucket_id = object_row.bucket_id and o.name = object_row.name
        and o.archived_at is null and not o.is_delete_marker) <> 1 then
    return false;
  end if;
  return exists (select 1 from public."Maintenance" m
    where m.user_id::text = object_row.owner_id
      and m.attachment_ref = jsonb_build_object('bucket', object_row.bucket_id,
        'id', object_row.id, 'name', object_row.name, 'version', object_row.version)
      and private.maintenance_record_access(m.user_id, m.location_id));
exception when sqlstate 'PT401' then return false;
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;

-- Caller-bearer RPC: a descriptor, never a public/signed URL or service-key read.
-- Full bigint IDs stay text across JavaScript/Flutter-web boundaries.
create function public.get_maintenance_attachment(p_maint_id text)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  report public."Maintenance"%rowtype;
  object_id uuid;
begin
  if not private.account_access_allowed() then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;
  if p_maint_id is null or p_maint_id !~ '^[1-9][0-9]{0,18}$'
  then
    raise exception 'invalid_request' using errcode = 'PT400';
  end if;
  if p_maint_id::numeric > 9223372036854775807 then
    raise exception 'invalid_request' using errcode = 'PT400';
  end if;
  select * into report from public."Maintenance" where maint_id = p_maint_id::bigint;
  if not found or not private.maintenance_record_access(report.user_id, report.location_id)
    or jsonb_typeof(report.attachment_ref) is distinct from 'object' then
    raise exception 'attachment_unavailable' using errcode = 'PT404';
  end if;
  -- Comparing as text rejects malformed references without casting caller data.
  select o.id into object_id from storage.objects o
    where o.id::text = report.attachment_ref->>'id'
      and o.owner_id = report.user_id::text
      and report.attachment_ref = jsonb_build_object('bucket', o.bucket_id,
        'id', o.id, 'name', o.name, 'version', o.version);
  if object_id is null or not private.maintenance_attachment_allowed(object_id) then
    raise exception 'attachment_unavailable' using errcode = 'PT404';
  end if;
  return jsonb_build_object('maint_id', p_maint_id, 'attachment', report.attachment_ref);
exception
  when sqlstate 'PT400' or sqlstate 'PT401' or sqlstate 'PT403' or sqlstate 'PT404' then raise;
  when others then raise exception 'maintenance_unavailable' using errcode = 'PT503';
end;
$$;

revoke all on function private.maintenance_upload_allowed(text,text,timestamptz,boolean),
  private.maintenance_attachment_allowed(uuid), public.get_maintenance_attachment(text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
-- Private predicates are callable by policies, not exposed as Data API RPCs.
grant execute on function private.maintenance_upload_allowed(text,text,timestamptz,boolean),
  private.maintenance_attachment_allowed(uuid) to anon, authenticated, supabase_storage_admin;
grant usage on schema private to supabase_storage_admin;
grant execute on function public.get_maintenance_attachment(text) to authenticated;
commit;
