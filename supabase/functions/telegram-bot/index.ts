import { createClient } from "npm:@supabase/supabase-js@2";
const cors = {"Access-Control-Allow-Origin":"https://arqon-esports.ru","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-telegram-bot-api-secret-token","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const esc=(v:unknown)=>String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");
async function send(token:string,chatId:string,text:string){
 const r=await fetch(`https://api.telegram.org/bot${token}/sendMessage`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:chatId,text,parse_mode:"HTML",disable_web_page_preview:true})});
 const payload=await r.json().catch(()=>({}));
 if(!r.ok||payload?.ok!==true)throw new Error("telegram_send_failed");
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"method_not_allowed"},405);
 const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,bot=Deno.env.get("TELEGRAM_BOT_TOKEN"),secret=Deno.env.get("TELEGRAM_WEBHOOK_SECRET");
 if(!bot||!secret)return json({error:"telegram_not_configured"},503);
 const admin=createClient(url,service,{auth:{persistSession:false}});
 if(new URL(req.url).searchParams.get("mode")==="webhook"){
  if(req.headers.get("x-telegram-bot-api-secret-token")!==secret)return json({error:"unauthorized_webhook"},401);
  const update=await req.json().catch(()=>({})),msg=update?.message,chat=msg?.chat?.id,txt=String(msg?.text??"").trim();
  if(!chat)return json({ok:true});
  const chatId=String(chat);
  const start=txt.match(/^\/start\s+([a-f0-9]{40,80})$/i);
  if(start){
   const {data:link}=await admin.from("telegram_link_tokens").select("token,user_id,expires_at").eq("token",start[1]).gt("expires_at",new Date().toISOString()).maybeSingle();
   if(!link){await send(bot,chatId,"Код подключения недействителен или истёк. Создай новый код в профиле ARQON.");return json({ok:true})}
   const {error}=await admin.from("telegram_accounts").upsert({user_id:link.user_id,chat_id:chatId,telegram_username:msg?.from?.username??null,first_name:msg?.from?.first_name??null,linked_at:new Date().toISOString()},{onConflict:"user_id"});
   if(error)return json({error:"link_save_failed"},500);
   await admin.from("telegram_link_tokens").delete().eq("token",link.token);
   await send(bot,chatId,"✅ Telegram успешно подключён к ARQON! Теперь сюда будут приходить уведомления и ответы техподдержки.");
   return json({ok:true});
  }
  const ticketReply=txt.match(/^\/ticket(?:@\w+)?\s+(\d+)\s+([\s\S]+)$/i);
  if(ticketReply){
   const ticketId=Number(ticketReply[1]),messageText=ticketReply[2].trim();
   if(!Number.isSafeInteger(ticketId)||ticketId<1||messageText.length<1||messageText.length>2000){
    await send(bot,chatId,"Формат ответа: <code>/ticket НОМЕР текст сообщения</code> (до 2000 символов).");
    return json({ok:true});
   }
   const {data:ticket}=await admin.from("support_tickets").select("id,user_id,arqon_id,subject,status").eq("id",ticketId).maybeSingle();
   if(!ticket||ticket.status==="closed"){
    await send(bot,chatId,"⛔ Обращение не найдено или уже закрыто.");
    return json({ok:true});
   }
   const {data:linked}=await admin.from("telegram_accounts").select("user_id").eq("user_id",ticket.user_id).eq("chat_id",chatId).maybeSingle();
   if(!linked){
    await send(bot,chatId,"⛔ Это обращение не привязано к твоему Telegram-аккаунту.");
    return json({ok:true});
   }
   const {error:insertError}=await admin.from("support_ticket_messages").insert({ticket_id:ticketId,sender_user_id:ticket.user_id,sender_role:"player",message:messageText});
   if(insertError){
    await send(bot,chatId,"Не удалось сохранить сообщение. Попробуй ещё раз или напиши на сайте.");
    return json({ok:true});
   }
   await admin.from("support_tickets").update({status:"waiting_admin",updated_at:new Date().toISOString()}).eq("id",ticketId).eq("user_id",ticket.user_id);
   const {data:admins,error:adminsError}=await admin.rpc("get_support_admin_telegram_chats");
   if(!adminsError){
    const note="💬 <b>Ответ игрока · обращение #"+ticketId+"</b>\nARQON #"+(ticket.arqon_id??"—")+"\nТема: <b>"+esc(ticket.subject)+"</b>\n\n"+esc(messageText)+"\n\nОтветить: <code>/reply "+ticketId+" текст</code>\nЗакрыть: <code>/close "+ticketId+"</code>";
    const notifiedChats=new Set<string>();
    for(const recipient of admins||[]){
     const recipientChat=String(recipient.chat_id??"");
     if(!recipientChat||notifiedChats.has(recipientChat))continue;
     notifiedChats.add(recipientChat);
     try{await send(bot,recipientChat,note)}catch(e){console.warn("Support player reply notification failed",e)}
    }
   }
   await send(bot,chatId,"✅ Сообщение добавлено в обращение #"+ticketId+". Поддержка получит уведомление.");
   return json({ok:true});
  }
  const reply=txt.match(/^\/reply(?:@\w+)?\s+(\d+)\s+([\s\S]+)$/i);
  if(reply){
   const ticketId=Number(reply[1]);
   const {data,error}=await admin.rpc("support_ticket_admin_reply",{p_chat_id:chatId,p_ticket_id:ticketId,p_message:reply[2].trim()});
   if(error||!data?.[0]){await send(bot,chatId,"⛔ Не удалось отправить ответ. Проверь номер обращения и права администратора.");return json({ok:true})}
   const target=data[0].player_chat_id;
   if(target)await send(bot,target,`💬 <b>Ответ техподдержки ARQON · обращение #${ticketId}</b>\n\n${esc(reply[2].trim())}\n\nОтветить в Telegram: /ticket ${ticketId} текст`);
   await send(bot,chatId,`✅ Ответ по обращению #${ticketId} отправлен игроку.`);
   return json({ok:true});
  }
  const close=txt.match(/^\/close(?:@\w+)?\s+(\d+)$/i);
  if(close){
   const ticketId=Number(close[1]);
   const {data,error}=await admin.rpc("support_ticket_admin_close",{p_chat_id:chatId,p_ticket_id:ticketId});
   if(error||!data?.[0]){await send(bot,chatId,"⛔ Не удалось закрыть обращение. Проверь номер и права администратора.");return json({ok:true})}
   if(data[0].player_chat_id)await send(bot,data[0].player_chat_id,`🔒 Обращение #${ticketId} закрыто администрацией ARQON. Если вопрос остался, создай новое обращение на сайте.`);
   await send(bot,chatId,`✅ Обращение #${ticketId} закрыто.`);
   return json({ok:true});
  }
  await send(bot,chatId,"🤖 <b>ARQON Support</b>\nПодключи Telegram в окне «Мой профиль» на сайте.\nОтветить в своём обращении: <code>/ticket НОМЕР текст</code>\nАдминистратор отвечает: <code>/reply НОМЕР текст</code>\nЗакрыть обращение: <code>/close НОМЕР</code>");
  return json({ok:true});
 }
 const jwt=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");
 if(!jwt)return json({error:"missing_auth"},401);
 const auth=createClient(url,anon,{auth:{persistSession:false}});
 const {data:userData,error:authErr}=await auth.auth.getUser(jwt);
 if(authErr||!userData.user)return json({error:"unauthorized"},401);
 const actor=userData.user.id,body=await req.json().catch(()=>({})),event=String(body?.event??"");
 if(["support_ticket_created","support_ticket_message"].includes(event)){
  const ticketId=Number(body?.ticket_id);
  if(!Number.isSafeInteger(ticketId)||ticketId<1)return json({error:"invalid_ticket_id"},400);
  const {data:ticket}=await admin.from("support_tickets").select("id,user_id,arqon_id,subject,status").eq("id",ticketId).maybeSingle();
  if(!ticket||ticket.user_id!==actor)return json({error:"forbidden"},403);
  const {data:message}=await admin.from("support_ticket_messages").select("message").eq("ticket_id",ticketId).eq("sender_role","player").order("created_at",{ascending:false}).limit(1).maybeSingle();
  const {data:admins,error:adminsError}=await admin.rpc("get_support_admin_telegram_chats");
  if(adminsError)return json({error:"support_admin_lookup_failed"},500);
  let sent=0;const notifiedChats=new Set<string>();
  for(const recipient of admins||[]){
   if(!recipient.chat_id||notifiedChats.has(String(recipient.chat_id)))continue;
   notifiedChats.add(String(recipient.chat_id));
   const note=`🆘 <b>${event==="support_ticket_created"?"Новое обращение":"Новое сообщение"} · #${ticketId}</b>\nИгрок: ARQON #${ticket.arqon_id??"—"}\nТема: <b>${esc(ticket.subject)}</b>\n\n${esc(message?.message||"Открой сайт для просмотра переписки.")}\n\nОтветить: <code>/reply ${ticketId} текст</code>\nЗакрыть: <code>/close ${ticketId}</code>`;
   try{await send(bot,recipient.chat_id,note);sent++}catch(e){console.warn("Support admin notification failed",e)}
  }
  return json({ok:true,sent,reason:sent?"notified":"admins_not_linked"});
 }
 const offerId=String(body?.offer_id??"");
 if(!offerId||!["offer_created","offer_accepted"].includes(event))return json({error:"invalid_event"},400);
 const {data:offer}=await admin.from("team_player_offers").select("id,team_id,team_name,player_user_id,player_name,player_arqon_id,offered_role,created_by").eq("id",offerId).maybeSingle();
 if(!offer)return json({error:"offer_not_found"},404);
 let recipient:string,message:string;
 if(event==="offer_created"){
  if(offer.created_by!==actor)return json({error:"forbidden"},403);
  recipient=offer.player_user_id;
  message=`🎮 <b>Новое предложение от команды!</b>\nКоманда: <b>${esc(offer.team_name)}</b>\nРоль: ${esc(offer.offered_role||"не указана")}\nОткрой профиль ARQON, чтобы принять или отклонить предложение.`;
 }else{
  if(offer.player_user_id!==actor)return json({error:"forbidden"},403);
  const {data:team}=await admin.from("team_profiles").select("captain_arqon_id").eq("team_id",offer.team_id).maybeSingle();
  if(!team?.captain_arqon_id)return json({ok:true,sent:false,reason:"captain_not_set"});
  const {data:captain}=await admin.from("profiles").select("user_id").eq("arqon_id",team.captain_arqon_id).maybeSingle();
  if(!captain?.user_id)return json({ok:true,sent:false,reason:"captain_not_found"});
  recipient=captain.user_id;
  message=`🤝 <b>Игрок принял предложение!</b>\nИгрок: <b>${esc(offer.player_name)}</b> · ARQON #${offer.player_arqon_id}\nКоманда: <b>${esc(offer.team_name)}</b>\nЗайди в профиль команды и оформи переход в состав.`;
 }
 const {data:tg}=await admin.from("telegram_accounts").select("chat_id").eq("user_id",recipient).maybeSingle();
 if(!tg?.chat_id)return json({ok:true,sent:false,reason:"telegram_not_linked"});
 await send(bot,tg.chat_id,message);return json({ok:true,sent:true});
});
