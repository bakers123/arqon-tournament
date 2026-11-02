-- ARQON organizer roles foundation. Additive only; does not alter legacy player/public policies.
create schema if not exists private;

create table if not exists private.organizer_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'editor')),
  created_at timestamptz not null default now()
);

alter table private.organizer_roles enable row level security;
revoke all on schema private from public, anon, authenticated;
revoke all on table private.organizer_roles from public, anon, authenticated;

create or replace function public.current_organizer_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select r.role
  from private.organizer_roles as r
  where r.user_id = (select auth.uid())
  limit 1;
$$;

create or replace function public.has_organizer_role(required_role text default 'editor')
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    case public.current_organizer_role()
      when 'owner' then 3
      when 'admin' then 2
      when 'editor' then 1
      else 0
    end >=
    case required_role
      when 'owner' then 3
      when 'admin' then 2
      when 'editor' then 1
      else 99
    end;
$$;

revoke all on function public.current_organizer_role() from public, anon;
revoke all on function public.has_organizer_role(text) from public, anon;
grant execute on function public.current_organizer_role() to authenticated;
grant execute on function public.has_organizer_role(text) to authenticated;

comment on table private.organizer_roles is
  'Private role assignments for ARQON organizers. Manage only through trusted administrative workflow.';
