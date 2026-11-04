begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $$
begin
  if current_user <> 'postgres' then raise exception 'Trusted operator required'; end if;
  if (select count(*) from storage.buckets where id='maintenance-images') <> 1 then
    raise exception 'Expected maintenance attachment bucket unavailable';
  end if;
  if to_regprocedure('private.maintenance_attachment_allowed(uuid)') is null then
    raise exception 'Installed authorized attachment contract required';
  end if;
end $$;
update storage.buckets set public=false
  where id='maintenance-images' and public is distinct from false
  returning id, public;
commit;
