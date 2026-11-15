import { createClient } from "npm:@supabase/supabase-js@2";
const cors = {"Access-Control-Allow-Origin":"https://arqon-esports.ru","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-telegram-bot-api-secret-token","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const esc=(v:unknown)=>String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");
const SITE="https://arqon-esports.ru";
const menuMarkup=(isAdmin=false)=>({inline_keyboard:[
 [{text:"👤 Мой профиль",callback_data:"profile"}],
 [{text:"🔔 Уведомления",callback_data:"notifications"}],
 [{text:"🏆 Киберспортивная лига",callback_data:"league"}],
 [{text:"👥 Команды",callback_data:"teams"},{text:"🎯 Игроки",callback_data:"players"}],
 [{text:"🛟 Поддержка",callback_data:"support"}],
 ...(isAdmin?[[{text:"🛡 Панель организатора",callback_data:"organizer"}]]:[])
]});
const backMenu={inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]};
async function linkedUser(admin:any,chatId:string){
 const {data:link}=await admin.from("telegram_accounts").select("user_id,telegram_username,first_name").eq("chat_id",chatId).maybeSingle();
 return link||null;
}
async function renderPanel(bot:string,chatId:string,messageId:number,text:string,keyboard:any){
 try{await telegram(bot,"editMessageText",{chat_id:chatId,message_id:messageId,text,parse_mode:"HTML",disable_web_page_preview:true,reply_markup:keyboard})}
 catch{await send(bot,chatId,text,keyboard)}
}
async function telegram(token:string,method:string,body:Record<string,unknown>){
 const r=await fetch(`https://api.telegram.org/bot${token}/${method}`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
 const payload=await r.json().catch(()=>({}));
 if(!r.ok||payload?.ok!==true)throw new Error("telegram_"+method+"_failed");
 return payload.result;
}
async function send(token:string,chatId:string,text:string,reply_markup?:unknown){
 return await telegram(token,"sendMessage",{chat_id:chatId,text,parse_mode:"HTML",disable_web_page_preview:true,...(reply_markup?{reply_markup}:{})});
}
async function showMenu(token:string,chatId:string,admin:any){
 let isSupportAdmin=false;
 try{const {data}=await admin.rpc("get_support_admin_telegram_chats");isSupportAdmin=(data||[]).some((x:any)=>String(x.chat_id)===chatId)}catch{}
 const greeting="<b>ＡＲＱＯＮ  ＥＳＰＯＲＴＳ</b>\n< i >YOUR GAME. YOUR LEGACY.</i>\n\nДобро пожаловать в ARQON! Управляй своим аккаунтом, следи за лигой и общайся с командой прямо здесь.\n\nВыбери раздел 👇".replace("< i >","<i>");
 await send(token,chatId,greeting,menuMarkup(isSupportAdmin));
}
async function setBotCommands(token:string){
 await telegram(token,"setMyCommands",{commands:[
  {command:"start",description:"Открыть главное меню ARQON"},
  {command:"menu",description:"Показать меню"},
  {command:"profile",description:"Открыть мой профиль ARQON"},
  {command:"help",description:"Команды и помощь"}
 ]});
 await telegram(token,"setChatMenuButton",{menu_button:{type:"commands"}});
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"method_not_allowed"},405);
 const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,bot=Deno.env.get("TELEGRAM_BOT_TOKEN"),secret=Deno.env.get("TELEGRAM_WEBHOOK_SECRET");
 if(!bot||!secret)return json({error:"telegram_not_configured"},503);
 const admin=createClient(url,service,{auth:{persistSession:false}});
 if(new URL(req.url).searchParams.get("mode")==="webhook"){
  if(req.headers.get("x-telegram-bot-api-secret-token")!==secret)return json({error:"unauthorized_webhook"},401);
  const update=await req.json().catch(()=>({}));
  const callback=update?.callback_query;
  if(callback){
   const callbackChat=callback?.message?.chat?.id,callbackId=String(callback?.id??""),action=String(callback?.data??"");
   if(callbackId)try{await telegram(bot,"answerCallbackQuery",{callback_query_id:callbackId})}catch{}
   if(callbackChat){
    const callbackChatId=String(callbackChat);
    if(action==="menu"){
     let isSupportAdmin=false;try{const {data}=await admin.rpc("get_support_admin_telegram_chats");isSupportAdmin=(data||[]).some((x:any)=>String(x.chat_id)===callbackChatId)}catch{}
     const text="<b>ＡＲＱＯＮ  ＥＳＰＯＲＴＳ</b>\n<i>YOUR GAME. YOUR LEGACY.</i>\n\nВыбери нужный раздел 👇";
     try{await telegram(bot,"editMessageText",{chat_id:callbackChatId,message_id:callback.message.message_id,text,parse_mode:"HTML",disable_web_page_preview:true,reply_markup:menuMarkup(isSupportAdmin)})}catch{}
    }else if(action==="profile"){
     const link=await linkedUser(admin,callbackChatId);
     if(!link){
      await renderPanel(bot,callbackChatId,callback.message.message_id,"👤 <b>МОЙ ПРОФИЛЬ ARQON</b>\n\nСначала подключи Telegram к своему аккаунту на сайте. После привязки эта кнопка будет открывать именно твой личный профиль.",{inline_keyboard:[[{text:"🔗 Подключить аккаунт",url:SITE+"/"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
     }else{
      const {data:profile}=await admin.from("profiles").select("arqon_id,display_name,steam_persona_name,avatar_url,cs2_faceit_elo,dota2_mmr").eq("user_id",link.user_id).maybeSingle();
      if(!profile?.arqon_id){
       await renderPanel(bot,callbackChatId,callback.message.message_id,"👤 <b>МОЙ ПРОФИЛЬ ARQON</b>\n\nTelegram подключён, но игровой профиль ARQON ещё не создан.",{inline_keyboard:[[{text:"Открыть создание профиля",url:SITE+"/"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
      }else{
       const name=esc(profile.display_name||profile.steam_persona_name||("Игрок #"+profile.arqon_id));
       const profileUrl=SITE+"/players/profile/?me=1";
       const text="👤 <b>"+name+"</b>\nARQON ID: <b>#"+profile.arqon_id+"</b>\nCS2 FACEIT ELO: "+(profile.cs2_faceit_elo??"—")+"\nDota 2 MMR: "+(profile.dota2_mmr??"—")+"\n\nТвой личный профиль ARQON готов.";
       await renderPanel(bot,callbackChatId,callback.message.message_id,text,{inline_keyboard:[[{text:"↗️ Открыть мой профиль на сайте",url:profileUrl}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
      }
     }
    }else if(action==="notifications"||action.startsWith("notif:")){
     const link=await linkedUser(admin,callbackChatId);
     if(!link){await renderPanel(bot,callbackChatId,callback.message.message_id,"🔔 <b>УВЕДОМЛЕНИЯ</b>\n\nПодключи Telegram к аккаунту ARQON, чтобы управлять уведомлениями.",{inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]})}
     else{
      let {data:prefs}=await admin.from("user_notification_preferences").select("support_enabled,teams_enabled,system_enabled").eq("user_id",link.user_id).maybeSingle();
      if(!prefs)prefs={support_enabled:true,teams_enabled:true,system_enabled:true};
      if(action.startsWith("notif:")){
       const key=action.slice(6);if(["support_enabled","teams_enabled","system_enabled"].includes(key)){
        prefs={...prefs,[key]:!prefs[key]};
        await admin.from("user_notification_preferences").upsert({user_id:link.user_id,...prefs,updated_at:new Date().toISOString()},{onConflict:"user_id"});
       }
      }
      const on=(v:boolean)=>v?"🟢 Включены":"⚫ Выключены";
      await renderPanel(bot,callbackChatId,callback.message.message_id,"🔔 <b>НАСТРОЙКИ УВЕДОМЛЕНИЙ</b>\n\nПоддержка: "+on(prefs.support_enabled)+"\nКоманды и приглашения: "+on(prefs.teams_enabled)+"\nСистемные: "+on(prefs.system_enabled),{inline_keyboard:[
       [{text:(prefs.support_enabled?"🟢":"⚫")+" Поддержка",callback_data:"notif:support_enabled"}],
       [{text:(prefs.teams_enabled?"🟢":"⚫")+" Команды и приглашения",callback_data:"notif:teams_enabled"}],
       [{text:(prefs.system_enabled?"🟢":"⚫")+" Системные",callback_data:"notif:system_enabled"}],
       [{text:"↩️ Главное меню",callback_data:"menu"}]
      ]});
     }
    }else if(action==="league"){
     const {data}=await admin.from("league_data").select("payload").limit(1).maybeSingle();
     const matches=Array.isArray(data?.payload?.matches)?data.payload.matches:[];
     const done=matches.filter((m:any)=>m.result_type==="normal"&&m.winner||m.result_type==="tech"&&m.tech_loss_team).length;
     const upcoming=matches.filter((m:any)=>!m.winner&&!m.tech_loss_team&&m.team1&&m.team2).slice(0,7);
     const recent=matches.filter((m:any)=>m.winner||m.tech_loss_team).slice(-5).reverse();
     const lines=[...recent.map((m:any)=>"• #"+(m.match_no??"?")+" "+esc(m.team1)+" — "+esc(m.team2)+" · "+(m.result_type==="tech"?"ТТ "+esc(m.tech_loss_team):"победа "+esc(m.winner))),...upcoming.map((m:any)=>"• #"+(m.match_no??"?")+" "+esc(m.date||"Дата уточняется")+" "+esc(m.time||"")+" · "+esc(m.team1)+" — "+esc(m.team2))];
     await renderPanel(bot,callbackChatId,callback.message.message_id,"🏆 <b>КИБЕРСПОРТИВНАЯ ЛИГА ARQON</b>\nМатчей в расписании: "+matches.length+"\nС результатом: "+done+"\n\n<b>Результаты и ближайшие матчи</b>\n"+(lines.join("\n")||"Пока нет данных."),{inline_keyboard:[[{text:"↻ Обновить",callback_data:"league"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    }else if(action==="teams"){
     const {data}=await admin.from("tournament").select("data").order("id",{ascending:false}).limit(1).maybeSingle();
     const teams=Array.isArray(data?.data?.teams)?data.data.teams:[];
     const rows=teams.slice(0,18).map((t:any)=>{const name=typeof t==="string"?t:(t.name||t.teamName||"Команда");return "• <b>"+esc(name)+"</b>"+(Array.isArray(t?.players)?" · "+t.players.length+" игроков":"")});
     await renderPanel(bot,callbackChatId,callback.message.message_id,"👥 <b>КОМАНДЫ ARQON</b>\n\n"+(rows.join("\n")||"Список команд пока пуст.")+"\n\nПолные составы и карточки команд появятся здесь по нажатию на название.",{inline_keyboard:[[{text:"↻ Обновить",callback_data:"teams"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    }else if(action==="players"){
     const {data,error}=await admin.from("profiles").select("arqon_id,display_name,steam_persona_name,cs2_faceit_elo,dota2_mmr").eq("is_public",true).order("arqon_id",{ascending:true}).limit(15);
     const rows=(data||[]).map((p:any)=>"• <b>"+esc(p.display_name||p.steam_persona_name||("Игрок #"+p.arqon_id))+"</b> · #"+p.arqon_id+" · FACEIT "+(p.cs2_faceit_elo??"—"));
     await renderPanel(bot,callbackChatId,callback.message.message_id,"🎯 <b>ИГРОКИ ARQON</b>\n\n"+(error?"Не удалось загрузить игроков.":rows.join("\n")||"Публичных профилей пока нет.")+"\n\nПоиск и открытие карточек игроков добавим следующим этапом.",{inline_keyboard:[[{text:"↻ Обновить",callback_data:"players"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    }else if(action==="support"){
     const link=await linkedUser(admin,callbackChatId);
     if(!link){await renderPanel(bot,callbackChatId,callback.message.message_id,"🛟 <b>ПОДДЕРЖКА ARQON</b>\n\nПодключи Telegram к своему аккаунту, чтобы видеть обращения и переписываться с администрацией прямо здесь.",{inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]})}
     else{
      const {data:tickets,error}=await admin.from("support_tickets").select("id,subject,status,updated_at").eq("user_id",link.user_id).order("updated_at",{ascending:false}).limit(8);
      const rows=(tickets||[]).map((t:any)=>"• <b>#"+t.id+" · "+esc(t.subject)+"</b> — "+esc(t.status));
      await renderPanel(bot,callbackChatId,callback.message.message_id,"🛟 <b>ТВОИ ОБРАЩЕНИЯ</b>\n\n"+(error?"Не удалось загрузить обращения.":rows.join("\n")||"У тебя пока нет обращений.")+"\n\nЧтобы ответить в обращении, отправь: <code>/ticket НОМЕР текст</code>",{inline_keyboard:[[{text:"↻ Обновить",callback_data:"support"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
     }
    }else if(action==="organizer"){
     const {data}=await admin.rpc("get_support_admin_telegram_chats");
     const allowed=(data||[]).some((x:any)=>String(x.chat_id)===callbackChatId);
     await renderPanel(bot,callbackChatId,callback.message.message_id,allowed?"🛡 <b>ПАНЕЛЬ ОРГАНИЗАТОРА</b>\n\nДоступ подтверждён. Административные действия и управление турниром добавим в защищённые разделы этого меню.":"⛔ Нет доступа к панели организатора.",{inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    }
   }
   return json({ok:true});
  }
  const msg=update?.message,chat=msg?.chat?.id,txt=String(msg?.text??"").trim();
  if(!chat)return json({ok:true});
  const chatId=String(chat);
  const start=txt.match(/^\/start\s+([a-f0-9]{40,80})$/i);
  if(start){
   const {data:link}=await admin.from("telegram_link_tokens").select("token,user_id,expires_at").eq("token",start[1]).gt("expires_at",new Date().toISOString()).maybeSingle();
   if(!link){await send(bot,chatId,"Код подключения недействителен или истёк. Создай новый код в профиле ARQON.");return json({ok:true})}
   const {error}=await admin.from("telegram_accounts").upsert({user_id:link.user_id,chat_id:chatId,telegram_username:msg?.from?.username??null,first_name:msg?.from?.first_name??null,linked_at:new Date().toISOString()},{onConflict:"user_id"});
   if(error)return json({error:"link_save_failed"},500);
   await admin.from("telegram_link_tokens").delete().eq("token",link.token);
   await setBotCommands(bot).catch(e=>console.warn("Bot commands setup failed",e));
   await send(bot,chatId,"<b>ＡＲＱＯＮ  ＥＳＰＯＲＴＳ</b>\n<i>YOUR GAME. YOUR LEGACY.</i>\n\n✅ <b>Telegram успешно подключён!</b>\nТеперь сюда будут приходить уведомления ARQON и ответы техподдержки.\n\nДобро пожаловать в команду 💜",menuMarkup(false));
   return json({ok:true});
  }
  if(/^\/(start|menu|help)(?:@\w+)?$/i.test(txt)){
   await setBotCommands(bot).catch(e=>console.warn("Bot commands setup failed",e));
   await showMenu(bot,chatId,admin);
   return json({ok:true});
  }
  if(/^\/profile(?:@\w+)?$/i.test(txt)){
   const link=await linkedUser(admin,chatId);
   if(!link){await send(bot,chatId,"👤 <b>МОЙ ПРОФИЛЬ ARQON</b>\n\nСначала подключи Telegram к аккаунту на сайте.",{inline_keyboard:[[{text:"🔗 Подключить аккаунт",url:SITE+"/"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]})}
   else{
    const {data:profile}=await admin.from("profiles").select("arqon_id,display_name,steam_persona_name").eq("user_id",link.user_id).maybeSingle();
    if(profile?.arqon_id)await send(bot,chatId,"👤 <b>"+esc(profile.display_name||profile.steam_persona_name||"Мой профиль")+"</b> · ARQON #"+profile.arqon_id,{inline_keyboard:[[{text:"↗️ Открыть мой профиль на сайте",url:SITE+"/players/profile/?me=1"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    else await send(bot,chatId,"Игровой профиль ARQON ещё не создан.",backMenu);
   }
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
  await setBotCommands(bot).catch(e=>console.warn("Bot commands setup failed",e));
  await send(bot,chatId,"Не понял команду. Открой меню ARQON — там все основные разделы и быстрые переходы 💜",menuMarkup(false));
  return json({ok:true});
 }
 const jwt=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");
 if(!jwt)return json({error:"missing_auth"},401);
 const auth=createClient(url,anon,{auth:{persistSession:false},global:{headers:{Authorization:`Bearer ${jwt}`}}});
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
 if(["support_admin_reply","support_admin_close"].includes(event)){
  const ticketId=Number(body?.ticket_id);
  if(!Number.isSafeInteger(ticketId)||ticketId<1)return json({error:"invalid_ticket_id"},400);
  const {data:adminCheck,error:adminCheckError}=await auth.rpc("list_support_tickets_admin");
  if(adminCheckError||!Array.isArray(adminCheck))return json({error:"forbidden"},403);
  const {data:ticket}=await admin.from("support_tickets").select("id,user_id,arqon_id,subject,status").eq("id",ticketId).maybeSingle();
  if(!ticket)return json({error:"ticket_not_found"},404);
  const {data:tg}=await admin.from("telegram_accounts").select("chat_id").eq("user_id",ticket.user_id).maybeSingle();
  if(!tg?.chat_id)return json({ok:true,sent:false,reason:"player_telegram_not_linked"});
  if(event==="support_admin_reply"){
   const message=String(body?.message??"").trim();
   if(!message||message.length>2000)return json({error:"invalid_message"},400);
   await send(bot,String(tg.chat_id),`💬 <b>Ответ техподдержки ARQON · обращение #${ticketId}</b>\n\n${esc(message)}\n\nОтветить на сайте: https://arqon-esports.ru/support/ или в Telegram: /ticket ${ticketId} текст`);
  }else{
   await send(bot,String(tg.chat_id),`🔒 Обращение #${ticketId} закрыто администрацией ARQON. Если вопрос остался, создай новое обращение на сайте: https://arqon-esports.ru/support/`);
  }
  return json({ok:true,sent:true});
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
