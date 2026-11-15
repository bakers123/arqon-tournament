create or replace function public.list_public_player_profile_cards()
returns table(
  player_name text,
  arqon_id bigint,
  display_name text,
  avatar_url text,
  steam_avatar_url text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select pl.name, pr.arqon_id, pr.display_name, pr.avatar_url, pr.steam_avatar_url
  from public.players pl
  join public.profiles pr on pr.user_id::text = pl.uid
  where pl.name is not null
    and btrim(pl.name) <> ''
    and pr.is_public = true
  order by pl.name;
$function$;

revoke all on function public.list_public_player_profile_cards() from public;
grant execute on function public.list_public_player_profile_cards() to anon, authenticated;
