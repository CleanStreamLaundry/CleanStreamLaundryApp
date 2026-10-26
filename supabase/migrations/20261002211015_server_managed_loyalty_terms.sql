begin;

create table public.loyalty_policy_documents (
  version text primary key check (length(btrim(version)) between 1 and 100),
  document jsonb not null,
  is_current boolean not null default false,
  published_at timestamptz not null default now()
);
create unique index loyalty_policy_one_current
  on public.loyalty_policy_documents (is_current) where is_current;
alter table public.loyalty_policy_documents enable row level security;
revoke all on public.loyalty_policy_documents from public, anon, authenticated;
grant select on public.loyalty_policy_documents to anon, authenticated;
grant select, insert, update on public.loyalty_policy_documents to service_role;
create policy loyalty_policy_public_read on public.loyalty_policy_documents
  for select to anon, authenticated using (true);

create function private.guard_loyalty_policy_document()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare section jsonb; paragraph jsonb;
begin
  if tg_op = 'DELETE' then
    raise exception 'Published policy history must be retained' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and (new.version is distinct from old.version
    or new.document is distinct from old.document
    or new.published_at is distinct from old.published_at) then
    raise exception 'Publish a new version instead of changing agreed terms' using errcode = '23514';
  end if;
  if jsonb_typeof(new.document) is distinct from 'object'
    or jsonb_typeof(new.document->'title') is distinct from 'string'
    or length(btrim(new.document->>'title')) = 0
    or jsonb_typeof(new.document->'effective_date') is distinct from 'string'
    or (new.document->>'effective_date') !~ '^\d{4}-\d{2}-\d{2}$'
    or jsonb_typeof(new.document->'sections') is distinct from 'array' then
    raise exception 'Invalid loyalty policy document' using errcode = '23514';
  end if;
  if (new.document->>'effective_date')::date::text <> new.document->>'effective_date'
    or jsonb_array_length(new.document->'sections') = 0 then
    raise exception 'Invalid loyalty policy document' using errcode = '23514';
  end if;
  for section in select value from jsonb_array_elements(new.document->'sections') loop
    if jsonb_typeof(section->'heading') is distinct from 'string'
      or length(btrim(section->>'heading')) = 0
      or jsonb_typeof(section->'paragraphs') is distinct from 'array' then
      raise exception 'Invalid loyalty policy section' using errcode = '23514';
    end if;
    if jsonb_array_length(section->'paragraphs') = 0 then
      raise exception 'Empty loyalty policy section' using errcode = '23514';
    end if;
    for paragraph in select value from jsonb_array_elements(section->'paragraphs') loop
      if jsonb_typeof(paragraph) is distinct from 'string' or length(btrim(paragraph #>> '{}')) = 0 then
        raise exception 'Invalid loyalty policy paragraph' using errcode = '23514';
      end if;
    end loop;
  end loop;
  return new;
end;
$$;
revoke all on function private.guard_loyalty_policy_document() from public, anon, authenticated;
create trigger loyalty_policy_document_guard before insert or update or delete
  on public.loyalty_policy_documents for each row
  execute function private.guard_loyalty_policy_document();

insert into public.loyalty_policy_documents (version, is_current, document) values
('2026-10-02.1', true, $document${
  "title": "Loyalty Program Terms",
  "effective_date": "2026-10-02",
  "sections": [
    {
      "heading": "1. Your purchased laundry credit",
      "paragraphs": [
        "Money successfully loaded into your Clean Stream wallet purchases prepaid laundry service credit. Purchased credit is usable only at participating Clean Stream-operated locations in Indiana. It is not a bank account, does not earn interest, and cannot be gifted, transferred to another customer, or withdrawn as cash except under the refund policy or as required by law.",
        "Purchased credit has no expiration date or inactivity fee. Deleting your account does not cause unused purchased credit to expire or be forfeited."
      ]
    },
    {
      "heading": "2. Promotional rewards",
      "paragraphs": [
        "Promotional reward credit and reward progress are tracked separately from purchased credit. Reward credit has no cash value and is applied before purchased credit when paying from your wallet. The applicable reward offer is displayed when loading your wallet; spending credit does not itself earn the load reward again.",
        "A refunded load loses its associated promotional credit and reward progress. Unrelated earlier rewards are not canceled merely because a later load is refunded. Free promotional credit and unissued reward progress end when account deletion becomes final after the 30-day recovery period."
      ]
    },
    {
      "heading": "3. Refunds of unused wallet loads",
      "paragraphs": [
        "You may request a voluntary refund of the full amount paid for a wallet load if our server receives the request within 48 hours of successful funding, including exactly 48 hours. No wallet spending may have occurred after that load, including promotional-credit spending or a failed machine vend that was subsequently reversed. Earlier account usage does not disqualify a later load.",
        "An Owner reviews the request and may approve it after the deadline if it was submitted on time. Approved refunds return the full paid principal to the original payment method. Clean Stream absorbs the original processing fees. Partial voluntary refunds and cash refunds of promotional credit are not offered.",
        "Deleting or restoring an account does not restart the refund window. These conditions do not limit rights required by law or replace remedies for machine and payment failures."
      ]
    },
    {
      "heading": "4. Machine or payment problems",
      "paragraphs": [
        "Report a machine or payment problem through the app or support@cleanstreamlaundry.com, preferably immediately and within 14 days. Include the location, machine, approximate time, payment reference, and a description of the problem. This reporting period does not shorten any rights required by law.",
        "The 48-hour unused-load restriction does not apply to a machine-failure or duplicate-charge claim. Support reviews the machine and payment records. An approved card refund goes to the original payment method; an approved wallet reversal restores the applicable purchased and promotional credit rather than replacing purchased value with promotional value. A pending payment or refund is not proof of completion."
      ]
    },
    {
      "heading": "5. Stripe and Nayax",
      "paragraphs": [
        "Clean Stream uses Stripe for supported app and website card payments and refunds. Nayax supplies connected-machine payment and vending services, including supported payments made directly at a machine. The processor and payment method used determine the refund route. Clean Stream remains your contact for laundry-service and wallet issues.",
        "A machine activation associated with a Stripe or wallet payment is not a second purchase merely because Nayax also records the machine activity. Payment processing and machine authorization may involve sharing necessary transaction and device information with these providers, as described in our Privacy Policy."
      ]
    },
    {
      "heading": "6. Account deletion and the 30-day recovery period",
      "paragraphs": [
        "Requesting deletion immediately restricts normal account access. You may explicitly restore your original account within 30 days after the request by verifying ownership and completing any required authentication. The app displays the exact deadline. Signing in alone does not restore an account.",
        "After that deadline, account restoration is no longer available and we delete your login and ordinary account profile through our cleanup process. Necessary settlement, refund, legal, security, and financial records are handled separately."
      ]
    },
    {
      "heading": "7. Purchased credit after deletion",
      "paragraphs": [
        "Unused purchased laundry credit is not forfeited solely because you delete your account. We retain limited records needed to establish ownership, honor the remaining credit, process refunds, and comply with legal obligations. Purchased credit remains available until redeemed, refunded, or transferred to the appropriate state authority if legally required; it has no automatic expiration.",
        "Contact support@cleanstreamlaundry.com to request access to remaining purchased credit after account deletion. We verify ownership before providing access. This does not restore the deleted profile, transfer credit to another person, create a new cash-withdrawal right, or extend the 48-hour voluntary refund window.",
        "Pending machine claims, refunds, and payment settlements continue despite account deletion. Restoration during the recovery period does not duplicate rewards or automatically renew revoked permissions or email subscriptions."
      ]
    },
    {
      "heading": "8. Responsible use and changes",
      "paragraphs": [
        "Use your own account and authorized payment methods, follow posted machine instructions, and report unauthorized activity promptly. Do not misuse machines, manipulate rewards, submit fraudulent claims, or attempt to bypass account or payment controls. Service may be restricted for security or misuse without automatically confiscating purchased credit.",
        "Machine prices, future reward offers, and these terms may change. Prices are shown before a purchase. Material revisions requiring agreement are presented for acceptance under a new version. Changes do not retroactively erase purchased credit or override rights required by law."
      ]
    },
    {
      "heading": "9. Questions and disputes",
      "paragraphs": [
        "Contact support@cleanstreamlaundry.com first so we can attempt to resolve a concern. We aim to work toward a resolution within 30 days; this does not prevent urgent relief or require you to miss a legal deadline.",
        "Unresolved disputes may be brought in an appropriate court, including small claims court when eligible. These terms do not require arbitration, waive a jury trial, or waive class-action rights. Mediation or arbitration may be used only if both sides separately agree in writing after a dispute arises. Applicable mandatory law controls if any part of these terms conflicts with it."
      ]
    }
  ]
}$document$::jsonb);

create or replace function public.get_loyalty_policy_descriptor()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare policy public.loyalty_policy_documents; text_value text;
begin
  select * into policy from public.loyalty_policy_documents where is_current;
  if not found then
    raise exception 'loyalty_policy_unavailable' using errcode = 'PT503';
  end if;
  text_value := policy.document::text;
  return jsonb_build_object('required_version', policy.version,
    'policy_text', text_value,
    'policy_sha256', encode(sha256(convert_to(text_value, 'UTF8')), 'hex'));
end;
$$;

-- Preserve the existing admission/authentication checks. Hold the active
-- publication while accepting so an operator cannot replace it mid-transaction.
create or replace function public.accept_loyalty_policy(p_version text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare policy_status jsonb; accepted_version text; accepted_at timestamptz; locked_version text;
begin
  select version into locked_version from public.loyalty_policy_documents where is_current for share;
  if not found or p_version is distinct from locked_version then
    raise exception 'policy_version_mismatch' using errcode = '22023';
  end if;
  policy_status := public.get_loyalty_policy_status();
  if locked_version is distinct from policy_status->>'required_version' then
    raise exception 'policy_version_mismatch' using errcode = '22023';
  end if;
  begin
    select p.loyalty_policy_version, p.loyalty_policy_accepted_at
      into accepted_version, accepted_at
    from public.profiles p where p.id = auth.uid() for no key update;
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    if accepted_version is distinct from p_version or accepted_at is null then
      accepted_at := clock_timestamp();
      update public.profiles set loyalty_policy_version = p_version,
        loyalty_policy_accepted_at = accepted_at where id = auth.uid();
    end if;
    if not private.account_access_allowed() then
      raise exception 'account_restricted' using errcode = 'PT403';
    end if;
    return policy_status || jsonb_build_object('accepted_version', p_version,
      'accepted_at', accepted_at, 'acceptance_required', false);
  exception
    when sqlstate 'PT401' then raise exception 'session_invalid' using errcode = 'PT401';
    when sqlstate 'PT403' then raise exception 'account_restricted' using errcode = 'PT403';
    when others then raise exception 'admission_unavailable' using errcode = 'PT503';
  end;
end;
$$;
revoke all on function public.get_loyalty_policy_descriptor(), public.accept_loyalty_policy(text)
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.get_loyalty_policy_descriptor() to anon, authenticated;
grant execute on function public.accept_loyalty_policy(text) to authenticated;

commit;
