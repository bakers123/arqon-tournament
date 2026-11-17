-- Notify players when a moderator issues or revokes a community sanction.
-- Uses the existing website notification inbox and Telegram delivery queue.

alter table public.user_notifications
  drop constraint if exists user_notifications_notification_type_check;
alter table public.user_notifications
  add constraint user_notifications_notification_type_check
  check (notification_type = any (array[
    'support_reply','team_invitation','team_offer','system','support_status',
    'team_status','team_role_changed','team_roster_changed',
    'follow','friend_request','friend_accepted','direct_message','moderation_notice'
  ]::text[]));

create or replace function public.notify_arqon_sanction_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_title text;
  v_body text;
  v_type text;
begin
  if tg_op = 'INSERT' then
    v_title := case new.sanction_type
      when 'warning' then 'Предупреждение от модерации ARQON'
      when 'restriction' then 'Ограничение функций сообщества ARQON'
      when 'account_block' then 'Блокировка сообщества ARQON'
      else 'Уведомление модерации ARQON'
    end;
    v_body := 'Причина: ' || left(new.reason, 1500);
    if new.expires_at is not null then
      v_body := v_body || ' Срок до: ' || to_char(new.expires_at at time zone 'UTC', 'DD.MM.YYYY HH24:MI') || ' UTC.';
    else
      v_body := v_body || ' Срок действия не ограничен.';
    end if;
  elsif tg_op = 'UPDATE' and old.revoked_at is null and new.revoked_at is not null then
    v_title := 'Санкция снята модерацией ARQON';
    v_body := 'Ограничение больше не действует.' ||
      case when new.revoke_reason is not null then ' Причина снятия: ' || left(new.revoke_reason, 800) else '' end;
  else
    return new;
  end if;

  insert into public.user_notifications(user_id, notification_type, title, body, target_url, related_id)
  values (new.target_user_id, 'moderation_notice', v_title, left(v_body, 2000), '/social/', new.id::text);
  return new;
end;
$function$;

revoke all on function public.notify_arqon_sanction_change() from public, anon, authenticated;
drop trigger if exists trg_notify_arqon_sanction_issued on public.arqon_user_sanctions;
create trigger trg_notify_arqon_sanction_issued
after insert on public.arqon_user_sanctions
for each row execute function public.notify_arqon_sanction_change();
drop trigger if exists trg_notify_arqon_sanction_revoked on public.arqon_user_sanctions;
create trigger trg_notify_arqon_sanction_revoked
after update of revoked_at on public.arqon_user_sanctions
for each row execute function public.notify_arqon_sanction_change();

-- Route moderation notices through the same private Telegram queue as other social events.
create or replace function public.enqueue_arqon_telegram_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_queue_id bigint;
begin
  if new.notification_type not in ('follow','friend_request','friend_accepted','direct_message','moderation_notice') then
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
