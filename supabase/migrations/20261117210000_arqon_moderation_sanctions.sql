-- ARQON moderation sanctions: warnings, scoped restrictions and account-level platform blocks.
-- This does not ban users from Supabase Auth; it enforces restrictions in ARQON data policies.

create table if not exists public.arqon_user_sanctions (
  id bigint generated always as identity primary key,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  issued_by uuid not null references auth.users(id) on delete restrict,
  sanction_type text not null check (sanction_type in ('warning','restriction','account_block')),
  scope text not null check (scope in ('social','content','account')),
  reason text not null check (char_length(btrim(reason)) between 5 and 2000),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoke_reason text check (revoke_reason is null or char_length(revoke_reason)<=1000),
  created_at timestamptz not null default now(),
  constraint arqon_sanction_expiry_after_start check (expires_at is null or expires_at > starts_at),
  constraint arqon_sanction_type_scope check (
    (sanction_type='warning' and scope='social') or
    (sanction_type='restriction' and scope in ('social','content')) or
    (sanction_type='account_block' and scope='account')
  )
);
create index if not exists arqon_user_sanctions_active_idx
  on public.arqon_user_sanctions(target_user_id, expires_at desc)
  where revoked_at is null;
alter table public.arqon_user_sanctions enable row level security;
revoke all on public.arqon_user_sanctions from public, anon, authenticated;

create table if not exists public.arqon_sanction_audit (
  id bigint generated always as identity primary key,
  sanction_id bigint not null references public.arqon_user_sanctions(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in ('issued','revoked')),
  details text,
  created_at timestamptz not null default now()
);
create index if not exists arqon_sanction_audit_sanction_idx
  on public.arqon_sanction_audit(sanction_id,created_at desc);
alter table public.arqon_sanction_audit enable row level security;
revoke all on public.arqon_sanction_audit from public, anon, authenticated;

create or replace function public.arqon_user_has_active_sanction(
  p_user_id uuid, p_scope text default 'account'
) returns boolean
language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.arqon_user_sanctions s
    where s.target_user_id=p_user_id and s.revoked_at is null
      and (s.expires_at is null or s.expires_at>now())
      and (s.sanction_type='account_block' or s.scope=p_scope)
  );
$$;
revoke all on function public.arqon_user_has_active_sanction(uuid,text) from public,anon;
grant execute on function public.arqon_user_has_active_sanction(uuid,text) to authenticated;

create or replace function public.issue_arqon_sanction(
  p_target_user_id uuid, p_type text, p_scope text, p_reason text, p_duration_days integer default null
) returns bigint
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid()); v_id bigint; v_expiry timestamptz;
begin
  if v_actor is null or not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  if p_target_user_id is null or p_target_user_id=v_actor then
    raise exception 'invalid_sanction_target' using errcode='22023';
  end if;
  if p_type not in ('warning','restriction','account_block')
    or p_scope not in ('social','content','account')
    or char_length(btrim(coalesce(p_reason,''))) not between 5 and 2000
    or (p_type='warning' and p_scope<>'social')
    or (p_type='restriction' and p_scope not in ('social','content'))
    or (p_type='account_block' and p_scope<>'account')
    or (p_duration_days is not null and p_duration_days not between 1 and 365) then
    raise exception 'invalid_sanction_parameters' using errcode='22023';
  end if;
  if p_type='account_block' and p_duration_days is null then
    raise exception 'account_block_requires_duration' using errcode='22023';
  end if;
  if p_duration_days is not null then v_expiry:=now()+make_interval(days=>p_duration_days); end if;
  insert into public.arqon_user_sanctions(target_user_id,issued_by,sanction_type,scope,reason,expires_at)
  values(p_target_user_id,v_actor,p_type,p_scope,btrim(p_reason),v_expiry)
  returning id into v_id;
  insert into public.arqon_sanction_audit(sanction_id,actor_user_id,action,details)
  values(v_id,v_actor,'issued',btrim(p_reason));
  return v_id;
end;
$$;

create or replace function public.revoke_arqon_sanction(p_sanction_id bigint,p_reason text default null)
returns void
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid()); v_exists boolean;
begin
  if v_actor is null or not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  if p_reason is not null and char_length(p_reason)>1000 then
    raise exception 'revoke_reason_too_long' using errcode='22023';
  end if;
  update public.arqon_user_sanctions
    set revoked_at=now(),revoked_by=v_actor,revoke_reason=nullif(btrim(p_reason),'')
    where id=p_sanction_id and revoked_at is null and (expires_at is null or expires_at>now());
  get diagnostics v_exists = row_count;
  if not v_exists then raise exception 'active_sanction_not_found' using errcode='P0002'; end if;
  insert into public.arqon_sanction_audit(sanction_id,actor_user_id,action,details)
  values(p_sanction_id,v_actor,'revoked',nullif(btrim(p_reason),''));
end;
$$;

create or replace function public.list_arqon_sanctions(p_target_user_id uuid default null)
returns table(
  sanction_id bigint,target_user_id uuid,target_name text,target_arqon_id bigint,
  sanction_type text,scope text,reason text,issued_by uuid,starts_at timestamptz,
  expires_at timestamptz,revoked_at timestamptz,revoke_reason text,active boolean
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  return query
  select s.id,s.target_user_id,
    coalesce(p.display_name,p.steam_persona_name,'Игрок'),
    p.arqon_id,s.sanction_type,s.scope,s.reason,s.issued_by,s.starts_at,
    s.expires_at,s.revoked_at,s.revoke_reason,
    (s.revoked_at is null and (s.expires_at is null or s.expires_at>now()))
  from public.arqon_user_sanctions s
  left join public.profiles p on p.user_id=s.target_user_id
  where p_target_user_id is null or s.target_user_id=p_target_user_id
  order by s.created_at desc limit 300;
end;
$$;

create or replace function public.get_my_arqon_moderation_status()
returns table(is_account_blocked boolean,is_social_restricted boolean,is_content_restricted boolean,active_reasons text[])
language sql stable security definer set search_path=''
as $$
  select
    public.arqon_user_has_active_sanction((select auth.uid()),'account'),
    public.arqon_user_has_active_sanction((select auth.uid()),'social'),
    public.arqon_user_has_active_sanction((select auth.uid()),'content'),
    coalesce(array_agg(s.reason) filter(where s.id is not null),'{}'::text[])
  from public.arqon_user_sanctions s
  where s.target_user_id=(select auth.uid()) and s.revoked_at is null
    and (s.expires_at is null or s.expires_at>now())
  group by (select auth.uid())
  union all
  select false,false,false,'{}'::text[]
  where (select auth.uid()) is not null
    and not exists(select 1 from public.arqon_user_sanctions s where s.target_user_id=(select auth.uid())
      and s.revoked_at is null and (s.expires_at is null or s.expires_at>now()));
$$;

create or replace function public.get_arqon_sanction_audit(p_sanction_id bigint)
returns table(actor_name text,action text,details text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not (public.has_organizer_role('owner') or public.has_organizer_role('admin')) then
    raise exception 'not_authorized_moderator' using errcode='42501';
  end if;
  return query select coalesce(p.display_name,p.steam_persona_name,'Модератор'),
    a.action,a.details,a.created_at
  from public.arqon_sanction_audit a
  left join public.profiles p on p.user_id=a.actor_user_id
  where a.sanction_id=p_sanction_id order by a.created_at desc limit 50;
end;
$$;

revoke all on function public.issue_arqon_sanction(uuid,text,text,text,integer) from public,anon;
revoke all on function public.revoke_arqon_sanction(bigint,text) from public,anon;
revoke all on function public.list_arqon_sanctions(uuid) from public,anon;
revoke all on function public.get_my_arqon_moderation_status() from public,anon;
revoke all on function public.get_arqon_sanction_audit(bigint) from public,anon;
grant execute on function public.issue_arqon_sanction(uuid,text,text,text,integer) to authenticated;
grant execute on function public.revoke_arqon_sanction(bigint,text) to authenticated;
grant execute on function public.list_arqon_sanctions(uuid) to authenticated;
grant execute on function public.get_my_arqon_moderation_status() to authenticated;
grant execute on function public.get_arqon_sanction_audit(bigint) to authenticated;

-- Server-side enforcement for core community actions; UI checks are not trusted.
drop policy if exists arqon_follows_insert_own on public.arqon_follows;
create policy arqon_follows_insert_own on public.arqon_follows for insert to authenticated
with check (follower_user_id=(select auth.uid())
  and not public.arqon_social_is_blocked(followed_user_id)
  and not public.arqon_user_has_active_sanction((select auth.uid()),'social'));
drop policy if exists arqon_friend_requests_insert_sender on public.arqon_friend_requests;
create policy arqon_friend_requests_insert_sender on public.arqon_friend_requests for insert to authenticated
with check (sender_user_id=(select auth.uid()) and status='pending'
  and not public.arqon_social_is_blocked(receiver_user_id)
  and not public.arqon_user_has_active_sanction((select auth.uid()),'social'));
drop policy if exists arqon_direct_messages_send_own on public.arqon_direct_messages;
create policy arqon_direct_messages_send_own on public.arqon_direct_messages for insert to authenticated
with check (sender_user_id=(select auth.uid())
  and exists(select 1 from public.arqon_friend_requests f where f.status='accepted'
    and ((f.sender_user_id=arqon_direct_messages.sender_user_id and f.receiver_user_id=arqon_direct_messages.recipient_user_id)
      or (f.sender_user_id=arqon_direct_messages.recipient_user_id and f.receiver_user_id=arqon_direct_messages.sender_user_id)))
  and not public.arqon_social_is_blocked(recipient_user_id)
  and not public.arqon_user_has_active_sanction((select auth.uid()),'social'));
drop policy if exists arqon_reports_insert_self on public.arqon_player_reports;
create policy arqon_reports_insert_self on public.arqon_player_reports for insert to authenticated
with check (reporter_user_id=(select auth.uid()) and status='open' and moderator_user_id is null and moderator_note is null
  and not public.arqon_user_has_active_sanction((select auth.uid()),'account'));

