begin;

-- The reviewed production graph has no parents for either client role. Stop
-- on drift; never revoke another role's grants or membership to force a pass.
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public."Location_to_Admin"'::regclass
      and c.relkind = 'r' and c.relrowsecurity and not c.relforcerowsecurity
      and pg_get_userbyid(c.relowner) = 'postgres'
  ) or current_user <> 'postgres' then
    raise exception 'Membership table ownership or RLS requires review'
      using errcode = '42501';
  end if;
  if (select count(*) from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated')) <> 2
    or exists (select 1 from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated')
        and (rolsuper or rolbypassrls or rolcreaterole))
    or exists (select 1 from pg_catalog.pg_auth_members m
      join pg_catalog.pg_roles r on r.oid = m.member
      where r.rolname in ('anon', 'authenticated')) then
    raise exception 'Client role authority or inheritance requires review'
      using errcode = '42501';
  end if;
end;
$$;

revoke insert, update, delete, truncate, references, trigger, maintain
  on public."Location_to_Admin" from public, anon, authenticated restrict;

do $$
declare
  columns_list text;
begin
  select string_agg(format('%I', attname), ', ' order by attnum)
    into columns_list
  from pg_catalog.pg_attribute
  where attrelid = 'public."Location_to_Admin"'::regclass
    and attnum > 0 and not attisdropped;
  execute format(
    'revoke insert (%1$s), update (%1$s), references (%1$s) on public."Location_to_Admin" from public, anon, authenticated restrict',
    columns_list
  );
  if exists (
    select 1 from (values ('anon'), ('authenticated')) r(name)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
      ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) p(privilege)
    where has_table_privilege(r.name, 'public."Location_to_Admin"', p.privilege)
  ) or exists (
    select 1 from (values ('anon'), ('authenticated')) r(name)
    cross join (values ('INSERT'), ('UPDATE'), ('REFERENCES')) p(privilege)
    where has_any_column_privilege(r.name, 'public."Location_to_Admin"', p.privilege)
  ) then
    raise exception 'Remaining effective membership privileges require review'
      using errcode = '42501';
  end if;
end;
$$;

-- Effective executor, not a forgeable JWT role: trusted definers and FK
-- cascades execute as their database owner. Their authorization is separate.
create function public.guard_location_membership_writes()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('anon', 'authenticated') then
    raise exception 'Membership writes require a trusted server writer'
      using errcode = '42501';
  end if;
  return null;
end;
$$;

create trigger location_membership_writes_guard
before insert or update or delete or truncate on public."Location_to_Admin"
for each statement execute function public.guard_location_membership_writes();
alter table public."Location_to_Admin"
  enable always trigger location_membership_writes_guard;
revoke all on function public.guard_location_membership_writes()
  from public, anon, authenticated, service_role;

commit;
