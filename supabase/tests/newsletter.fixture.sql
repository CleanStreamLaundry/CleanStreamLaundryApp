-- Only fills missing Auth columns in the existing synthetic admission fixture.
alter table auth.users add column email text;
alter table auth.users add column created_at timestamptz not null default clock_timestamp();
