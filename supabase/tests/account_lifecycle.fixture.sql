-- Representative linked financial rows only, not a production schema baseline.
-- The lifecycle batch must not touch any of these tables or Auth records.
create table public.wallet_accounts (
  id uuid primary key, user_id uuid references auth.users(id), balance integer,
  created_at timestamptz not null default now()
);
create table public.wallet_loads (
  id uuid primary key, wallet_account_id uuid references public.wallet_accounts(id),
  user_id uuid references auth.users(id), paid_amount integer, created_at timestamptz default now()
);
create table public.wallet_redemptions (
  id uuid primary key, wallet_account_id uuid references public.wallet_accounts(id),
  user_id uuid references auth.users(id), amount integer, reward boolean,
  created_at timestamptz default now()
);
create table public.transactions (
  id uuid primary key, user_id uuid references auth.users(id), amount integer,
  created_at timestamptz default now()
);
create table public."Refunds" (
  id uuid primary key, user_id uuid references auth.users(id), status text,
  created_at timestamptz default now(), notification_sent_at timestamptz
);
