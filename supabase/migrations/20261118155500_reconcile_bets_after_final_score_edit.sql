create or replace function private.auto_settle_arqon_bets_from_match()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_event uuid; v_market record; v_winner uuid;
begin
 if new.status<>'finished' or new.score1 is null or new.score2 is null or new.score1=new.score2 then return new; end if;
 select id into v_event from public.arqon_bet_events where live_match_id=new.id and status in ('open','closed') limit 1;
 if v_event is null then return new; end if;
 for v_market in select * from public.arqon_bet_markets where event_id=v_event and status in ('open','closed') loop
  v_winner:=null;
  if v_market.market_type='winner' then
   select id into v_winner from public.arqon_bet_selections where market_id=v_market.id
   and selection_key=case when new.score1>new.score2 then 'team1' else 'team2' end limit 1;
  elsif v_market.market_type='exact_score' then
   select id into v_winner from public.arqon_bet_selections where market_id=v_market.id
   and selection_key=new.score1::text||':'||new.score2::text limit 1;
  end if;
  if v_winner is not null then perform private.settle_arqon_bet_market(v_market.id,v_winner,null); end if;
 end loop;
 return new;
end $$;