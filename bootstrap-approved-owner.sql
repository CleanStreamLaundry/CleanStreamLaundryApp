begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $$
declare target uuid; prior_role text;
begin
  if current_user <> 'postgres' then raise exception 'Trusted operator required'; end if;
  perform pg_advisory_xact_lock(814716290);
  if (select count(*) from auth.users where lower(email)='jake@cleanstreamlaundry.com') <> 1 then
    raise exception 'The explicitly approved existing Auth account is missing or ambiguous';
  end if;
  select id into strict target from auth.users
    where lower(email)='jake@cleanstreamlaundry.com'
      and deleted_at is null and coalesce(is_anonymous,false)=false
      and (banned_until is null or banned_until<=clock_timestamp()) for update;
  if exists(select 1 from private.account_lifecycle where user_id=target and restored_at is null) then
    raise exception 'Approved account has a pending deletion';
  end if;
  select roles::text into prior_role from public.profiles where id=target for update;
  perform public.admin_portal_bootstrap_owner(target, '{}'::bigint[]);
  if prior_role is distinct from 'Owner' then
    insert into public.admin_audit_events(actor_id,actor_name,entity,entity_id,operation,before_values,after_values)
    values(null,'Approved development operator','owner_bootstrap',target::text,'bootstrap',
      jsonb_build_object('role',prior_role),
      jsonb_build_object('role','Owner','authorization','User approved jake@cleanstreamlaundry.com on 2026-10-01'));
  end if;
end $$;
commit;
