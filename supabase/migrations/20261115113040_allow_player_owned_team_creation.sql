create or replace function public.create_arqon_team(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_data jsonb;
  v_teams jsonb;
  v_team_id text;
  v_name text := btrim(coalesce(p_name, ''));
  v_team jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if char_length(v_name) < 3 or char_length(v_name) > 30
     or v_name !~ '^[[:alnum:]А-Яа-яЁё _.-]+$' then
    raise exception 'invalid_team_name';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  select * into v_profile from public.profiles where user_id = v_uid;
  if not found then raise exception 'profile_required'; end if;
  if exists (select 1 from public.team_profiles tp where tp.captain_arqon_id = v_profile.arqon_id) then
    raise exception 'team_limit_reached';
  end if;
  select data into v_data from public.tournament where id = 1 for update;
  if v_data is null then raise exception 'tournament_unavailable'; end if;
  v_teams := coalesce(v_data->'teams', '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(v_teams) t where lower(btrim(t->>'name')) = lower(v_name)) then
    raise exception 'team_name_taken';
  end if;
  v_team_id := replace(gen_random_uuid()::text, '-', '');
  v_team := jsonb_build_object(
    'id', v_team_id, 'name', v_name, 'logo', null,
    'players', jsonb_build_array(jsonb_build_object(
      'name', coalesce(nullif(v_profile.display_name, ''), 'Игрок ARQON #' || v_profile.arqon_id::text),
      'avatar', coalesce(v_profile.avatar_url, v_profile.steam_avatar_url),
      'account_id', v_uid::text, 'arqonId', v_profile.arqon_id, 'rosterRole', 'main'
    )),
    'captainArqonId', v_profile.arqon_id, 'captainId', v_uid::text
  );
  update public.tournament
  set data = jsonb_set(coalesce(v_data, '{}'::jsonb), '{teams}', v_teams || jsonb_build_array(v_team), true)
  where id = 1;
  insert into public.team_profiles(team_id, team_name, captain_arqon_id, updated_by)
  values (v_team_id, v_name, v_profile.arqon_id, v_uid);
  return jsonb_build_object('id', v_team_id, 'name', v_name);
end;
$$;
revoke all on function public.create_arqon_team(text) from public, anon;
grant execute on function public.create_arqon_team(text) to authenticated;

drop policy if exists team_profiles_captain_insert on public.team_profiles;
create policy team_profiles_captain_insert on public.team_profiles
for insert to authenticated
with check (
  updated_by = (select auth.uid())
  and exists (select 1 from public.profiles p where p.user_id = (select auth.uid()) and p.arqon_id = captain_arqon_id)
);

drop policy if exists team_profiles_captain_update on public.team_profiles;
create policy team_profiles_captain_update on public.team_profiles
for update to authenticated
using (exists (select 1 from public.profiles p where p.user_id = (select auth.uid()) and p.arqon_id = team_profiles.captain_arqon_id))
with check (
  updated_by = (select auth.uid())
  and exists (select 1 from public.profiles p where p.user_id = (select auth.uid()) and p.arqon_id = team_profiles.captain_arqon_id)
);

create or replace function public.create_team_invitation(p_team_id text, p_arqon_id bigint)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid; v_team jsonb; v_invitation uuid;
begin
 if not (
   public.has_organizer_role('editor')
   or exists (select 1 from public.team_profiles tp join public.profiles captain on captain.arqon_id=tp.captain_arqon_id
              where tp.team_id=p_team_id and captain.user_id=(select auth.uid()))
 ) then raise exception 'not_authorized'; end if;
 select pr.user_id into v_user from public.profiles pr where pr.arqon_id=p_arqon_id and pr.is_public=true;
 if v_user is null then raise exception 'player_not_found'; end if;
 select t into v_team from public.tournament tr, lateral jsonb_array_elements(tr.data->'teams') t where tr.id=1 and t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 if exists(select 1 from public.tournament tr, lateral jsonb_array_elements(tr.data->'teams') t, lateral jsonb_array_elements(coalesce(t->'players','[]'::jsonb)) pl where tr.id=1 and pl->>'account_id'=v_user::text) then raise exception 'already_in_team'; end if;
 insert into public.team_invitations(team_id,team_name,target_user_id,target_arqon_id,invited_by)
 values(p_team_id,coalesce(v_team->>'name','Команда'),v_user,p_arqon_id,(select auth.uid())) returning id into v_invitation;
 return v_invitation;
exception when unique_violation then raise exception 'invitation_already_pending';
end;
$function$;
revoke all on function public.create_team_invitation(text,bigint) from public, anon;
grant execute on function public.create_team_invitation(text,bigint) to authenticated;

create or replace function public.manage_team_roster(p_team_id text, p_account_id text, p_action text)
returns text language plpgsql security definer set search_path = ''
as $function$
declare v_data jsonb; v_teams jsonb; v_team jsonb; v_players jsonb; v_player jsonb; v_name text; v_arqon bigint; v_from_name text; v_idx int; v_active int; v_reserve int; v_new_role text;
begin
 if not (
   public.has_organizer_role('editor')
   or exists (select 1 from public.team_profiles tp join public.profiles captain on captain.arqon_id=tp.captain_arqon_id
              where tp.team_id=p_team_id and captain.user_id=(select auth.uid()))
 ) then raise exception 'not_authorized'; end if;
 if p_action not in ('promote','demote','release') then raise exception 'invalid_action'; end if;
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 v_players:=coalesce(v_team->'players','[]'::jsonb);
 select pl into v_player from jsonb_array_elements(v_players) pl where pl->>'account_id'=p_account_id limit 1;
 if v_player is null then raise exception 'player_not_found'; end if;
 v_name:=coalesce(v_player->>'name','Игрок');v_arqon:=nullif(v_player->>'arqonId','')::bigint;v_from_name:=v_team->>'name';
 v_idx:=(select ordinality-1 from jsonb_array_elements(v_players) with ordinality e(pl,ordinality) where e.pl->>'account_id'=p_account_id limit 1);
 if p_action='release' then
  select coalesce(jsonb_agg(pl order by ordinality),'[]'::jsonb) into v_players from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) with ordinality e(pl,ordinality) where pl->>'account_id'<>p_account_id;
  insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,event_type) values(v_arqon,v_name,p_team_id,v_from_name,'released');
 else
  v_active:=(select count(*) from jsonb_array_elements(v_players) pl where coalesce(pl->>'rosterRole','main')<>'reserve');
  v_reserve:=(select count(*) from jsonb_array_elements(v_players) pl where pl->>'rosterRole'='reserve');
  if p_action='promote' then
   if coalesce(v_player->>'rosterRole','main')<>'reserve' then raise exception 'already_main'; end if;
   if v_active>=5 then raise exception 'main_roster_full'; end if;
   v_new_role:='main';v_players:=jsonb_set(v_players,array[v_idx::text],v_player-'rosterRole',false);
   insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,to_team_id,to_team_name,event_type) values(v_arqon,v_name,p_team_id,v_from_name,p_team_id,v_from_name,'promoted');
  else
   if v_player->>'rosterRole'='reserve' then raise exception 'already_reserve'; end if;
   if v_reserve>=2 then raise exception 'reserve_roster_full'; end if;
   v_new_role:='reserve';v_players:=jsonb_set(v_players,array[v_idx::text],v_player||jsonb_build_object('rosterRole','reserve'),false);
   insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,to_team_id,to_team_name,event_type) values(v_arqon,v_name,p_team_id,v_from_name,p_team_id,v_from_name,'demoted');
  end if;
 end if;
 v_team:=jsonb_set(v_team,'{players}',v_players,true);
 select jsonb_agg(case when t->>'id'=p_team_id then v_team else t end order by ordinality) into v_teams from jsonb_array_elements(v_teams) with ordinality e(t,ordinality);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 return coalesce(v_new_role,p_action);
end;
$function$;
revoke all on function public.manage_team_roster(text,text,text) from public, anon;
grant execute on function public.manage_team_roster(text,text,text) to authenticated;
