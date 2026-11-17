-- Direct messages are restricted to accepted friends and blocked pairs are excluded.
-- Additive security hardening; does not touch league data.
drop policy if exists arqon_direct_messages_read_participant on public.arqon_direct_messages;
create policy arqon_direct_messages_read_participant
on public.arqon_direct_messages for select to authenticated
using (
  (sender_user_id = (select auth.uid()) or recipient_user_id = (select auth.uid()))
  and exists (
    select 1 from public.arqon_friend_requests f
    where f.status = 'accepted'
      and ((f.sender_user_id = sender_user_id and f.receiver_user_id = recipient_user_id)
        or (f.sender_user_id = recipient_user_id and f.receiver_user_id = sender_user_id))
  )
  and not exists (
    select 1 from public.arqon_user_blocks b
    where (b.blocker_user_id = sender_user_id and b.blocked_user_id = recipient_user_id)
       or (b.blocker_user_id = recipient_user_id and b.blocked_user_id = sender_user_id)
  )
);
drop policy if exists arqon_direct_messages_send_own on public.arqon_direct_messages;
create policy arqon_direct_messages_send_own
on public.arqon_direct_messages for insert to authenticated
with check (
  sender_user_id = (select auth.uid())
  and exists (
    select 1 from public.arqon_friend_requests f
    where f.status = 'accepted'
      and ((f.sender_user_id = sender_user_id and f.receiver_user_id = recipient_user_id)
        or (f.sender_user_id = recipient_user_id and f.receiver_user_id = sender_user_id))
  )
  and not exists (
    select 1 from public.arqon_user_blocks b
    where (b.blocker_user_id = sender_user_id and b.blocked_user_id = recipient_user_id)
       or (b.blocker_user_id = recipient_user_id and b.blocked_user_id = sender_user_id)
  )
);
drop policy if exists arqon_direct_messages_read_receipt on public.arqon_direct_messages;
create policy arqon_direct_messages_read_receipt
on public.arqon_direct_messages for update to authenticated
using (
  recipient_user_id = (select auth.uid())
  and exists (
    select 1 from public.arqon_friend_requests f
    where f.status = 'accepted'
      and ((f.sender_user_id = sender_user_id and f.receiver_user_id = recipient_user_id)
        or (f.sender_user_id = recipient_user_id and f.receiver_user_id = sender_user_id))
  )
)
with check (
  recipient_user_id = (select auth.uid())
  and sender_user_id <> (select auth.uid())
  and exists (
    select 1 from public.arqon_friend_requests f
    where f.status = 'accepted'
      and ((f.sender_user_id = sender_user_id and f.receiver_user_id = recipient_user_id)
        or (f.sender_user_id = recipient_user_id and f.receiver_user_id = sender_user_id))
  )
);
create index if not exists arqon_direct_messages_unread_idx
on public.arqon_direct_messages(recipient_user_id, read_at, created_at desc);
