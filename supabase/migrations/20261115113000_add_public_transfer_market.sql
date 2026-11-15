alter table public.profiles add column if not exists looking_for_team boolean not null default false, add column if not exists preferred_role text not null default '';
alter table public.profiles drop constraint if exists profiles_preferred_role_length;
alter table public.profiles add constraint profiles_preferred_role_length check (char_length(preferred_role) <= 80);
grant select (looking_for_team, preferred_role) on public.profiles to authenticated;
grant update (looking_for_team, preferred_role) on public.profiles to authenticated;
create or replace function public.list_transfer_market_players()
returns table (arqon_id bigint,display_name text,player_name text,bio text,avatar_url text,preferred_role text,cs2_faceit_elo integer,dota2_mmr integer)
language sql stable security definer set search_path = ''
as $$ select pr.arqon_id,pr.display_name,pl.name,pr.bio,pr.avatar_url,pr.preferred_role,pr.cs2_faceit_elo,pr.dota2_mmr from public.profiles pr join public.players pl on pl.uid=pr.user_id::text where pr.is_public=true and pr.looking_for_team=true and pl.name is not null and btrim(pl.name)<>'' order by pr.cs2_faceit_elo desc nulls last,pr.arqon_id $$;
revoke all on function public.list_transfer_market_players() from public;
grant execute on function public.list_transfer_market_players() to anon,authenticated;