begin;

create schema if not exists private;

-- Three project-wide capacity buckets, not caller identities or request history.
create table private.cortina_request_capacity (
  bucket text primary key check (bucket in ('quote', 'card', 'status')),
  tokens numeric not null check (
    tokens >= 0 and tokens <= case bucket when 'quote' then 30 when 'card' then 5 else 120 end
  ),
  updated_at timestamptz not null check (pg_catalog.isfinite(updated_at))
);
alter table private.cortina_request_capacity enable row level security;
revoke all on table private.cortina_request_capacity from public, anon, authenticated, service_role;

insert into private.cortina_request_capacity(bucket, tokens, updated_at)
values ('quote', 30, pg_catalog.clock_timestamp()),
       ('card', 5, pg_catalog.clock_timestamp()),
       ('status', 120, pg_catalog.clock_timestamp());

-- Definer access is narrowly needed for this private table; only service_role may execute.
create function public.consume_cortina_request_capacity(p_bucket text)
returns jsonb language plpgsql security definer
set search_path = '' set lock_timeout = '500ms' as $$
declare
  current_bucket private.cortina_request_capacity%rowtype;
  capacity integer;
  refill_per_minute integer;
  observed_at timestamptz;
  available numeric;
begin
  case p_bucket
    when 'quote' then capacity := 30; refill_per_minute := 120;
    when 'card' then capacity := 5; refill_per_minute := 10;
    when 'status' then capacity := 120; refill_per_minute := 1200;
    else raise exception 'Invalid Cortina capacity bucket' using errcode = '22023';
  end case;

  select * into current_bucket from private.cortina_request_capacity
  where bucket = p_bucket for update;
  if not found then
    raise exception 'Cortina capacity unavailable' using errcode = '55000';
  end if;

  -- Sample after the lock wait. Backward wall-clock changes cannot mint tokens.
  observed_at := greatest(pg_catalog.clock_timestamp(), current_bucket.updated_at);
  available := least(capacity, current_bucket.tokens +
    extract(epoch from (observed_at - current_bucket.updated_at)) * refill_per_minute / 60);
  if available < 1 then
    return pg_catalog.jsonb_build_object('allowed', false,
      'retry_after_seconds', pg_catalog.ceil((1 - available) * 60 / refill_per_minute)::integer);
  end if;

  update private.cortina_request_capacity
  set tokens = available - 1, updated_at = observed_at where bucket = p_bucket;
  return pg_catalog.jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end;
$$;

revoke all on function public.consume_cortina_request_capacity(text)
  from public, anon, authenticated, service_role;
grant execute on function public.consume_cortina_request_capacity(text) to service_role;

commit;
