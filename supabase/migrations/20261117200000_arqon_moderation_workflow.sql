-- ARQON moderation workflow: auditable report review, without automatic bans.
create table if not exists public.arqon_moderation_audit (
  id bigint generated always as identity primary key,
  report_id bigint not null references public.arqon_player_reports(id) on delete cascade,
  moderator_user_id uuid not null references auth.users(id) on delete restrict,
  old_status text not null,
  new_status text not null,
  moderator_note text,
  created_at timestamptz not null default now()
);
create index if not exists arqon_moderation_audit_report_idx
  on public.arqon_moderation_audit(report_id, created_at desc);
alter table public.arqon_moderation_audit enable row level security;
revoke all on public.arqon_moderation_audit from public, anon, authenticated;

-- Force all report status changes through the audited SECURITY DEFINER RPC.
revoke update on public.arqon_player_reports from authenticated;
revoke update (status, moderator_user_id, moderator_note, updated_at) on public.arqon_player_reports from authenticated;
drop policy if exists arqon_reports_admin_update on public.arqon_player_reports;

-- Prevent one reporter from opening multiple simultaneous reports for the same account.
create unique index if not exists arqon_player_reports_one_open_per_pair
  on public.arqon_player_reports(reporter_user_id, reported_user_id)
  where status in ('open','reviewing');

create or replace function public.list_arqon_moderation_reports(p_status text default 'open')
returns table(
  report_id bigint, reporter_user_id uuid, reported_user_id uuid,
  reporter_name text, reported_name text, reporter_arqon_id bigint, reported_arqon_id bigint,
  category text, details text, status text, moderator_note text,
  moderator_user_id uuid, created_at timestamptz, updated_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  if p_status not in ('open','reviewing','resolved','dismissed','all') then
    raise exception 'invalid_report_filter' using errcode='22023';
  end if;
  return query
  select r.id,r.reporter_user_id,r.reported_user_id,
    coalesce(rp.display_name,rp.steam_persona_name,'Игрок'),
    coalesce(tp.display_name,tp.steam_persona_name,'Игрок'),
    rp.arqon_id,tp.arqon_id,r.category,r.details,r.status,r.moderator_note,
    r.moderator_user_id,r.created_at,r.updated_at
  from public.arqon_player_reports r
  left join public.profiles rp on rp.user_id=r.reporter_user_id
  left join public.profiles tp on tp.user_id=r.reported_user_id
  where p_status='all' or r.status=p_status
  order by case r.status when 'open' then 0 when 'reviewing' then 1 else 2 end,
           r.created_at desc
  limit 300;
end;
$$;

create or replace function public.review_arqon_player_report(
  p_report_id bigint, p_status text, p_moderator_note text default null
)
returns void
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid()); v_old_status text; v_note text := nullif(btrim(p_moderator_note),'');
begin
  if not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'invalid_moderation_status' using errcode='22023';
  end if;
  if v_note is not null and char_length(v_note)>2000 then
    raise exception 'moderator_note_too_long' using errcode='22023';
  end if;
  select status into v_old_status from public.arqon_player_reports
    where id=p_report_id for update;
  if v_old_status is null then raise exception 'report_not_found' using errcode='P0002'; end if;
  update public.arqon_player_reports
    set status=p_status, moderator_user_id=v_actor, moderator_note=v_note, updated_at=now()
    where id=p_report_id;
  insert into public.arqon_moderation_audit(report_id,moderator_user_id,old_status,new_status,moderator_note)
    values(p_report_id,v_actor,v_old_status,p_status,v_note);
end;
$$;

create or replace function public.get_arqon_moderation_audit(p_report_id bigint)
returns table(moderator_name text, old_status text, new_status text, moderator_note text, created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $audit$
begin
  if not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  return query
  select coalesce(p.display_name,p.steam_persona_name,'Организатор'),
         a.old_status,a.new_status,a.moderator_note,a.created_at
  from public.arqon_moderation_audit a
  left join public.profiles p on p.user_id=a.moderator_user_id
  where a.report_id=p_report_id
  order by a.created_at desc
  limit 50;
end;
$audit$;

revoke all on function public.list_arqon_moderation_reports(text) from public, anon;
revoke all on function public.review_arqon_player_report(bigint,text,text) from public, anon;
grant execute on function public.list_arqon_moderation_reports(text) to authenticated;
grant execute on function public.review_arqon_player_report(bigint,text,text) to authenticated;
revoke all on function public.get_arqon_moderation_audit(bigint) from public, anon;
grant execute on function public.get_arqon_moderation_audit(bigint) to authenticated;
