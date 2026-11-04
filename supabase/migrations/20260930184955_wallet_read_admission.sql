begin;

do $$
begin
  if to_regprocedure('public.get_admission_status()') is null
    or not exists (select 1 from pg_class where oid = 'public.wallet_balances'::regclass
      and relkind = 'v' and 'security_invoker=true' = any(reloptions))
    or (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
      where c.relnamespace = 'public'::regnamespace and c.relrowsecurity
        and not p.polpermissive and p.polcmd = 'r'
        and 'authenticated'::regrole = any(p.polroles)
        and (c.relname, p.polname) in (
          ('wallet_accounts', 'portal_wallet_direct_self'),
          ('wallet_loads', 'portal_load_direct_self'),
          ('wallet_ledger_entries', 'portal_ledger_direct_self'),
          ('wallet_redemptions', 'portal_redemption_direct_self'))) <> 4 then
    raise exception 'Reviewed canonical admission and self-only wallet policies required'
      using errcode = '55000';
  end if;
end;
$$;

-- AND with existing ownership policies. The scalar subquery evaluates the
-- canonical caller once per scan; no parallel eligibility rules or global role
-- grants. Definer settlement/refund routines retain their existing exceptions.
create policy wallet_accounts_home_admission on public.wallet_accounts
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

create policy wallet_loads_home_admission on public.wallet_loads
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

create policy wallet_ledger_home_admission on public.wallet_ledger_entries
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

create policy wallet_redemptions_home_admission on public.wallet_redemptions
as restrictive for select to authenticated using ((select
  public.get_admission_status() @> jsonb_build_object(
    'subject_id', auth.uid(), 'account_access', 'eligible', 'next_step', 'home')));

commit;
