-- ARQON sanction appeals: player submissions and audited moderator decisions.
create table if not exists public.arqon_sanction_appeals (
  id bigint generated always as identity primary key,
  sanction_id bigint not null references public.arqon_user_sanctions(id) on delete cascade,
  appellant_user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(btrim(message)) between 10 and 2000),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  moderator_user_id uuid references auth.users(id) on delete set null,
  moderator_response text check (moderator_response is null or char_length(moderator_response)<=2000),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint arqon_appeal_review_fields check (
    (status='pending' and moderator_user_id is null and reviewed_at is null)
    or (status in ('accepted','rejected') and moderator_user_id is not null and reviewed_at is not null)
  )
);
create unique index if not exists arqon_one_pending_appeal_per_sanction
  on public.arqon_sanction_appeals(sanction_id) where status='pending';
create index if not exists arqon_appeals_appellant_idx
  on public.arqon_sanction_appeals(appellant_user_id,created_at desc);
create index if not exists arqon_appeals_status_idx
  on public.arqon_sanction_appeals(status,created_at asc);
alter table public.arqon_sanction_appeals enable row level security;
revoke all on public.arqon_sanction_appeals from public,anon,authenticated;

create or replace function public.submit_arqon_sanction_appeal(p_sanction_id bigint,p_message text)
returns bigint language plpgsql security definer set search_path=''
as $$
declare v_user uuid := (select auth.uid()); v_appeal_id bigint;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if char_length(btrim(coalesce(p_message,''))) not between 10 and 2000 then
    raise exception 'appeal_message_length_invalid' using errcode='22023';
  end if;
  if not exists(select 1 from public.arqon_user_sanctions s
    where s.id=p_sanction_id and s.target_user_id=v_user and s.revoked_at is null
      and s.starts_at<=now() and (s.expires_at is null or s.expires_at>now())) then
    raise exception 'active_own_sanction_not_found' using errcode='P0002';
  end if;
  insert into public.arqon_sanction_appeals(sanction_id,appellant_user_id,message)
  values(p_sanction_id,v_user,btrim(p_message)) returning id into v_appeal_id;
  return v_appeal_id;
exception when unique_violation then
  raise exception 'pending_appeal_already_exists' using errcode='23505';
end;
$$;

create or replace function public.get_my_arqon_sanction_appeals()
returns table(appeal_id bigint,sanction_id bigint,sanction_type text,scope text,
 sanction_reason text,sanction_expires_at timestamptz,sanction_active boolean,
 appeal_message text,appeal_status text,moderator_response text,created_at timestamptz,reviewed_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select a.id,s.id,s.sanction_type,s.scope,s.reason,s.expires_at,
    (s.revoked_at is null and (s.expires_at is null or s.expires_at>now())),
    a.message,a.status,a.moderator_response,coalesce(a.created_at,s.created_at),a.reviewed_at
  from public.arqon_user_sanctions s
  left join lateral (
    select ap.id,ap.message,ap.status,ap.moderator_response,ap.created_at,ap.reviewed_at
    from public.arqon_sanction_appeals ap
    where ap.sanction_id=s.id and ap.appellant_user_id=(select auth.uid())
    order by ap.created_at desc limit 1
  ) a on true
  where s.target_user_id=(select auth.uid())
  order by s.created_at desc limit 100;
$$;

create or replace function public.list_arqon_sanction_appeals(p_status text default 'pending')
returns table(appeal_id bigint,sanction_id bigint,appellant_user_id uuid,appellant_name text,
 appellant_arqon_id bigint,sanction_type text,scope text,sanction_reason text,
 sanction_active boolean,appeal_message text,appeal_status text,moderator_response text,
 created_at timestamptz,reviewed_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  if p_status not in ('pending','accepted','rejected','all') then
    raise exception 'invalid_appeal_status' using errcode='22023';
  end if;
  return query select a.id,s.id,a.appellant_user_id,
    coalesce(p.display_name,p.steam_persona_name,'Игрок'),p.arqon_id,
    s.sanction_type,s.scope,s.reason,
    (s.revoked_at is null and (s.expires_at is null or s.expires_at>now())),
    a.message,a.status,a.moderator_response,a.created_at,a.reviewed_at
  from public.arqon_sanction_appeals a
  join public.arqon_user_sanctions s on s.id=a.sanction_id
  left join public.profiles p on p.user_id=a.appellant_user_id
  where p_status='all' or a.status=p_status
  order by case when a.status='pending' then 0 else 1 end,a.created_at asc limit 300;
end;
$$;

create or replace function public.review_arqon_sanction_appeal(p_appeal_id bigint,p_decision text,p_response text default null)
returns void language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid()); v_sanction_id bigint; v_status text;
begin
  if v_actor is null or not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  if p_decision not in ('accepted','rejected') or char_length(coalesce(p_response,''))>2000 then
    raise exception 'invalid_appeal_decision' using errcode='22023';
  end if;
  select a.sanction_id,a.status into v_sanction_id,v_status
  from public.arqon_sanction_appeals a where a.id=p_appeal_id for update;
  if v_sanction_id is null then raise exception 'appeal_not_found' using errcode='P0002'; end if;
  if v_status<>'pending' then raise exception 'appeal_already_reviewed' using errcode='22023'; end if;
  if p_decision='accepted' and exists(
    select 1 from public.arqon_user_sanctions s where s.id=v_sanction_id
      and s.revoked_at is null and (s.expires_at is null or s.expires_at>now())
  ) then
    perform public.revoke_arqon_sanction(v_sanction_id,
      coalesce(nullif(btrim(p_response),''),'Апелляция удовлетворена'));
  end if;
  update public.arqon_sanction_appeals set status=p_decision,moderator_user_id=v_actor,
    moderator_response=nullif(btrim(p_response),''),reviewed_at=now(),updated_at=now()
  where id=p_appeal_id and status='pending';
end;
$$;

create or replace function public.notify_arqon_appeal_review()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_title text; v_body text;
begin
  if old.status='pending' and new.status in ('accepted','rejected') then
    v_title:=case new.status when 'accepted' then 'Апелляция удовлетворена' else 'Апелляция отклонена' end;
    v_body:=case new.status when 'accepted' then 'Модерация ARQON удовлетворила апелляцию. Санкция снята.'
      else 'Модерация ARQON рассмотрела апелляцию.' end;
    if new.moderator_response is not null then v_body:=v_body||' Ответ: '||left(new.moderator_response,1500); end if;
    insert into public.user_notifications(user_id,notification_type,title,body,target_url,related_id)
    values(new.appellant_user_id,'moderation_notice',v_title,left(v_body,2000),'/appeals/',new.id::text);
  end if;
  return new;
end;
$$;
revoke all on function public.notify_arqon_appeal_review() from public,anon,authenticated;
drop trigger if exists trg_notify_arqon_appeal_review on public.arqon_sanction_appeals;
create trigger trg_notify_arqon_appeal_review after update of status
on public.arqon_sanction_appeals for each row execute function public.notify_arqon_appeal_review();

revoke all on function public.submit_arqon_sanction_appeal(bigint,text) from public,anon;
revoke all on function public.get_my_arqon_sanction_appeals() from public,anon;
revoke all on function public.list_arqon_sanction_appeals(text) from public,anon;
revoke all on function public.review_arqon_sanction_appeal(bigint,text,text) from public,anon;
grant execute on function public.submit_arqon_sanction_appeal(bigint,text) to authenticated;
grant execute on function public.get_my_arqon_sanction_appeals() to authenticated;
grant execute on function public.list_arqon_sanction_appeals(text) to authenticated;
grant execute on function public.review_arqon_sanction_appeal(bigint,text,text) to authenticated;
