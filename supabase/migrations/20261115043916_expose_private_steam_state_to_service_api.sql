create table if not exists public.steam_openid_states (
  state text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  return_origin text not null check (return_origin in (
    'https://arqon-esports.ru',
    'https://www.arqon-esports.ru',
    'https://arqon-esports.online',
    'https://www.arqon-esports.online'
  )),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  response_nonce text unique
);

alter table public.steam_openid_states enable row level security;
revoke all on table public.steam_openid_states from public, anon, authenticated;
grant all on table public.steam_openid_states to service_role;
create index if not exists steam_openid_states_expiry_idx
  on public.steam_openid_states (expires_at)
  where consumed_at is null;