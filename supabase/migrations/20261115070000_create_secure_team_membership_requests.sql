-- Secure team membership applications. Players may create and view only their own requests;
-- organizer admins/owners can review requests. This does not modify active tournament rosters.
create table if not exists public.team_membership_requests (
  id uuid primary key default gen_random_uuid(),
  team_id text not null check (char_length(team_id) between 1 and 80),
  team_name text not null check (char_length(team_name) between 1 and 100),
  user_id uuid not null references auth.users(id) on delete cascade,
  arqon_id bigint not null references public.profiles(arqon_id) on delete cascade,
  player_name text not null check (char_length(player_name) between 1 and 64),
  message text not null default '' check (char_length(message) <= 500),
  status text not null default 'pending' check (status in ('pending','accepted','rejected','withdrawn')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);
create unique index if not exists team_membership_requests_one_pending on public.team_membership_requests(team_id,user_id) where status='pending';
create index if not exists team_membership_requests_team_status on public.team_membership_requests(team_id,status,created_at desc);
alter table public.team_membership_requests enable row level security;
revoke all on public.team_membership_requests from anon, public;
grant select,insert on public.team_membership_requests to authenticated;
drop policy if exists team_requests_read_self_or_admin on public.team_membership_requests;
create policy team_requests_read_self_or_admin on public.team_membership_requests for select to authenticated using (user_id=(select auth.uid()) or public.current_organizer_role() in ('admin','owner'));
drop policy if exists team_requests_insert_self on public.team_membership_requests;
create policy team_requests_insert_self on public.team_membership_requests for insert to authenticated with check (
 user_id=(select auth.uid())
 and arqon_id=(select p.arqon_id from public.profiles p where p.user_id=(select auth.uid()))
 and player_name=coalesce((select nullif(p.display_name,'') from public.profiles p where p.user_id=(select auth.uid())),'Игрок ARQON #'||(select p.arqon_id::text from public.profiles p where p.user_id=(select auth.uid())))
 and status='pending' and reviewed_at is null and reviewed_by is null
);
drop policy if exists team_requests_update_self_or_admin on public.team_membership_requests;
create policy team_requests_update_self_or_admin on public.team_membership_requests for update to authenticated using ((user_id=(select auth.uid()) and status='pending') or public.current_organizer_role() in ('admin','owner')) with check ((user_id=(select auth.uid()) and status='withdrawn' and reviewed_at is null and reviewed_by is null) or (public.current_organizer_role() in ('admin','owner') and status in ('accepted','rejected','pending')));
revoke update on public.team_membership_requests from authenticated;
grant update (status,reviewed_at,reviewed_by) on public.team_membership_requests to authenticated;
