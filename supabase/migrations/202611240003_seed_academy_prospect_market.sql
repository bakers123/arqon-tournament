-- Seed academy teams and young prospects into the marketplace.
insert into public.manager_pro_players(id,discipline_id,team_id,nickname,real_name,role,rating,potential,source_url,snapshot_date) values
 ('cs2-academy-navi-junior-kodak','cs2','cs2-navi-junior','kodak','Nazar Buchma','Academy • IGL',68,90,'https://navi.gg/en/teams/cs2-junior','2026-11-24'),
 ('cs2-academy-navi-junior-yoki','cs2','cs2-navi-junior','yoki','Danil Istomin','Academy • AWPer',69,91,'https://navi.gg/en/teams/cs2-junior','2026-11-24'),
 ('cs2-academy-navi-junior-fazery','cs2','cs2-navi-junior','FAZERY','David Procházka','Academy • Player',70,90,'https://navi.gg/en/teams/cs2-junior','2026-11-24'),
 ('cs2-academy-navi-junior-mahar','cs2','cs2-navi-junior','MahaR','Samuel Horáček','Academy • Player',68,89,'https://navi.gg/en/teams/cs2-junior','2026-11-24'),
 ('cs2-academy-navi-junior-skizzyee','cs2','cs2-navi-junior','skizzyee','Novica Novković','Academy • Player',67,88,'https://navi.gg/en/teams/cs2-junior','2026-11-24'),
 ('cs2-academy-spirit-kiryasoo','cs2','cs2-spirit-academy','Kiryasoo','Kirill Solovkov','Academy • Player',68,89,'https://www.hltv.org/team/7900/spirit-academy','2026-11-24'),
 ('cs2-academy-spirit-vilby','cs2','cs2-spirit-academy','VILBy','Vitaly Zakharyuta','Academy • Player',67,87,'https://www.hltv.org/team/7900/spirit-academy','2026-11-24'),
 ('cs2-academy-spirit-s1nside','cs2','cs2-spirit-academy','s1nside','Nikita Besedin','Academy • Player',69,90,'https://www.hltv.org/team/7900/spirit-academy','2026-11-24'),
 ('cs2-academy-spirit-netrix','cs2','cs2-spirit-academy','Netrix','David Kudziev','Academy • Player',66,88,'https://www.hltv.org/team/7900/spirit-academy','2026-11-24'),
 ('cs2-academy-inner-3ippoch','cs2','cs2-inner-circle-academy','3ippoch','Volodymyr Sivak','Academy • IGL',67,87,'https://www.hltv.org/team/13681/inner-circle-academy','2026-11-24'),
 ('cs2-academy-inner-nayz','cs2','cs2-inner-circle-academy','NaYz','Dmytro Khylchuk','Academy • AWPer',68,89,'https://www.hltv.org/team/13681/inner-circle-academy','2026-11-24'),
 ('cs2-academy-inner-l1seyoung','cs2','cs2-inner-circle-academy','L1seYoung','Dmytro Liebidynskyi','Academy • Player',69,90,'https://www.hltv.org/team/13681/inner-circle-academy','2026-11-24'),
 ('cs2-academy-inner-tamefear','cs2','cs2-inner-circle-academy','Tamefear','Vladyslav Yurchenko','Academy • Player',66,87,'https://www.hltv.org/team/13681/inner-circle-academy','2026-11-24'),
 ('cs2-academy-inner-flierax','cs2','cs2-inner-circle-academy','Flierax',null,'Academy • Player',67,88,'https://www.hltv.org/team/13681/inner-circle-academy','2026-11-24'),
 ('cs2-prospect-tired73','cs2','cs2-wbt-academy','tired73','Andrii Hlushko','Prospect • HLTV #22',66,92,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-nikodeon','cs2',null,'Nikodeon','Nikolai Aabling Sørensen','Prospect • HLTV #23',66,91,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-slaxejezzz','cs2',null,'slaxejezzz','Vyacheslav Vinokurov','Prospect • HLTV #24',65,89,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-robo','cs2','cs2-nemiga','robo','Nikita Dushin','Prospect • HLTV #25',68,90,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-aldikon','cs2',null,'Aldikon','Aldiyar Alim','Prospect • HLTV #28',67,89,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-oz1k','cs2',null,'oz1k','Alexandr Sevastyanov','Prospect • HLTV #29',68,88,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-aquars','cs2','cs2-virtus-pro','AquaRS','Aleksandr Kovalev','Prospect • HLTV #30',67,90,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-prospect-ta9z','cs2',null,'ta9z','Maksym Hrytsai','Prospect • HLTV #32',65,90,'https://www.hltv.org/players/prospects/2026/november','2026-11-20'),
 ('cs2-bench-inner-n0rths','cs2','cs2-inner-circle-academy','n0rths','Rostyslav Zhyvun','Benched • Academy',64,82,'https://www.hltv.org/team/13681/inner-circle-academy','2026-11-24'),
 ('cs2-transfer-moon','cs2','cs2-magic','mo0N',null,'Transfer Listed',67,81,'https://www.gameofskill.gg/cs2-lineups','2026-10-06')
on conflict(id) do update set team_id=excluded.team_id,real_name=excluded.real_name,role=excluded.role,rating=excluded.rating,potential=excluded.potential,source_url=excluded.source_url,snapshot_date=excluded.snapshot_date;

insert into public.manager_player_market(player_id,market_status,is_available,current_team_id,current_team_name,asking_fee,salary_weekly,status_source_url,source_snapshot_date,notes)
select p.id,
 case when p.role like 'Academy%' then 'academy' when p.role like 'Prospect%' then 'prospect' when p.role like 'Benched%' then 'benched' else 'transfer_listed' end,
 true,p.team_id,
 case when p.id='cs2-prospect-nikodeon' then 'MOUZ NXT'
      when p.id='cs2-prospect-slaxejezzz' then 'Свободный агент'
      when p.id='cs2-prospect-aldikon' then 'Omega'
      when p.id='cs2-prospect-oz1k' then 'Color'
      when p.id='cs2-prospect-ta9z' then 'NT' else t.name end,
 greatest(20000,coalesce(p.rating,65)::bigint*case when p.role like 'Academy%' then 1800 when p.role like 'Prospect%' then 1600 else 1800 end),
 greatest(5000,coalesce(p.rating,65)::bigint*200),p.source_url,p.snapshot_date,
 case when p.role like 'Academy%' then 'Academy roster; ARQON gameplay rating'
      when p.role like 'Prospect%' then 'HLTV Prospects ranking; ARQON gameplay rating'
      when p.role like 'Benched%' then 'Academy bench; not a free agent'
      else 'Transfer-listed snapshot; verify status before refresh' end
from public.manager_pro_players p left join public.manager_pro_teams t on t.id=p.team_id
where p.id like 'cs2-academy-%' or p.id like 'cs2-prospect-%' or p.id in ('cs2-bench-inner-n0rths','cs2-transfer-moon')
on conflict(player_id) do update set market_status=excluded.market_status,is_available=excluded.is_available,
 current_team_id=excluded.current_team_id,current_team_name=excluded.current_team_name,asking_fee=excluded.asking_fee,
 salary_weekly=excluded.salary_weekly,status_source_url=excluded.status_source_url,source_snapshot_date=excluded.source_snapshot_date,notes=excluded.notes;
