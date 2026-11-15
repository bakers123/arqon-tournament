
create or replace function public.get_arqon_prediction_stats(p_arqon_id bigint)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  with target_profile as (
    select arqon_id,user_id,is_public
    from public.profiles
    where arqon_id=p_arqon_id
  ),
  settled as (
    select
      p.*,
      m.title as match_title,
      m.team1,
      m.team2
    from public.arqon_predictions p
    join public.live_matches m on m.id=p.live_match_id
    where p.arqon_id=p_arqon_id and p.settled_at is not null
  ),
  totals as (
    select
      count(*)::integer as predictions,
      count(*) filter(where winner_correct)::integer as winner_correct,
      count(*) filter(where score_correct)::integer as score_correct,
      count(*) filter(where mvp_correct)::integer as mvp_correct,
      (count(*) filter(where winner_correct)
       +count(*) filter(where score_correct)
       +count(*) filter(where mvp_correct))::integer as correct_answers,
      (count(*)*3)::integer as possible_answers,
      coalesce(sum(coins_awarded),0)::bigint as coins
    from settled
  )
  select case
    when not exists(select 1 from target_profile where is_public or user_id=(select auth.uid())) then '{}'::jsonb
    else jsonb_build_object(
      'predictions',totals.predictions,
      'winner_correct',totals.winner_correct,
      'score_correct',totals.score_correct,
      'mvp_correct',totals.mvp_correct,
      'correct_answers',totals.correct_answers,
      'possible_answers',totals.possible_answers,
      'accuracy_percent',case when totals.possible_answers=0 then 0 else round(totals.correct_answers::numeric*100/totals.possible_answers,1) end,
      'coins_earned',totals.coins,
      'recent',coalesce((
        select jsonb_agg(jsonb_build_object(
          'match_title',s.match_title,'team1',s.team1,'team2',s.team2,
          'predicted_winner',s.predicted_winner,
          'predicted_score1',s.predicted_score1,'predicted_score2',s.predicted_score2,
          'predicted_mvp',s.predicted_mvp,
          'winner_correct',s.winner_correct,'score_correct',s.score_correct,
          'mvp_correct',s.mvp_correct,'coins_awarded',s.coins_awarded,'settled_at',s.settled_at
        ) order by s.settled_at desc)
        from (select * from settled order by settled_at desc limit 5) s
      ),'[]'::jsonb)
    )
  end
  from totals;
$$;
revoke all on function public.get_arqon_prediction_stats(bigint) from public;
grant execute on function public.get_arqon_prediction_stats(bigint) to anon,authenticated;
