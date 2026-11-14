create or replace function public.create_player_access_code(p_player_name text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_code text;
  v_name text := btrim(p_player_name);
begin
  if not public.has_organizer_role('editor') then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if v_name is null or length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid player name' using errcode = '22023';
  end if;
  loop
    -- 12 hexadecimal characters provide 48 bits of random code space.
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    exit when not exists (select 1 from public.access_codes ac where ac.code = v_code);
  end loop;
  insert into public.access_codes(code, player_name) values (v_code, v_name);
  return v_code;
end;
$function$;

revoke all on function public.create_player_access_code(text) from public, anon;
grant execute on function public.create_player_access_code(text) to authenticated;
