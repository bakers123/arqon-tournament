-- Notify recipients about incoming direct messages. Website inbox and existing Telegram queue are reused.
alter table public.user_notifications
  drop constraint if exists user_notifications_notification_type_check;
alter table public.user_notifications
  add constraint user_notifications_notification_type_check
  check (notification_type = any (array[
    'support_reply','team_invitation','team_offer','system','support_status',
    'team_status','team_role_changed','team_roster_changed',
    'follow','friend_request','friend_accepted','direct_message'
  ]::text[]));

create or replace function public.notify_arqon_direct_message()
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
    new.recipient_user_id,
    'direct_message',
    'Новое сообщение',
    left(coalesce(v_name, 'Игрок ARQON'), 80) || ' отправил тебе сообщение.',
    '/messages/',
    new.id::text
  );
  return new;
end;
$function$;

revoke all on function public.notify_arqon_direct_message() from public, anon, authenticated;
drop trigger if exists trg_notify_arqon_direct_message on public.arqon_direct_messages;
create trigger trg_notify_arqon_direct_message
after insert on public.arqon_direct_messages
for each row execute function public.notify_arqon_direct_message();
