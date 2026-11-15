
create or replace function public.settle_arqon_predictions()
returns trigger language plpgsql security definer set search_path=''
as $$
declare p record; v_winner text; v_amount bigint; v_settings public.arqon_prediction_settings%rowtype;
begin
  if new.status <> 'finished'
     or length(trim(coalesce(new.mvp_name,'')))=0
     or (old.status='finished' and old.score1=new.score1 and old.score2=new.score2 and old.mvp_name=new.mvp_name) then
    return new;
  end if;
  if new.score1=new.score2 then v_winner := null;
  elsif new.score1>new.score2 then v_winner := 'team1';
  else v_winner := 'team2'; end if;
  select * into v_settings from public.arqon_prediction_settings where id=true;
  for p in select * from public.arqon_predictions where live_match_id=new.id and settled_at is null for update
  loop
    update public.arqon_predictions set
      winner_correct=(v_winner is not null and predicted_winner=v_winner),
      score_correct=(predicted_score1=new.score1 and predicted_score2=new.score2),
      mvp_correct=(lower(trim(predicted_mvp))=lower(trim(new.mvp_name))),
      settled_at=now(),updated_at=now()
    where id=p.id;
    v_amount := 0;
    if v_winner is not null and p.predicted_winner=v_winner then v_amount:=v_amount+v_settings.winner_reward; end if;
    if p.predicted_score1=new.score1 and p.predicted_score2=new.score2 then v_amount:=v_amount+v_settings.score_reward; end if;
    if lower(trim(p.predicted_mvp))=lower(trim(new.mvp_name)) then v_amount:=v_amount+v_settings.mvp_reward; end if;
    update public.arqon_predictions set coins_awarded=v_amount where id=p.id;
    if v_amount>0 then
      perform public.award_arqon_coins(p.arqon_id,v_amount,'activity','Прогнозы ARQON · '||new.team1||' vs '||new.team2,'prediction:'||p.id::text);
    end if;
  end loop;
  return new;
end; $$;
revoke all on function public.settle_arqon_predictions() from public,anon,authenticated;
