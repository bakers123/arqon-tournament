create index if not exists arqon_bet_events_created_by_idx on public.arqon_bet_events(created_by);
create index if not exists arqon_bet_markets_winning_selection_idx on public.arqon_bet_markets(winning_selection_id);
create index if not exists arqon_bets_arqon_id_idx on public.arqon_bets(arqon_id);
create index if not exists arqon_bets_event_id_idx on public.arqon_bets(event_id);
create index if not exists arqon_bets_selection_id_idx on public.arqon_bets(selection_id);