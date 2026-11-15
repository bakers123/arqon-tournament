-- Public-safe ARQON player identifiers. Never expose auth user IDs, emails or Steam IDs.
create or replace function public.list_public_player_profiles()
returns table (
  player_name text,
  arqon_id bigint,
  display_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select pl.name, pr.arqon_id, pr.display_name
  from public.players as pl
  join public.profiles as pr
    on pr.user_id::text = pl.uid
  where pl.name is not null
    and btrim(pl.name) <> ''
  order by pl.name;
$$;

revoke all on function public.list_public_player_profiles() from public;
grant execute on function public.list_public_player_profiles() to anon, authenticated;
