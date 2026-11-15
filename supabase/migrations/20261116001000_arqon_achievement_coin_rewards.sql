-- Durable achievement catalog, one-time Coins rewards and notifications.
alter table public.arqon_automatic_achievements
  drop constraint if exists arqon_automatic_achievements_key_check,
  drop constraint if exists arqon_automatic_achievements_category_check;
alter table public.arqon_automatic_achievements
  add constraint arqon_automatic_achievements_key_check check (
    achievement_key in (
      'tournament_first','tournament_podium','tournament_champion',
      'tournament_mvp','tournament_veteran','tournament_legend',
      'live_first_match','live_stability','live_adr_100',
      'live_fragger','live_team_player','live_mvp'
    )
  ),
  add constraint arqon_automatic_achievements_category_check check (category in ('live','tournament'));

create or replace function public.award_arqon_achievement_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_reward bigint; v_awarded boolean; v_user_id uuid;
begin
  v_reward := case new.achievement_key
    when 'tournament_first' then 20 when 'tournament_podium' then 30
    when 'tournament_champion' then 60 when 'tournament_mvp' then 50
    when 'tournament_veteran' then 75 when 'tournament_legend' then 150
    when 'live_first_match' then 20 when 'live_stability' then 50
    when 'live_adr_100' then 75 when 'live_fragger' then 75
    when 'live_team_player' then 50 when 'live_mvp' then 60 else 0 end;
  if v_reward<=0 then return new; end if;
  v_awarded:=public.award_arqon_coins(new.arqon_id,v_reward,'achievement',
    'Достижение «'||new.achievement_name||'»','achievement:'||new.achievement_key);
  if v_awarded then
    select p.user_id into v_user_id from public.profiles p where p.arqon_id=new.arqon_id;
    if v_user_id is not null then
      insert into public.user_notifications(user_id,notification_type,title,body,target_url,related_id)
      values(v_user_id,'system','Новое достижение ARQON!',
        'Получено «'||new.achievement_name||'». Начислено +'||v_reward||' Coins.',
        '/achievements/','achievement:'||new.arqon_id::text||':'||new.achievement_key);
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists arqon_achievement_coins_award on public.arqon_automatic_achievements;
create trigger arqon_achievement_coins_award after insert on public.arqon_automatic_achievements
for each row execute function public.award_arqon_achievement_coins();

create or replace function public.sync_arqon_tournament_achievements_for_profile(p_arqon_id bigint)
returns void language plpgsql security definer set search_path=''
as $$
declare v_names text[]; v_played integer:=0; v_podiums integer:=0; v_wins integer:=0; v_mvps integer:=0;
begin
  select array_remove(array[nullif(lower(btrim(p.display_name)),''),nullif(lower(btrim(p.steam_persona_name)), '')],null)
  into v_names from public.profiles p where p.arqon_id=p_arqon_id;
  if not found then return; end if;
  select array(select distinct n from unnest(
    coalesce(v_names,array[]::text[]) || coalesce(array(
      select nullif(lower(btrim(pl.name)),'') from public.players pl
      join public.profiles pr on pr.user_id::text=pl.uid
      where pr.arqon_id=p_arqon_id and nullif(btrim(pl.name),'') is not null
    ),array[]::text[])
  ) n where n is not null) into v_names;
  select
    count(*) filter(where lower(btrim(coalesce(r.place_1,'')))=any(coalesce(v_names,array[]::text[]))
      or lower(btrim(coalesce(r.place_2,'')))=any(coalesce(v_names,array[]::text[]))
      or lower(btrim(coalesce(r.place_3,'')))=any(coalesce(v_names,array[]::text[]))
      or lower(btrim(coalesce(r.mvp,'')))=any(coalesce(v_names,array[]::text[])))::integer,
    count(*) filter(where lower(btrim(coalesce(r.place_1,'')))=any(coalesce(v_names,array[]::text[]))
      or lower(btrim(coalesce(r.place_2,'')))=any(coalesce(v_names,array[]::text[]))
      or lower(btrim(coalesce(r.place_3,'')))=any(coalesce(v_names,array[]::text[])))::integer,
    count(*) filter(where lower(btrim(coalesce(r.place_1,'')))=any(coalesce(v_names,array[]::text[])))::integer,
    count(*) filter(where lower(btrim(coalesce(r.mvp,'')))=any(coalesce(v_names,array[]::text[])))::integer
  into v_played,v_podiums,v_wins,v_mvps from public.results r;

  insert into public.arqon_automatic_achievements(arqon_id,achievement_key,category,achievement_name,description,icon)
  select p_arqon_id,x.key,'tournament',x.name,x.description,x.icon
  from (values
    ('tournament_first','Первый результат','Попал в опубликованные результаты турнира','🎮',v_played>=1),
    ('tournament_podium','Первый пьедестал','Попал в топ-3 турнира','🥉',v_podiums>=1),
    ('tournament_champion','Чемпион','Занял первое место на турнире','🏆',v_wins>=1),
    ('tournament_mvp','MVP турнира','Получил награду самого ценного игрока турнира','⭐',v_mvps>=1),
    ('tournament_veteran','Ветеран','Пять попаданий в опубликованные результаты','🔥',v_played>=5),
    ('tournament_legend','Легенда ARQON','Пять побед на турнирах','👑',v_wins>=5)
  ) x(key,name,description,icon,earned) where x.earned
  on conflict(arqon_id,achievement_key) do update set
    achievement_name=excluded.achievement_name,description=excluded.description,icon=excluded.icon;

  delete from public.arqon_automatic_achievements a
  where a.arqon_id=p_arqon_id and a.category='tournament'
    and not exists(select 1 from (values
      ('tournament_first',v_played>=1),('tournament_podium',v_podiums>=1),
      ('tournament_champion',v_wins>=1),('tournament_mvp',v_mvps>=1),
      ('tournament_veteran',v_played>=5),('tournament_legend',v_wins>=5)
    ) e(key,qualifies) where e.key=a.achievement_key and e.qualifies);
end;
$$;

create or replace function public.sync_arqon_tournament_achievements_for_name(p_player_name text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_profile record; v_name text:=nullif(lower(btrim(p_player_name)),'');
begin
  if v_name is null then return; end if;
  for v_profile in
    select distinct p.arqon_id from public.profiles p
    left join public.players pl on pl.uid=p.user_id::text
    where lower(btrim(coalesce(p.display_name,'')))=v_name
       or lower(btrim(coalesce(p.steam_persona_name,'')))=v_name
       or lower(btrim(coalesce(pl.name,'')))=v_name
  loop perform public.sync_arqon_tournament_achievements_for_profile(v_profile.arqon_id); end loop;
end;
$$;

create or replace function public.sync_arqon_tournament_achievements_from_results()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    perform public.sync_arqon_tournament_achievements_for_name(old.place_1);
    perform public.sync_arqon_tournament_achievements_for_name(old.place_2);
    perform public.sync_arqon_tournament_achievements_for_name(old.place_3);
    perform public.sync_arqon_tournament_achievements_for_name(old.mvp);
  end if;
  if tg_op in ('INSERT','UPDATE') then
    perform public.sync_arqon_tournament_achievements_for_name(new.place_1);
    perform public.sync_arqon_tournament_achievements_for_name(new.place_2);
    perform public.sync_arqon_tournament_achievements_for_name(new.place_3);
    perform public.sync_arqon_tournament_achievements_for_name(new.mvp);
  end if;
  if tg_op='DELETE' then return old; end if; return new;
end;
$$;

create or replace function public.sync_arqon_live_achievements_from_profile()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.sync_arqon_live_achievements_for_profile(new.arqon_id);
  perform public.sync_arqon_tournament_achievements_for_profile(new.arqon_id);
  return new;
end;
$$;

drop trigger if exists arqon_tournament_achievements_results_sync on public.results;
create trigger arqon_tournament_achievements_results_sync after insert or update or delete on public.results
for each row execute function public.sync_arqon_tournament_achievements_from_results();

do $$ declare r record; begin
  for r in select arqon_id from public.profiles loop
    perform public.sync_arqon_tournament_achievements_for_profile(r.arqon_id);
    perform public.sync_arqon_live_achievements_for_profile(r.arqon_id);
  end loop;
end $$;

revoke all on function public.award_arqon_achievement_coins() from public,anon,authenticated;
revoke all on function public.sync_arqon_tournament_achievements_for_profile(bigint) from public,anon,authenticated;
revoke all on function public.sync_arqon_tournament_achievements_for_name(text) from public,anon,authenticated;
revoke all on function public.sync_arqon_tournament_achievements_from_results() from public,anon,authenticated;
revoke all on function public.sync_arqon_live_achievements_from_profile() from public,anon,authenticated;
