create table if not exists public.arqon_bet_events (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 3 and 140),
  description text not null default '' check (char_length(description) <= 1000),
  starts_at timestamptz not null,
  live_match_id uuid unique references public.live_matches(id) on delete set null,
  status text not null default 'open' check (status in ('draft','open','closed','settled','cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.arqon_bet_markets (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.arqon_bet_events(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 2 and 120),
  market_type text not null default 'custom' check (market_type in ('winner','exact_score','map_winner','total_rounds','custom')),
  min_stake bigint not null default 10 check (min_stake between 1 and 1000000),
  max_stake bigint not null default 1000 check (max_stake between min_stake and 10000000),
  status text not null default 'open' check (status in ('open','closed','settled','void')),
  winning_selection_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.arqon_bet_selections (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.arqon_bet_markets(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 100),
  selection_key text not null check (char_length(selection_key) between 1 and 80),
  odds numeric(8,3) not null check (odds between 1.010 and 100.000),
  pool_amount bigint not null default 0 check (pool_amount >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (market_id, selection_key),
  unique (id, market_id)
);

alter table public.arqon_bet_markets
  add constraint arqon_bet_markets_winning_selection_fk
  foreign key (winning_selection_id) references public.arqon_bet_selections(id) on delete set null;

create table if not exists public.arqon_bets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  arqon_id bigint not null references public.profiles(arqon_id) on delete cascade,
  event_id uuid not null references public.arqon_bet_events(id) on delete cascade,
  market_id uuid not null references public.arqon_bet_markets(id) on delete cascade,
  selection_id uuid not null references public.arqon_bet_selections(id),
  stake bigint not null check (stake > 0),
  odds_locked numeric(8,3) not null check (odds_locked between 1.010 and 100.000),
  potential_payout bigint not null check (potential_payout >= 0),
  status text not null default 'pending' check (status in ('pending','won','lost','void')),
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create index if not exists arqon_bet_events_status_start_idx on public.arqon_bet_events(status, starts_at);
create index if not exists arqon_bet_markets_event_status_idx on public.arqon_bet_markets(event_id, status);
create index if not exists arqon_bet_selections_market_idx on public.arqon_bet_selections(market_id);
create index if not exists arqon_bets_user_created_idx on public.arqon_bets(user_id, created_at desc);
create index if not exists arqon_bets_market_status_idx on public.arqon_bets(market_id, status);

alter table public.arqon_bet_events enable row level security;
alter table public.arqon_bet_markets enable row level security;
alter table public.arqon_bet_selections enable row level security;
alter table public.arqon_bets enable row level security;

create policy "Public reads published ARQON bet events" on public.arqon_bet_events
for select to anon, authenticated using (status <> 'draft' or exists (
  select 1 from private.organizer_roles r where r.user_id = (select auth.uid()) and r.role in ('owner','admin')
));
create policy "Public reads markets for published ARQON bet events" on public.arqon_bet_markets
for select to anon, authenticated using (exists (
  select 1 from public.arqon_bet_events e where e.id = event_id and
  (e.status <> 'draft' or exists (select 1 from private.organizer_roles r where r.user_id = (select auth.uid()) and r.role in ('owner','admin')))
));
create policy "Public reads selections for published ARQON bet markets" on public.arqon_bet_selections
for select to anon, authenticated using (exists (
  select 1 from public.arqon_bet_markets m join public.arqon_bet_events e on e.id=m.event_id
  where m.id=market_id and (e.status <> 'draft' or exists (select 1 from private.organizer_roles r where r.user_id=(select auth.uid()) and r.role in ('owner','admin')))
));
create policy "Users read own ARQON bets" on public.arqon_bets
for select to authenticated using (
  user_id = (select auth.uid()) or exists (
    select 1 from private.organizer_roles r where r.user_id=(select auth.uid()) and r.role in ('owner','admin')
  )
);

grant select on public.arqon_bet_events, public.arqon_bet_markets, public.arqon_bet_selections to anon, authenticated;
grant select on public.arqon_bets to authenticated;
revoke insert, update, delete on public.arqon_bet_events, public.arqon_bet_markets, public.arqon_bet_selections, public.arqon_bets from anon, authenticated;

create or replace function public.create_arqon_bet_event(
  p_title text, p_description text, p_starts_at timestamptz, p_live_match_id uuid default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  if p_starts_at is null or p_starts_at <= now() then raise exception 'event_start_must_be_future'; end if;
  if p_live_match_id is not null and not exists(select 1 from public.live_matches m where m.id=p_live_match_id) then
    raise exception 'live_match_not_found';
  end if;
  insert into public.arqon_bet_events(title,description,starts_at,live_match_id,created_by)
  values(left(btrim(p_title),140),coalesce(left(p_description,1000),''),p_starts_at,p_live_match_id,auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.create_arqon_bet_market(
  p_event_id uuid, p_title text, p_market_type text, p_min_stake bigint, p_max_stake bigint, p_selections jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_market uuid; v_item jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  if not exists(select 1 from public.arqon_bet_events e where e.id=p_event_id and e.status in ('draft','open') and e.starts_at>now()) then
    raise exception 'event_not_open';
  end if;
  if jsonb_typeof(p_selections)<>'array' or jsonb_array_length(p_selections)<2 or jsonb_array_length(p_selections)>30 then
    raise exception 'market_requires_2_to_30_selections';
  end if;
  if p_min_stake is null or p_max_stake is null or p_min_stake<1 or p_max_stake<p_min_stake or p_max_stake>10000000 then
    raise exception 'invalid_stake_limits';
  end if;
  insert into public.arqon_bet_markets(event_id,title,market_type,min_stake,max_stake)
  values(p_event_id,left(btrim(p_title),120),p_market_type,p_min_stake,p_max_stake) returning id into v_market;
  for v_item in select value from jsonb_array_elements(p_selections) loop
    if coalesce(length(btrim(v_item->>'label')),0) not between 1 and 100
       or coalesce(length(v_item->>'key'),0) not between 1 and 80
       or coalesce((v_item->>'odds')::numeric,0)<1.010
       or coalesce((v_item->>'odds')::numeric,0)>100 then raise exception 'invalid_market_selection'; end if;
    insert into public.arqon_bet_selections(market_id,label,selection_key,odds)
    values(v_market,left(btrim(v_item->>'label'),100),v_item->>'key',(v_item->>'odds')::numeric);
  end loop;
  return v_market;
end;
$$;

create or replace function public.update_arqon_bet_odds(p_selection_id uuid, p_odds numeric)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  if p_odds<1.010 or p_odds>100 then raise exception 'odds_out_of_range'; end if;
  update public.arqon_bet_selections s set odds=round(p_odds,3)
  from public.arqon_bet_markets m join public.arqon_bet_events e on e.id=m.event_id
  where s.id=p_selection_id and s.market_id=m.id and m.status='open' and e.status='open' and e.starts_at>now();
  if not found then raise exception 'selection_not_open'; end if;
end;
$$;

create or replace function public.place_arqon_bet(p_selection_id uuid, p_stake bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_event public.arqon_bet_events%rowtype;
 v_market public.arqon_bet_markets%rowtype; v_selection public.arqon_bet_selections%rowtype;
 v_balance bigint; v_bet uuid; v_payout bigint;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode='42501'; end if;
  if p_stake is null or p_stake<1 then raise exception 'invalid_stake'; end if;
  select * into v_profile from public.profiles p where p.user_id=v_uid;
  if not found then raise exception 'profile_required'; end if;
  select s.* into v_selection from public.arqon_bet_selections s where s.id=p_selection_id;
  if not found then raise exception 'selection_not_found'; end if;
  select * into v_market from public.arqon_bet_markets m where m.id=v_selection.market_id for update;
  select * into v_event from public.arqon_bet_events e where e.id=v_market.event_id for update;
  if v_event.status<>'open' or v_market.status<>'open' or v_event.starts_at<=now() then raise exception 'betting_closed'; end if;
  if p_stake<v_market.min_stake or p_stake>v_market.max_stake then raise exception 'stake_out_of_range'; end if;
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
end;
$$;

create or replace function private.settle_arqon_bet_market(p_market_id uuid,p_winning_selection_id uuid,p_actor uuid default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_market public.arqon_bet_markets%rowtype; v_bet public.arqon_bets%rowtype; v_balance bigint;
begin
  select * into v_market from public.arqon_bet_markets where id=p_market_id for update;
  if not found or v_market.status not in ('open','closed') then return; end if;
  if not exists(select 1 from public.arqon_bet_selections s where s.id=p_winning_selection_id and s.market_id=p_market_id) then
    raise exception 'winning_selection_not_in_market';
  end if;
  update public.arqon_bet_markets set status='settled',winning_selection_id=p_winning_selection_id,updated_at=now() where id=p_market_id;
  for v_bet in select * from public.arqon_bets where market_id=p_market_id and status='pending' for update loop
    if v_bet.selection_id=p_winning_selection_id then
      insert into public.arqon_coin_wallets(arqon_id,balance) values(v_bet.arqon_id,0) on conflict(arqon_id) do nothing;
      update public.arqon_coin_wallets set balance=balance+v_bet.potential_payout,updated_at=now()
        where arqon_id=v_bet.arqon_id returning balance into v_balance;
      insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
      values(v_bet.arqon_id,v_bet.potential_payout,v_balance,'activity','Выигрыш ARQON Bets','bet-win:'||v_bet.id::text);
      update public.arqon_bets set status='won',settled_at=now() where id=v_bet.id;
    else
      update public.arqon_bets set status='lost',settled_at=now() where id=v_bet.id;
    end if;
  end loop;
  update public.arqon_bet_events e set status='settled',updated_at=now()
  where e.id=v_market.event_id and not exists(
    select 1 from public.arqon_bet_markets m where m.event_id=e.id and m.status not in ('settled','void')
  );
end;
$$;

create or replace function public.settle_arqon_bet_market(p_market_id uuid,p_winning_selection_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  perform private.settle_arqon_bet_market(p_market_id,p_winning_selection_id,auth.uid());
end;
$$;

create or replace function public.void_arqon_bet_market(p_market_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_bet public.arqon_bets%rowtype; v_balance bigint; v_event uuid;
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  update public.arqon_bet_markets set status='void',updated_at=now() where id=p_market_id and status in ('open','closed') returning event_id into v_event;
  if v_event is null then raise exception 'market_not_voidable'; end if;
  for v_bet in select * from public.arqon_bets where market_id=p_market_id and status='pending' for update loop
    update public.arqon_coin_wallets set balance=balance+v_bet.stake,updated_at=now()
      where arqon_id=v_bet.arqon_id returning balance into v_balance;
    insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
    values(v_bet.arqon_id,v_bet.stake,v_balance,'refund','Возврат ставки ARQON Bets','bet-refund:'||v_bet.id::text);
    update public.arqon_bets set status='void',settled_at=now() where id=v_bet.id;
  end loop;
  update public.arqon_bet_events e set status='settled',updated_at=now()
  where e.id=v_event and not exists(select 1 from public.arqon_bet_markets m where m.event_id=e.id and m.status not in ('settled','void'));
end;
$$;

create or replace function public.close_arqon_bet_event(p_event_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  update public.arqon_bet_events set status='closed',updated_at=now() where id=p_event_id and status='open';
  if not found then raise exception 'event_not_open'; end if;
  update public.arqon_bet_markets set status='closed',updated_at=now() where event_id=p_event_id and status='open';
end;
$$;

create or replace function public.recalculate_arqon_bet_odds(p_market_id uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_total numeric; v_count integer; v_updated integer:=0; v_row record; v_odds numeric;
begin
  if auth.uid() is null or not exists (
    select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then raise exception 'not_authorized_admin' using errcode='42501'; end if;
  select count(*),coalesce(sum(pool_amount),0) into v_count,v_total
  from public.arqon_bet_selections where market_id=p_market_id and is_active;
  if v_count<2 then raise exception 'market_requires_multiple_selections'; end if;
  if not exists(select 1 from public.arqon_bet_markets m join public.arqon_bet_events e on e.id=m.event_id where m.id=p_market_id and m.status='open' and e.status='open' and e.starts_at>now()) then
    raise exception 'market_not_open';
  end if;
  for v_row in select id,pool_amount from public.arqon_bet_selections where market_id=p_market_id and is_active loop
    if v_total=0 then v_odds:=round(0.95*v_count,3);
    else v_odds:=round(least(100,greatest(1.01,0.95*(v_total+v_count*10)/(v_row.pool_amount+10))),3); end if;
    update public.arqon_bet_selections set odds=v_odds where id=v_row.id;
    v_updated:=v_updated+1;
  end loop;
  return v_updated;
end;
$$;

create or replace function private.auto_settle_arqon_bets_from_match()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_event uuid; v_market record; v_winner uuid; v_total integer;
begin
  if new.status<>'finished' or old.status='finished' or new.score1 is null or new.score2 is null then return new; end if;
  if new.score1=new.score2 then return new; end if;
  select id into v_event from public.arqon_bet_events where live_match_id=new.id and status in ('open','closed') limit 1;
  if v_event is null then return new; end if;
  v_total:=new.score1+new.score2;
  for v_market in select * from public.arqon_bet_markets where event_id=v_event and status in ('open','closed') loop
    v_winner:=null;
    if v_market.market_type='winner' then
      select id into v_winner from public.arqon_bet_selections where market_id=v_market.id and selection_key=case when new.score1>new.score2 then 'team1' else 'team2' end limit 1;
    elsif v_market.market_type='exact_score' then
      select id into v_winner from public.arqon_bet_selections where market_id=v_market.id and selection_key=new.score1::text||':'||new.score2::text limit 1;
    elsif v_market.market_type='total_rounds' then
      select id into v_winner from public.arqon_bet_selections
      where market_id=v_market.id and (
        (selection_key like 'over:%' and v_total>split_part(selection_key,':',2)::numeric) or
        (selection_key like 'under:%' and v_total<split_part(selection_key,':',2)::numeric) or
        (selection_key='exact:'||v_total::text)
      ) limit 1;
    end if;
    if v_winner is not null then perform private.settle_arqon_bet_market(v_market.id,v_winner,null); end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists arqon_auto_settle_bets_from_live_match on public.live_matches;
create trigger arqon_auto_settle_bets_from_live_match
after update of status,score1,score2 on public.live_matches
for each row execute function private.auto_settle_arqon_bets_from_match();

revoke all on function private.settle_arqon_bet_market(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function private.auto_settle_arqon_bets_from_match() from public, anon, authenticated;
revoke all on function public.create_arqon_bet_event(text,text,timestamptz,uuid) from public, anon;
revoke all on function public.create_arqon_bet_market(uuid,text,text,bigint,bigint,jsonb) from public, anon;
revoke all on function public.update_arqon_bet_odds(uuid,numeric) from public, anon;
revoke all on function public.place_arqon_bet(uuid,bigint) from public, anon;
revoke all on function public.settle_arqon_bet_market(uuid,uuid) from public, anon;
revoke all on function public.void_arqon_bet_market(uuid) from public, anon;
revoke all on function public.close_arqon_bet_event(uuid) from public, anon;
revoke all on function public.recalculate_arqon_bet_odds(uuid) from public, anon;
grant execute on function public.create_arqon_bet_event(text,text,timestamptz,uuid) to authenticated;
grant execute on function public.create_arqon_bet_market(uuid,text,text,bigint,bigint,jsonb) to authenticated;
grant execute on function public.update_arqon_bet_odds(uuid,numeric) to authenticated;
grant execute on function public.place_arqon_bet(uuid,bigint) to authenticated;
grant execute on function public.settle_arqon_bet_market(uuid,uuid) to authenticated;
grant execute on function public.void_arqon_bet_market(uuid) to authenticated;
grant execute on function public.close_arqon_bet_event(uuid) to authenticated;
grant execute on function public.recalculate_arqon_bet_odds(uuid) to authenticated;
