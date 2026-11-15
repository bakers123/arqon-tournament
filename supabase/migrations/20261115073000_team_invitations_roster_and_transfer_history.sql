-- Team invitations, controlled roster operations and public transfer history.
create table if not exists public.team_invitations (
  id uuid primary key default gen_random_uuid(),
  team_id text not null check (char_length(team_id) between 1 and 80),
  team_name text not null check (char_length(team_name) between 1 and 100),
  target_user_id uuid not null references auth.users(id) on delete cascade,
  target_arqon_id bigint not null references public.profiles(arqon_id) on delete cascade,
  invited_by uuid not null references auth.users(id),
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create unique index if not exists team_invitations_one_pending on public.team_invitations(team_id,target_user_id) where status='pending';
create index if not exists team_invitations_user_status on public.team_invitations(target_user_id,status,created_at desc);
alter table public.team_invitations enable row level security;
revoke all on public.team_invitations from anon,public;
grant select on public.team_invitations to authenticated;
drop policy if exists team_invitations_read_recipient_or_admin on public.team_invitations;
create policy team_invitations_read_recipient_or_admin on public.team_invitations for select to authenticated using (target_user_id=(select auth.uid()) or public.has_organizer_role('editor'));

create table if not exists public.team_transfer_history (
 id bigint generated always as identity primary key, arqon_id bigint, player_name text not null,
 from_team_id text, from_team_name text, to_team_id text, to_team_name text,
 event_type text not null check(event_type in ('joined','released','promoted','demoted')), created_at timestamptz not null default now()
);
create index if not exists team_transfer_history_created on public.team_transfer_history(created_at desc);
alter table public.team_transfer_history enable row level security;
revoke all on public.team_transfer_history from anon,public;
grant select on public.team_transfer_history to anon,authenticated;
drop policy if exists team_transfer_history_public_read on public.team_transfer_history;
create policy team_transfer_history_public_read on public.team_transfer_history for select to anon,authenticated using(true);

create or replace function public.create_team_invitation(p_team_id text,p_arqon_id bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_team jsonb; v_invitation uuid;
begin
 if not public.has_organizer_role('editor') then raise exception 'not_authorized'; end if;
 select pr.user_id into v_user from public.profiles pr where pr.arqon_id=p_arqon_id and pr.is_public=true;
 if v_user is null then raise exception 'player_not_found'; end if;
 select t into v_team from public.tournament tr,lateral jsonb_array_elements(tr.data->'teams') t where tr.id=1 and t->>'id'=p_team_id limit 1;
 if v_team is null then raise exception 'team_not_found'; end if;
 if exists(select 1 from public.tournament tr,lateral jsonb_array_elements(tr.data->'teams') t,lateral jsonb_array_elements(coalesce(t->'players','[]'::jsonb)) pl where tr.id=1 and pl->>'account_id'=v_user::text) then raise exception 'already_in_team'; end if;
 insert into public.team_invitations(team_id,team_name,target_user_id,target_arqon_id,invited_by) values(p_team_id,coalesce(v_team->>'name','Команда'),v_user,p_arqon_id,(select auth.uid())) returning id into v_invitation;
 return v_invitation;
exception when unique_violation then raise exception 'invitation_already_pending';
end $$;

create or replace function public.respond_team_invitation(p_invitation_id uuid,p_accept boolean) returns text
language plpgsql security definer set search_path='' as $$
declare v_inv public.team_invitations%rowtype; v_data jsonb; v_team jsonb; v_teams jsonb; v_profile public.profiles%rowtype; v_name text; v_role text; v_active int; v_reserve int; v_player jsonb; v_index text;
begin
 select * into v_inv from public.team_invitations where id=p_invitation_id and target_user_id=(select auth.uid()) and status='pending' for update;
 if not found then raise exception 'invitation_not_found_or_processed'; end if;
 if not p_accept then update public.team_invitations set status='declined',responded_at=now() where id=p_invitation_id; return 'declined'; end if;
 select * into v_profile from public.profiles where user_id=(select auth.uid());
 if not found then raise exception 'profile_not_found'; end if;
 select data into v_data from public.tournament where id=1 for update; v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 if exists(select 1 from jsonb_array_elements(v_teams) t,lateral jsonb_array_elements(coalesce(t->'players','[]'::jsonb)) pl where pl->>'account_id'=(select auth.uid())::text) then raise exception 'already_in_team'; end if;
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=v_inv.team_id limit 1; if v_team is null then raise exception 'team_not_found'; end if;
 select count(*) into v_active from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where coalesce(pl->>'rosterRole','main')<>'reserve';
 select count(*) into v_reserve from jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where pl->>'rosterRole'='reserve';
 if v_active<5 then v_role:='main'; elsif v_reserve<2 then v_role:='reserve'; else raise exception 'team_roster_full'; end if;
 select coalesce(nullif(v_profile.display_name,''),pl.name,'Игрок ARQON #'||v_profile.arqon_id::text) into v_name from (select 1) x left join public.players pl on pl.uid=v_profile.user_id::text limit 1;
 v_player:=jsonb_build_object('name',v_name,'account_id',(select auth.uid())::text,'arqonId',v_profile.arqon_id);
 if v_profile.avatar_url is not null then v_player:=v_player||jsonb_build_object('avatar',v_profile.avatar_url); end if;
 if v_role='reserve' then v_player:=v_player||jsonb_build_object('rosterRole','reserve'); end if;
 select (ordinality-1)::text into v_index from jsonb_array_elements(v_teams) with ordinality e(t,ordinality) where e.t->>'id'=v_inv.team_id limit 1;
 v_teams:=jsonb_set(v_teams,array[v_index,'players'],coalesce(v_team->'players','[]'::jsonb)||jsonb_build_array(v_player),true);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 update public.team_invitations set status='accepted',responded_at=now() where id=p_invitation_id;
 insert into public.team_transfer_history(arqon_id,player_name,to_team_id,to_team_name,event_type) values(v_profile.arqon_id,v_name,v_inv.team_id,v_inv.team_name,'joined');
 return v_role;
end $$;

create or replace function public.manage_team_roster(p_team_id text,p_account_id text,p_action text) returns text
language plpgsql security definer set search_path='' as $$
declare v_data jsonb; v_teams jsonb; v_team jsonb; v_players jsonb; v_player jsonb; v_name text; v_arqon bigint; v_team_name text; v_index int; v_active int; v_reserve int; v_new_role text;
begin
 if not public.has_organizer_role('editor') then raise exception 'not_authorized'; end if;
 if p_action not in ('promote','demote','release') then raise exception 'invalid_action'; end if;
 select data into v_data from public.tournament where id=1 for update; v_teams:=coalesce(v_data->'teams','[]'::jsonb);
 select t into v_team from jsonb_array_elements(v_teams) t where t->>'id'=p_team_id limit 1; if v_team is null then raise exception 'team_not_found'; end if;
 v_players:=coalesce(v_team->'players','[]'::jsonb);
 select pl into v_player from jsonb_array_elements(v_players) pl where pl->>'account_id'=p_account_id limit 1; if v_player is null then raise exception 'player_not_found'; end if;
 v_name:=coalesce(v_player->>'name','Игрок'); v_arqon:=nullif(v_player->>'arqonId','')::bigint; v_team_name:=v_team->>'name';
 select (ordinality-1)::int into v_index from jsonb_array_elements(v_players) with ordinality e(pl,ordinality) where e.pl->>'account_id'=p_account_id limit 1;
 if p_action='release' then
  select coalesce(jsonb_agg(pl order by ordinality),'[]'::jsonb) into v_players from jsonb_array_elements(v_players) with ordinality e(pl,ordinality) where pl->>'account_id'<>p_account_id;
  insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,event_type) values(v_arqon,v_name,p_team_id,v_team_name,'released');
 else
  select count(*) into v_active from jsonb_array_elements(v_players) pl where coalesce(pl->>'rosterRole','main')<>'reserve';
  select count(*) into v_reserve from jsonb_array_elements(v_players) pl where pl->>'rosterRole'='reserve';
  if p_action='promote' then
   if coalesce(v_player->>'rosterRole','main')<>'reserve' then raise exception 'already_main'; end if;
   if v_active>=5 then raise exception 'main_roster_full'; end if;
   v_players:=jsonb_set(v_players,array[v_index::text],v_player-'rosterRole',false); v_new_role:='main';
   insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,to_team_id,to_team_name,event_type) values(v_arqon,v_name,p_team_id,v_team_name,p_team_id,v_team_name,'promoted');
  else
   if v_player->>'rosterRole'='reserve' then raise exception 'already_reserve'; end if;
   if v_reserve>=2 then raise exception 'reserve_roster_full'; end if;
   v_players:=jsonb_set(v_players,array[v_index::text],v_player||jsonb_build_object('rosterRole','reserve'),false); v_new_role:='reserve';
   insert into public.team_transfer_history(arqon_id,player_name,from_team_id,from_team_name,to_team_id,to_team_name,event_type) values(v_arqon,v_name,p_team_id,v_team_name,p_team_id,v_team_name,'demoted');
  end if;
 end if;
 v_team:=jsonb_set(v_team,'{players}',v_players,true);
 select jsonb_agg(case when t->>'id'=p_team_id then v_team else t end order by ordinality) into v_teams from jsonb_array_elements(v_teams) with ordinality e(t,ordinality);
 update public.tournament set data=jsonb_set(v_data,'{teams}',v_teams,true) where id=1;
 return coalesce(v_new_role,p_action);
end $$;

revoke all on function public.create_team_invitation(text,bigint) from public,anon;
revoke all on function public.respond_team_invitation(uuid,boolean) from public,anon;
revoke all on function public.manage_team_roster(text,text,text) from public,anon;
grant execute on function public.create_team_invitation(text,bigint) to authenticated;
grant execute on function public.respond_team_invitation(uuid,boolean) to authenticated;
grant execute on function public.manage_team_roster(text,text,text) to authenticated;
