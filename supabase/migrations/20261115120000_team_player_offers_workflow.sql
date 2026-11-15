-- Team-to-player recruitment offers. This migration is idempotent so it can
-- also document the schema already applied to the connected Supabase project.

create table if not exists public.team_player_offers (
  id uuid primary key default gen_random_uuid(),
  team_id text not null check (char_length(team_id) between 1 and 80),
  team_name text not null check (char_length(team_name) <= 100),
  player_user_id uuid not null references auth.users(id) on delete cascade,
  player_arqon_id bigint not null references public.profiles(arqon_id) on delete cascade,
  player_name text not null check (char_length(player_name) <= 80),
  offered_role text not null default '' check (char_length(offered_role) <= 80),
  message text not null default '' check (char_length(message) <= 500),
  status text not null default 'pending'
    check (status = any (array['pending','accepted','rejected','cancelled'])),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique(team_id,player_user_id)
);

alter table public.team_player_offers enable row level security;
revoke all on table public.team_player_offers from anon, authenticated;
grant select,insert,update,delete on table public.team_player_offers to service_role;

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

create or replace function public.list_my_team_player_offers()
returns table(id uuid,team_id text,team_name text,offered_role text,message text,status text,created_at timestamptz)
language sql stable security definer set search_path=''
as $function$
  select o.id,o.team_id,o.team_name,o.offered_role,o.message,o.status,o.created_at
  from public.team_player_offers o
  where o.player_user_id=auth.uid()
  order by o.created_at desc
$function$;

create or replace function public.respond_team_player_offer(p_offer_id uuid,p_response text)
returns text
language plpgsql security definer set search_path=''
as $function$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_response not in ('accepted','rejected') then raise exception 'invalid_response'; end if;
  update public.team_player_offers
  set status=p_response,responded_at=now()
  where id=p_offer_id and player_user_id=auth.uid() and status='pending';
  if not found then raise exception 'offer_not_found_or_closed'; end if;
  return p_response;
end
$function$;

create or replace function public.list_team_player_offers(p_team_id text)
returns table(id uuid,player_arqon_id bigint,player_name text,offered_role text,message text,status text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if auth.uid() is null or not (
    public.has_organizer_role('editor')
    or exists(
      select 1 from public.team_profiles tp
      join public.profiles pr on pr.arqon_id=tp.captain_arqon_id
      where tp.team_id=p_team_id and pr.user_id=auth.uid()
    )
  ) then raise exception 'not_authorized'; end if;
  return query
  select o.id,o.player_arqon_id,o.player_name,o.offered_role,o.message,o.status,o.created_at
  from public.team_player_offers o
  where o.team_id=p_team_id
  order by o.created_at desc;
end
$function$;

revoke all on function public.create_team_player_offer(text,bigint,text,text) from public,anon;
revoke all on function public.list_my_team_player_offers() from public,anon;
revoke all on function public.respond_team_player_offer(uuid,text) from public,anon;
revoke all on function public.list_team_player_offers(text) from public,anon;
grant execute on function public.create_team_player_offer(text,bigint,text,text) to authenticated;
grant execute on function public.list_my_team_player_offers() to authenticated;
grant execute on function public.respond_team_player_offer(uuid,text) to authenticated;
grant execute on function public.list_team_player_offers(text) to authenticated;
