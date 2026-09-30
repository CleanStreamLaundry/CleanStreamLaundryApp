begin;

-- Table grants override column revocations. Preserve existing nonprotected
-- access without granting clients access to future profile columns.
do $$
declare
  saved_grants jsonb;
  saved_grant jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb) into saved_grants
  from (
    select r.rolname as grantee, p.privilege,
      string_agg(format('%I', a.attname), ', ' order by a.attnum) as columns
    from pg_catalog.pg_roles r
    cross join (values ('INSERT'), ('UPDATE')) as p(privilege)
    join pg_catalog.pg_attribute a on a.attrelid = 'public.profiles'::regclass
      and a.attnum > 0 and not a.attisdropped
    where r.rolname in ('anon', 'authenticated', 'service_role', 'supabase_auth_admin')
      and (r.rolname in ('service_role', 'supabase_auth_admin')
        or a.attname not in ('roles', 'balance', 'reward_tracker'))
      and has_column_privilege(r.oid, a.attrelid, a.attnum, p.privilege)
    group by r.rolname, p.privilege
  ) g;

  revoke insert, update on public.profiles from public, anon, authenticated;
  revoke insert (roles, balance, reward_tracker),
    update (roles, balance, reward_tracker)
    on public.profiles from public, anon, authenticated;

  for saved_grant in select value from jsonb_array_elements(saved_grants) loop
    execute format('grant %s (%s) on public.profiles to %I',
      saved_grant->>'privilege', saved_grant->>'columns', saved_grant->>'grantee');
  end loop;

  if exists (
    select 1
    from (values ('anon'), ('authenticated')) r(grantee)
    cross join (values ('INSERT'), ('UPDATE')) p(privilege)
    cross join (values ('roles'), ('balance'), ('reward_tracker')) c(column_name)
    where has_column_privilege(r.grantee, 'public.profiles', c.column_name, p.privilege)
  ) then
    raise exception 'Inherited profile write privileges require review'
      using errcode = '42501';
  end if;
end;
$$;

-- Independent of the unshipped portal_authority_guard. Both guards may coexist.
-- An invoker trigger sees the database executor of a trusted definer RPC, not
-- its caller's JWT role. Callable definer RPCs still require separate review.
create function public.guard_profile_protected_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.roles::text is distinct from 'User'
        or new.balance is distinct from 0::double precision
        or new.reward_tracker is distinct from 0::double precision then
        raise exception 'Protected profile fields require a trusted server writer'
          using errcode = '42501';
      end if;
    elsif new.roles is distinct from old.roles
      or new.balance is distinct from old.balance
      or new.reward_tracker is distinct from old.reward_tracker then
      raise exception 'Protected profile fields require a trusted server writer'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protected_fields_guard
before insert or update on public.profiles
for each row execute function public.guard_profile_protected_fields();

revoke all on function public.guard_profile_protected_fields()
  from public, anon, authenticated;

commit;
