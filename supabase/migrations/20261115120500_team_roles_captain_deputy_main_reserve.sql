
create or replace function public.set_arqon_team_member_role(p_team_id text,p_account_id text,p_role text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_data jsonb; v_teams jsonb; v_team jsonb; v_players jsonb; v_player jsonb; v_idx int; v_arqon bigint; v_captain bigint; v_active int; v_reserve int;
begin
 if v_uid is null then raise exception 'not_authenticated'; end if;
 if p_role not in ('main','reserve','deputy') then raise exception 'invalid_role'; end if;
 select * into v_profile from public.profiles where user_id=v_uid;
 if not found then raise exception 'profile_required'; end if;
 if not exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_profile.arqon_id) then raise exception 'not_team_captain'; end if;
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 v_captain:=coalesce((v_team->>'captainArqonId')::bigint,(select tp.captain_arqon_id from public.team_profiles tp where tp.team_id=p_team_id));
 v_players:=coalesce(v_team->'players','[]'::jsonb);
 select pl into v_player from jsonb_array_elements(v_players) pl where pl->>'account_id'=p_account_id limit 1;
 if v_player is null then raise exception 'player_not_found'; end if;
 v_arqon:=nullif(v_player->>'arqonId','')::bigint;
 if v_arqon is null then raise exception 'player_profile_required'; end if;
 if v_arqon=v_captain then raise exception 'captain_role_managed_separately'; end if;
 if p_role='deputy' and exists(select 1 from jsonb_array_elements(v_players) pl where pl->>'rosterRole'='deputy' and pl->>'account_id'<>p_account_id) then raise exception 'deputy_already_exists'; end if;
 v_active:=(select count(*) from jsonb_array_elements(v_players) pl where coalesce(pl->>'rosterRole','main')<>'reserve');
 v_reserve:=(select count(*) from jsonb_array_elements(v_players) pl where pl->>'rosterRole'='reserve');
 if p_role<>'reserve' and coalesce(v_player->>'rosterRole','main')='reserve' and v_active>=5 then raise exception 'main_roster_full'; end if;
 if p_role='reserve' and coalesce(v_player->>'rosterRole','main')<>'reserve' and v_reserve>=2 then raise exception 'reserve_roster_full'; end if;
 select ordinality-1 into v_idx from jsonb_array_elements(v_players) with ordinality e(pl,ordinality) where e.pl->>'account_id'=p_account_id limit 1;
 v_players:=jsonb_set(v_players,array[v_idx::text],v_player||jsonb_build_object('rosterRole',p_role),false);
 v_team:=jsonb_set(v_team,'{players}',v_players,true);
 select jsonb_agg(case when t->>'id'=p_team_id then v_team else t end order by ordinality) into v_teams from jsonb_array_elements(v_teams) with ordinality e(t,ordinality);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 return p_role;
end;
$function$;
revoke all on function public.set_arqon_team_member_role(text,text,text) from public,anon;
grant execute on function public.set_arqon_team_member_role(text,text,text) to authenticated;

create or replace function public.manage_team_roster(p_team_id text,p_account_id text,p_action text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_data jsonb; v_teams jsonb; v_team jsonb; v_players jsonb; v_player jsonb; v_name text; v_arqon bigint; v_from_name text; v_idx int; v_active int; v_reserve int; v_new_role text; v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_is_captain boolean; v_is_deputy boolean;
begin
 select * into v_profile from public.profiles where user_id=v_uid;
 v_is_captain:=exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_profile.arqon_id);
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 v_players:=coalesce(v_team->'players','[]'::jsonb);
 v_is_deputy:=exists(select 1 from jsonb_array_elements(v_players) pl where pl->>'arqonId'=v_profile.arqon_id::text and pl->>'rosterRole'='deputy');
 if not (public.has_organizer_role('editor') or v_is_captain or v_is_deputy) then raise exception 'not_authorized'; end if;
 if p_action not in ('promote','demote','release') then raise exception 'invalid_action'; end if;
 select pl into v_player from jsonb_array_elements(v_players) pl where pl->>'account_id'=p_account_id limit 1;
 if v_player is null then raise exception 'player_not_found'; end if;
 v_name:=coalesce(v_player->>'name','Игрок');v_arqon:=nullif(v_player->>'arqonId','')::bigint;v_from_name:=v_team->>'name';
 if exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_arqon) then raise exception 'cannot_change_captain_role'; end if;
 if v_is_deputy and (v_player->>'rosterRole'='deputy' or p_action='release' and v_player->>'rosterRole'='deputy') then raise exception 'deputy_cannot_manage_deputy'; end if;
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
   v_new_role:='main';v_players:=jsonb_set(v_players,array[v_idx::text],v_player||jsonb_build_object('rosterRole','main'),false);
   insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,to_team_id,to_team_name,event_type) values(v_arqon,v_name,p_team_id,v_from_name,p_team_id,v_from_name,'promoted');
  else
   if coalesce(v_player->>'rosterRole','main')='reserve' then raise exception 'already_reserve'; end if;
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
revoke all on function public.manage_team_roster(text,text,text) from public,anon;
grant execute on function public.manage_team_roster(text,text,text) to authenticated;
