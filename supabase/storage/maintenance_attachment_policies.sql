-- NOT a normal postgres migration and NOT deployment authorization.
-- Execute only through a separately approved, supported Storage-owner path.
-- Do not change owner/membership to make this run. Bucket privacy is unchanged.
begin;
do $$
begin
  if current_user <> 'supabase_storage_admin'
    or not exists (select 1 from pg_catalog.pg_class
      where oid = 'storage.objects'::regclass and relrowsecurity
        and pg_get_userbyid(relowner) = current_user)
    or to_regprocedure('private.maintenance_attachment_allowed(uuid)') is null
    or to_regprocedure('private.maintenance_upload_allowed(text,text,timestamptz,boolean)') is null then
    raise exception 'Supported Storage-owner activation and attachment contract required'
      using errcode = '55000';
  end if;
end;
$$;

-- Restrictive predicates compose with old/future permissive policies. Other
-- buckets retain their policies; no existing policy or object is rewritten.
create policy maintenance_attachment_read_scope on storage.objects
  as restrictive for select to public using (
    bucket_id is distinct from 'maintenance-images'
    or private.maintenance_attachment_allowed(id));
create policy maintenance_attachment_read on storage.objects
  for select to authenticated using (
    bucket_id = 'maintenance-images' and private.maintenance_attachment_allowed(id));
create policy maintenance_attachment_upload_scope on storage.objects
  as restrictive for insert to public with check (
    bucket_id is distinct from 'maintenance-images'
    or private.maintenance_upload_allowed(name, owner_id, archived_at, is_delete_marker));
-- The existing upload policy remains the permissive INSERT grant. No upsert,
-- overwrite, move or delete permission is added for clients.
create policy maintenance_attachment_no_update on storage.objects
  as restrictive for update to public
  using (bucket_id is distinct from 'maintenance-images')
  with check (bucket_id is distinct from 'maintenance-images');
create policy maintenance_attachment_no_delete on storage.objects
  as restrictive for delete to public
  using (bucket_id is distinct from 'maintenance-images');
commit;
