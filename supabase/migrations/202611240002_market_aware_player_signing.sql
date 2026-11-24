create or replace function public.manager_sign_player(p_user_id uuid,p_player_id text)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
 v_club public.manager_clubs;
 v_player public.manager_pro_players;
 v_market public.manager_player_market;
 v_count int;
 v_price bigint;
 v_salary bigint;
 v_contract uuid;
begin
 select * into v_club from public.manager_clubs where owner_user_id=p_user_id for update;
 if not found then raise exception 'club_not_found'; end if;
 select * into v_player from public.manager_pro_players where id=p_player_id;
 if not found then raise exception 'player_not_found'; end if;
 select * into v_market from public.manager_player_market where player_id=p_player_id;
 if not found or not v_market.is_available or v_market.market_status in ('loaned','retired','unverified') then
   raise exception 'player_not_available';
 end if;
 select count(*) into v_count from public.manager_contracts c
 join public.manager_pro_players p on p.id=c.pro_player_id
 where c.club_id=v_club.id and c.status='active' and p.discipline_id=v_player.discipline_id;
 if v_count>=5 then raise exception 'roster_full'; end if;
 if exists(select 1 from public.manager_contracts where pro_player_id=p_player_id and status='active') then
   raise exception 'player_unavailable';
 end if;
 v_price:=coalesce(v_market.asking_fee,greatest(25000,coalesce(v_player.rating,70)::bigint*
   case v_market.market_status when 'free_agent' then 1500 when 'benched' then 1800
   when 'academy' then 2000 when 'prospect' then 1800 when 'transfer_listed' then 2200 else 2500 end));
 v_salary:=coalesce(v_market.salary_weekly,greatest(5000,coalesce(v_player.rating,70)::bigint*250));
 if v_club.balance<v_price then raise exception 'insufficient_funds'; end if;
 update public.manager_clubs set balance=balance-v_price,updated_at=now() where id=v_club.id returning * into v_club;
 insert into public.manager_contracts(club_id,pro_player_id,role,salary_weekly)
 values(v_club.id,p_player_id,v_player.role,v_salary) returning id into v_contract;
 insert into public.manager_player_progress(contract_id,club_id,pro_player_id) values(v_contract,v_club.id,p_player_id);
 insert into public.manager_wallet_ledger(club_id,amount,balance_after,reason,reference_id)
 values(v_club.id,-v_price,v_club.balance,'player_signing',p_player_id);
 return jsonb_build_object('ok',true,'balance',v_club.balance,'player',v_player.nickname,
   'fee',v_price,'salary_weekly',v_salary,'market_status',v_market.market_status);
end
$function$;
revoke all on function public.manager_sign_player(uuid,text) from public,anon,authenticated;
grant execute on function public.manager_sign_player(uuid,text) to service_role;
