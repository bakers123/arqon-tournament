create or replace function public.get_organizer_roles_for_users(p_user_ids uuid[])
returns table(user_id uuid, role text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;
  return query
    select r.user_id, r.role::text
    from private.organizer_roles r
    where r.user_id = any(coalesce(p_user_ids, array[]::uuid[]));
end;
$$;
revoke all on function public.get_organizer_roles_for_users(uuid[]) from public, anon, authenticated;
grant execute on function public.get_organizer_roles_for_users(uuid[]) to service_role;