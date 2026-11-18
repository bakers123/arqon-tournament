drop policy if exists "Public reads published ARQON bet events" on public.arqon_bet_events;
create policy "Public reads published ARQON bet events" on public.arqon_bet_events
for select to anon, authenticated using (status <> 'draft' or public.has_organizer_role('admin'));
drop policy if exists "Public reads markets for published ARQON bet events" on public.arqon_bet_markets;
create policy "Public reads markets for published ARQON bet events" on public.arqon_bet_markets
for select to anon, authenticated using (exists (
 select 1 from public.arqon_bet_events e where e.id=event_id and (e.status <> 'draft' or public.has_organizer_role('admin'))
));
drop policy if exists "Public reads selections for published ARQON bet markets" on public.arqon_bet_selections;
create policy "Public reads selections for published ARQON bet markets" on public.arqon_bet_selections
for select to anon, authenticated using (exists (
 select 1 from public.arqon_bet_markets m join public.arqon_bet_events e on e.id=m.event_id
 where m.id=market_id and (e.status <> 'draft' or public.has_organizer_role('admin'))
));
drop policy if exists "Users read own ARQON bets" on public.arqon_bets;
create policy "Users read own ARQON bets" on public.arqon_bets
for select to authenticated using (user_id=(select auth.uid()) or public.has_organizer_role('admin'));
