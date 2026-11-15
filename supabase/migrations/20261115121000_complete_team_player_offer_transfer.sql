-- A player accepts first; only the team captain or an organizer can
-- finalize the move into the actual tournament roster.

alter table public.team_player_offers
  drop constraint if exists team_player_offers_status_check;
alter table public.team_player_offers
  add constraint team_player_offers_status_check
  check (status = any (array['pending','accepted','rejected','cancelled','completed']));

create or replace function public.create_team_player_offer(
  p_team_id text, p_arqon_id bigint, p_role text default '', p_message text default ''
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare
  v_user uuid:=auth.uid();
  v_player public.profiles%rowtype;
  v_team public.team_profiles%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  select * into v_team from public.team_profiles where team_id=p_team_id;
  if not found then raise exception 'team_not_found'; end if;
  if not (public.has_organizer_role('editor') or exists(
    select 1 from public.profiles captain
    where captain.arqon_id=v_team.captain_arqon_id and captain.user_id=v_user
  )) then raise exception 'not_authorized'; end if;
  if char_length(coalesce(p_role,''))>80 or char_length(coalesce(p_message,''))>500 then
    raise exception 'invalid_input';
  end if;
  select * into v_player from public.profiles
  where arqon_id=p_arqon_id and is_public=true and looking_for_team=true;
  if not found then raise exception 'player_not_available'; end if;
  if exists(
    select 1 from public.tournament t
    cross join lateral jsonb_array_elements(coalesce(t.data->'teams','[]'::jsonb)) tm
    cross join lateral jsonb_array_elements(coalesce(tm->'players','[]'::jsonb)) pl
    where pl->>'account_id'=v_player.user_id::text
       or pl->>'arqonId'=p_arqon_id::text
  ) then raise exception 'player_already_in_team'; end if;
  insert into public.team_player_offers(
    team_id,team_name,player_user_id,player_arqon_id,player_name,offered_role,message,created_by
  ) values(
    p_team_id,v_team.team_name,v_player.user_id,v_player.arqon_id,
    coalesce(nullif(v_player.display_name,''),'Игрок ARQON #'||v_player.arqon_id),
    coalesce(p_role,''),coalesce(p_message,''),v_user
  )
  on conflict(team_id,player_user_id) do update
  set offered_role=excluded.offered_role,message=excluded.message,
      created_by=excluded.created_by,created_at=now(),status='pending',responded_at=null
  returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.complete_team_player_offer(
  p_offer_id uuid, p_roster_role text default 'main'
) returns text
language plpgsql security definer set search_path=''
as $function$
declare
  v_user uuid:=auth.uid();
  v_offer public.team_player_offers%rowtype;
  v_team_profile public.team_profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_data jsonb;
  v_teams jsonb;
  v_team jsonb;
  v_players jsonb;
  v_player jsonb;
  v_name text;
  v_active integer;
  v_reserve integer;
  v_idx integer;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_roster_role not in ('main','reserve') then raise exception 'invalid_roster_role'; end if;
  select * into v_offer from public.team_player_offers
  where id=p_offer_id and status='accepted' for update;
  if not found then raise exception 'offer_not_accepted_or_closed'; end if;
  select * into v_team_profile from public.team_profiles where team_id=v_offer.team_id;
  if not found then raise exception 'team_not_found'; end if;
  if not (
    public.has_organizer_role('editor')
    or exists(select 1 from public.profiles captain
      where captain.arqon_id=v_team_profile.captain_arqon_id
        and captain.user_id=v_user)
  ) then raise exception 'not_authorized'; end if;
  select * into v_profile from public.profiles where user_id=v_offer.player_user_id;
  if not found or v_profile.arqon_id<>v_offer.player_arqon_id then
    raise exception 'player_profile_not_found';
  end if;
  select data into v_data from public.tournament where id=1 for update;
  if v_data is null then raise exception 'tournament_not_found'; end if;
  v_teams:=coalesce(v_data->'teams','[]'::jsonb);
  if exists(
    select 1 from jsonb_array_elements(v_teams) tm
    cross join lateral jsonb_array_elements(coalesce(tm->'players','[]'::jsonb)) pl
    where pl->>'account_id'=v_profile.user_id::text
       or pl->>'arqonId'=v_profile.arqon_id::text
  ) then raise exception 'player_already_in_team'; end if;
  select tm into v_team from jsonb_array_elements(v_teams) tm
  where tm->>'id'=v_offer.team_id limit 1;
  if v_team is null then raise exception 'team_not_found'; end if;
  v_players:=coalesce(v_team->'players','[]'::jsonb);
  v_active:=(select count(*) from jsonb_array_elements(v_players) pl
            where coalesce(pl->>'rosterRole','main')<>'reserve');
  v_reserve:=(select count(*) from jsonb_array_elements(v_players) pl
              where pl->>'rosterRole'='reserve');
  if p_roster_role='main' and v_active>=5 then raise exception 'main_roster_full'; end if;
  if p_roster_role='reserve' and v_reserve>=2 then raise exception 'reserve_roster_full'; end if;
  select coalesce(nullif(v_profile.display_name,''),pl.name,
                  'Игрок ARQON #'||v_profile.arqon_id::text)
  into v_name from (select 1) x
  left join public.players pl on pl.uid=v_profile.user_id::text limit 1;
  v_player:=jsonb_build_object('name',v_name,'account_id',v_profile.user_id::text,'arqonId',v_profile.arqon_id);
  if v_profile.avatar_url is not null then
    v_player:=v_player||jsonb_build_object('avatar',v_profile.avatar_url);
  end if;
  if p_roster_role='reserve' then
    v_player:=v_player||jsonb_build_object('rosterRole','reserve');
  end if;
  v_idx:=(select ordinality-1 from jsonb_array_elements(v_teams)
          with ordinality e(tm,ordinality)
          where e.tm->>'id'=v_offer.team_id limit 1);
  v_team:=jsonb_set(v_team,'{players}',v_players||jsonb_build_array(v_player),true);
  select jsonb_agg(case when ordinality-1=v_idx then v_team else tm end order by ordinality)
  into v_teams from jsonb_array_elements(v_teams) with ordinality e(tm,ordinality);
  update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
  insert into public.team_transfer_history(arqon_id,player_name,to_team_id,to_team_name,event_type)
  values(v_profile.arqon_id,v_name,v_offer.team_id,v_offer.team_name,'joined');
  update public.team_player_offers set status='completed',responded_at=coalesce(responded_at,now())
  where id=p_offer_id;
  return p_roster_role;
end
$function$;

revoke all on function public.create_team_player_offer(text,bigint,text,text) from public,anon;
revoke all on function public.complete_team_player_offer(uuid,text) from public,anon;
grant execute on function public.create_team_player_offer(text,bigint,text,text) to authenticated;
grant execute on function public.complete_team_player_offer(uuid,text) to authenticated;
