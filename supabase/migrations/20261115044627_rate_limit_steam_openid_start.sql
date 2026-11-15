alter table public.steam_openid_states
  add column if not exists request_ip_hash text;

create index if not exists steam_openid_states_ip_created_idx
  on public.steam_openid_states (request_ip_hash, created_at desc)
  where request_ip_hash is not null;