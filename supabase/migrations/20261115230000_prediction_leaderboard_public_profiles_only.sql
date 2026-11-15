
create or replace function public.get_arqon_prediction_leaderboard(p_limit integer default 10)
returns table(arqon_id bigint, display_name text, predictions_count bigint, correct_answers bigint, coins_earned bigint)
language sql
stable
security definer
set search_path=''
as $$
  select
    p.arqon_id,
    coalesce(nullif(trim(pr.display_name),''),'Игрок #'||p.arqon_id::text) as display_name,
    count(*)::bigint as predictions_count,
    (count(*) filter(where p.winner_correct is true)
      + count(*) filter(where p.score_correct is true)
      + count(*) filter(where p.mvp_correct is true))::bigint as correct_answers,
    coalesce(sum(p.coins_awarded),0)::bigint as coins_earned
  from public.arqon_predictions p
  join public.profiles pr on pr.arqon_id=p.arqon_id and pr.is_public is true
  where p.settled_at is not null
  group by p.arqon_id,pr.display_name
  order by coins_earned desc,correct_answers desc,predictions_count desc,p.arqon_id asc
  limit greatest(1,least(coalesce(p_limit,10),50));
$$;
revoke all on function public.get_arqon_prediction_leaderboard(integer) from public;
grant execute on function public.get_arqon_prediction_leaderboard(integer) to anon,authenticated;
