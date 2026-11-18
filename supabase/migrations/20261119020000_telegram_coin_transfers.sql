alter table public.arqon_coin_transactions
  drop constraint if exists arqon_coin_transactions_transaction_type_check;
alter table public.arqon_coin_transactions
  add constraint arqon_coin_transactions_transaction_type_check
  check (transaction_type = any (array['welcome','activity','achievement','tournament','purchase','refund','admin_adjustment','transfer']::text[]));

create or replace function public.telegram_transfer_arqon_coins(
  p_chat_id text,
  p_recipient_username text,
  p_amount bigint
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_sender_user uuid;
  v_sender record;
  v_recipient record;
  v_matches integer;
  v_sender_balance bigint;
  v_recipient_balance bigint;
  v_reference text;
  v_username text;
begin
  if coalesce(nullif(current_setting('request.jwt.claim.role',true),''),coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role','') <> 'service_role' then
    raise exception 'forbidden';
  end if;
  if p_chat_id is null or p_chat_id !~ '^[0-9]{1,24}$' then
    raise exception 'telegram_not_linked';
  end if;
  if p_amount is null or p_amount < 1 or p_amount > 1000000 then
    raise exception 'pay_amount_invalid';
  end if;
  v_username:=lower(regexp_replace(btrim(coalesce(p_recipient_username,'')),'^@',''));
  if v_username !~ '^[a-z0-9_]{5,32}$' then
    raise exception 'pay_username_invalid';
  end if;

  select ta.user_id into v_sender_user
  from public.telegram_accounts ta
  where ta.chat_id=p_chat_id
  order by ta.linked_at desc
  limit 1;
  if v_sender_user is null then raise exception 'telegram_not_linked'; end if;

  select p.arqon_id,p.user_id,
    coalesce(nullif(p.display_name,''),nullif(p.game_nick,''),nullif(p.steam_persona_name,''),'Игрок') as player_name,
    coalesce(ta.telegram_username,'') as telegram_username
  into v_sender
  from public.profiles p
  left join lateral (
    select telegram_username from public.telegram_accounts
    where user_id=p.user_id order by linked_at desc limit 1
  ) ta on true
  where p.user_id=v_sender_user;
  if v_sender.arqon_id is null then raise exception 'profile_required'; end if;

  select count(distinct p.arqon_id) into v_matches
  from public.telegram_accounts ta
  join public.profiles p on p.user_id=ta.user_id
  where lower(ta.telegram_username)=v_username;
  if v_matches=0 then raise exception 'pay_recipient_not_found'; end if;
  if v_matches>1 then raise exception 'pay_recipient_ambiguous'; end if;

  select p.arqon_id,p.user_id,
    coalesce(nullif(p.display_name,''),nullif(p.game_nick,''),nullif(p.steam_persona_name,''),'Игрок') as player_name,
    ta.chat_id
  into v_recipient
  from public.telegram_accounts ta
  join public.profiles p on p.user_id=ta.user_id
  where lower(ta.telegram_username)=v_username
  order by ta.linked_at desc
  limit 1;
  if v_recipient.user_id=v_sender_user or v_recipient.arqon_id=v_sender.arqon_id then
    raise exception 'pay_self_transfer';
  end if;

  insert into public.arqon_coin_wallets(arqon_id,balance)
  values(v_sender.arqon_id,0),(v_recipient.arqon_id,0)
  on conflict(arqon_id) do nothing;

  perform 1 from public.arqon_coin_wallets
  where arqon_id in (v_sender.arqon_id,v_recipient.arqon_id)
  order by arqon_id
  for update;

  select balance into v_sender_balance from public.arqon_coin_wallets where arqon_id=v_sender.arqon_id;
  select balance into v_recipient_balance from public.arqon_coin_wallets where arqon_id=v_recipient.arqon_id;
  if v_sender_balance<p_amount then raise exception 'pay_insufficient_funds'; end if;

  update public.arqon_coin_wallets
  set balance=balance-p_amount,updated_at=now()
  where arqon_id=v_sender.arqon_id
  returning balance into v_sender_balance;

  update public.arqon_coin_wallets
  set balance=balance+p_amount,updated_at=now()
  where arqon_id=v_recipient.arqon_id
  returning balance into v_recipient_balance;

  v_reference:='tgpay:'||pg_catalog.gen_random_uuid()::text;
  insert into public.arqon_coin_transactions(arqon_id,amount,balance_after,transaction_type,description,reference_key)
  values
   (v_sender.arqon_id,-p_amount,v_sender_balance,'transfer','Перевод игроку @'||v_username,v_reference||':out'),
   (v_recipient.arqon_id,p_amount,v_recipient_balance,'transfer','Перевод от @'||coalesce(nullif(v_sender.telegram_username,''),'ARQON #'||v_sender.arqon_id::text),v_reference||':in');

  return jsonb_build_object(
    'ok',true,
    'amount',p_amount,
    'sender_arqon_id',v_sender.arqon_id,
    'sender_name',v_sender.player_name,
    'sender_balance',v_sender_balance,
    'recipient_arqon_id',v_recipient.arqon_id,
    'recipient_name',v_recipient.player_name,
    'recipient_username',v_username,
    'recipient_chat_id',v_recipient.chat_id,
    'recipient_balance',v_recipient_balance
  );
end;
$function$;

revoke all on function public.telegram_transfer_arqon_coins(text,text,bigint) from public,anon,authenticated;
grant execute on function public.telegram_transfer_arqon_coins(text,text,bigint) to service_role;
