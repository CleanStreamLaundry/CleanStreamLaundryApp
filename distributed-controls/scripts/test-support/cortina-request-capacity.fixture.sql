-- Disposable policy-admission-pg cluster only; no Auth or financial schema.
create role anon;
create role authenticated;
create role service_role nologin nosuperuser bypassrls;
create role capacity_owner nologin nosuperuser nobypassrls;
grant create on database loyalty_policy_fixture to capacity_owner;
grant usage, create on schema public to capacity_owner;
create schema private authorization capacity_owner;
