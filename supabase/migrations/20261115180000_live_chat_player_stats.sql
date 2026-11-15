create table if not exists public.live_match_chat (
 id uuid primary key default gen_random_uuid(),
 live_match_id uuid not null references public.live_matches(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 display_name text not null default 'Игрок ARQON' check (char_length(display_name) between 1 and 64),
 message text not null check (char_length(btrim(message)) between 1 and 500),
 created_at timestamptz not null default now()
);
create index if not exists live_match_chat_match_created_idx on public.live_match_chat(live_match_id, created_at desc);
create index if not exists live_match_chat_user_created_idx on public.live_match_chat(user_id, created_at desc);
create or replace function public.prepare_live_match_chat_message() returns trigger language plpgsql security definer set search_path = '' as $$
declare profile_name text; last_message_at timestamptz;
begin
 if new.user_id is distinct from auth.uid() then raise exception 'Можно отправлять сообщения только от своего аккаунта'; end if;
 select p.display_name into profile_name from public.profiles p where p.user_id = new.user_id;
 new.display_name := coalesce(nullif(btrim(profile_name), ''), 'Игрок ARQON');
 select max(c.created_at) into last_message_at from public.live_match_chat c where c.user_id = new.user_id;
 if last_message_at is not null and last_message_at > now() - interval '2 seconds' then raise exception 'Не отправляй сообщения так часто'; end if;
 new.message := btrim(new.message); return new;
end; $$;
drop trigger if exists trg_prepare_live_match_chat_message on public.live_match_chat;
create trigger trg_prepare_live_match_chat_message before insert on public.live_match_chat for each row execute function public.prepare_live_match_chat_message();
create table if not exists public.live_match_player_stats (
 id uuid primary key default gen_random_uuid(),
 live_match_id uuid not null references public.live_matches(id) on delete cascade,
 player_name text not null check (char_length(btrim(player_name)) between 1 and 64),
 team_name text not null check (char_length(btrim(team_name)) between 1 and 100),
 kills integer not null default 0 check (kills between 0 and 999),
 deaths integer not null default 0 check (deaths between 0 and 999),
 assists integer not null default 0 check (assists between 0 and 999),
 adr numeric(6,2) not null default 0 check (adr between 0 and 999.99),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(live_match_id, player_name, team_name)
);
create index if not exists live_match_player_stats_match_idx on public.live_match_player_stats(live_match_id, kills desc, adr desc);
alter table public.live_match_chat enable row level security;
alter table public.live_match_player_stats enable row level security;
drop policy if exists "Live match chat is publicly readable" on public.live_match_chat;
create policy "Live match chat is publicly readable" on public.live_match_chat for select to anon, authenticated using (true);
drop policy if exists "Authenticated users can send live match chat" on public.live_match_chat;
create policy "Authenticated users can send live match chat" on public.live_match_chat for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Live player stats are publicly readable" on public.live_match_player_stats;
create policy "Live player stats are publicly readable" on public.live_match_player_stats for select to anon, authenticated using (true);
drop policy if exists "Organizers manage live player stats" on public.live_match_player_stats;
create policy "Organizers manage live player stats" on public.live_match_player_stats for all to authenticated using (public.has_organizer_role('editor')) with check (public.has_organizer_role('editor'));
grant select on public.live_match_chat, public.live_match_player_stats to anon, authenticated;
grant insert on public.live_match_chat to authenticated;
grant insert, update, delete on public.live_match_player_stats to authenticated;
do $$ begin
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='live_match_chat') then alter publication supabase_realtime add table public.live_match_chat; end if;
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='live_match_player_stats') then alter publication supabase_realtime add table public.live_match_player_stats; end if;
end $$;