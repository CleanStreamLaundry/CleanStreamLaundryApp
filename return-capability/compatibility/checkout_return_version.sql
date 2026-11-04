-- Additive cutover identity. The legacy default is permanent, including old writers.
begin;

do $$
begin
  if to_regclass('public.cortina_vend_sessions') is null or
     to_regprocedure('public.guard_cortina_payment_binding()') is null then
    raise exception 'Reviewed Cortina payment bindings required' using errcode = '55000';
  end if;
end;
$$;

alter table public.cortina_vend_sessions
  add column checkout_return_version smallint not null default 1,
  add constraint cortina_checkout_return_version_valid check (
    checkout_return_version in (1, 2) and
    (checkout_return_version = 1 or (payment_method = 'card' and channel = 'web'))
  );

create function public.guard_cortina_checkout_return_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.checkout_return_version is distinct from old.checkout_return_version then
    raise exception 'Checkout return version is immutable' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_cortina_checkout_return_version()
  from public, anon, authenticated, service_role;
create trigger guard_cortina_checkout_return_version
before update on public.cortina_vend_sessions
for each row execute function public.guard_cortina_checkout_return_version();

commit;
