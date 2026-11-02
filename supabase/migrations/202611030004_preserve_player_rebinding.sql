-- Preserve the legacy behavior when an existing player's one-time code is reissued.
-- Rebind the existing roster row to the new anonymous auth user instead of creating
-- a second row with the same display name.
create or replace function public.redeem_player_access_code(p_code text, p_uid uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_name text;
  v_existing_uid text;
  v_uid_name text;
begin
  if p_uid is null or auth.uid() is distinct from p_uid then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select ac.player_name into v_player_name
  from public.access_codes ac
  where ac.code = upper(trim(p_code))
  for update;

  if v_player_name is null then
    raise exception 'invalid or already used access code' using errcode = '22023';
  end if;

  select p.name into v_uid_name
  from public.players p
  where p.uid = p_uid::text
  for update;

  if v_uid_name is not null and v_uid_name <> v_player_name then
    raise exception 'this session is already linked to another player' using errcode = '23505';
  end if;

  if v_uid_name is null then
    select p.uid into v_existing_uid
    from public.players p
    where p.name = v_player_name
    order by p.uid
    limit 1
    for update;

    if v_existing_uid is not null then
      update public.players set uid = p_uid::text where uid = v_existing_uid;
    else
      insert into public.players(uid, name) values (p_uid::text, v_player_name);
    end if;
  end if;

  delete from public.access_codes where code = upper(trim(p_code));
  return v_player_name;
end;
$function$;

revoke all on function public.redeem_player_access_code(text,uuid) from public, anon, authenticated;
grant execute on function public.redeem_player_access_code(text,uuid) to authenticated;
