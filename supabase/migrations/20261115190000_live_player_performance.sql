create or replace view public.live_player_performance
with (security_invoker = true) as
select
  lower(btrim(player_name)) as player_key,
  min(player_name) as player_name,
  count(distinct live_match_id)::integer as matches_played,
  sum(kills)::integer as total_kills,
  sum(deaths)::integer as total_deaths,
  sum(assists)::integer as total_assists,
  round(avg(adr)::numeric, 2) as avg_adr,
  round(sum(kills)::numeric / nullif(sum(deaths), 0), 2) as kd_ratio,
  round(sum(kills)::numeric / nullif(count(distinct live_match_id), 0), 2) as kills_per_match,
  round(sum(assists)::numeric / nullif(count(distinct live_match_id), 0), 2) as assists_per_match,
  least(100, greatest(0, round(
    35 * least((sum(kills)::numeric / nullif(sum(deaths), 0)) / 1.5, 1)
    + 35 * least(avg(adr)::numeric / 120, 1)
    + 20 * least((sum(kills)::numeric / nullif(count(distinct live_match_id), 0)) / 20, 1)
    + 10 * least((sum(assists)::numeric / nullif(count(distinct live_match_id), 0)) / 8, 1)
  )))::integer as performance_index
from public.live_match_player_stats
group by lower(btrim(player_name));

grant select on public.live_player_performance to anon, authenticated;
