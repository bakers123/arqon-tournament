-- Expose equipped cosmetics on public profiles and lock down trigger-only wallet initializer.
revoke all on function public.ensure_arqon_coin_wallet() from public,anon,authenticated;
drop function if exists public.get_public_arqon_profile(bigint);
create function public.get_public_arqon_profile(p_arqon_id bigint)
returns table(
 arqon_id bigint,display_name text,player_name text,bio text,avatar_url text,cover_url text,steam_id text,
 created_at timestamptz,cs2_faceit_url text,cs2_faceit_elo integer,dota2_profile_url text,dota2_mmr integer,
 equipped_frame_id text,equipped_theme_id text,equipped_title_id text
)
language sql stable security definer set search_path=''
as $$
 select p.arqon_id,
   coalesce(nullif(p.display_name,''),nullif(p.steam_persona_name,''),pl.name,'Игрок ARQON'),
   pl.name,p.bio,coalesce(p.avatar_url,p.steam_avatar_url),p.cover_url,
   case when p.show_steam then p.steam_id else null end,p.created_at,
   p.cs2_faceit_url,p.cs2_faceit_elo,p.dota2_profile_url,p.dota2_mmr,
   p.equipped_frame_id,p.equipped_theme_id,p.equipped_title_id
 from public.profiles p left join public.players pl on pl.uid=p.user_id::text
 where p.arqon_id=p_arqon_id and p.is_public=true limit 1;
$$;
revoke all on function public.get_public_arqon_profile(bigint) from public;
grant execute on function public.get_public_arqon_profile(bigint) to anon,authenticated;
