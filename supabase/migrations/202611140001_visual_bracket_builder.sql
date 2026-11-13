-- ARQON visual bracket builder: additive schema, role-safe judge workflows.
create extension if not exists pgcrypto;

alter table private.organizer_roles
  drop constraint if exists organizer_roles_role_check;
alter table private.organizer_roles
  add constraint organizer_roles_role_check
  check (role = any (array['owner','admin','editor','judge']::text[]));

create table if not exists public.bracket_documents (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 1 and 120),
  format text not null check (format in ('single','double','round_robin','custom')),
  status text not null default 'draft' check (status in ('draft','published')),
  data jsonb not null default '{"sections":[],"nodes":[],"edges":[],"teams":[]}'::jsonb
    check (jsonb_typeof(data) = 'object'),
  published_data jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz
);

create table if not exists public.bracket_judges (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.bracket_assignments (
  id uuid primary key default gen_random_uuid(),
  bracket_id uuid not null references public.bracket_documents(id) on delete cascade,
  match_id text,
  judge_user_id uuid not null references public.bracket_judges(user_id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.bracket_audit (
  id bigint generated always as identity primary key,
  bracket_id uuid not null references public.bracket_documents(id) on delete cascade,
  match_id text,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists bracket_assignments_lookup_idx
  on public.bracket_assignments (judge_user_id, bracket_id, match_id);
create index if not exists bracket_audit_bracket_created_idx
  on public.bracket_audit (bracket_id, created_at desc);

alter table public.bracket_documents enable row level security;
alter table public.bracket_judges enable row level security;
alter table public.bracket_assignments enable row level security;
alter table public.bracket_audit enable row level security;

revoke all on public.bracket_documents, public.bracket_judges,
  public.bracket_assignments, public.bracket_audit from public, anon, authenticated;
grant select on public.bracket_documents to anon, authenticated;
grant insert, update, delete on public.bracket_documents to authenticated;
grant select on public.bracket_judges, public.bracket_assignments, public.bracket_audit to authenticated;
grant insert, update, delete on public.bracket_assignments to authenticated;

drop policy if exists bracket_documents_public_published_read on public.bracket_documents;
create policy bracket_documents_public_published_read on public.bracket_documents
for select to anon, authenticated using (status = 'published');

drop policy if exists bracket_documents_editor_all on public.bracket_documents;
create policy bracket_documents_editor_all on public.bracket_documents
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

drop policy if exists bracket_judges_editor_read on public.bracket_judges;
create policy bracket_judges_editor_read on public.bracket_judges
for select to authenticated using (public.has_organizer_role('editor'));

drop policy if exists bracket_assignments_editor_all on public.bracket_assignments;
create policy bracket_assignments_editor_all on public.bracket_assignments
for all to authenticated
using (public.has_organizer_role('editor'))
with check (public.has_organizer_role('editor'));

drop policy if exists bracket_assignments_judge_read_own on public.bracket_assignments;
create policy bracket_assignments_judge_read_own on public.bracket_assignments
for select to authenticated using (judge_user_id = (select auth.uid()));

drop policy if exists bracket_audit_editor_read on public.bracket_audit;
create policy bracket_audit_editor_read on public.bracket_audit
for select to authenticated using (public.has_organizer_role('editor'));

drop policy if exists bracket_audit_judge_read_own on public.bracket_audit;
create policy bracket_audit_judge_read_own on public.bracket_audit
for select to authenticated using (actor_id = (select auth.uid()));

create or replace function public.save_bracket_document(
  p_id uuid,
  p_title text,
  p_format text,
  p_data jsonb,
  p_publish boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if not public.has_organizer_role('editor') then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if p_title is null or length(btrim(p_title)) not between 1 and 120 then
    raise exception 'invalid bracket title' using errcode = '22023';
  end if;
  if p_format not in ('single','double','round_robin','custom') then
    raise exception 'invalid bracket format' using errcode = '22023';
  end if;
  if jsonb_typeof(p_data) <> 'object'
     or jsonb_typeof(p_data->'nodes') <> 'array'
     or jsonb_typeof(p_data->'edges') <> 'array'
     or jsonb_typeof(p_data->'sections') <> 'array' then
    raise exception 'invalid bracket document structure' using errcode = '22023';
  end if;

  insert into public.bracket_documents
    (id, title, format, status, data, published_data, created_by, updated_by, published_at)
  values
    (v_id, btrim(p_title), p_format,
     case when p_publish then 'published' else 'draft' end,
     p_data, case when p_publish then p_data else null end,
     (select auth.uid()), (select auth.uid()),
     case when p_publish then now() else null end)
  on conflict (id) do update set
    title = excluded.title,
    format = excluded.format,
    data = excluded.data,
    status = case when p_publish then 'published' else bracket_documents.status end,
    published_data = case when p_publish then excluded.data else bracket_documents.published_data end,
    published_at = case when p_publish then now() else bracket_documents.published_at end,
    updated_by = (select auth.uid()),
    updated_at = now();

  insert into public.bracket_audit(bracket_id, actor_id, action, details)
  values (v_id, (select auth.uid()),
    case when p_publish then 'published' else 'saved_draft' end,
    jsonb_build_object('title', btrim(p_title), 'format', p_format));

  return v_id;
end;
$$;

create or replace function public.update_assigned_bracket_match(
  p_bracket_id uuid,
  p_match_id text,
  p_maps jsonb,
  p_status text,
  p_result_type text default 'normal',
  p_winner_side integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.bracket_documents%rowtype;
  v_node jsonb;
  v_ordinal bigint;
  v_role text := public.current_organizer_role();
begin
  if v_role not in ('owner','admin','editor','judge') then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if v_role = 'judge' and not exists (
    select 1 from public.bracket_assignments a
    where a.bracket_id = p_bracket_id
      and a.judge_user_id = (select auth.uid())
      and (a.match_id is null or a.match_id = p_match_id)
  ) then
    raise exception 'match is not assigned to this judge' using errcode = '42501';
  end if;
  if jsonb_typeof(p_maps) <> 'array' or jsonb_array_length(p_maps) > 5 then
    raise exception 'invalid map results' using errcode = '22023';
  end if;
  if p_status not in ('pending','live','completed','technical','cancelled') then
    raise exception 'invalid match status' using errcode = '22023';
  end if;
  if p_result_type not in ('normal','technical_win','technical_loss','disqualified','cancelled') then
    raise exception 'invalid result type' using errcode = '22023';
  end if;
  if p_winner_side not in (1,2) and p_winner_side is not null then
    raise exception 'invalid winner side' using errcode = '22023';
  end if;

  select * into v_doc
  from public.bracket_documents
  where id = p_bracket_id and status = 'published'
  for update;
  if not found or v_doc.published_data is null then
    raise exception 'published bracket not found' using errcode = 'P0002';
  end if;

  select e.value, e.ordinality into v_node, v_ordinal
  from jsonb_array_elements(v_doc.published_data->'nodes') with ordinality as e(value, ordinality)
  where e.value->>'id' = p_match_id
  limit 1;
  if v_node is null then
    raise exception 'match not found' using errcode = 'P0002';
  end if;

  v_node := v_node || jsonb_build_object(
    'maps', p_maps,
    'status', p_status,
    'resultType', p_result_type,
    'winnerSide', p_winner_side
  );

  update public.bracket_documents
  set published_data = jsonb_set(published_data, array['nodes',(v_ordinal - 1)::text], v_node, false),
      updated_by = (select auth.uid()),
      updated_at = now()
  where id = p_bracket_id;

  insert into public.bracket_audit(bracket_id, match_id, actor_id, action, details)
  values (p_bracket_id, p_match_id, (select auth.uid()), 'match_result_updated',
    jsonb_build_object('status', p_status, 'resultType', p_result_type,
      'winnerSide', p_winner_side, 'maps', p_maps));
end;
$$;

create or replace function public.assign_bracket_judge_role(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'user id required' using errcode = '22023';
  end if;
  insert into private.organizer_roles(user_id, role)
  values (p_user_id, 'judge')
  on conflict (user_id) do update set role = 'judge';
  insert into public.bracket_judges(user_id, username)
  values (p_user_id, 'sudiya')
  on conflict (user_id) do update set username = excluded.username;
end;
$$;

revoke all on function public.save_bracket_document(uuid,text,text,jsonb,boolean) from public, anon;
grant execute on function public.save_bracket_document(uuid,text,text,jsonb,boolean) to authenticated;
revoke all on function public.update_assigned_bracket_match(uuid,text,jsonb,text,text,integer) from public, anon;
grant execute on function public.update_assigned_bracket_match(uuid,text,jsonb,text,text,integer) to authenticated;
revoke all on function public.assign_bracket_judge_role(uuid) from public, anon, authenticated;
grant execute on function public.assign_bracket_judge_role(uuid) to service_role;

comment on table public.bracket_documents is 'ARQON visual tournament bracket documents. Public reads only the published snapshot.';
comment on table public.bracket_assignments is 'Judge assignments: null match_id grants access to all matches in a bracket.';
comment on table public.bracket_audit is 'Audit trail for bracket structure and match-result changes.';
