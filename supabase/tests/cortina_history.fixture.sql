-- Local-only synthetic contracts for the existing production tables and roles.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key);
create type public."Roles" as enum ('Customer', 'Admin', 'Owner');
create type public.refund_status as enum ('pending', 'approved', 'denied');
create table public.profiles (
  id uuid primary key references auth.users(id), balance numeric default 7,
  roles public."Roles" default 'Customer', refund_attempts int default 0
);
create table public."Machines" (id bigint primary key, "Name" text, "Machine_type" text);
create table public.cortina_vend_sessions (
  id uuid primary key, user_id uuid references auth.users(id),
  machine_id bigint references public."Machines"(id), amount_cents int,
  payment_method text, status text, completed_at timestamptz,
  created_at timestamptz default now()
);
create table public.transactions (
  id bigserial primary key, user_id uuid references auth.users(id) on delete cascade,
  amount numeric not null, description text, created_at timestamptz default now(),
  type text not null default 'debit', requested_refund bool not null default false
);
create function public.update_user_balance() returns trigger language plpgsql as $$
begin
  if new.type = 'credit' then
    update public.profiles set balance = balance + new.amount where id = new.user_id;
  elsif new.type = 'debit' then
    update public.profiles set balance = balance - new.amount where id = new.user_id;
  end if;
  return new;
end;
$$;
create trigger handle_transaction after insert on public.transactions
for each row execute function public.update_user_balance();
create table public."Refunds" (
  refund_id bigserial primary key, user_id uuid not null references public.profiles(id),
  transaction_id bigint not null references public.transactions(id),
  description text not null, amount double precision,
  created_at timestamptz default now(), status public.refund_status default 'pending'
);
create table public.wallet_accounts (id uuid primary key, user_id uuid);
create table public.wallet_ledger_entries (
  id bigserial primary key, wallet_account_id uuid, entry_type text,
  amount_cents int, paid_amount_cents int, promo_amount_cents int,
  note text, created_by uuid
);
create function public.get_or_create_wallet_account(target_user_id uuid)
returns uuid language sql as $$ select id from public.wallet_accounts where user_id = target_user_id $$;
create function public.sync_profile_wallet_balance(wallet_id uuid)
returns void language sql as $$
  update public.profiles set balance = (
    select sum(amount_cents)::numeric / 100 from public.wallet_ledger_entries
    where wallet_account_id = wallet_id
  ) where id = (select user_id from public.wallet_accounts where id = wallet_id);
$$;
create function public.increment_user_refund_attempts(uid uuid) returns void language sql as $$
  update public.profiles set refund_attempts = refund_attempts + 1 where id = uid;
$$;
alter table public.transactions enable row level security;
alter table public."Refunds" enable row level security;
alter table public.cortina_vend_sessions enable row level security;
create policy own_transactions on public.transactions for select using (user_id = auth.uid());
create policy insert_own_transactions on public.transactions for insert with check (user_id = auth.uid());
create policy no_updates on public.transactions for update using (false);
create policy own_refunds on public."Refunds" for insert with check (user_id = auth.uid());
create policy view_refunds on public."Refunds" for select using (auth.uid() is not null);
grant all on all tables in schema public to service_role, authenticated, anon;
grant all on all sequences in schema public to service_role, authenticated, anon;
revoke all on public.cortina_vend_sessions from authenticated, anon;

insert into auth.users values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222'),
  ('33333333-3333-4333-8333-333333333333');
insert into public.profiles(id,roles)
select id, case when id::text like '3333%' then 'Owner'::public."Roles" else 'Customer'::public."Roles" end
from auth.users;
insert into public.wallet_accounts values ('11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111');
insert into public.wallet_ledger_entries(wallet_account_id,entry_type,amount_cents,paid_amount_cents,promo_amount_cents)
values ('11111111-1111-4111-8111-111111111111','load_paid',1100,1100,0),
  ('11111111-1111-4111-8111-111111111111','redeem_paid',-400,-400,0);
insert into public."Machines" values (1, 'Washer 1', 'Washer'), (2, 'Dryer 2', 'Dryer');
insert into public.cortina_vend_sessions(id,user_id,machine_id,amount_cents,payment_method,status,completed_at)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111',1,400,'wallet','started',now()),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',null,1,400,'card','started',now()),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','11111111-1111-4111-8111-111111111111',2,450,'card','approved',null),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','11111111-1111-4111-8111-111111111111',1,400,'wallet','refunded',now());
