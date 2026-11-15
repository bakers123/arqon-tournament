-- Keep XP milestone bonuses in sync with the current source XP ledger.
-- Milestone thresholds are calculated from tournament + Live XP only; milestone
-- bonus XP never recursively unlocks another milestone.
create or replace function public.reconcile_arqon_xp_milestones(p_arqon_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_xp bigint;
begin
  if p_arqon_id is null then return; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('arqon-xp-milestones:' || p_arqon_id::text, 0)
  );

  select coalesce(sum(xp_amount), 0)
    into base_xp
  from public.arqon_xp_events
  where arqon_id = p_arqon_id
    and source_type <> 'achievement';

  insert into public.arqon_xp_events(arqon_id, source_type, source_key, source_label, xp_amount)
  select p_arqon_id, 'achievement', m.key, m.label, m.bonus
  from (values
    ('xp_500',   'Достижение: 500 XP',    25,  500),
    ('xp_1500',  'Достижение: 1 500 XP',  50, 1500),
    ('xp_3000',  'Достижение: 3 000 XP',  75, 3000),
    ('xp_6000',  'Достижение: 6 000 XP', 100, 6000),
    ('xp_10000', 'Достижение: 10 000 XP',150,10000)
  ) as m(key, label, bonus, threshold)
  where base_xp >= m.threshold
  on conflict (arqon_id, source_type, source_key)
  do update set source_label = excluded.source_label,
                xp_amount = excluded.xp_amount;

  delete from public.arqon_xp_events e
  using (values
    ('xp_500',   500),
    ('xp_1500', 1500),
    ('xp_3000', 3000),
    ('xp_6000', 6000),
    ('xp_10000',10000)
  ) as m(key, threshold)
  where e.arqon_id = p_arqon_id
    and e.source_type = 'achievement'
    and e.source_key = m.key
    and base_xp < m.threshold;
end;
$$;

create or replace function public.sync_arqon_xp_milestones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.source_type <> 'achievement' then
      perform public.reconcile_arqon_xp_milestones(new.arqon_id);
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.source_type <> 'achievement' then
      perform public.reconcile_arqon_xp_milestones(old.arqon_id);
    end if;
    return old;
  else
    if old.source_type <> 'achievement' then
      perform public.reconcile_arqon_xp_milestones(old.arqon_id);
    end if;
    if new.source_type <> 'achievement'
       and (new.arqon_id is distinct from old.arqon_id
            or new.source_type is distinct from old.source_type
            or new.xp_amount is distinct from old.xp_amount) then
      perform public.reconcile_arqon_xp_milestones(new.arqon_id);
    end if;
    return new;
  end if;
end;
$$;

drop trigger if exists arqon_xp_milestones_after_insert on public.arqon_xp_events;
drop trigger if exists arqon_xp_milestones_sync on public.arqon_xp_events;
create trigger arqon_xp_milestones_sync
after insert or update or delete on public.arqon_xp_events
for each row execute function public.sync_arqon_xp_milestones();

revoke all on function public.reconcile_arqon_xp_milestones(bigint) from public, anon, authenticated;
revoke all on function public.sync_arqon_xp_milestones() from public, anon, authenticated;

do $$
declare profile_row record;
begin
  for profile_row in
    select distinct arqon_id
    from public.arqon_xp_events
    where source_type <> 'achievement'
  loop
    perform public.reconcile_arqon_xp_milestones(profile_row.arqon_id);
  end loop;
end;
$$;
