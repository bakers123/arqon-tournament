create or replace function public.manager_simulate_match(p_user_id uuid, p_discipline_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_club public.manager_clubs;
  v_rival public.manager_pro_teams;
  v_count int;
  v_home_rating numeric;
  v_away_rating numeric;
  v_fatigue numeric;
  v_home int := 0;
  v_away int := 0;
  v_round int := 0;
  v_home_win boolean;
  v_won boolean;
  v_reward bigint;
  v_seed bigint;
  v_rounds jsonb := '[]'::jsonb;
  v_event text;
  v_home_roster jsonb;
  v_away_roster jsonb;
begin
  select * into v_club from public.manager_clubs where owner_user_id=p_user_id for update;
  if not found then raise exception 'club_not_found'; end if;

  select count(*), coalesce(avg(p.rating + coalesce(pr.rating_bonus,0) + (coalesce(pr.form,75)-75)*0.08 - coalesce(pr.fatigue,0)*0.04),70),
         coalesce(avg(pr.fatigue),0),
         jsonb_agg(jsonb_build_object('nickname',p.nickname,'role',coalesce(c.role,p.role),'rating',round((p.rating+coalesce(pr.rating_bonus,0))::numeric,1),'country',p.country_code) order by p.rating desc)
    into v_count,v_home_rating,v_fatigue,v_home_roster
  from public.manager_contracts c
  join public.manager_pro_players p on p.id=c.pro_player_id
  left join public.manager_player_progress pr on pr.contract_id=c.id
  where c.club_id=v_club.id and c.status='active' and p.discipline_id=p_discipline_id;
  if v_count<>5 then raise exception 'full_roster_required'; end if;

  select t.* into v_rival
  from public.manager_pro_teams t
  where t.discipline_id=p_discipline_id and t.is_active=true
    and not exists (select 1 from public.manager_contracts c join public.manager_pro_players p on p.id=c.pro_player_id where c.club_id=v_club.id and c.status='active' and p.team_id=t.id)
  order by random() limit 1;
  if not found then raise exception 'no_opponent_available'; end if;

  select coalesce(avg(p.rating),coalesce(v_rival.ranking_points/100,72)),
         jsonb_agg(jsonb_build_object('nickname',p.nickname,'role',p.role,'rating',p.rating,'country',p.country_code) order by p.rating desc)
    into v_away_rating,v_away_roster
  from public.manager_pro_players p where p.team_id=v_rival.id and p.discipline_id=p_discipline_id;
  v_away_rating := coalesce(v_away_rating,coalesce(v_rival.ranking_points/100,72));
  v_away_roster := coalesce(v_away_roster,'[]'::jsonb);
  v_seed := floor(extract(epoch from clock_timestamp())*1000)::bigint;

  if p_discipline_id='cs2' then
    while v_home<13 and v_away<13 and not(v_home=12 and v_away=12) loop
      v_round:=v_round+1;
      v_home_win:=random()<greatest(0.18,least(0.82,0.5+(v_home_rating-v_away_rating)*0.018));
      if v_home_win then v_home:=v_home+1; else v_away:=v_away+1; end if;
      v_event:=case when random()<0.06 then 'Клатч 1v2' when random()<0.12 then 'Двойное убийство' when random()<0.18 then 'Решающий ретейк' when random()<0.22 then 'Эйс!' when random()<0.30 then 'Открывающий фраг' when random()<0.40 then 'Победа после установки бомбы' else 'Тактический раунд' end;
      v_rounds:=v_rounds||jsonb_build_array(jsonb_build_object('round',v_round,'score_home',v_home,'score_away',v_away,'winner',case when v_home_win then 'home' else 'away' end,'event',v_event,'description',case when v_home_win then v_club.name else v_rival.name end||' забирает раунд: '||v_event));
    end loop;
    if v_home=12 and v_away=12 then
      while abs(v_home-v_away)<2 or greatest(v_home,v_away)<16 loop
        v_round:=v_round+1;
        v_home_win:=random()<greatest(0.18,least(0.82,0.5+(v_home_rating-v_away_rating)*0.018));
        if v_home_win then v_home:=v_home+1; else v_away:=v_away+1; end if;
        v_event:=case when random()<0.2 then 'Овертайм: клатч' when random()<0.4 then 'Овертайм: решающий энтри' else 'Овертайм: размен и ретейк' end;
        v_rounds:=v_rounds||jsonb_build_array(jsonb_build_object('round',v_round,'score_home',v_home,'score_away',v_away,'winner',case when v_home_win then 'home' else 'away' end,'event',v_event,'description',v_event));
        if v_round>60 then exit; end if;
      end loop;
    end if;
  else
    for v_round in 1..3 loop
      exit when v_home=2 or v_away=2;
      v_home_win:=random()<greatest(0.18,least(0.82,0.5+(v_home_rating-v_away_rating)*0.018));
      if v_home_win then v_home:=v_home+1; else v_away:=v_away+1; end if;
      v_rounds:=v_rounds||jsonb_build_array(jsonb_build_object('round',v_round,'score_home',v_home,'score_away',v_away,'winner',case when v_home_win then 'home' else 'away' end,'event','Карта завершена','description','Карта '||v_round||': '||case when v_home_win then v_club.name else v_rival.name end||' победила'));
    end loop;
  end if;

  v_won:=v_home>v_away;
  v_reward:=case when v_won then 45000 else 12000 end;
  update public.manager_clubs set balance=balance+v_reward,reputation=reputation+case when v_won then 8 else 2 end,trophies=trophies+case when v_won then 1 else 0 end,updated_at=now() where id=v_club.id returning * into v_club;
  update public.manager_player_progress pr set fatigue=least(100,pr.fatigue+12),form=greatest(40,least(100,pr.form+case when v_won then 2 else -2 end)),updated_at=now()
  from public.manager_contracts c join public.manager_pro_players p on p.id=c.pro_player_id
  where pr.contract_id=c.id and c.club_id=v_club.id and c.status='active' and p.discipline_id=p_discipline_id;

  insert into public.manager_matches(discipline_id,home_club_id,away_team_id,seed,home_score,away_score,winner,input_snapshot,result,played_at)
  values(p_discipline_id,v_club.id,v_rival.id,v_seed,v_home,v_away,case when v_won then 'home' else 'away' end,
    jsonb_build_object('club_rating',round(v_home_rating,2),'opponent_rating',round(v_away_rating,2),'average_fatigue',v_fatigue,'home_roster',v_home_roster,'away_roster',v_away_roster,'opponent',v_rival.name,'opponent_rank',v_rival.rank),
    jsonb_build_object('reward',v_reward,'winner',case when v_won then v_club.name else v_rival.name end,'rounds',v_rounds,'format',case when p_discipline_id='cs2' then 'MR12 BO1' else 'BO3' end),now());
  insert into public.manager_wallet_ledger(club_id,amount,balance_after,reason) values(v_club.id,v_reward,v_club.balance,'match_reward');
  return jsonb_build_object('ok',true,'won',v_won,'home_score',v_home,'away_score',v_away,'reward',v_reward,'balance',v_club.balance,'opponent',v_rival.name,'opponent_id',v_rival.id,'opponent_rank',v_rival.rank,'home_roster',v_home_roster,'away_roster',v_away_roster,'rounds',v_rounds,'format',case when p_discipline_id='cs2' then 'MR12 BO1' else 'BO3' end);
end
$function$;
revoke execute on function public.manager_simulate_match(uuid,text) from public, anon, authenticated;
grant execute on function public.manager_simulate_match(uuid,text) to service_role;