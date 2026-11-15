create or replace function public.list_support_tickets_admin()
returns table(ticket_id bigint,arqon_id bigint,player_name text,subject text,status text,created_at timestamptz,updated_at timestamptz,last_message text,last_sender_role text)
language plpgsql stable security definer set search_path=''
as $function$
begin
 if not exists(select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin','editor')) then raise exception 'not_authorized_admin'; end if;
 return query
 select t.id,t.arqon_id,coalesce(nullif(p.display_name,''),'Игрок #'||coalesce(t.arqon_id::text,'?')),t.subject,t.status,t.created_at,t.updated_at,
  (select m.message from public.support_ticket_messages m where m.ticket_id=t.id order by m.created_at desc limit 1),
  (select m.sender_role from public.support_ticket_messages m where m.ticket_id=t.id order by m.created_at desc limit 1)
 from public.support_tickets t left join public.profiles p on p.user_id=t.user_id
 order by case when t.status='closed' then 1 else 0 end,t.updated_at desc limit 200;
end
$function$;

create or replace function public.get_support_ticket_messages_admin(p_ticket_id bigint)
returns table(message_id bigint,sender_role text,message text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $function$
begin
 if not exists(select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin','editor')) then raise exception 'not_authorized_admin'; end if;
 if not exists(select 1 from public.support_tickets t where t.id=p_ticket_id) then raise exception 'ticket_not_found'; end if;
 return query select m.id,m.sender_role,m.message,m.created_at from public.support_ticket_messages m where m.ticket_id=p_ticket_id order by m.created_at asc;
end
$function$;

create or replace function public.reply_support_ticket_admin(p_ticket_id bigint,p_message text)
returns table(player_chat_id text,player_arqon_id bigint)
language plpgsql security definer set search_path=''
as $function$
declare v_admin uuid:=auth.uid(); v_player uuid; v_arqon bigint; v_chat text; v_message text:=btrim(coalesce(p_message,''));
begin
 if not exists(select 1 from private.organizer_roles r where r.user_id=v_admin and r.role in ('owner','admin','editor')) then raise exception 'not_authorized_admin'; end if;
 if char_length(v_message) not between 1 and 2000 then raise exception 'message_length_invalid'; end if;
 select t.user_id,t.arqon_id,ta.chat_id into v_player,v_arqon,v_chat from public.support_tickets t left join public.telegram_accounts ta on ta.user_id=t.user_id where t.id=p_ticket_id and t.status<>'closed';
 if v_player is null then raise exception 'ticket_not_found_or_closed'; end if;
 insert into public.support_ticket_messages(ticket_id,sender_user_id,sender_role,message) values(p_ticket_id,v_admin,'admin',v_message);
 update public.support_tickets set status='waiting_user',updated_at=now() where id=p_ticket_id;
 return query select v_chat,v_arqon;
end
$function$;

create or replace function public.close_support_ticket_admin(p_ticket_id bigint)
returns table(player_chat_id text,player_arqon_id bigint)
language plpgsql security definer set search_path=''
as $function$
declare v_admin uuid:=auth.uid(); v_player uuid; v_arqon bigint; v_chat text;
begin
 if not exists(select 1 from private.organizer_roles r where r.user_id=v_admin and r.role in ('owner','admin','editor')) then raise exception 'not_authorized_admin'; end if;
 select t.user_id,t.arqon_id,ta.chat_id into v_player,v_arqon,v_chat from public.support_tickets t left join public.telegram_accounts ta on ta.user_id=t.user_id where t.id=p_ticket_id;
 if v_player is null then raise exception 'ticket_not_found'; end if;
 update public.support_tickets set status='closed',updated_at=now() where id=p_ticket_id;
 insert into public.support_ticket_messages(ticket_id,sender_user_id,sender_role,message) values(p_ticket_id,v_admin,'admin','Обращение закрыто администрацией.');
 return query select v_chat,v_arqon;
end
$function$;

revoke all on function public.list_support_tickets_admin() from public,anon;
revoke all on function public.get_support_ticket_messages_admin(bigint) from public,anon;
revoke all on function public.reply_support_ticket_admin(bigint,text) from public,anon;
revoke all on function public.close_support_ticket_admin(bigint) from public,anon;
grant execute on function public.list_support_tickets_admin() to authenticated;
grant execute on function public.get_support_ticket_messages_admin(bigint) to authenticated;
grant execute on function public.reply_support_ticket_admin(bigint,text) to authenticated;
grant execute on function public.close_support_ticket_admin(bigint) to authenticated;
