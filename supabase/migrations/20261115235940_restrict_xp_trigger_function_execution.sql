-- Trigger-only SECURITY DEFINER routines must not be callable as public RPC endpoints.
revoke all on function public.award_arqon_xp_milestones() from public, anon, authenticated;
revoke all on function public.award_arqon_live_match_xp() from public, anon, authenticated;
revoke all on function public.sync_arqon_tournament_xp() from public, anon, authenticated;
revoke all on function public.sync_arqon_live_mvp_xp() from public, anon, authenticated;
