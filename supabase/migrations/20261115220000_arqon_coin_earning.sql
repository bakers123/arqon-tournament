-- Award ARQON Coins for tournament results, Live Center participation, and achievements.
-- Rewards are server-side, idempotent and cannot be minted from client requests.
create or replace function public.award_arqon_coins(
  p_arqon_id bigint,
  p_amount bigint,
  p_transaction_type text,
  p_description text,
  p_reference_key text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_balance bigint;
begin
  if p_arqon_id is null or p_amount is null or p_amount<=0
     or p_transaction_type not in ('activity','achievement','tournament')
     or p_reference_key is null or length(p_reference_key)>180 then
    raise exception 'Invalid ARQON Coins reward';
  end if;
  insert into public.arqon_coin_wallets(arqon_id,balance)
    values(p_arqon_id,0) on conflict(arqon_id) do nothing;
  select balance into v_balance from public.arqon_coin_wallets
    where arqon_id=p_arqon_id for update;
  if exists(select 1 from public.arqon_coin_transactions
      where arqon_id=p_arqon_id and transaction_type=p_transaction_type
        and reference_key=p_reference_key) then
    return false;
  end if;
  update public.arqon_coin_wallets set balance=balance+p_amount,updated_at=now()
    where arqon_id=p_arqon_id returning balance into v_balance;
  insert into public.arqon_coin_transactions(
    arqon_id,amount,balance_after,transaction_type,description,reference_key
  ) values(
    p_arqon_id,p_amount,v_balance,p_transaction_type,
    left(coalesce(p_description,'Награда ARQON'),180),p_reference_key
  );
  return true;
end;
$$;
revoke all on function public.award_arqon_coins(bigint,bigint,text,text,text) from public,anon,authenticated;

create or replace function public.award_arqon_tournament_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
declare r record;
begin
  for r in
    select pr.arqon_id,
      (case when bool_or(lower(btrim(pl.name))=lower(btrim(new.place_1))) then 100
            when bool_or(lower(btrim(pl.name))=lower(btrim(new.place_2))) then 70
            when bool_or(lower(btrim(pl.name))=lower(btrim(new.place_3))) then 50 else 0 end)
      + (case when bool_or(new.mvp is not null and lower(btrim(pl.name))=lower(btrim(new.mvp))) then 50 else 0 end) as coins
    from public.players pl
    join public.profiles pr on pr.user_id::text=pl.uid
    where lower(btrim(pl.name)) in (
      lower(btrim(new.place_1)),lower(btrim(new.place_2)),
      lower(btrim(new.place_3)),lower(btrim(coalesce(new.mvp,'')))
    )
    group by pr.arqon_id
  loop
    if r.coins>0 then
      perform public.award_arqon_coins(
        r.arqon_id,r.coins,'tournament',
        'Награда турнира: '||coalesce(new.tournament_name,'Турнир ARQON'),
        'result:'||new.id::text
      );
    end if;
  end loop;
  return new;
end;
$$;
drop trigger if exists arqon_tournament_coins_award on public.results;
create trigger arqon_tournament_coins_award
after insert on public.results for each row
execute function public.award_arqon_tournament_coins();

create or replace function public.award_arqon_live_activity_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_arqon_id bigint; v_label text;
begin
  select pr.arqon_id into v_arqon_id
  from public.players pl join public.profiles pr on pr.user_id::text=pl.uid
  where lower(btrim(pl.name))=lower(btrim(new.player_name))
  order by pr.arqon_id limit 1;
  if v_arqon_id is not null then
    select coalesce(title,'Матч Live Center') into v_label
      from public.live_matches where id=new.live_match_id;
    perform public.award_arqon_coins(
      v_arqon_id,10,'activity',
      'Участие в Live Center: '||coalesce(v_label,'матч'),
      'live:'||new.live_match_id::text||':player:'||v_arqon_id::text
    );
  end if;
  return new;
end;
$$;
drop trigger if exists arqon_live_activity_coins_award on public.live_match_player_stats;
create trigger arqon_live_activity_coins_award
after insert on public.live_match_player_stats for each row
execute function public.award_arqon_live_activity_coins();

create or replace function public.award_arqon_live_mvp_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_arqon_id bigint;
begin
  if new.mvp_name is null or (tg_op='UPDATE' and old.mvp_name is not null) then
    return new;
  end if;
  select pr.arqon_id into v_arqon_id
  from public.players pl join public.profiles pr on pr.user_id::text=pl.uid
  where lower(btrim(pl.name))=lower(btrim(new.mvp_name))
  order by pr.arqon_id limit 1;
  if v_arqon_id is not null then
    perform public.award_arqon_coins(
      v_arqon_id,50,'activity',
      'MVP матча Live Center: '||coalesce(new.title,'матч'),
      'live:'||new.id::text||':mvp'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists arqon_live_mvp_coins_award on public.live_matches;
create trigger arqon_live_mvp_coins_award
after insert or update of mvp_name on public.live_matches
for each row execute function public.award_arqon_live_mvp_coins();

create or replace function public.award_arqon_xp_milestone_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.source_type='achievement' then
    perform public.award_arqon_coins(
      new.arqon_id,new.xp_amount,'achievement',
      'Награда за достижение: '||coalesce(new.source_label,'ARQON'),
      'xp-milestone:'||new.source_key
    );
  end if;
  return new;
end;
$$;
drop trigger if exists arqon_xp_milestone_coins_award on public.arqon_xp_events;
create trigger arqon_xp_milestone_coins_award
after insert on public.arqon_xp_events
for each row execute function public.award_arqon_xp_milestone_coins();

create or replace function public.award_arqon_manual_award_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_amount bigint;
begin
  if new.revoked_at is not null then return new; end if;
  v_amount:=case new.rarity
    when 'common' then 25 when 'rare' then 50
    when 'epic' then 100 when 'legendary' then 200 else 0 end;
  if v_amount>0 then
    perform public.award_arqon_coins(
      new.arqon_id,v_amount,'achievement',
      'Награда профиля: '||coalesce(new.award_name,'ARQON'),
      'player-award:'||new.id::text
    );
  end if;
  return new;
end;
$$;
drop trigger if exists arqon_manual_award_coins on public.arqon_player_awards;
create trigger arqon_manual_award_coins
after insert on public.arqon_player_awards
for each row execute function public.award_arqon_manual_award_coins();

-- Backfill existing tournament placements, Live Center stats/MVPs and active profile awards.
do $$
declare r record;
begin
  for r in
    select pr.arqon_id,
      (case when bool_or(lower(btrim(pl.name))=lower(btrim(res.place_1))) then 100
            when bool_or(lower(btrim(pl.name))=lower(btrim(res.place_2))) then 70
            when bool_or(lower(btrim(pl.name))=lower(btrim(res.place_3))) then 50 else 0 end)
      + (case when bool_or(res.mvp is not null and lower(btrim(pl.name))=lower(btrim(res.mvp))) then 50 else 0 end) as coins,
      res.id,res.tournament_name
    from public.results res join public.players pl
      on lower(btrim(pl.name)) in (lower(btrim(res.place_1)),lower(btrim(res.place_2)),lower(btrim(res.place_3)),lower(btrim(coalesce(res.mvp,''))))
    join public.profiles pr on pr.user_id::text=pl.uid
    group by pr.arqon_id,res.id,res.tournament_name
  loop
    if r.coins>0 then perform public.award_arqon_coins(
      r.arqon_id,r.coins,'tournament',
      'Награда турнира: '||coalesce(r.tournament_name,'Турнир ARQON'),
      'result:'||r.id::text
    ); end if;
  end loop;
  for r in
    select distinct on (pr.arqon_id,ls.live_match_id)
      pr.arqon_id,ls.live_match_id,coalesce(lm.title,'Матч Live Center') as label
    from public.live_match_player_stats ls
    join public.players pl on lower(btrim(pl.name))=lower(btrim(ls.player_name))
    join public.profiles pr on pr.user_id::text=pl.uid
    left join public.live_matches lm on lm.id=ls.live_match_id
    order by pr.arqon_id,ls.live_match_id,ls.created_at
  loop
    perform public.award_arqon_coins(
      r.arqon_id,10,'activity','Участие в Live Center: '||r.label,
      'live:'||r.live_match_id::text||':player:'||r.arqon_id::text
    );
  end loop;
  for r in
    select lm.id,lm.title,lm.mvp_name,pr.arqon_id
    from public.live_matches lm
    join public.players pl on lower(btrim(pl.name))=lower(btrim(lm.mvp_name))
    join public.profiles pr on pr.user_id::text=pl.uid
    where lm.mvp_name is not null
  loop
    perform public.award_arqon_coins(
      r.arqon_id,50,'activity','MVP матча Live Center: '||coalesce(r.title,'матч'),
      'live:'||r.id::text||':mvp'
    );
  end loop;
  for r in
    select id,arqon_id,award_name,rarity
    from public.arqon_player_awards where revoked_at is null
  loop
    perform public.award_arqon_coins(
      r.arqon_id,
      case r.rarity when 'common' then 25 when 'rare' then 50 when 'epic' then 100 when 'legendary' then 200 else 0 end,
      'achievement','Награда профиля: '||coalesce(r.award_name,'ARQON'),
      'player-award:'||r.id::text
    );
  end loop;
end;
$$;

-- Trigger-only functions must not be callable as public RPC endpoints.
revoke all on function public.award_arqon_tournament_coins() from public,anon,authenticated;
revoke all on function public.award_arqon_live_activity_coins() from public,anon,authenticated;
revoke all on function public.award_arqon_live_mvp_coins() from public,anon,authenticated;
revoke all on function public.award_arqon_xp_milestone_coins() from public,anon,authenticated;
revoke all on function public.award_arqon_manual_award_coins() from public,anon,authenticated;
