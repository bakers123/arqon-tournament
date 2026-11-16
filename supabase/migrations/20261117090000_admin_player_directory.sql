create or replace function public.list_admin_player_directory()
returns table (
  arqon_id bigint,
  display_name text,
  player_name text,
  game_nick text,
  steam_persona_name text,
  has_steam boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.current_organizer_role() not in ('owner','admin','editor') then
    raise exception 'organizer_required' using errcode='42501';
  end if;

  return query
  select
    pr.arqon_id,
    coalesce(nullif(btrim(pr.display_name),''),nullif(btrim(pr.steam_persona_name),''),nullif(btrim(pr.game_nick),''),nullif(btrim(pl.name),''),'Игрок ARQON #'||pr.arqon_id::text),
    nullif(btrim(pl.name),''),
    nullif(btrim(pr.game_nick),''),
    nullif(btrim(pr.steam_persona_name),''),
    (pr.steam_id is not null and btrim(pr.steam_id)<>'')
  from public.profiles pr
  left join lateral (
    select p.name from public.players p
    where p.uid=pr.user_id::text
    order by p.id
    limit 1
  ) pl on true
  where pr.arqon_id is not null
  order by coalesce(nullif(btrim(pr.game_nick),''),nullif(btrim(pl.name),''),nullif(btrim(pr.display_name),''),nullif(btrim(pr.steam_persona_name),''),'') asc, pr.arqon_id;
end;
$$;

revoke all on function public.list_admin_player_directory() from public, anon;
grant execute on function public.list_admin_player_directory() to authenticated;
