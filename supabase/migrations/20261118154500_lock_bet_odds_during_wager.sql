create or replace function public.place_arqon_bet(p_selection_id uuid,p_stake bigint)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_event public.arqon_bet_events%rowtype;
 v_market public.arqon_bet_markets%rowtype; v_selection public.arqon_bet_selections%rowtype;
 v_balance bigint; v_bet uuid; v_payout bigint;
begin
 if v_uid is null then raise exception 'not_authenticated' using errcode='42501'; end if;
 if p_stake is null or p_stake<1 then raise exception 'invalid_stake'; end if;
 select * into v_profile from public.profiles p where p.user_id=v_uid;
 if not found then raise exception 'profile_required'; end if;
 select s.* into v_selection from public.arqon_bet_selections s where s.id=p_selection_id;
 if not found then raise exception 'selection_not_found'; end if;
 -- Lock event before market to use the same lock order as event closure.
 select e.* into v_event from public.arqon_bet_events e
 join public.arqon_bet_markets m on m.event_id=e.id
 where m.id=v_selection.market_id for update of e;
 if not found then raise exception 'event_not_found'; end if;
 select * into v_market from public.arqon_bet_markets m where m.id=v_selection.market_id for update;
 if v_event.status<>'open' or v_market.status<>'open' or v_event.starts_at<=now() then raise exception 'betting_closed'; end if;
 if p_stake<v_market.min_stake or p_stake>v_market.max_stake then raise exception 'stake_out_of_range'; end if;
 -- Lock the outcome after the market; odds cannot change during acceptance.
 select * into v_selection from public.arqon_bet_selections s where s.id=p_selection_id and s.market_id=v_market.id for update;
 if not found or not v_selection.is_active then raise exception 'selection_not_available'; end if;
 select w.balance into v_balance from public.arqon_coin_wallets w where w.arqon_id=v_profile.arqon_id for update;
 if not found then raise exception 'coin_wallet_not_found'; end if;
 if v_balance<p_stake then raise exception 'insufficient_coins'; end if;
 v_payout:=floor(p_stake*v_selection.odds)::bigint;
 update public.arqon_coin_wallets set balance=balance-p_stake,updated_at=now()
 where arqon_id=v_profile.arqon_id returning balance into v_balance;
 insert into public.arqon_bets(user_id,arqon_id,event_id,market_id,selection_id,stake,odds_locked,potential_payout)
 values(v_uid,v_profile.arqon_id,v_event.id,v_market.id,v_selection.id,p_stake,v_selection.odds,v_payout)
 returning id into v_bet;
 insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
 values(v_profile.arqon_id,-p_stake,v_balance,'purchase','Ставка ARQON Bets · '||left(v_event.title,100),'bet-stake:'||v_bet::text);
 update public.arqon_bet_selections set pool_amount=pool_amount+p_stake where id=v_selection.id;
 return jsonb_build_object('bet_id',v_bet,'stake',p_stake,'odds',v_selection.odds,'potential_payout',v_payout,'balance_after',v_balance);
end $$;