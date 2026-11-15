-- Per-user controls for ARQON notification categories.
create table if not exists public.user_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  support_enabled boolean not null default true,
  teams_enabled boolean not null default true,
  system_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.user_notification_preferences enable row level security;

drop policy if exists "Users can view own notification preferences" on public.user_notification_preferences;
create policy "Users can view own notification preferences"
  on public.user_notification_preferences
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own notification preferences" on public.user_notification_preferences;
create policy "Users can insert own notification preferences"
  on public.user_notification_preferences
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own notification preferences" on public.user_notification_preferences;
create policy "Users can update own notification preferences"
  on public.user_notification_preferences
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update on public.user_notification_preferences to authenticated;
revoke all on public.user_notification_preferences from anon;

create or replace function public.filter_disabled_user_notification()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_enabled boolean;
begin
  select case
    when new.notification_type in ('support_reply','support_status') then p.support_enabled
    when new.notification_type in ('team_invitation','team_offer','team_status') then p.teams_enabled
    else p.system_enabled
  end
  into v_enabled
  from public.user_notification_preferences p
  where p.user_id = new.user_id;

  -- No preference row means all categories remain enabled by default.
  if v_enabled is false then
    return null;
  end if;
  return new;
end;
$function$;

revoke all on function public.filter_disabled_user_notification() from public, anon, authenticated;

drop trigger if exists trg_filter_disabled_user_notification on public.user_notifications;
create trigger trg_filter_disabled_user_notification
  before insert on public.user_notifications
  for each row
  execute function public.filter_disabled_user_notification();
