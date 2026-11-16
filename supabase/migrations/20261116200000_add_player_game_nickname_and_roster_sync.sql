alter table public.profiles
  add column if not exists game_nick text;

alter table public.profiles
  drop constraint if exists profiles_game_nick_length_check;
alter table public.profiles
  add constraint profiles_game_nick_length_check
  check (game_nick is null or char_length(btrim(game_nick)) between 1 and 32);

create or replace function public.create_arqon_team(p_name text)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
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
  if char_length(v_name) < 3 or char_length(v_name) > 30 or v_name !~ '^[[:alnum:]А-Яа-яЁё _.-]+$' then raise exception 'invalid_team_name'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  select * into v_profile from public.profiles where user_id = v_uid;
  if not found then raise exception 'profile_required'; end if;
  if exists (select 1 from public.team_profiles tp where tp.captain_arqon_id = v_profile.arqon_id) then raise exception 'team_limit_reached'; end if;
  select data into v_data from public.tournament where id = 1 for update;
  if v_data is null then raise exception 'tournament_unavailable'; end if;
  v_teams := coalesce(v_data->'teams', '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(v_teams) t where lower(btrim(t->>'name')) = lower(v_name)) then raise exception 'team_name_taken'; end if;
  v_team_id := replace(gen_random_uuid()::text, '-', '');
  v_team := jsonb_build_object(
    'id', v_team_id, 'name', v_name, 'logo', null,
    'players', jsonb_build_array(jsonb_build_object(
      'name', coalesce(nullif(v_profile.game_nick, ''), nullif(v_profile.display_name, ''), 'Игрок ARQON #' || v_profile.arqon_id::text),
      'avatar', coalesce(v_profile.avatar_url, v_profile.steam_avatar_url),
      'account_id', v_uid::text, 'arqonId', v_profile.arqon_id, 'rosterRole', 'main'
    )),
    'captainArqonId', v_profile.arqon_id, 'captainId', v_uid::text
  );
  update public.tournament set data = jsonb_set(coalesce(v_data, '{}'::jsonb), '{teams}', v_teams || jsonb_build_array(v_team), true) where id = 1;
  insert into public.team_profiles(team_id, team_name, captain_arqon_id, updated_by) values (v_team_id, v_name, v_profile.arqon_id, v_uid);
  return jsonb_build_object('id', v_team_id, 'name', v_name);
end;
$function$;

create or replace function public.respond_team_invitation(p_invitation_id uuid, p_accept boolean)
returns text language plpgsql security definer set search_path = ''
as $function$
declare
 v_inv public.team_invitations%rowtype; v_data jsonb; v_team jsonb; v_teams jsonb;
 v_profile public.profiles%rowtype; v_name text; v_role text; v_active int; v_reserve int; v_player jsonb;
begin
 select * into v_inv from public.team_invitations where id=p_invitation_id and target_user_id=(select auth.uid()) and status='pending' for update;
 if not found then raise exception 'invitation_not_found_or_processed'; end if;
 if not p_accept then update public.team_invitations set status='declined',responded_at=now() where id=p_invitation_id; return 'declined'; end if;
 select * into v_profile from public.profiles where user_id=(select auth.uid());
 if not found then raise exception 'profile_not_found'; end if;
 select data into v_data from public.tournament where id=1 for update; v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 if exists(select 1 from jsonb_array_elements(v_teams) t, lateral jsonb_array_elements(coalesce(t->'players','[]'::jsonb)) pl where pl->>'account_id'=(select auth.uid())::text) then raise exception 'already_in_team'; end if;
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=v_inv.team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 v_active:=(select count(*) from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where coalesce(pl->>'rosterRole','main')<>'reserve');
 v_reserve:=(select count(*) from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where pl->>'rosterRole'='reserve');
 if v_active<5 then v_role:='main'; elsif v_reserve<2 then v_role:='reserve'; else raise exception 'team_roster_full'; end if;
 select coalesce(nullif(v_profile.game_nick,''),nullif(v_profile.display_name,''),pl.name,'Игрок ARQON #'||v_profile.arqon_id::text)
 into v_name from (select 1) x left join public.players pl on pl.uid=v_profile.user_id::text limit 1;
 v_player:=jsonb_build_object('name',v_name,'account_id',(select auth.uid())::text,'arqonId',v_profile.arqon_id);
 if v_profile.avatar_url is not null then v_player:=v_player||jsonb_build_object('avatar',v_profile.avatar_url); end if;
 if v_role='reserve' then v_player:=v_player||jsonb_build_object('rosterRole','reserve'); end if;
 v_teams:=jsonb_set(v_teams,array[(select ordinality-1 from jsonb_array_elements(v_teams) with ordinality e(t,ordinality) where e.t->>'id'=v_inv.team_id limit 1),'players'],coalesce(v_team->'players','[]'::jsonb)||jsonb_build_array(v_player),true);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 update public.team_invitations set status='accepted',responded_at=now() where id=p_invitation_id;
 insert into public.team_transfer_history(arqon_id,player_name,to_team_id,to_team_name,event_type) values(v_profile.arqon_id,v_name,v_inv.team_id,v_inv.team_name,'joined');
 return v_role;
end;
$function$;

create or replace function public.list_public_player_game_nicks()
returns table(arqon_id bigint, game_nick text)
language sql stable security definer set search_path = ''
as $function$
  select p.arqon_id, p.game_nick from public.profiles p
  where p.is_public = true and p.game_nick is not null and btrim(p.game_nick) <> '';
$function$;
revoke all on function public.list_public_player_game_nicks() from public;
grant execute on function public.list_public_player_game_nicks() to anon, authenticated;
