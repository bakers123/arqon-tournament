-- Remove unnecessary anonymous write-level table grants.
-- Public SELECT remains available under the existing RLS policies.
-- Authenticated organizer/player permissions are unchanged.
revoke all privileges on table
  public.arqon_player_awards,
  public.arqon_prediction_settings,
  public.live_match_chat,
  public.live_match_events,
  public.live_match_player_stats,
  public.live_matches
from anon;

grant select on table
  public.arqon_player_awards,
  public.arqon_prediction_settings,
  public.live_match_chat,
  public.live_match_events,
  public.live_match_player_stats,
  public.live_matches
to anon;
