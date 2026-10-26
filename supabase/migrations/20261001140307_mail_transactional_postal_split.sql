-- Optional claim filter only. No activation, enqueue, backfill or policy rewrite.
begin;

-- One signature avoids PostgREST overload ambiguity; omitted args retain behavior.
drop function public.mail_claim();
create function public.mail_claim(p_include_newsletter boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o private.mail_outbox;
begin
  perform private.mail_lock();
  if not exists(select 1 from private.mail_settings where enabled) then return null; end if;
  update private.mail_outbox set state='uncertain',last_error='worker_lost'
    where state='sending' and lease_until<clock_timestamp();
  update private.mail_outbox set state='ready' where state='leased' and lease_until<clock_timestamp();
  update private.mail_outbox m set state='suppressed',last_error='suppressed_or_stale'
    where state in ('ready','leased') and not private.mail_allowed(m);
  update private.mail_outbox set state='failed',last_error='retry_exhausted'
    where state='ready' and (attempts>=5 or first_attempt_at<clock_timestamp()-interval '23 hours');
  select * into o from private.mail_outbox where state='ready' and next_at<=clock_timestamp()
    and (p_include_newsletter is true or kind not in ('newsletter_confirm','newsletter_welcome'))
    order by created_at,id limit 1 for update;
  if not found then return null; end if;
  update private.mail_outbox set state='leased',lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes'
    where id=o.id returning * into o;
  return to_jsonb(o);
end $$;

revoke all on function public.mail_claim(boolean)
  from public,anon,authenticated,service_role,supabase_auth_admin;
grant execute on function public.mail_claim(boolean) to service_role;

notify pgrst, 'reload schema';
commit;
