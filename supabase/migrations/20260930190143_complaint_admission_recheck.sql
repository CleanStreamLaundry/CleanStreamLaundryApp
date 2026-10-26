begin;

do $$
begin
  if to_regprocedure('private.portal_staff_context()') is null
    or to_regprocedure('public.record_deleted_account_complaint(uuid,text,text)') is null then
    raise exception 'Reviewed staff admission and complaint prerequisites required'
      using errcode = '55000';
  end if;
end;
$$;

create or replace function public.record_deleted_account_complaint(
  wallet_id uuid,
  complaint_note text,
  resolution text default 'denied'
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  complaint_id bigint;
  actor uuid;
  staff_context jsonb;
begin
  staff_context := private.portal_staff_context();
  actor := (staff_context->>'actor')::uuid;

  if complaint_note is null or btrim(complaint_note) = '' then
    raise exception 'Complaint note required';
  end if;

  insert into public.deleted_account_complaints(
    wallet_account_id, complaint_note, resolution, created_by
  ) values (
    wallet_id, complaint_note, resolution, actor
  ) returning id into complaint_id;

  -- FK and trigger waits can outlive authority. Reuse the fresh staff evaluator;
  -- wallet complaints do not acquire a new location or customer-terms policy.
  staff_context := private.portal_staff_context();
  if (staff_context->>'actor')::uuid is distinct from actor then
    raise exception 'admin_access_changed' using errcode = 'PT403';
  end if;
  return complaint_id;
end;
$$;

commit;
