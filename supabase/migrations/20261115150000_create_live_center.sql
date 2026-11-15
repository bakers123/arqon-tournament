create table if not exists public.live_matches (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  game text not null default 'CS2' check (game in ('CS2','Dota 2','Other')),
  team1 text not null check (char_length(btrim(team1)) between 1 and 100),
  team2 text not null check (char_length(btrim(team2)) between 1 and 100),
  status text not null default 'scheduled' check (status in ('scheduled','live','paused','finished','cancelled')),
  starts_at timestamptz,
  score1 integer not null default 0 check (score1 >= 0 and score1 <= 999),
  score2 integer not null default 0 check (score2 >= 0 and score2 <= 999),
  best_of integer not null default 1 check (best_of in (1,3,5)),
  map_name text not null default '' check (char_length(map_name) <= 80),
  stream_url text not null default '' check (stream_url = '' or (stream_url like 'https://%' and char_length(stream_url) <= 2048)),
  stream_platform text not null default 'other' check (stream_platform in ('twitch','youtube','other')),
  mvp_name text not null default '' check (char_length(mvp_name) <= 100),
  lineup1 jsonb not null default '[]'::jsonb check (jsonb_typeof(lineup1) = 'array'),
  lineup2 jsonb not null default '[]'::jsonb check (jsonb_typeof(lineup2) = 'array'),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.live_match_events (
  id uuid primary key default gen_random_uuid(),
  live_match_id uuid not null references public.live_matches(id) on delete cascade,
  event_type text not null default 'info' check (event_type in ('info','round','kill','map','score','mvp')),
  team_name text not null default '' check (char_length(team_name) <= 100),
  player_name text not null default '' check (char_length(player_name) <= 100),
  description text not null check (char_length(btrim(description)) between 1 and 300),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists live_matches_status_start_idx on public.live_matches(status, starts_at desc);
create index if not exists live_match_events_match_created_idx on public.live_match_events(live_match_id, created_at desc);
alter table public.live_matches enable row level security;
alter table public.live_match_events enable row level security;
drop policy if exists "Live matches are publicly readable" on public.live_matches;
create policy "Live matches are publicly readable" on public.live_matches for select to anon, authenticated using (true);
drop policy if exists "Organizers manage live matches" on public.live_matches;
create policy "Organizers manage live matches" on public.live_matches for all to authenticated using (public.has_organizer_role('editor')) with check (public.has_organizer_role('editor'));
drop policy if exists "Live events are publicly readable" on public.live_match_events;
create policy "Live events are publicly readable" on public.live_match_events for select to anon, authenticated using (true);
drop policy if exists "Organizers manage live events" on public.live_match_events;
create policy "Organizers manage live events" on public.live_match_events for all to authenticated using (public.has_organizer_role('editor')) with check (public.has_organizer_role('editor'));
grant select on public.live_matches, public.live_match_events to anon, authenticated;
grant insert, update, delete on public.live_matches, public.live_match_events to authenticated;
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='live_matches') then
    alter publication supabase_realtime add table public.live_matches;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='live_match_events') then
    alter publication supabase_realtime add table public.live_match_events;
  end if;
end $$;