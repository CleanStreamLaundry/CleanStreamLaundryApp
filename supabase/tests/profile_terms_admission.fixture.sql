-- Synthetic extension only, never a production baseline or deployable file.
-- Match the observed global admin SELECT branch without widening own UPDATE.
create function public.is_admin_or_owner() returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.roles in ('Admin'::"Roles", 'Owner'::"Roles"));
$$;
revoke all on function public.is_admin_or_owner() from public, anon;
grant execute on function public.is_admin_or_owner() to authenticated;
create policy profile_admin_select on public.profiles for select to authenticated
using (public.is_admin_or_owner());

-- Existing invoker RPC shape: its table operation must acquire the new RLS.
create function public.increment_user_refund_attempts(uid uuid) returns void
language plpgsql security invoker set search_path = public as $$
begin
  update public.profiles set refund_attempts = refund_attempts + 1 where id = uid;
end;
$$;
grant execute on function public.increment_user_refund_attempts(uuid) to anon, authenticated;

-- Stand-ins prove trusted executor compatibility, not financial correctness or
-- hosted Auth trigger permissions. No wallet routines or Auth DDL are copied.
create function public.fixture_trusted_profile_sync(target uuid, name text) returns void
language sql security definer set search_path = '' as $$
  update public.profiles set full_name = name where id = target;
$$;
create function public.fixture_trusted_cache_write(target uuid, paid double precision) returns void
language sql security definer set search_path = '' as $$
  update public.profiles set balance = paid, reward_tracker = 3 where id = target;
$$;
revoke all on function public.fixture_trusted_profile_sync(uuid,text),
  public.fixture_trusted_cache_write(uuid,double precision)
  from public, anon, authenticated, supabase_auth_admin;
grant execute on function public.fixture_trusted_profile_sync(uuid,text),
  public.fixture_trusted_cache_write(uuid,double precision) to service_role;
