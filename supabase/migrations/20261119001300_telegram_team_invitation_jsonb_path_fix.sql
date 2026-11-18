create or replace function public.respond_team_invitation(p_invitation_id uuid,p_accept boolean)
returns text language plpgsql security definer set search_path=''
as $function$
declare
 v_inv public.team_invitations%rowtype; v_data jsonb; v_team jsonb; v_teams jsonb;
 v_profile public.profiles%rowtype; v_name text; v_role text; v_active int; v_reserve int;
 v_player jsonb; v_team_idx integer;
begin
 select * into v_inv from public.team_invitations
 where id=p_invitation_id and target_user_id=(select auth.uid()) and status='pending' for update;
 if not found then raise exception 'invitation_not_found_or_processed'; end if;
 if not p_accept then
  update public.team_invitations set status='declined',responded_at=now() where id=p_invitation_id;
  return 'declined';
 end if;
 select * into v_profile from public.profiles where user_id=(select auth.uid());
 if not found then raise exception 'profile_not_found'; end if;
 select data into v_data from public.tournament where id=1 for update;
 v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 if exists(select 1 from jsonb_array_elements(v_teams) t,lateral jsonb_array_elements(coalesce(t->'players','[]'::jsonb)) pl where pl->>'account_id'=(select auth.uid())::text) then raise exception 'already_in_team'; end if;
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=v_inv.team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 select (ordinality-1)::integer into v_team_idx from jsonb_array_elements(v_teams) with ordinality e(t,ordinality) where e.t->>'id'=v_inv.team_id limit 1;
 if v_team_idx is null then raise exception 'team_not_found'; end if;
 v_active:=(select count(*) from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where coalesce(pl->>'rosterRole','main')<>'reserve');
 v_reserve:=(select count(*) from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where pl->>'rosterRole'='reserve');
 if v_active<5 then v_role:='main'; elsif v_reserve<2 then v_role:='reserve'; else raise exception 'team_roster_full'; end if;
 select coalesce(nullif(v_profile.game_nick,''),nullif(v_profile.display_name,''),pl.name,'Игрок ARQON #'||v_profile.arqon_id::text)
 into v_name from (select 1) x left join public.players pl on pl.uid=v_profile.user_id::text limit 1;
 v_player:=jsonb_build_object('name',v_name,'account_id',(select auth.uid())::text,'arqonId',v_profile.arqon_id);
 if v_profile.avatar_url is not null then v_player:=v_player||jsonb_build_object('avatar',v_profile.avatar_url); end if;
 if v_role='reserve' then v_player:=v_player||jsonb_build_object('rosterRole','reserve'); end if;
 v_teams:=jsonb_set(v_teams,array[v_team_idx::text,'players'],coalesce(v_team->'players','[]'::jsonb)||jsonb_build_array(v_player),true);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 update public.team_invitations set status='accepted',responded_at=now() where id=p_invitation_id;
 insert into public.team_transfer_history(arqon_id,player_name,to_team_id,to_team_name,event_type)
 values(v_profile.arqon_id,v_name,v_inv.team_id,v_inv.team_name,'joined');
 return v_role;
end;
$function$;
