create table if not exists public.arqon_automatic_achievements (
  arqon_id bigint not null references public.profiles(arqon_id) on delete cascade,
  achievement_key text not null,
  category text not null default 'live',
  achievement_name text not null,
  description text not null,
  icon text not null,
  earned_at timestamptz not null default now(),
  primary key (arqon_id, achievement_key),
  constraint arqon_automatic_achievements_key_check check (achievement_key in ('live_first_match','live_stability','live_adr_100','live_fragger','live_team_player','live_mvp')),
  constraint arqon_automatic_achievements_category_check check (category = 'live')
);
alter table public.arqon_automatic_achievements enable row level security;
revoke all on public.arqon_automatic_achievements from public;
grant select on public.arqon_automatic_achievements to anon, authenticated;
drop policy if exists "Visible automatic achievements are readable" on public.arqon_automatic_achievements;
create policy "Visible automatic achievements are readable" on public.arqon_automatic_achievements
for select to anon, authenticated using (
  exists (select 1 from public.profiles p where p.arqon_id = arqon_automatic_achievements.arqon_id
    and (p.is_public = true or p.user_id = (select auth.uid())))
);
create index if not exists arqon_automatic_achievements_profile on public.arqon_automatic_achievements (arqon_id, earned_at desc);

create or replace function public.sync_arqon_live_achievements_for_profile(p_arqon_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_names text[];
  v_match_count integer := 0;
  v_avg_kills numeric := 0;
  v_avg_assists numeric := 0;
  v_avg_adr numeric := 0;
  v_adr_count integer := 0;
  v_mvp_count integer := 0;
begin
  select array_remove(array[nullif(lower(btrim(p.display_name)), ''),nullif(lower(btrim(p.steam_persona_name)), '')], null)
  into v_names from public.profiles p where p.arqon_id = p_arqon_id;
  if not found then return; end if;
  select count(distinct s.live_match_id)::integer, coalesce(avg(s.kills),0), coalesce(avg(s.assists),0),
         coalesce(avg(s.adr) filter (where s.adr is not null),0), count(s.adr)::integer
  into v_match_count,v_avg_kills,v_avg_assists,v_avg_adr,v_adr_count
  from public.live_match_player_stats s
  where lower(btrim(s.player_name)) = any(coalesce(v_names,array[]::text[]));
  select count(*)::integer into v_mvp_count from public.live_matches m
  where lower(btrim(m.mvp_name)) = any(coalesce(v_names,array[]::text[]));

  insert into public.arqon_automatic_achievements(arqon_id,achievement_key,achievement_name,description,icon)
  select p_arqon_id,x.key,x.name,x.description,x.icon
  from (values
    ('live_first_match','Первый матч','Получил статистику хотя бы за один матч Live Center','🎮',v_match_count>=1),
    ('live_stability','Стабильность','Сыграл минимум пять матчей со внесённой статистикой','🧱',v_match_count>=5),
    ('live_adr_100','ADR 100+','Средний ADR не ниже 100 по матчам Live Center','💥',v_adr_count>0 and v_avg_adr>=100),
    ('live_fragger','Фраггер','В среднем не менее 20 убийств за матч','🔥',v_match_count>0 and v_avg_kills>=20),
    ('live_team_player','Командный игрок','В среднем не менее 8 ассистов за матч','🤝',v_match_count>0 and v_avg_assists>=8),
    ('live_mvp','MVP Live','Получил отметку MVP минимум в одном матче Live Center','🌟',v_mvp_count>=1)
  ) as x(key,name,description,icon,earned) where x.earned
  on conflict(arqon_id,achievement_key) do update set achievement_name=excluded.achievement_name,description=excluded.description,icon=excluded.icon;

  delete from public.arqon_automatic_achievements a
  where a.arqon_id=p_arqon_id and a.achievement_key in ('live_first_match','live_stability','live_adr_100','live_fragger','live_team_player','live_mvp')
  and not exists (
    select 1 from (values
      ('live_first_match',v_match_count>=1),('live_stability',v_match_count>=5),
      ('live_adr_100',v_adr_count>0 and v_avg_adr>=100),('live_fragger',v_match_count>0 and v_avg_kills>=20),
      ('live_team_player',v_match_count>0 and v_avg_assists>=8),('live_mvp',v_mvp_count>=1)
    ) as e(key,qualifies) where e.key=a.achievement_key and e.qualifies
  );
end; $$;

create or replace function public.sync_arqon_live_achievements_for_name(p_player_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_profile record; v_name text := nullif(lower(btrim(p_player_name)),'');
begin
  if v_name is null then return; end if;
  for v_profile in select p.arqon_id from public.profiles p
    where lower(btrim(coalesce(p.display_name,'')))=v_name or lower(btrim(coalesce(p.steam_persona_name,'')))=v_name
  loop perform public.sync_arqon_live_achievements_for_profile(v_profile.arqon_id); end loop;
end; $$;

create or replace function public.sync_arqon_live_achievements_from_stats()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE','DELETE') then perform public.sync_arqon_live_achievements_for_name(old.player_name); end if;
  if tg_op in ('INSERT','UPDATE') then perform public.sync_arqon_live_achievements_for_name(new.player_name); end if;
  if tg_op='DELETE' then return old; end if; return new;
end; $$;

create or replace function public.sync_arqon_live_achievements_from_mvp()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE','DELETE') then perform public.sync_arqon_live_achievements_for_name(old.mvp_name); end if;
  if tg_op in ('INSERT','UPDATE') then perform public.sync_arqon_live_achievements_for_name(new.mvp_name); end if;
  if tg_op='DELETE' then return old; end if; return new;
end; $$;

create or replace function public.sync_arqon_live_achievements_from_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin perform public.sync_arqon_live_achievements_for_profile(new.arqon_id); return new; end; $$;

drop trigger if exists arqon_live_achievements_stats_sync on public.live_match_player_stats;
create trigger arqon_live_achievements_stats_sync after insert or update or delete on public.live_match_player_stats
for each row execute function public.sync_arqon_live_achievements_from_stats();
drop trigger if exists arqon_live_achievements_mvp_sync on public.live_matches;
create trigger arqon_live_achievements_mvp_sync after insert or update of mvp_name or delete on public.live_matches
for each row execute function public.sync_arqon_live_achievements_from_mvp();
drop trigger if exists arqon_live_achievements_profile_sync on public.profiles;
create trigger arqon_live_achievements_profile_sync after insert or update of display_name,steam_persona_name on public.profiles
for each row execute function public.sync_arqon_live_achievements_from_profile();

revoke all on function public.sync_arqon_live_achievements_for_profile(bigint) from public,anon,authenticated;
revoke all on function public.sync_arqon_live_achievements_for_name(text) from public,anon,authenticated;
revoke all on function public.sync_arqon_live_achievements_from_stats() from public,anon,authenticated;
revoke all on function public.sync_arqon_live_achievements_from_mvp() from public,anon,authenticated;
revoke all on function public.sync_arqon_live_achievements_from_profile() from public,anon,authenticated;

do $$ declare r record; begin
  for r in select arqon_id from public.profiles loop perform public.sync_arqon_live_achievements_for_profile(r.arqon_id); end loop;
end; $$;
