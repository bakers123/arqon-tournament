-- ARQON social foundation: follows, friend requests, direct messages, blocks and reports.
-- This migration is intentionally additive; it does not modify league, match or tournament data.

create table if not exists public.arqon_follows (
  follower_user_id uuid not null references auth.users(id) on delete cascade,
  followed_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_user_id, followed_user_id),
  constraint arqon_follows_no_self check (follower_user_id <> followed_user_id)
);

create table if not exists public.arqon_friend_requests (
  id bigint generated always as identity primary key,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  receiver_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint arqon_friend_requests_no_self check (sender_user_id <> receiver_user_id),
  constraint arqon_friend_requests_unique_pair unique (sender_user_id, receiver_user_id)
);

create table if not exists public.arqon_user_blocks (
  blocker_user_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_user_id, blocked_user_id),
  constraint arqon_user_blocks_no_self check (blocker_user_id <> blocked_user_id)
);

create table if not exists public.arqon_direct_messages (
  id bigint generated always as identity primary key,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint arqon_direct_messages_no_self check (sender_user_id <> recipient_user_id)
);

create table if not exists public.arqon_player_reports (
  id bigint generated always as identity primary key,
  reporter_user_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('harassment','spam','impersonation','cheating','other')),
  details text not null check (char_length(btrim(details)) between 10 and 2000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  moderator_user_id uuid references auth.users(id) on delete set null,
  moderator_note text check (moderator_note is null or char_length(moderator_note) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint arqon_player_reports_no_self check (reporter_user_id <> reported_user_id)
);

create index if not exists arqon_friend_requests_receiver_status_idx on public.arqon_friend_requests(receiver_user_id,status,created_at desc);
create index if not exists arqon_friend_requests_sender_status_idx on public.arqon_friend_requests(sender_user_id,status,created_at desc);
create index if not exists arqon_direct_messages_conversation_idx on public.arqon_direct_messages(sender_user_id,recipient_user_id,created_at desc);
create index if not exists arqon_direct_messages_recipient_idx on public.arqon_direct_messages(recipient_user_id,created_at desc);
create index if not exists arqon_player_reports_status_idx on public.arqon_player_reports(status,created_at desc);

alter table public.arqon_follows enable row level security;
alter table public.arqon_friend_requests enable row level security;
alter table public.arqon_user_blocks enable row level security;
alter table public.arqon_direct_messages enable row level security;
alter table public.arqon_player_reports enable row level security;

revoke all on public.arqon_follows, public.arqon_friend_requests, public.arqon_user_blocks,
  public.arqon_direct_messages, public.arqon_player_reports from public, anon;
grant select, insert, delete on public.arqon_follows to authenticated;
grant select, insert, update, delete on public.arqon_friend_requests to authenticated;
grant select, insert, delete on public.arqon_user_blocks to authenticated;
grant select, insert, update on public.arqon_direct_messages to authenticated;
grant select, insert, update on public.arqon_player_reports to authenticated;
grant usage, select on sequence public.arqon_friend_requests_id_seq,
  public.arqon_direct_messages_id_seq, public.arqon_player_reports_id_seq to authenticated;

drop policy if exists arqon_follows_read on public.arqon_follows;
create policy arqon_follows_read on public.arqon_follows for select to authenticated using (true);
drop policy if exists arqon_follows_insert_own on public.arqon_follows;
create policy arqon_follows_insert_own on public.arqon_follows for insert to authenticated
  with check (follower_user_id = (select auth.uid())
    and not exists (select 1 from public.arqon_user_blocks b where
      (b.blocker_user_id = (select auth.uid()) and b.blocked_user_id = followed_user_id)
      or (b.blocker_user_id = followed_user_id and b.blocked_user_id = (select auth.uid()))));
drop policy if exists arqon_follows_delete_own on public.arqon_follows;
create policy arqon_follows_delete_own on public.arqon_follows for delete to authenticated
  using (follower_user_id = (select auth.uid()));

drop policy if exists arqon_friend_requests_read_participant on public.arqon_friend_requests;
create policy arqon_friend_requests_read_participant on public.arqon_friend_requests for select to authenticated
  using (sender_user_id = (select auth.uid()) or receiver_user_id = (select auth.uid()));
drop policy if exists arqon_friend_requests_insert_sender on public.arqon_friend_requests;
create policy arqon_friend_requests_insert_sender on public.arqon_friend_requests for insert to authenticated
  with check (sender_user_id = (select auth.uid()) and status = 'pending'
    and not exists (select 1 from public.arqon_user_blocks b where
      (b.blocker_user_id = (select auth.uid()) and b.blocked_user_id = receiver_user_id)
      or (b.blocker_user_id = receiver_user_id and b.blocked_user_id = (select auth.uid()))));
drop policy if exists arqon_friend_requests_update_receiver on public.arqon_friend_requests;
create policy arqon_friend_requests_update_receiver on public.arqon_friend_requests for update to authenticated
  using (receiver_user_id = (select auth.uid()) and status = 'pending')
  with check (receiver_user_id = (select auth.uid()) and status in ('accepted','declined'));
drop policy if exists arqon_friend_requests_cancel_sender on public.arqon_friend_requests;
create policy arqon_friend_requests_cancel_sender on public.arqon_friend_requests for delete to authenticated
  using (sender_user_id = (select auth.uid()) and status = 'pending');

drop policy if exists arqon_blocks_read_own on public.arqon_user_blocks;
create policy arqon_blocks_read_own on public.arqon_user_blocks for select to authenticated
  using (blocker_user_id = (select auth.uid()));
drop policy if exists arqon_blocks_insert_own on public.arqon_user_blocks;
create policy arqon_blocks_insert_own on public.arqon_user_blocks for insert to authenticated
  with check (blocker_user_id = (select auth.uid()));
drop policy if exists arqon_blocks_delete_own on public.arqon_user_blocks;
create policy arqon_blocks_delete_own on public.arqon_user_blocks for delete to authenticated
  using (blocker_user_id = (select auth.uid()));

drop policy if exists arqon_direct_messages_read_participant on public.arqon_direct_messages;
create policy arqon_direct_messages_read_participant on public.arqon_direct_messages for select to authenticated
  using ((sender_user_id = (select auth.uid()) or recipient_user_id = (select auth.uid()))
    and not exists (select 1 from public.arqon_user_blocks b where
      (b.blocker_user_id = sender_user_id and b.blocked_user_id = recipient_user_id)
      or (b.blocker_user_id = recipient_user_id and b.blocked_user_id = sender_user_id)));
drop policy if exists arqon_direct_messages_send_own on public.arqon_direct_messages;
create policy arqon_direct_messages_send_own on public.arqon_direct_messages for insert to authenticated
  with check (sender_user_id = (select auth.uid())
    and not exists (select 1 from public.arqon_user_blocks b where
      (b.blocker_user_id = sender_user_id and b.blocked_user_id = recipient_user_id)
      or (b.blocker_user_id = recipient_user_id and b.blocked_user_id = sender_user_id)));
drop policy if exists arqon_direct_messages_read_receipt on public.arqon_direct_messages;
create policy arqon_direct_messages_read_receipt on public.arqon_direct_messages for update to authenticated
  using (recipient_user_id = (select auth.uid()))
  with check (recipient_user_id = (select auth.uid()) and sender_user_id <> (select auth.uid()));

drop policy if exists arqon_reports_insert_self on public.arqon_player_reports;
create policy arqon_reports_insert_self on public.arqon_player_reports for insert to authenticated
  with check (reporter_user_id = (select auth.uid()) and status = 'open' and moderator_user_id is null and moderator_note is null);
drop policy if exists arqon_reports_read_reporter on public.arqon_player_reports;
create policy arqon_reports_read_reporter on public.arqon_player_reports for select to authenticated
  using (reporter_user_id = (select auth.uid()));
drop policy if exists arqon_reports_admin_read on public.arqon_player_reports;
create policy arqon_reports_admin_read on public.arqon_player_reports for select to authenticated
  using (public.has_organizer_role('admin') or public.has_organizer_role('owner'));
drop policy if exists arqon_reports_admin_update on public.arqon_player_reports;
create policy arqon_reports_admin_update on public.arqon_player_reports for update to authenticated
  using (public.has_organizer_role('admin') or public.has_organizer_role('owner'))
  with check ((public.has_organizer_role('admin') or public.has_organizer_role('owner'))
    and status in ('open','reviewing','resolved','dismissed'));
