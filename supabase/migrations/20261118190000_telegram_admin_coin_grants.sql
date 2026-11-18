-- Secure Telegram admin grants of ARQON Coins by linked Telegram username.
create or replace function public.telegram_admin_grant_coins(p_chat_id text,p_username text,p_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target record;
  v_count integer;
  v_balance bigint;
  v_reference text;
  v_admin_username text;
begin
  if coalesce(nullif(current_setting('request.jwt.claim.role',true),''),coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role','') <> 'service_role' then
    raise exception 'forbidden';
  end if;
  if not exists (select 1 from public.get_support_admin_telegram_chats() a where a.chat_id=p_chat_id) then
    raise exception 'Нет доступа к выдаче койнов';
  end if;
  if p_amount is null or p_amount < 1 or p_amount > 1000000 then
    raise exception 'Количество должно быть от 1 до 1 000 000';
  end if;
  if nullif(trim(p_username),'') is null then
    raise exception 'Укажи Telegram username игрока';
  end if;
  select ta.telegram_username into v_admin_username
  from public.telegram_accounts ta where ta.chat_id=p_chat_id limit 1;
  select count(distinct p.arqon_id) into v_count
  from public.telegram_accounts ta join public.profiles p on p.user_id=ta.user_id
  where lower(ta.telegram_username)=lower(regexp_replace(trim(p_username),'^@',''));
  if v_count=0 then raise exception 'Игрок с таким Telegram username не найден. Он должен привязать Telegram к ARQON'; end if;
  if v_count>1 then raise exception 'Найдено несколько профилей с таким username. Выдача отменена'; end if;
  select ta.user_id,ta.chat_id,p.arqon_id,coalesce(nullif(p.display_name,''),nullif(p.steam_persona_name,''),'Игрок') as player_name
  into v_target
  from public.telegram_accounts ta
  join public.profiles p on p.user_id=ta.user_id
  where lower(ta.telegram_username)=lower(regexp_replace(trim(p_username),'^@',''))
  order by ta.linked_at desc
  limit 1;
  if v_target.arqon_id is null then raise exception 'У игрока не найден профиль ARQON'; end if;
  insert into public.arqon_coin_wallets(arqon_id,balance) values(v_target.arqon_id,0) on conflict(arqon_id) do nothing;
  select w.balance into v_balance from public.arqon_coin_wallets w where w.arqon_id=v_target.arqon_id for update;
  update public.arqon_coin_wallets set balance=balance+p_amount,updated_at=now()
  where arqon_id=v_target.arqon_id returning balance into v_balance;
  v_reference:='tgadmin:grant:'||gen_random_uuid()::text;
  insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
  values(v_target.arqon_id,p_amount,v_balance,'admin_adjustment',
    'Выдача администратором Telegram'||case when v_admin_username is not null then ' @'||v_admin_username else '' end,
    v_reference);
  return jsonb_build_object('arqon_id',v_target.arqon_id,'player_name',v_target.player_name,
    'target_chat_id',v_target.chat_id,'amount',p_amount,'balance',v_balance);
end;
$$;
revoke all on function public.telegram_admin_grant_coins(text,text,bigint) from public, anon, authenticated;
grant execute on function public.telegram_admin_grant_coins(text,text,bigint) to service_role;
