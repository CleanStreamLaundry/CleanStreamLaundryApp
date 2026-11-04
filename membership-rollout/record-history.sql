-- Inert migration provenance only; run after the exact policy install and postflight.
-- No schema replay or customer data changes.
begin;
insert into supabase_migrations.schema_migrations(version, name, statements)
values ('20261001094740', 'deny_anonymous_location_membership', array[$membership_source$begin;

do $$ begin
  if to_regprocedure('private.current_account_access()') is null
    or not exists (
      select 1 from pg_catalog.pg_policy p
      join pg_catalog.pg_class c on c.oid=p.polrelid
      where p.polrelid='public."Location_to_Admin"'::regclass
        and p.polname='portal_membership_direct_self'
        and p.polcmd='r' and not p.polpermissive and c.relrowsecurity
        and p.polroles=array['authenticated'::regrole::oid]
    ) then
    raise exception 'Installed canonical membership read policy required' using errcode='55000';
  end if;
end $$;

-- The legacy PUBLIC read policy must not expose private staff assignments to
-- signed-out callers. Authenticated self/staff admission stays unchanged.
create policy portal_membership_no_anon on public."Location_to_Admin"
  as restrictive for select to anon using(false);

commit;
$membership_source$]);
select version, name, cardinality(statements) as source_files,
  encode(sha256(convert_to(statements[1], 'UTF8')), 'hex') as source_sha256
from supabase_migrations.schema_migrations where version='20261001094740';
commit;
