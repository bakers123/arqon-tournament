-- ARQON social activity notifications: website inbox + asynchronous Telegram delivery.
-- Depends on 20261117130000_arqon_social_foundation.sql and existing user_notifications.

create extension if not exists pg_net;

alter table public.user_notifications
  drop constraint if exists user_notifications_notification_type_check;
alter table public.user_notifications
  add constraint user_notifications_notification_type_check
  check (notification_type = any (array[
    'support_reply','team_invitation','team_offer','system','support_status',
    'team_status','team_role_changed','team_roster_changed',
    'follow','friend_request','friend_accepted'
  ]::text[]));

create table if not exists public.arqon_telegram_notification_queue (
  id bigint generated always as identity primary key,
  notification_id bigint not null unique references public.user_notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','sent','skipped','failed')),
  attempts integer not null default 0 check (attempts >= 0),
  locked_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

create index if not exists arqon_telegram_notification_queue_pending_idx
  on public.arqon_telegram_notification_queue(status, created_at)
  where status in ('pending','failed','processing');

alter table public.arqon_telegram_notification_queue enable row level security;
revoke all on public.arqon_telegram_notification_queue from public, anon, authenticated;
grant select, insert, update, delete on public.arqon_telegram_notification_queue to service_role;
grant usage, select on sequence public.arqon_telegram_notification_queue_id_seq to service_role;

create or replace function public.claim_arqon_telegram_notification(p_queue_id bigint)
returns table(queue_id bigint, notification_id bigint, user_id uuid)
language sql
security definer
set search_path = ''
as $function$
  update public.arqon_telegram_notification_queue q
     set status = 'processing',
         locked_at = now(),
         attempts = q.attempts + 1,
         last_error = null
   where q.id = p_queue_id
     and q.sent_at is null
     and (
       q.status in ('pending','failed')
       or (q.status = 'processing' and q.locked_at < now() - interval '5 minutes')
     )
  returning q.id, q.notification_id, q.user_id;
$function$;

revoke all on function public.claim_arqon_telegram_notification(bigint) from public, anon, authenticated;
grant execute on function public.claim_arqon_telegram_notification(bigint) to service_role;

create or replace function public.enqueue_arqon_telegram_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_queue_id bigint;
begin
  if new.notification_type not in ('follow','friend_request','friend_accepted') then
    return new;
  end if;

  insert into public.arqon_telegram_notification_queue(notification_id, user_id)
  values (new.id, new.user_id)
  on conflict (notification_id) do nothing
  returning id into v_queue_id;

  if v_queue_id is not null then
    perform net.http_post(
      url := 'https://uscnaqcvuwjrmkjyuklp.supabase.co/functions/v1/dispatch-social-notification',
      body := jsonb_build_object('queue_id', v_queue_id),
      headers := jsonb_build_object('Content-Type', 'application/json'),
      timeout_milliseconds := 5000
    );
  end if;
  return new;
end;
$function$;

revoke all on function public.enqueue_arqon_telegram_notification() from public, anon, authenticated;
drop trigger if exists trg_enqueue_arqon_telegram_notification on public.user_notifications;
create trigger trg_enqueue_arqon_telegram_notification
after insert on public.user_notifications
for each row execute function public.enqueue_arqon_telegram_notification();

create or replace function public.notify_arqon_new_follower()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_name text;
  v_arqon_id bigint;
begin
  select coalesce(nullif(p.display_name,''), nullif(p.steam_persona_name,''), 'Игрок ARQON'), p.arqon_id
    into v_name, v_arqon_id
    from public.profiles p
   where p.user_id = new.follower_user_id;

  insert into public.user_notifications(user_id, notification_type, title, body, target_url, related_id)
  values (
    new.followed_user_id,
    'follow',
    'Новый подписчик',
    left(coalesce(v_name, 'Игрок ARQON'), 80) || ' подписался на тебя.',
    case when v_arqon_id is not null then '/players/profile/?id=' || v_arqon_id::text else '/players/' end,
    new.follower_user_id::text
  );
  return new;
end;
$function$;

revoke all on function public.notify_arqon_new_follower() from public, anon, authenticated;
drop trigger if exists trg_notify_arqon_new_follower on public.arqon_follows;
create trigger trg_notify_arqon_new_follower
after insert on public.arqon_follows
for each row execute function public.notify_arqon_new_follower();

create or replace function public.notify_arqon_friend_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_name text;
  v_arqon_id bigint;
begin
  select coalesce(nullif(p.display_name,''), nullif(p.steam_persona_name,''), 'Игрок ARQON'), p.arqon_id
    into v_name, v_arqon_id
    from public.profiles p
   where p.user_id = new.sender_user_id;

  insert into public.user_notifications(user_id, notification_type, title, body, target_url, related_id)
  values (
    new.receiver_user_id,
    'friend_request',
    'Новая заявка в друзья',
    left(coalesce(v_name, 'Игрок ARQON'), 80) || ' отправил тебе заявку в друзья.',
    case when v_arqon_id is not null then '/players/profile/?id=' || v_arqon_id::text else '/players/' end,
    new.id::text
  );
  return new;
end;
$function$;

revoke all on function public.notify_arqon_friend_request() from public, anon, authenticated;
drop trigger if exists trg_notify_arqon_friend_request on public.arqon_friend_requests;
create trigger trg_notify_arqon_friend_request
after insert on public.arqon_friend_requests
for each row execute function public.notify_arqon_friend_request();

create or replace function public.notify_arqon_friend_accepted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_name text;
  v_arqon_id bigint;
begin
  if old.status <> 'pending' or new.status <> 'accepted' then
    return new;
  end if;

  select coalesce(nullif(p.display_name,''), nullif(p.steam_persona_name,''), 'Игрок ARQON'), p.arqon_id
    into v_name, v_arqon_id
    from public.profiles p
   where p.user_id = new.receiver_user_id;

  insert into public.user_notifications(user_id, notification_type, title, body, target_url, related_id)
  values (
    new.sender_user_id,
    'friend_accepted',
    'Заявка в друзья принята',
    left(coalesce(v_name, 'Игрок ARQON'), 80) || ' принял твою заявку в друзья.',
    case when v_arqon_id is not null then '/players/profile/?id=' || v_arqon_id::text else '/players/' end,
    new.id::text
  );
  return new;
end;
$function$;

revoke all on function public.notify_arqon_friend_accepted() from public, anon, authenticated;
drop trigger if exists trg_notify_arqon_friend_accepted on public.arqon_friend_requests;
create trigger trg_notify_arqon_friend_accepted
after update of status on public.arqon_friend_requests
for each row execute function public.notify_arqon_friend_accepted();
