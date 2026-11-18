create table if not exists public.arqon_bet_audit (
 id bigint generated always as identity primary key,
 event_id uuid not null references public.arqon_bet_events(id) on delete cascade,
 market_id uuid not null references public.arqon_bet_markets(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,
 action text not null check (action in ('created','odds_changed','closed','settled','voided','result_corrected')),
 old_winning_selection_id uuid,
 new_winning_selection_id uuid,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists arqon_bet_audit_market_created_idx on public.arqon_bet_audit(market_id,created_at desc);
alter table public.arqon_bet_audit enable row level security;
create policy "Admins read ARQON bet audit" on public.arqon_bet_audit
for select to authenticated using (public.has_organizer_role('admin'));
grant select on public.arqon_bet_audit to authenticated;
revoke insert,update,delete on public.arqon_bet_audit from anon,authenticated;

create or replace function public.correct_arqon_bet_market_result(p_market_id uuid,p_winning_selection_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare
 v_market public.arqon_bet_markets%rowtype;
 v_bet public.arqon_bets%rowtype;
 v_balance bigint;
 v_old_winner uuid;
 v_reversed bigint:=0;
 v_credited bigint:=0;
begin
 if auth.uid() is null or not exists (
  select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
 ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
 select * into v_market from public.arqon_bet_markets where id=p_market_id for update;
 if not found or v_market.status<>'settled' then raise exception 'market_not_already_settled'; end if;
 if not exists(select 1 from public.arqon_bet_selections s where s.id=p_winning_selection_id and s.market_id=p_market_id) then
  raise exception 'winning_selection_not_in_market';
 end if;
 v_old_winner:=v_market.winning_selection_id;
 if v_old_winner=p_winning_selection_id then return; end if;
 for v_bet in select * from public.arqon_bets where market_id=p_market_id and status in ('won','lost') order by arqon_id,id for update loop
  if v_bet.status='won' and v_bet.selection_id<>p_winning_selection_id then
   select balance into v_balance from public.arqon_coin_wallets where arqon_id=v_bet.arqon_id for update;
   if coalesce(v_balance,0)<v_bet.potential_payout then
    raise exception 'cannot_reverse_spent_winnings_for_arqon_id_%',v_bet.arqon_id;
   end if;
   update public.arqon_coin_wallets set balance=balance-v_bet.potential_payout,updated_at=now()
    where arqon_id=v_bet.arqon_id returning balance into v_balance;
   insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
    values(v_bet.arqon_id,-v_bet.potential_payout,v_balance,'admin_adjustment','Корректировка выплаты ARQON Bets','bet-correct-reverse:'||v_bet.id::text||':'||p_winning_selection_id::text);
   update public.arqon_bets set status='lost' where id=v_bet.id;
   v_reversed:=v_reversed+v_bet.potential_payout;
  elsif v_bet.status='lost' and v_bet.selection_id=p_winning_selection_id then
   insert into public.arqon_coin_wallets(arqon_id,balance) values(v_bet.arqon_id,0) on conflict(arqon_id) do nothing;
   update public.arqon_coin_wallets set balance=balance+v_bet.potential_payout,updated_at=now()
    where arqon_id=v_bet.arqon_id returning balance into v_balance;
   insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
    values(v_bet.arqon_id,v_bet.potential_payout,v_balance,'activity','Доплата после корректировки ARQON Bets','bet-correct-credit:'||v_bet.id::text||':'||p_winning_selection_id::text);
   update public.arqon_bets set status='won' where id=v_bet.id;
   v_credited:=v_credited+v_bet.potential_payout;
  end if;
 end loop;
 update public.arqon_bet_markets set winning_selection_id=p_winning_selection_id,updated_at=now() where id=p_market_id;
 insert into public.arqon_bet_audit(event_id,market_id,actor_id,action,old_winning_selection_id,new_winning_selection_id,details)
 values(v_market.event_id,p_market_id,auth.uid(),'result_corrected',v_old_winner,p_winning_selection_id,
  jsonb_build_object('reversed_coins',v_reversed,'credited_coins',v_credited));
end $$;
revoke all on function public.correct_arqon_bet_market_result(uuid,uuid) from public,anon;
grant execute on function public.correct_arqon_bet_market_result(uuid,uuid) to authenticated;