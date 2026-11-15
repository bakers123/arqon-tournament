
create or replace function public.transfer_arqon_team_captain(p_team_id text,p_new_captain_arqon_id bigint)
returns void language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_team jsonb; v_players jsonb; v_target jsonb; v_data jsonb; v_teams jsonb; v_old_id bigint;
begin
 if v_uid is null then raise exception 'not_authenticated'; end if;
 select * into v_profile from public.profiles where user_id=v_uid;
 if not found then raise exception 'profile_required'; end if;
 select * into v_profile from public.profiles where user_id=v_uid;
 if not exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_profile.arqon_id) then
  raise exception 'not_team_captain';
 end if;
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 v_players:=coalesce(v_team->'players','[]'::jsonb);
 select pl into v_target from jsonb_array_elements(v_players) pl where (pl->>'arqonId')::bigint=p_new_captain_arqon_id limit 1;
 if v_target is null then raise exception 'player_not_in_team'; end if;
 if p_new_captain_arqon_id=v_profile.arqon_id then raise exception 'already_captain'; end if;
 if not exists(select 1 from public.profiles p where p.arqon_id=p_new_captain_arqon_id and p.user_id=(v_target->>'account_id')::uuid) then raise exception 'player_account_invalid'; end if;
 update public.team_profiles set captain_arqon_id=p_new_captain_arqon_id,updated_by=v_uid,updated_at=now() where team_id=p_team_id;
 v_team:=jsonb_set(v_team,'{captainArqonId}',to_jsonb(p_new_captain_arqon_id),true);
 v_team:=jsonb_set(v_team,'{captainId}',to_jsonb(v_target->>'account_id'),true);
 select jsonb_agg(case when t->>'id'=p_team_id then v_team else t end order by ordinality) into v_teams from jsonb_array_elements(v_teams) with ordinality e(t,ordinality);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
end $$;
revoke all on function public.transfer_arqon_team_captain(text,bigint) from public,anon;
grant execute on function public.transfer_arqon_team_captain(text,bigint) to authenticated;

create or replace function public.leave_arqon_team(p_team_id text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_data jsonb; v_teams jsonb; v_team jsonb; v_players jsonb; v_player jsonb;
begin
 if v_uid is null then raise exception 'not_authenticated'; end if;
 select * into v_profile from public.profiles where user_id=v_uid;
 if not found then raise exception 'profile_required'; end if;
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 if exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_profile.arqon_id) then raise exception 'captain_must_transfer_first'; end if;
 v_players:=coalesce(v_team->'players','[]'::jsonb);
 select pl into v_player from jsonb_array_elements(v_players) pl where pl->>'account_id'=v_uid::text limit 1;
 if v_player is null then raise exception 'not_team_member'; end if;
 select coalesce(jsonb_agg(pl order by ordinality),'[]'::jsonb) into v_players
 from jsonb_array_elements(v_players) with ordinality e(pl,ordinality) where pl->>'account_id'<>v_uid::text;
 insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,event_type)
 values(v_profile.arqon_id,coalesce(v_player->>'name',v_profile.display_name,'Игрок'),p_team_id,v_team->>'name','released');
 v_team:=jsonb_set(v_team,'{players}',v_players,true);
 select jsonb_agg(case when t->>'id'=p_team_id then v_team else t end order by ordinality) into v_teams
 from jsonb_array_elements(v_teams) with ordinality e(t,ordinality);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
end $$;
revoke all on function public.leave_arqon_team(text) from public,anon;
grant execute on function public.leave_arqon_team(text) to authenticated;

create or replace function public.delete_arqon_team(p_team_id text,p_confirmation text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_data jsonb; v_teams jsonb; v_team jsonb; v_name text; v_table text;
begin
 if v_uid is null then raise exception 'not_authenticated'; end if;
 select * into v_profile from public.profiles where user_id=v_uid;
 if not found then raise exception 'profile_required'; end if;
 if not exists(select 1 from public.team_profiles tp where tp.team_id=p_team_id and tp.captain_arqon_id=v_profile.arqon_id) then raise exception 'not_team_captain'; end if;
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 v_name:=v_team->>'name';
 if btrim(coalesce(p_confirmation,''))<>v_name then raise exception 'confirmation_mismatch'; end if;
 select coalesce(jsonb_agg(t order by ordinality),'[]'::jsonb) into v_teams
 from jsonb_array_elements(v_teams) with ordinality e(t,ordinality) where t->>'id'<>p_team_id;
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 foreach v_table in array array['team_invitations','team_player_offers','team_membership_requests','team_recruitment_requests'] loop
  if exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=v_table and c.column_name='team_id') then
   execute format('delete from public.%I where team_id=$1',v_table) using p_team_id;
  end if;
 end loop;
 delete from public.team_profiles where team_id=p_team_id;
end $$;
revoke all on function public.delete_arqon_team(text,text) from public,anon;
grant execute on function public.delete_arqon_team(text,text) to authenticated;
