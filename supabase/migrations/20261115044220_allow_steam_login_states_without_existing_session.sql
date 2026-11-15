alter table public.steam_openid_states
  alter column user_id drop not null;

create index if not exists steam_openid_states_user_created_idx
  on public.steam_openid_states (user_id, created_at desc)
  where consumed_at is null;