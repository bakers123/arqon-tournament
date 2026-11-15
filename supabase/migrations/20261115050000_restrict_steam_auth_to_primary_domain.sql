alter table public.steam_openid_states drop constraint if exists steam_openid_states_return_origin_check;
alter table public.steam_openid_states add constraint steam_openid_states_return_origin_check
  check (return_origin in ('https://arqon-esports.ru','https://www.arqon-esports.ru'));