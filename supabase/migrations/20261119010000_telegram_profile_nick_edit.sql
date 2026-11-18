create or replace function public.telegram_update_profile_nick(
  p_chat_id text,
  p_nick text,
  p_field text default 'display_name'
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid;
  v_nick text:=nullif(regexp_replace(btrim(coalesce(p_nick,'')), '\s+', ' ', 'g'),'');
  v_profile public.profiles%rowtype;
begin
  if p_chat_id is null or p_chat_id !~ '^[0-9]{1,24}$' then
    raise exception 'telegram_not_linked';
  end if;
  if p_field not in ('display_name','game_nick') then
    raise exception 'invalid_nick_field';
  end if;
  if v_nick is null or char_length(v_nick)<2 or char_length(v_nick)>32 then
    raise exception 'nick_length_invalid';
  end if;
  if v_nick ~ '[<>]' then
    raise exception 'nick_characters_invalid';
  end if;
  select ta.user_id into v_user_id
  from public.telegram_accounts ta
  where ta.chat_id=p_chat_id
  order by ta.linked_at desc
  limit 1;
  if v_user_id is null then raise exception 'telegram_not_linked'; end if;

  update public.profiles p
  set display_name=case when p_field='display_name' then v_nick else p.display_name end,
      game_nick=case when p_field='game_nick' then v_nick else p.game_nick end,
      updated_at=now()
  where p.user_id=v_user_id
  returning * into v_profile;
  if not found then raise exception 'profile_required'; end if;

  return jsonb_build_object(
    'ok',true,
    'arqon_id',v_profile.arqon_id,
    'display_name',v_profile.display_name,
    'game_nick',v_profile.game_nick,
    'updated_field',p_field
  );
end;
$function$;

revoke all on function public.telegram_update_profile_nick(text,text,text) from public,anon,authenticated;
grant execute on function public.telegram_update_profile_nick(text,text,text) to service_role;
