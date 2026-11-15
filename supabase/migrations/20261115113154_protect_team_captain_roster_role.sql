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
 if exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_arqon) then
   raise exception 'cannot_change_captain_role';
 end if;
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
