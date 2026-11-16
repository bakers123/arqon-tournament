drop function if exists public.list_public_player_game_nicks();
drop function if exists public.list_public_player_profile_cards();
create function public.list_public_player_profile_cards()
returns table(player_name text, arqon_id bigint, display_name text, avatar_url text, steam_avatar_url text, game_nick text)
language sql stable security definer set search_path = ''
as $function$
  select pl.name, pr.arqon_id, pr.display_name, pr.avatar_url, pr.steam_avatar_url, pr.game_nick
  from public.profiles pr
  left join public.players pl on pl.uid = pr.user_id::text
  where pr.is_public = true
  order by coalesce(pl.name, pr.display_name, pr.steam_persona_name);
$function$;
revoke all on function public.list_public_player_profile_cards() from public;
grant execute on function public.list_public_player_profile_cards() to anon, authenticated;