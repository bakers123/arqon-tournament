create table if not exists private.steam_openid_states (
  state text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  return_origin text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  response_nonce text unique
);

alter table private.steam_openid_states enable row level security;
revoke all on table private.steam_openid_states from public, anon, authenticated;
grant all on table private.steam_openid_states to service_role;
create index if not exists steam_openid_states_expiry_idx on private.steam_openid_states (expires_at) where consumed_at is null;