create table public.nayax_availability_state (
  machine_id bigint primary key references public."Machines"(id) on delete cascade,
  device_serial text,
  nayax_machine_id bigint,
  status text not null default 'unknown' check (status in ('idle','busy','unknown')),
  event_code integer,
  event_at timestamptz,
  checked_at timestamptz not null,
  reconcile_after timestamptz,
  reason text
);
create table public.nayax_availability_sync (
  location_id bigint primary key references public."Locations"(id) on delete cascade,
  lease uuid not null,
  next_check_at timestamptz not null
);
alter table public.nayax_availability_state enable row level security;
alter table public.nayax_availability_sync enable row level security;
revoke all on public.nayax_availability_state, public.nayax_availability_sync from public, anon, authenticated;
grant all on public.nayax_availability_state, public.nayax_availability_sync to service_role;

create function public.claim_nayax_availability_sync(p_location_id bigint)
returns uuid language sql security invoker set search_path = '' as $$
  insert into public.nayax_availability_sync(location_id, lease, next_check_at)
  values(p_location_id, gen_random_uuid(), now() + interval '25 seconds')
  on conflict(location_id) do update
    set lease = gen_random_uuid(), next_check_at = now() + interval '25 seconds'
    where public.nayax_availability_sync.next_check_at <= now()
  returning lease;
$$;

create function public.finish_nayax_availability_sync(p_location_id bigint, p_lease uuid, p_states jsonb)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  perform 1 from public.nayax_availability_sync
    where location_id = p_location_id and lease = p_lease and next_check_at > now() for update;
  if not found then return false; end if;
  insert into public.nayax_availability_state
    (machine_id,device_serial,nayax_machine_id,status,event_code,event_at,checked_at,reconcile_after,reason)
  select s.machine_id,s.device_serial,s.nayax_machine_id,s.status,s.event_code,s.event_at,s.checked_at,s.reconcile_after,s.reason
  from jsonb_to_recordset(p_states) as s(machine_id bigint,device_serial text,nayax_machine_id bigint,status text,event_code integer,event_at timestamptz,checked_at timestamptz,reconcile_after timestamptz,reason text)
  join public."Machines" m on m.id=s.machine_id and m."Location_ID"=p_location_id
  on conflict(machine_id) do update set
    device_serial=excluded.device_serial,nayax_machine_id=excluded.nayax_machine_id,status=excluded.status,
    event_code=excluded.event_code,event_at=excluded.event_at,checked_at=excluded.checked_at,
    reconcile_after=excluded.reconcile_after,reason=excluded.reason
  where excluded.checked_at >= public.nayax_availability_state.checked_at;
  update public.nayax_availability_sync set next_check_at=now()+interval '5 seconds'
    where location_id=p_location_id and lease=p_lease;
  return true;
end;
$$;
revoke all on function public.claim_nayax_availability_sync(bigint), public.finish_nayax_availability_sync(bigint,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.claim_nayax_availability_sync(bigint), public.finish_nayax_availability_sync(bigint,uuid,jsonb) to service_role;
