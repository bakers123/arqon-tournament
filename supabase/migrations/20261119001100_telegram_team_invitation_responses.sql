create or replace function public.telegram_team_action(
  p_chat_id text,p_action text,p_team_id text default null,p_team_name text default null,
  p_target_arqon_id bigint default null,p_role text default null,p_confirmation text default null
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_user_id uuid; v_profile public.profiles%rowtype; v_data jsonb; v_team jsonb; v_player jsonb; v_account_id text; v_result jsonb; v_invitation uuid;
begin
 if p_chat_id is null or p_chat_id !~ '^[0-9]{1,24}$' then raise exception 'telegram_not_linked'; end if;
 select ta.user_id into v_user_id from public.telegram_accounts ta where ta.chat_id=p_chat_id order by ta.linked_at desc limit 1;
 if v_user_id is null then raise exception 'telegram_not_linked'; end if;
 select * into v_profile from public.profiles p where p.user_id=v_user_id;
 if not found then raise exception 'profile_required'; end if;
 perform pg_catalog.set_config('request.jwt.claim.sub',v_user_id::text,true);
 if p_action='create' then return public.create_arqon_team(p_team_name);
 elsif p_action='leave' then perform public.leave_arqon_team(p_team_id); return jsonb_build_object('ok',true,'action',p_action);
 elsif p_action='invite' then v_invitation:=public.create_team_invitation(p_team_id,p_target_arqon_id); return jsonb_build_object('ok',true,'invitation_id',v_invitation);
 elsif p_action in ('accept_invitation','decline_invitation') then
  if coalesce(p_confirmation,'') !~* '^[0-9a-f-]{36}$' then raise exception 'invalid_invitation'; end if;
  perform public.respond_team_invitation(p_confirmation::uuid,p_action='accept_invitation');
  return jsonb_build_object('ok',true,'action',p_action);
 elsif p_action in ('release','promote','demote','set_main','set_reserve','set_deputy') then
  if p_team_id is null or p_target_arqon_id is null then raise exception 'invalid_target'; end if;
  select tr.data into v_data from public.tournament tr where tr.id=1;
  select t into v_team from pg_catalog.jsonb_array_elements(coalesce(v_data->'teams','[]'::jsonb)) t where t->>'id'=p_team_id limit 1;
  if v_team is null then raise exception 'team_not_found'; end if;
  select pl into v_player from pg_catalog.jsonb_array_elements(coalesce(v_team->'players','[]'::jsonb)) pl where nullif(pl->>'arqonId','')::bigint=p_target_arqon_id limit 1;
  if v_player is null then raise exception 'player_not_found'; end if;
  v_account_id:=v_player->>'account_id';
  if p_action in ('release','promote','demote') then perform public.manage_team_roster(p_team_id,v_account_id,p_action);
  else perform public.set_arqon_team_member_role(p_team_id,v_account_id,case p_action when 'set_main' then 'main' when 'set_reserve' then 'reserve' else 'deputy' end); end if;
  return jsonb_build_object('ok',true,'action',p_action);
 elsif p_action='transfer_captain' then perform public.transfer_arqon_team_captain(p_team_id,p_target_arqon_id); return jsonb_build_object('ok',true,'action',p_action);
 elsif p_action='delete' then perform public.delete_arqon_team(p_team_id,p_confirmation); return jsonb_build_object('ok',true,'action',p_action);
 else raise exception 'invalid_action'; end if;
end;$function$;
revoke all on function public.telegram_team_action(text,text,text,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.telegram_team_action(text,text,text,text,bigint,text,text) to service_role;
