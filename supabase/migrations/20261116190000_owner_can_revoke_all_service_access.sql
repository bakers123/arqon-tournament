-- Let the owner revoke a full organizer role explicitly, while granting only bracket_editor.
create or replace function public.set_service_access(p_user_id uuid, p_allowed boolean)
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
  select r.role into existing_role from private.organizer_roles r where r.user_id = p_user_id;
  if existing_role = 'owner' or existing_role = 'judge' then
    raise exception 'owner and judge roles are managed separately' using errcode = '22023';
  end if;
  if p_allowed then
    if existing_role is null then
      insert into private.organizer_roles(user_id, role) values (p_user_id, 'bracket_editor')
      on conflict (user_id) do nothing;
    end if;
  else
    delete from private.organizer_roles
    where user_id = p_user_id and role in ('admin','editor','bracket_editor');
  end if;
end;
$$;
revoke all on function public.set_service_access(uuid, boolean) from public, anon;
grant execute on function public.set_service_access(uuid, boolean) to authenticated;
comment on function public.set_service_access(uuid, boolean) is
  'Owner-only. Grants bracket-only access to accounts without an organizer role; revocation removes bracket_editor or the complete admin/editor role.';
