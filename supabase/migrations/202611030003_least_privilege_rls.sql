-- ARQON least-privilege RLS and organizer-only code issuance.
-- Additive/restrictive only: no application rows are deleted or rewritten.

create or replace function public.create_player_access_code(p_player_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_name text := btrim(p_player_name);
begin
  if not public.has_organizer_role('editor') then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if v_name is null or length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid player name' using errcode = '22023';
  end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
    exit when not exists (select 1 from public.access_codes where code = v_code);
  end loop;
  insert into public.access_codes(code, player_name) values (v_code, v_name);
  return v_code;
end;
$$;
revoke all on function public.create_player_access_code(text) from public, anon;
grant execute on function public.create_player_access_code(text) to authenticated;

-- The public directory exposes names only, never anonymous player UUIDs.
create or replace view public.player_directory as
  select name from public.players;
revoke all on public.player_directory from public;
grant select on public.player_directory to anon, authenticated;

-- Remove permissive legacy policies before enabling row-level enforcement.
drop policy if exists "Allow all" on public.access_codes;
drop policy if exists "Allow all access_codes" on public.access_codes;
drop policy if exists "Allow all drafts" on public.drafts;
drop policy if exists "Allow all" on public.players;

drop policy if exists "League data can be managed by site admin UI" on public.league_data;
drop policy if exists "League data is publicly readable" on public.league_data;
drop policy if exists "Allow all inserts" on public.messages;
drop policy if exists "Allow all messages" on public.messages;
drop policy if exists "Allow all selects" on public.messages;
drop policy if exists "Allow public insert on messages" on public.messages;
drop policy if exists "Allow public read on messages" on public.messages;
drop policy if exists "Allow all news" on public.news;
drop policy if exists "Allow all results" on public.results;
drop policy if exists "Allow all schedule" on public.schedule;
drop policy if exists "Allow all sponsors" on public.sponsors;
drop policy if exists "Allow all" on public.tournament;

alter table public.access_codes enable row level security;
alter table public.players enable row level security;
alter table public.drafts enable row level security;
alter table public.league_data enable row level security;
alter table public.messages enable row level security;
alter table public.news enable row level security;
alter table public.results enable row level security;
alter table public.schedule enable row level security;
alter table public.sponsors enable row level security;
alter table public.tournament enable row level security;

-- Access codes have no direct table policies. They can only be issued/redeemed by RPCs.
-- Players can read their own record; organizers can read the full roster.
create policy players_read_self_or_organizer on public.players
for select to authenticated
using (uid = (select auth.uid())::text or public.has_organizer_role('editor'));

create policy tournament_public_read on public.tournament
for select to anon, authenticated using (true);
create policy tournament_organizer_write on public.tournament
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

create policy league_public_read on public.league_data
for select to anon, authenticated using (true);
create policy league_organizer_write on public.league_data
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

create policy news_public_read on public.news
for select to anon, authenticated using (true);
create policy news_organizer_write on public.news
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

create policy results_public_read on public.results
for select to anon, authenticated using (true);
create policy results_organizer_write on public.results
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

create policy schedule_public_read on public.schedule
for select to anon, authenticated using (true);
create policy schedule_organizer_write on public.schedule
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

create policy sponsors_public_read on public.sponsors
for select to anon, authenticated using (true);
create policy sponsors_organizer_write on public.sponsors
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

-- Draft contents are visible to both teams. Only the two assigned captains or an
-- organizer can mutate the active draft. Participant identity fields are immutable
-- to players (enforced by the trigger below).
create policy drafts_public_read on public.drafts
for select to anon, authenticated using (true);
create policy drafts_organizer_insert on public.drafts
for insert to authenticated
with check (public.has_organizer_role('editor'));
create policy drafts_organizer_update on public.drafts
for update to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

create or replace function public.update_player_draft(p_data jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old jsonb;
begin
  if jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid draft payload' using errcode = '22023';
  end if;
  select data into v_old from public.drafts where id = 1 for update;
  if v_old is null then
    raise exception 'draft not found' using errcode = 'P0002';
  end if;
  if (v_old->>'p1_captain_uid') is distinct from (select auth.uid())::text
    and (v_old->>'p2_captain_uid') is distinct from (select auth.uid())::text then
    raise exception 'not an assigned draft captain' using errcode = '42501';
  end if;
  if p_data->>'p1_uid' is distinct from v_old->>'p1_uid'
    or p_data->>'p2_uid' is distinct from v_old->>'p2_uid'
    or p_data->>'p1_captain_uid' is distinct from v_old->>'p1_captain_uid'
    or p_data->>'p2_captain_uid' is distinct from v_old->>'p2_captain_uid'
    or p_data->>'match_id' is distinct from v_old->>'match_id' then
    raise exception 'draft participant assignments are immutable' using errcode = '42501';
  end if;
  update public.drafts set data = p_data where id = 1;
end;
$function$;
revoke all on function public.update_player_draft(jsonb) from public, anon;
grant execute on function public.update_player_draft(jsonb) to authenticated;
create policy drafts_organizer_delete on public.drafts
for delete to authenticated
using (public.has_organizer_role('editor'));

create or replace function private.protect_draft_participants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_organizer_role('editor') and (
    new.data->>'p1_uid' is distinct from old.data->>'p1_uid'
    or new.data->>'p2_uid' is distinct from old.data->>'p2_uid'
    or new.data->>'p1_captain_uid' is distinct from old.data->>'p1_captain_uid'
    or new.data->>'p2_captain_uid' is distinct from old.data->>'p2_captain_uid'
    or new.data->>'match_id' is distinct from old.data->>'match_id'
  ) then
    raise exception 'draft participant assignments are immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_draft_participants on public.drafts;
create trigger protect_draft_participants
before update on public.drafts
for each row execute function private.protect_draft_participants();

-- Public chat remains readable. Inserts must come from a real participant
-- assigned to the active draft, or an authenticated organizer.
create policy messages_public_read on public.messages
for select to anon, authenticated using (true);
create policy messages_participant_insert on public.messages
for insert to authenticated
with check (
  length(btrim(coalesce(text, ''))) between 1 and 1000
  and length(btrim(coalesce(sender, ''))) between 1 and 80
  and (
    public.has_organizer_role('editor')
    or exists (
      select 1 from public.players p
      where p.uid = (select auth.uid())::text
        and p.name = sender
    )
  )
  and (
    public.has_organizer_role('editor')
    or exists (
      select 1 from public.drafts d
      where d.data->>'match_id' = match_id
        and (
          d.data->>'p1_uid' = (select auth.uid())::text
          or d.data->>'p2_uid' = (select auth.uid())::text
        )
    )
  )
);
create policy messages_organizer_delete on public.messages
for delete to authenticated using (public.has_organizer_role('editor'));
