-- Owner-controlled access to the ARQON bracket service area.
-- The owner is the only role allowed to grant or revoke editor/admin service access.
create or replace function public.list_service_access_accounts()
returns table (
  user_id uuid,
  email text,
  display_name text,
  created_at timestamptz,
  organizer_role text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(public.current_organizer_role(), '') <> 'owner' then
    raise exception 'owner role required' using errcode = '42501';
  end if;

  return query
  select
    u.id,
    u.email::text,
    coalesce(nullif(p.display_name, ''), nullif(u.raw_user_meta_data ->> 'full_name', ''), nullif(u.raw_user_meta_data ->> 'name', '')),
    u.created_at,
    r.role
  from auth.users as u
  left join public.profiles as p on p.user_id = u.id
  left join private.organizer_roles as r on r.user_id = u.id
  where coalesce(u.is_anonymous, false) = false
  order by u.created_at desc
  limit 500;
end;
$$;

create or replace function public.set_service_access(
  p_user_id uuid,
  p_allowed boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_role text;
begin
  if coalesce(public.current_organizer_role(), '') <> 'owner' then
    raise exception 'owner role required' using errcode = '42501';
  end if;

  if p_user_id is null or p_allowed is null then
    raise exception 'user and access decision are required' using errcode = '22023';
  end if;

  if p_user_id = (select auth.uid()) then
    raise exception 'the owner cannot change their own access here' using errcode = '42501';
  end if;

  select r.role into existing_role
  from private.organizer_roles as r
  where r.user_id = p_user_id;

  if existing_role = 'owner' then
    raise exception 'owner access cannot be changed here' using errcode = '42501';
  end if;

  if existing_role = 'judge' then
    raise exception 'judge access is managed separately' using errcode = '22023';
  end if;

  if p_allowed then
    insert into private.organizer_roles(user_id, role)
    values (p_user_id, 'editor')
    on conflict (user_id) do nothing;
  else
    delete from private.organizer_roles
    where user_id = p_user_id
      and role in ('admin', 'editor');
  end if;
end;
$$;

revoke all on function public.list_service_access_accounts() from public, anon;
revoke all on function public.set_service_access(uuid, boolean) from public, anon;
grant execute on function public.list_service_access_accounts() to authenticated;
grant execute on function public.set_service_access(uuid, boolean) to authenticated;

comment on function public.list_service_access_accounts() is
  'Lists registered non-anonymous accounts and organizer access; owner-only.';
comment on function public.set_service_access(uuid, boolean) is
  'Grants editor access or revokes editor/admin access; owner-only. Judge and owner roles are protected.';
