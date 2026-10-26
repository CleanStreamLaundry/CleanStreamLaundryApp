-- Exercise the deployed cache controls without retaining fixture changes.
begin;
do $$
declare token uuid; result boolean;
begin
  if has_table_privilege('authenticated','public.nayax_availability_state','select')
     or has_table_privilege('anon','public.nayax_availability_state','select')
     or has_function_privilege('authenticated','public.claim_nayax_availability_sync(bigint)','execute')
     or has_function_privilege('anon','public.finish_nayax_availability_sync(bigint,uuid,jsonb)','execute') then
    raise exception 'Private availability cache is exposed';
  end if;
  if (select count(*) from pg_class where oid in ('public.nayax_availability_state'::regclass,'public.nayax_availability_sync'::regclass) and relrowsecurity) <> 2 then
    raise exception 'RLS must be enabled';
  end if;
  delete from public.nayax_availability_sync where location_id=1;
  token := public.claim_nayax_availability_sync(1);
  if token is null or public.claim_nayax_availability_sync(1) is not null then
    raise exception 'Concurrent polls were not throttled';
  end if;
  result := public.finish_nayax_availability_sync(1,gen_random_uuid(),'[]');
  if result then raise exception 'Wrong lease accepted'; end if;
  result := public.finish_nayax_availability_sync(1,token,'[]');
  if not result or public.claim_nayax_availability_sync(1) is not null then
    raise exception 'Completion throttle failed';
  end if;
end $$;
rollback;
select 'availability permissions, RLS, and concurrent poll controls passed' as verification;
