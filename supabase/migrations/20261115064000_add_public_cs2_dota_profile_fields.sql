-- Add player-managed public CS2 and Dota 2 profile details.
alter table public.profiles
  add column if not exists cs2_faceit_url text,
  add column if not exists cs2_faceit_elo integer,
  add column if not exists dota2_profile_url text,
  add column if not exists dota2_mmr integer;

alter table public.profiles drop constraint if exists profiles_cs2_faceit_elo_check;
alter table public.profiles add constraint profiles_cs2_faceit_elo_check
  check (cs2_faceit_elo is null or cs2_faceit_elo between 0 and 5000);
alter table public.profiles drop constraint if exists profiles_dota2_mmr_check;
alter table public.profiles add constraint profiles_dota2_mmr_check
  check (dota2_mmr is null or dota2_mmr between 0 and 20000);
alter table public.profiles drop constraint if exists profiles_cs2_faceit_url_check;
alter table public.profiles add constraint profiles_cs2_faceit_url_check
  check (cs2_faceit_url is null or (cs2_faceit_url like 'https://%' and char_length(cs2_faceit_url) <= 2048));
alter table public.profiles drop constraint if exists profiles_dota2_profile_url_check;
alter table public.profiles add constraint profiles_dota2_profile_url_check
  check (dota2_profile_url is null or (dota2_profile_url like 'https://%' and char_length(dota2_profile_url) <= 2048));

grant select (cs2_faceit_url, cs2_faceit_elo, dota2_profile_url, dota2_mmr)
  on public.profiles to authenticated;
grant update (cs2_faceit_url, cs2_faceit_elo, dota2_profile_url, dota2_mmr)
  on public.profiles to authenticated;

drop function if exists public.get_public_arqon_profile(bigint);
create function public.get_public_arqon_profile(p_arqon_id bigint)
returns table (
  arqon_id bigint, display_name text, player_name text, bio text,
  avatar_url text, cover_url text, steam_id text, created_at timestamptz,
  cs2_faceit_url text, cs2_faceit_elo integer,
  dota2_profile_url text, dota2_mmr integer
)
language sql stable security definer set search_path = ''
as $$
  select p.arqon_id,
    coalesce(nullif(p.display_name, ''), pl.name, 'Игрок ARQON'),
    pl.name, p.bio, p.avatar_url, p.cover_url,
    case when p.show_steam then p.steam_id else null end,
    p.created_at, p.cs2_faceit_url, p.cs2_faceit_elo,
    p.dota2_profile_url, p.dota2_mmr
  from public.profiles p
  left join public.players pl on pl.uid = p.user_id::text
  where p.arqon_id = p_arqon_id and p.is_public = true
  limit 1;
$$;
revoke all on function public.get_public_arqon_profile(bigint) from public;
grant execute on function public.get_public_arqon_profile(bigint) to anon, authenticated;
