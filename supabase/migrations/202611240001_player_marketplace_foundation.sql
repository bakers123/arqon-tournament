create table if not exists public.manager_player_market (
  player_id text primary key references public.manager_pro_players(id) on delete cascade,
  market_status text not null default 'team_roster'
    check (market_status in ('team_roster','free_agent','transfer_listed','benched','academy','prospect','loaned','retired','unverified')),
  is_available boolean not null default true,
  current_team_id text references public.manager_pro_teams(id) on delete set null,
  current_team_name text,
  asking_fee bigint,
  salary_weekly bigint,
  status_source_url text,
  source_snapshot_date date,
  notes text,
  updated_at timestamptz not null default now(),
  constraint manager_player_market_nonnegative_values
    check ((asking_fee is null or asking_fee >= 0) and (salary_weekly is null or salary_weekly >= 0))
);
create index if not exists manager_player_market_status_idx on public.manager_player_market(market_status,is_available);
create index if not exists manager_player_market_current_team_idx on public.manager_player_market(current_team_id);
alter table public.manager_player_market enable row level security;
drop policy if exists "manager player market readable" on public.manager_player_market;
create policy "manager player market readable" on public.manager_player_market for select to anon,authenticated using (true);
revoke insert,update,delete on public.manager_player_market from anon,authenticated;
grant select on public.manager_player_market to anon,authenticated;
grant all on public.manager_player_market to service_role;

insert into public.manager_player_market(player_id,market_status,is_available,current_team_id,asking_fee,salary_weekly,notes)
select p.id,
 case when p.role ilike 'Former%' or p.team_id is null then 'unverified' else 'team_roster' end,
 case when p.role ilike 'Former%' or p.team_id is null then false else true end,
 p.team_id,greatest(25000,coalesce(p.rating,70)::bigint*2500),
 greatest(5000,coalesce(p.rating,70)::bigint*250),
 case when p.role ilike 'Former%' then 'Historical roster membership; current contract status unconfirmed'
      when p.team_id is null then 'Current status requires verification'
      else 'Team roster; available for in-game buyout' end
from public.manager_pro_players p on conflict(player_id) do nothing;

insert into public.manager_pro_players(id,discipline_id,team_id,nickname,real_name,role,rating,potential,source_url,snapshot_date) values
 ('cs2-fa-ultimate','cs2',null,'ultimate','Roland Tomkowiak','Free Agent',76,82,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-jabbi','cs2',null,'jabbi','Jakob Nygaard','Free Agent',80,84,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-k1slll','cs2',null,'k1slll','Nikita Kuzminov','Free Agent',67,82,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-motm','cs2',null,'motm','Ian Hardy','Free Agent',70,78,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-infinite','cs2',null,'Infinite','Gage Green','Free Agent',69,81,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-consti','cs2',null,'consti','Kevin Yi','Free Agent',66,80,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-shane','cs2',null,'shane','Shane Dressler','Free Agent',68,79,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-fa-peeping','cs2',null,'Peeping','Jaxon Cornwell','Free Agent',65,79,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-bench-scr0b','cs2',null,'Scr0b','Benched',64,78,'https://www.hltv.org/transfers','2026-11-24'),
 ('cs2-bench-onic','cs2',null,'onic','Benched',67,80,'https://www.hltv.org/transfers','2026-11-24')
on conflict(id) do update set nickname=excluded.nickname,real_name=excluded.real_name,role=excluded.role,source_url=excluded.source_url,snapshot_date=excluded.snapshot_date;

update public.manager_player_market m set market_status='free_agent',is_available=true,current_team_id=null,current_team_name='Former Virtus.pro',
 asking_fee=greatest(25000,coalesce(p.rating,70)::bigint*1800),salary_weekly=greatest(5000,coalesce(p.rating,70)::bigint*220),
 status_source_url='https://www.gosugamers.net/dota2/news/79066-dota-2-post-the-international-2026-roster-shuffle-tracker',
 source_snapshot_date='2026-08-24',notes='Virtus.pro disbanded its international roster; roster-shuffle tracker reported players as free agents'
from public.manager_pro_players p where m.player_id=p.id and p.id in
 ('dota2-virtus-pro-timado','dota2-virtus-pro-abed','dota2-virtus-pro-saberlight-','dota2-virtus-pro-hellscream','dota2-virtus-pro-fly');

insert into public.manager_pro_players(id,discipline_id,team_id,nickname,real_name,role,rating,potential,source_url,snapshot_date) values
 ('dota2-fa-yuma','dota2',null,'Yuma','Yuma Langlet','Free Agent • Position 1',78,87,'https://www.gosugamers.net/dota2/news/79066-dota-2-post-the-international-2026-roster-shuffle-tracker','2026-08-24'),
 ('dota2-fa-kj','dota2',null,'KJ','Matheus Santos Jungles Diniz','Free Agent • Position 5',72,82,'https://www.gosugamers.net/dota2/news/79066-dota-2-post-the-international-2026-roster-shuffle-tracker','2026-08-24')
on conflict(id) do update set real_name=excluded.real_name,role=excluded.role,source_url=excluded.source_url,snapshot_date=excluded.snapshot_date;

update public.manager_player_market m set market_status='free_agent',is_available=true,current_team_id=null,current_team_name='Former LGD Gaming',
 asking_fee=greatest(25000,coalesce(p.rating,70)::bigint*1800),salary_weekly=greatest(5000,coalesce(p.rating,70)::bigint*220),
 status_source_url='https://www.gosugamers.net/dota2/news/79066-dota-2-post-the-international-2026-roster-shuffle-tracker',
 source_snapshot_date='2026-08-24',notes='Former LGD South American roster; reported released after TI 2026'
from public.manager_pro_players p where m.player_id=p.id and p.id='dota2-lgd-thiolicor';

insert into public.manager_player_market(player_id,market_status,is_available,asking_fee,salary_weekly,status_source_url,source_snapshot_date,notes)
select p.id,'free_agent',true,greatest(25000,coalesce(p.rating,70)::bigint*1800),greatest(5000,coalesce(p.rating,70)::bigint*220),
 p.source_url,'2026-08-24','Reported free agent after LGD Gaming released its South American roster'
from public.manager_pro_players p where p.id in ('dota2-fa-yuma','dota2-fa-kj')
on conflict(player_id) do update set market_status=excluded.market_status,is_available=excluded.is_available,
 asking_fee=excluded.asking_fee,salary_weekly=excluded.salary_weekly,status_source_url=excluded.status_source_url,
 source_snapshot_date=excluded.source_snapshot_date,notes=excluded.notes;

insert into public.manager_player_market(player_id,market_status,is_available,asking_fee,salary_weekly,status_source_url,source_snapshot_date,notes)
select p.id,case when p.role='Benched' then 'benched' else 'free_agent' end,true,
 greatest(25000,coalesce(p.rating,70)::bigint*case when p.role='Benched' then 1800 else 1500 end),
 greatest(5000,coalesce(p.rating,70)::bigint*220),'https://www.hltv.org/transfers','2026-11-24',
 case when p.role='Benched' then 'HLTV transfer feed: benched, not a confirmed free agent'
 else 'HLTV transfer feed: no team / parted ways, Nov 14–21 2026' end
from public.manager_pro_players p where p.id like 'cs2-fa-%' or p.id in ('cs2-bench-scr0b','cs2-bench-onic')
on conflict(player_id) do update set market_status=excluded.market_status,is_available=excluded.is_available,
 asking_fee=excluded.asking_fee,salary_weekly=excluded.salary_weekly,status_source_url=excluded.status_source_url,
 source_snapshot_date=excluded.source_snapshot_date,notes=excluded.notes;

update public.manager_player_market m set market_status='unverified',is_available=false,
 notes='Historical roster membership only; current contract status not confirmed'
from public.manager_pro_players p where m.player_id=p.id and p.role ilike 'Former%'
 and m.market_status not in ('free_agent','transfer_listed');

update public.manager_player_market set market_status='team_roster',is_available=true,current_team_id='dota2-liquid',
 current_team_name='Team Liquid',asking_fee=greatest(25000,coalesce((select rating from public.manager_pro_players where id='dota2-liquid-wisper'),70)::bigint*2500),
 salary_weekly=greatest(5000,coalesce((select rating from public.manager_pro_players where id='dota2-liquid-wisper'),70)::bigint*250),
 status_source_url='https://liquipedia.net/dota2/Team_Liquid',source_snapshot_date='2026-11-24',
 notes='Current Team Liquid roster snapshot; not a free agent'
where player_id='dota2-liquid-wisper';
update public.manager_player_market set current_team_name='HYPERSPIRIT',notes='HLTV transfer feed: benched on HYPERSPIRIT, not a confirmed free agent' where player_id='cs2-bench-scr0b';
update public.manager_player_market set current_team_id='cs2-inner-circle',current_team_name='Inner Circle',notes='HLTV transfer feed: benched on Inner Circle, not a confirmed free agent' where player_id='cs2-bench-onic';
