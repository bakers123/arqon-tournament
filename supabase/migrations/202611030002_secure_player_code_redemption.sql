create or replace function public.redeem_player_access_code(p_code text, p_uid uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_player_name text;
begin
  if p_uid is null or auth.uid() is distinct from p_uid then raise exception 'not authorized' using errcode = '42501'; end if;
  select ac.player_name into v_player_name from public.access_codes ac where ac.code = upper(trim(p_code)) for update;
  if v_player_name is null then raise exception 'invalid or already used access code' using errcode = '22023'; end if;
  insert into public.players(uid,name) values(p_uid::text,v_player_name) on conflict(uid) do update set name=excluded.name;
  delete from public.access_codes where code=upper(trim(p_code));
  return v_player_name;
end; $$;
revoke all on function public.redeem_player_access_code(text,uuid) from public,anon,authenticated;
grant execute on function public.redeem_player_access_code(text,uuid) to authenticated;
comment on function public.redeem_player_access_code(text,uuid) is 'Atomically redeems one player access code for the authenticated user.';