drop view if exists public.live_player_performance;
create view public.live_player_performance
with (security_invoker = true) as
select
  lower(btrim(s.player_name)) as player_key,
  min(s.player_name) as player_name,
  count(distinct s.live_match_id)::integer as matches_played,
  sum(s.kills)::integer as total_kills,
  sum(s.deaths)::integer as total_deaths,
  sum(s.assists)::integer as total_assists,
  round(avg(s.adr)::numeric, 2) as avg_adr,
  round(coalesce(sum(s.kills)::numeric / nullif(sum(s.deaths), 0), 1.5), 2) as kd_ratio,
  round(sum(s.kills)::numeric / nullif(count(distinct s.live_match_id), 0), 2) as kills_per_match,
  round(sum(s.assists)::numeric / nullif(count(distinct s.live_match_id), 0), 2) as assists_per_match,
  least(100, greatest(0, round(
    35 * least(coalesce((sum(s.kills)::numeric / nullif(sum(s.deaths), 0)) / 1.5, 1), 1)
    + 35 * least(avg(s.adr)::numeric / 120, 1)
    + 20 * least((sum(s.kills)::numeric / nullif(count(distinct s.live_match_id), 0)) / 20, 1)
    + 10 * least((sum(s.assists)::numeric / nullif(count(distinct s.live_match_id), 0)) / 8, 1)
  )))::integer as performance_index,
  round(max(s.adr)::numeric, 2) as best_adr,
  count(distinct s.live_match_id) filter (
    where lower(btrim(coalesce(m.mvp_name,''))) = lower(btrim(s.player_name))
  )::integer as mvp_awards
from public.live_match_player_stats s
join public.live_matches m on m.id=s.live_match_id
group by lower(btrim(s.player_name));

grant select on public.live_player_performance to anon, authenticated;
