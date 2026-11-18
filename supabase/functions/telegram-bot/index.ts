import { createClient } from "npm:@supabase/supabase-js@2";
const cors = {"Access-Control-Allow-Origin":"https://arqon-esports.ru","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-telegram-bot-api-secret-token","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const esc=(v:unknown)=>String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");
const SITE="https://arqon-esports.ru";
const menuMarkup=(isAdmin=false,profileUrl=SITE+"/players/")=>({inline_keyboard:[
 [{text:"👤 Мой профиль",url:profileUrl}],
 [{text:"🔔 Уведомления",callback_data:"notifications"}],
 [{text:"🏆 Киберспортивная лига",callback_data:"league"}],
 [{text:"👥 Команды",callback_data:"teams"},{text:"🎯 Игроки",callback_data:"players"}],
 [{text:"🎯 SHOOT / SHIELD",callback_data:"shoot_help"}],
 [{text:"🛟 Поддержка",callback_data:"support"}],
 ...(isAdmin?[[{text:"🛡 Панель организатора",callback_data:"organizer"}]]:[])
]});
const backMenu={inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]};
function shootRolePrompt(round:number,playerId:number,creatorId:number){
 const isAttacking=round%2===1?Number(playerId)===Number(creatorId):Number(playerId)!==Number(creatorId);
 return isAttacking
  ?"⚔️ <b>ТЫ АТАКУЕШЬ</b>\nВыбери зону, куда будешь стрелять."
  :"🛡️ <b>ТЫ ЗАЩИЩАЕШЬСЯ</b>\nВыбери зону, куда поставишь щит.";
}
async function linkedUser(admin:any,chatId:string){
 const {data:link}=await admin.from("telegram_accounts").select("user_id,telegram_username,first_name").eq("chat_id",chatId).maybeSingle();
 return link||null;
}
async function isBroadcastOwner(admin:any,chatId:string,telegramUsername?:string){
 if(String(telegramUsername||"").toLowerCase()!=="kostkoteam")return false;
 const {data:link}=await admin.from("telegram_accounts").select("telegram_username").eq("chat_id",chatId).maybeSingle();
 if(String(link?.telegram_username||"").toLowerCase()!=="kostkoteam")return false;
 const {data:admins,error}=await admin.rpc("get_support_admin_telegram_chats");
 return !error&&(admins||[]).some((x:any)=>String(x.chat_id)===chatId);
}
async function renderPanel(bot:string,chatId:string,messageId:number,text:string,keyboard:any){
 try{await telegram(bot,"editMessageText",{chat_id:chatId,message_id:messageId,text,parse_mode:"HTML",disable_web_page_preview:true,reply_markup:keyboard})}
 catch{await send(bot,chatId,text,keyboard)}
}
async function loadTournamentTeams(admin:any){
 const {data}=await admin.from("tournament").select("data").order("id",{ascending:false}).limit(1).maybeSingle();
 const raw=data?.data?.teams;
 if(Array.isArray(raw))return raw;
 if(typeof raw==="string"){try{const parsed=JSON.parse(raw);return Array.isArray(parsed)?parsed:[]}catch{}}
 return [];
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
async function getTelegramProfileUrl(admin:any,chatId:string){
 const link=await linkedUser(admin,chatId);
 if(!link?.user_id)return SITE+"/players/";
 const {data:profile}=await admin.from("profiles").select("arqon_id").eq("user_id",link.user_id).maybeSingle();
 const id=Number(profile?.arqon_id);
 return Number.isSafeInteger(id)&&id>0?SITE+"/players/profile/?id="+id:SITE+"/players/";
}
async function showMenu(token:string,chatId:string,admin:any){
 let isSupportAdmin=false;
 try{const {data}=await admin.rpc("get_support_admin_telegram_chats");isSupportAdmin=(data||[]).some((x:any)=>String(x.chat_id)===chatId)}catch{}
 const greeting="<b>ＡＲＱＯＮ  ＥＳＰＯＲＴＳ</b>\n< i >YOUR GAME. YOUR LEGACY.</i>\n\nДобро пожаловать в ARQON! Управляй своим аккаунтом, следи за лигой и общайся с командой прямо здесь.\n\nВыбери раздел 👇".replace("< i >","<i>");
 const profileUrl=await getTelegramProfileUrl(admin,chatId);
 await send(token,chatId,greeting,menuMarkup(isSupportAdmin,profileUrl));
}
async function setBotCommands(token:string){
 await telegram(token,"setMyCommands",{commands:[
  {command:"start",description:"Открыть главное меню ARQON"},
  {command:"menu",description:"Показать меню"},
  {command:"profile",description:"Открыть мой профиль ARQON"},
  {command:"help",description:"Команды и помощь"},
  {command:"duel",description:"Вызвать игрока на SHOOT / SHIELD"}
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
    if(action==="shoot_help"){
     await renderPanel(bot,callbackChatId,callback.message.message_id,"🎯 <b>SHOOT / SHIELD В TELEGRAM</b>\n\nОтправь команду:\n<code>/duel @username 50</code>\n\nМинимальная ставка — 10 ARQON Coins. Лобби Telegram отдельные от сайта. Соперник должен подключить Telegram к профилю ARQON и открыть бота хотя бы один раз.",{inline_keyboard:[[{text:"💰 Баланс",callback_data:"tgshoot:balance"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    }else if(action==="tgshoot:balance"){
     const link=await linkedUser(admin,callbackChatId);
     if(!link){await send(bot,callbackChatId,"Сначала подключи Telegram к своему профилю ARQON.");}
     else{
      const {data:profile}=await admin.from("profiles").select("arqon_id").eq("user_id",link.user_id).maybeSingle();
      if(!profile?.arqon_id){await send(bot,callbackChatId,"Профиль ARQON не найден.");}
      else{const {data:wallet}=await admin.from("arqon_coin_wallets").select("balance").eq("arqon_id",profile.arqon_id).maybeSingle();await send(bot,callbackChatId,"💰 <b>ТВОЙ БАЛАНС ARQON COINS</b>\n\nARQON #"+profile.arqon_id+"\nДоступно: <b>"+Number(wallet?.balance??0)+" 🪙</b>");}
     }
    }else if(action.startsWith("tgshoot:")){
     const parts=action.split(":");
     try{
      if(parts[1]==="cancel"){
       const {data:d,error}=await admin.rpc("telegram_shoot_cancel",{p_chat_id:callbackChatId,p_duel_id:parts[2]});if(error)throw error;
       await send(bot,callbackChatId,"Дуэль отменена, ставка возвращена.");await send(bot,String(d.opponent_chat_id),"Вызов отменён создателем.");
      }else if(parts[1]==="rematch"){
       const opponentArqonId=Number(parts[2]),stake=Number(parts[3]);
       if(!Number.isSafeInteger(opponentArqonId)||!Number.isSafeInteger(stake)||stake<10)throw new Error("Не удалось создать реванш.");
       const {data:target}=await admin.from("profiles").select("user_id").eq("arqon_id",opponentArqonId).maybeSingle();if(!target?.user_id)throw new Error("Профиль соперника не найден.");
       const {data:tg}=await admin.from("telegram_accounts").select("telegram_username").eq("user_id",target.user_id).maybeSingle();if(!tg?.telegram_username)throw new Error("Соперник больше не подключён к Telegram.");
       const {data:d,error}=await admin.rpc("telegram_shoot_action",{p_chat_id:callbackChatId,p_action:"create",p_stake:stake,p_target_username:tg.telegram_username});if(error)throw error;
       const challenge="⚔️ <b>ВЫЗОВ НА РЕВАНШ SHOOT / SHIELD!</b>\nСоперник: ARQON #"+d.creator_arqon_id+"\nСтавка: <b>"+stake+" 🪙</b>\nБанк: <b>"+(stake*2)+" 🪙</b>\n\nПринять реванш?";
       const kb={inline_keyboard:[[{text:"✅ Принять реванш",callback_data:"tgshoot:accept:"+d.id},{text:"❌ Отклонить",callback_data:"tgshoot:decline:"+d.id}]]};
       try{await send(bot,String(d.target_chat_id),challenge,kb);}catch(e){await admin.rpc("telegram_shoot_cancel",{p_chat_id:callbackChatId,p_duel_id:d.id});throw new Error("Не удалось доставить вызов. Ставка возвращена.");}
       await send(bot,callbackChatId,"✅ Реванш предложен. Ставка "+stake+" 🪙 зарезервирована до ответа соперника.",{inline_keyboard:[[{text:"Отменить реванш и вернуть ставку",callback_data:"tgshoot:cancel:"+d.id}]]});
      }else if(parts[1]==="accept"||parts[1]==="decline"){
       const {data:d,error}=await admin.rpc("telegram_shoot_action",{p_chat_id:callbackChatId,p_action:parts[1],p_duel_id:parts[2]});if(error)throw error;
       if(parts[1]==="decline"){await send(bot,callbackChatId,"Вызов отклонён. Ставка создателя возвращена.");await send(bot,String(d.creator_chat_id),"Игрок отклонил дуэль. Ставка возвращена.");}
       else{const base="🎯 <b>SHOOT / SHIELD — МАТЧ НАЧАЛСЯ</b>\nСтавка каждого: <b>"+d.stake+" 🪙</b> · Банк: <b>"+(2*d.stake)+" 🪙</b>\nПервый до 3 очков.\n\n";const kb={inline_keyboard:[[{text:"🎯 Голова",callback_data:"tgshoot:zone:"+d.id+":1"},{text:"🛡️ Тело",callback_data:"tgshoot:zone:"+d.id+":2"},{text:"👢 Ноги",callback_data:"tgshoot:zone:"+d.id+":3"}],[{text:"💰 Баланс",callback_data:"tgshoot:balance"}]]};await send(bot,String(d.creator_chat_id),base+shootRolePrompt(1,d.creator_arqon_id,d.creator_arqon_id),kb);await send(bot,String(d.opponent_chat_id),base+shootRolePrompt(1,d.opponent_arqon_id,d.creator_arqon_id),kb);}
      }else if(parts[1]==="zone"){
       const duelId=parts[2],zone=Number(parts[3]);const {data:d,error}=await admin.rpc("telegram_shoot_action",{p_chat_id:callbackChatId,p_action:"move",p_duel_id:duelId,p_zone:zone});if(error)throw error;
       if(d.status==="waiting")await send(bot,callbackChatId,"✅ Выбор принят и скрыт. Ждём ход соперника.");
       else{
        const names=["","Голова","Тело","Ноги"];
        const {data:players}=await admin.from("profiles").select("arqon_id,display_name,steam_persona_name").in("arqon_id",[d.creator_arqon_id,d.opponent_arqon_id]);
        const label=(id:number)=>{const p=(players||[]).find((x:any)=>Number(x.arqon_id)===Number(id));return p?.display_name||p?.steam_persona_name||("ARQON #"+id);};
        const creatorName=esc(label(d.creator_arqon_id)),opponentName=esc(label(d.opponent_arqon_id));
        const scoreText=creatorName+": <b>"+d.creator_score+"</b>\n"+opponentName+": <b>"+d.opponent_score+"</b>";
        const result="🎯 <b>РАУНД "+d.round+" ЗАВЕРШЁН</b>\nВыстрел: "+names[d.shot_zone]+" · Щит: "+names[d.shield_zone]+"\n\n<b>Счёт:</b>\n"+scoreText;
        if(d.status==="finished"){
         const winnerName=esc(label(d.winner_arqon_id));
         const finalText=result+"\n\n🏆 Победитель: <b>"+winnerName+"</b>\nВыплата: <b>"+(2*d.stake)+" 🪙</b>";
         const rematchKb=(opponentId:number)=>({inline_keyboard:[[{text:"🔁 Реванш ("+d.stake+" 🪙)",callback_data:"tgshoot:rematch:"+opponentId+":"+d.stake}],[{text:"💰 Баланс",callback_data:"tgshoot:balance"},{text:"↩️ Главное меню",callback_data:"menu"}]]});
         await send(bot,String(d.creator_chat_id),finalText,rematchKb(d.opponent_arqon_id));await send(bot,String(d.opponent_chat_id),finalText,rematchKb(d.creator_arqon_id));
        }else{
         const nextRound=Number(d.round)+1;const nextBase=result+"\n\n";const creatorNext=nextBase+shootRolePrompt(nextRound,d.creator_arqon_id,d.creator_arqon_id);const opponentNext=nextBase+shootRolePrompt(nextRound,d.opponent_arqon_id,d.creator_arqon_id);
         const kb={inline_keyboard:[[{text:"🎯 Голова",callback_data:"tgshoot:zone:"+duelId+":1"},{text:"🛡️ Тело",callback_data:"tgshoot:zone:"+duelId+":2"},{text:"👢 Ноги",callback_data:"tgshoot:zone:"+duelId+":3"}],[{text:"💰 Баланс",callback_data:"tgshoot:balance"}]]};
         await send(bot,String(d.creator_chat_id),creatorNext,kb);await send(bot,String(d.opponent_chat_id),opponentNext,kb);
        }
       }
      }
     }catch(e){await send(bot,callbackChatId,"⚠️ "+esc((e as Error)?.message||"Не удалось выполнить действие."));}
    }else if(action==="menu"){
     let isSupportAdmin=false;try{const {data}=await admin.rpc("get_support_admin_telegram_chats");isSupportAdmin=(data||[]).some((x:any)=>String(x.chat_id)===callbackChatId)}catch{}
     const text="<b>ＡＲＱＯＮ  ＥＳＰＯＲＴＳ</b>\n<i>YOUR GAME. YOUR LEGACY.</i>\n\nВыбери нужный раздел 👇";
     try{await telegram(bot,"editMessageText",{chat_id:callbackChatId,message_id:callback.message.message_id,text,parse_mode:"HTML",disable_web_page_preview:true,reply_markup:menuMarkup(isSupportAdmin,await getTelegramProfileUrl(admin,callbackChatId))})}catch{}
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
       const profileUrl=await getTelegramProfileUrl(admin,callbackChatId);
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
    }else if(action==="teams"||action.startsWith("teams:page:")){
     const pageMatch=action.match(/^teams:page:(\d+)$/),page=Math.max(0,Number(pageMatch?.[1]??0));
     const teams=await loadTournamentTeams(admin),pageSize=5,totalPages=Math.max(1,Math.ceil(teams.length/pageSize)),currentPage=Math.min(page,totalPages-1),visible=teams.slice(currentPage*pageSize,(currentPage+1)*pageSize);
     const keyboard:any[][]=visible.map((t:any)=>[{text:"👥 "+String(t.name||"Команда").slice(0,45),callback_data:"team:"+String(t.id||"").slice(0,40)+":"+currentPage}]);
     const nav:any[]=[];
     if(currentPage>0)nav.push({text:"⬅️ Назад",callback_data:"teams:page:"+(currentPage-1)});
     nav.push({text:(currentPage+1)+" / "+totalPages,callback_data:"teams:page:"+currentPage});
     if(currentPage<totalPages-1)nav.push({text:"Вперёд ➡️",callback_data:"teams:page:"+(currentPage+1)});
     if(nav.length)keyboard.push(nav);
     keyboard.push([{text:"↻ Обновить",callback_data:"teams:page:"+currentPage},{text:"↩️ Главное меню",callback_data:"menu"}]);
     await renderPanel(bot,callbackChatId,callback.message.message_id,"👥 <b>КОМАНДЫ ARQON</b>\n\nВсего команд: "+teams.length+"\nСтраница "+(currentPage+1)+" из "+totalPages+" · по 5 команд\n\nВыбери команду, чтобы посмотреть её состав и игроков.",{inline_keyboard:keyboard});
    }else if(action.startsWith("team:")){
     const teamParts=action.slice(5).split(":"),teamId=teamParts[0],returnPage=Math.max(0,Number(teamParts[1]??0)),teams=await loadTournamentTeams(admin),team=teams.find((t:any)=>String(t.id)===teamId);
     if(!team){await renderPanel(bot,callbackChatId,callback.message.message_id,"Команда не найдена или состав обновился.",backMenu)}
     else{
      const roster=Array.isArray(team.players)?team.players:[];
      const rows=roster.map((p:any)=>"• <b>"+esc(p.name)+"</b> · FACEIT "+(p.faceitLevel??"—")+" · ARQON "+(p.arqonRating??"—")+(p.rosterRole==="reserve"?" · запас":""));
      const buttons=roster.slice(0,20).map((p:any)=>[{text:"🎯 "+String(p.name||"Игрок").slice(0,45),callback_data:"player:"+String(p.account_id||"").slice(0,45)}]);
      buttons.push([{text:"↩️ К командам",callback_data:"teams:page:"+returnPage},{text:"Главное меню",callback_data:"menu"}]);
      await renderPanel(bot,callbackChatId,callback.message.message_id,"👥 <b>"+esc(team.name)+"</b>\nИгроков: "+roster.length+"\n\n"+(rows.join("\n")||"Состав пока не заполнен."),{inline_keyboard:buttons});
     }
    }else if(action==="players"||action.startsWith("players:page:")){
     const pageMatch=action.match(/^players:page:(\d+)$/),page=Math.max(0,Number(pageMatch?.[1]??0));
     const teams=await loadTournamentTeams(admin),roster=teams.flatMap((t:any)=>(Array.isArray(t.players)?t.players:[]).map((p:any)=>({...p,teamName:t.name,teamId:t.id})));
     const unique=Array.from(new Map(roster.map((p:any)=>[String(p.account_id||p.name),p])).values()) as any[];
     const pageSize=5,totalPages=Math.max(1,Math.ceil(unique.length/pageSize)),currentPage=Math.min(page,totalPages-1),visible=unique.slice(currentPage*pageSize,(currentPage+1)*pageSize);
     const keyboard:any[][]=visible.map((p:any)=>[{text:"🎯 "+String(p.name||"Игрок").slice(0,45),callback_data:"player:"+String(p.account_id||"").slice(0,45)+":"+currentPage}]);
     const nav:any[]=[];
     if(currentPage>0)nav.push({text:"⬅️ Назад",callback_data:"players:page:"+(currentPage-1)});
     nav.push({text:(currentPage+1)+" / "+totalPages,callback_data:"players:page:"+currentPage});
     if(currentPage<totalPages-1)nav.push({text:"Вперёд ➡️",callback_data:"players:page:"+(currentPage+1)});
     if(nav.length)keyboard.push(nav);
     keyboard.push([{text:"↻ Обновить",callback_data:"players:page:"+currentPage},{text:"↩️ Главное меню",callback_data:"menu"}]);
     await renderPanel(bot,callbackChatId,callback.message.message_id,"🎯 <b>ИГРОКИ ARQON</b>\n\nВсего игроков в составах: "+roster.length+"\nСтраница "+(currentPage+1)+" из "+totalPages+" · по 5 игроков\n\nВыбери игрока, чтобы посмотреть его игровые данные.",{inline_keyboard:keyboard});
    }else if(action.startsWith("player:")){
     const playerParts=action.slice(7).split(":"),playerId=playerParts[0],returnPage=Math.max(0,Number(playerParts[1]??0)),teams=await loadTournamentTeams(admin);
     let found:any=null;for(const t of teams){const p=(t.players||[]).find((x:any)=>String(x.account_id)===playerId);if(p){found={...p,teamName:t.name};break}}
     if(!found){await renderPanel(bot,callbackChatId,callback.message.message_id,"Игрок не найден в текущих составах.",backMenu)}
     else{
      const text="🎯 <b>"+esc(found.name)+"</b>\nКоманда: "+esc(found.teamName||"Свободный агент")+"\nFACEIT: "+(found.faceitLevel??"не указан")+"\nРейтинг ARQON: "+(found.arqonRating??"не указан")+"\nРоль: "+esc(found.rosterRole||"основной состав");
      await renderPanel(bot,callbackChatId,callback.message.message_id,text,{inline_keyboard:[[{text:"↩️ К игрокам",callback_data:"players:page:"+returnPage}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
     }
    }else if(action==="support"){
     const link=await linkedUser(admin,callbackChatId);
     if(!link){await renderPanel(bot,callbackChatId,callback.message.message_id,"🛟 <b>ПОДДЕРЖКА ARQON</b>\n\nПодключи Telegram к своему аккаунту, чтобы видеть обращения и переписываться с администрацией прямо здесь.",{inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]})}
     else{
      const {data:tickets,error}=await admin.from("support_tickets").select("id,subject,status,updated_at").eq("user_id",link.user_id).order("updated_at",{ascending:false}).limit(8);
      const rows=(tickets||[]).map((t:any)=>"• <b>#"+t.id+" · "+esc(t.subject)+"</b> — "+esc(t.status));
      await renderPanel(bot,callbackChatId,callback.message.message_id,"🛟 <b>ТВОИ ОБРАЩЕНИЯ</b>\n\n"+(error?"Не удалось загрузить обращения.":rows.join("\n")||"У тебя пока нет обращений.")+"\n\nЧтобы ответить в обращении, отправь: <code>/ticket НОМЕР текст</code>",{inline_keyboard:[[{text:"↻ Обновить",callback_data:"support"}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
     }
    }else if(action==="organizer"||action.startsWith("org:")){
     const {data:organizerChats,error:organizerError}=await admin.rpc("get_support_admin_telegram_chats");
     const allowed=!organizerError&&(organizerChats||[]).some((x:any)=>String(x.chat_id)===callbackChatId);
     if(!allowed){
      await renderPanel(bot,callbackChatId,callback.message.message_id,"⛔ Нет доступа к панели организатора.",{inline_keyboard:[[{text:"↩️ Главное меню",callback_data:"menu"}]]});
     }else if(action==="organizer"||action==="org:overview"){
      const [teams,leagueResponse,ticketResponse]=await Promise.all([
       loadTournamentTeams(admin),
       admin.from("league_data").select("payload").limit(1).maybeSingle(),
       admin.from("support_tickets").select("id").neq("status","closed")
      ]);
      const players=teams.reduce((sum:number,team:any)=>sum+(Array.isArray(team.players)?team.players.length:0),0);
      const matches=Array.isArray(leagueResponse.data?.payload?.matches)?leagueResponse.data.payload.matches:[];
      const pending=matches.filter((m:any)=>m.result_type==="pending"||(!m.winner&&!m.tech_loss_team)).length;
      const openTickets=ticketResponse.data?.length??0;
      const dashboard="🛡 <b>ПАНЕЛЬ ОРГАНИЗАТОРА ARQON</b>\n\nКоманд: <b>"+teams.length+"</b>\nИгроков в составах: <b>"+players+"</b>\nМатчей лиги: <b>"+matches.length+"</b>\nОжидают результата: <b>"+pending+"</b>\nОткрытых обращений: <b>"+openTickets+"</b>\n\nВыбери раздел управления.";
      await renderPanel(bot,callbackChatId,callback.message.message_id,dashboard,{inline_keyboard:[
       [{text:"🪙 Выдать ARQON Coins",callback_data:"org:coins"}],
       ...((await isBroadcastOwner(admin,callbackChatId,(await linkedUser(admin,callbackChatId))?.telegram_username))?[[{text:"📣 Рассылка всем пользователям",callback_data:"org:broadcast"}],[{text:"👥 Список Telegram-пользователей",callback_data:"org:telegram_users"}]]:[]),
       [{text:"🛟 Обращения ("+openTickets+")",callback_data:"org:tickets"}],
       [{text:"🏆 Открыть лигу",callback_data:"league"}],
       [{text:"↻ Обновить сводку",callback_data:"org:overview"}],
       [{text:"↩️ Главное меню",callback_data:"menu"}]
      ]});
     }else if(action==="org:coins"){
      await renderPanel(bot,callbackChatId,callback.message.message_id,"🪙 <b>ВЫДАЧА ARQON COINS</b>\n\nОтправь команду:\n<code>/givecoins @username 100</code>\n\nУкажи Telegram username игрока и количество монет. Игрок должен привязать Telegram к профилю ARQON.\n\nМожно выдать от 1 до 1 000 000 🪙. Каждая выдача записывается в историю транзакций.",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
     }else if(action==="org:broadcast"){
      const owner=await isBroadcastOwner(admin,callbackChatId,(await linkedUser(admin,callbackChatId))?.telegram_username);
      if(!owner){
       await renderPanel(bot,callbackChatId,callback.message.message_id,"⛔ Рассылка доступна только владельцу бота.",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
      }else{
       await renderPanel(bot,callbackChatId,callback.message.message_id,"📣 <b>РАССЫЛКА ПОЛЬЗОВАТЕЛЯМ ARQON</b>\n\nОтправь сообщение командой:\n<code>/broadcast Текст сообщения</code>\n\nСообщение получат все пользователи, привязавшие Telegram к профилю ARQON.",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
      }
     }else if(action==="org:telegram_users"){
      const owner=await isBroadcastOwner(admin,callbackChatId,(await linkedUser(admin,callbackChatId))?.telegram_username);
      if(!owner){
       await renderPanel(bot,callbackChatId,callback.message.message_id,"⛔ Список доступен только владельцу бота.",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
      }else{
       await renderPanel(bot,callbackChatId,callback.message.message_id,"⏳ Собираю список подключённых пользователей…",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
       const accounts:any[]=[];
       for(let offset=0;;offset+=1000){
        const {data:batch,error}=await admin.from("telegram_accounts").select("user_id,chat_id,telegram_username,first_name").not("chat_id","is",null).order("linked_at",{ascending:true}).range(offset,offset+999);
        if(error)throw error;
        accounts.push(...(batch||[]));
        if(!batch||batch.length<1000)break;
       }
       const userIds=[...new Set(accounts.map((x:any)=>String(x.user_id)).filter(Boolean))];
       const profiles:any[]=[];
       for(let offset=0;offset<userIds.length;offset+=500){
        const {data:batch,error}=await admin.from("profiles").select("user_id,arqon_id,display_name,steam_persona_name").in("user_id",userIds.slice(offset,offset+500));
        if(error)throw error;
        profiles.push(...(batch||[]));
       }
       const byUser=new Map(profiles.map((p:any)=>[String(p.user_id),p]));
       const rows=accounts.map((a:any)=>{
        const p:any=byUser.get(String(a.user_id));
        const who=a.telegram_username?"@"+String(a.telegram_username).replace(/^@/,""):"Без username ("+String(a.first_name||"пользователь").replace(/[<>]/g,"")+")";
        const id=Number(p?.arqon_id);
        const url=Number.isSafeInteger(id)&&id>0?SITE+"/players/profile/?id="+id:SITE+"/players/";
        return "• "+esc(who)+" — <a href=\\""+url+"\\">"+(Number.isSafeInteger(id)&&id>0?"ARQON #"+id:"Профиль ARQON")+"</a>";
       });
       const header="👥 <b>ПОДКЛЮЧЁННЫЕ TELEGRAM-ПОЛЬЗОВАТЕЛИ</b>\nВсего: <b>"+rows.length+"</b>\n\n";
       if(!rows.length)await send(bot,callbackChatId,header+"Пока никто не подключил Telegram к ARQON.");
       else{
        let chunk=header;
        for(const row of rows){
         if((chunk+"\n"+row).length>3700){await send(bot,callbackChatId,chunk);chunk="👥 <b>ПРОДОЛЖЕНИЕ СПИСКА</b>\n\n";}
         chunk+=(chunk.endsWith("\n\n")?"":"\n")+row;
        }
        if(chunk.trim())await send(bot,callbackChatId,chunk);
       }
       await send(bot,callbackChatId,"✅ Список сформирован. Ссылки ведут на профили ARQON.",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
      }
     }else if(action==="org:tickets"){
      const {data:tickets,error}=await admin.from("support_tickets").select("id,arqon_id,subject,status,updated_at").neq("status","closed").order("updated_at",{ascending:false}).limit(8);
      if(error){
       await renderPanel(bot,callbackChatId,callback.message.message_id,"Не удалось загрузить обращения. Попробуй обновить позже.",{inline_keyboard:[[{text:"↻ Повторить",callback_data:"org:tickets"}],[{text:"↩️ К панели",callback_data:"org:overview"}]]});
      }else{
       const keyboard:any[][]=(tickets||[]).map((t:any)=>[{text:"#"+t.id+" · "+String(t.subject||"Без темы").slice(0,42),callback_data:"org:ticket:"+t.id}]);
       keyboard.push([{text:"↻ Обновить",callback_data:"org:tickets"},{text:"↩️ К панели",callback_data:"org:overview"}]);
       const lines=(tickets||[]).map((t:any)=>"• <b>#"+t.id+"</b> · "+esc(t.subject)+" · ARQON #"+(t.arqon_id??"—")+" · "+esc(t.status));
       await renderPanel(bot,callbackChatId,callback.message.message_id,"🛟 <b>ОТКРЫТЫЕ ОБРАЩЕНИЯ</b>\n\n"+(lines.join("\n")||"Открытых обращений нет."),{inline_keyboard:keyboard});
      }
     }else if(action.startsWith("org:ticket:")){
      const ticketId=Number(action.slice("org:ticket:".length));
      if(!Number.isSafeInteger(ticketId)||ticketId<1){
       await renderPanel(bot,callbackChatId,callback.message.message_id,"Некорректный номер обращения.",{inline_keyboard:[[{text:"↩️ К обращениям",callback_data:"org:tickets"}]]});
      }else{
       const [{data:ticket,error:ticketError},{data:messages}]=await Promise.all([
        admin.from("support_tickets").select("id,arqon_id,subject,status,created_at,updated_at").eq("id",ticketId).maybeSingle(),
        admin.from("support_ticket_messages").select("sender_role,message,created_at").eq("ticket_id",ticketId).order("created_at",{ascending:false}).limit(6)
       ]);
       if(ticketError||!ticket){
        await renderPanel(bot,callbackChatId,callback.message.message_id,"Обращение не найдено.",{inline_keyboard:[[{text:"↩️ К обращениям",callback_data:"org:tickets"}]]});
       }else{
        const history=(messages||[]).slice().reverse().map((m:any)=>"["+(m.sender_role==="admin"?"Админ":"Игрок")+"] "+esc(String(m.message||"").slice(0,240)));
        const detail="🛟 <b>ОБРАЩЕНИЕ #"+ticket.id+"</b>\n"+esc(ticket.subject)+"\nARQON #"+(ticket.arqon_id??"—")+" · "+esc(ticket.status)+"\n\n"+(history.join("\n\n")||"Сообщений пока нет.")+"\n\nОтветить: <code>/reply "+ticket.id+" текст</code>";
        const keyboard:any[][]=[];
        if(ticket.status!=="closed")keyboard.push([{text:"🔒 Закрыть обращение",callback_data:"org:close:"+ticket.id}]);
        keyboard.push([{text:"↩️ К обращениям",callback_data:"org:tickets"},{text:"↩️ К панели",callback_data:"org:overview"}]);
        await renderPanel(bot,callbackChatId,callback.message.message_id,detail,{inline_keyboard:keyboard});
       }
      }
     }else if(action.startsWith("org:close:")){
      const ticketId=Number(action.slice("org:close:".length));
      if(!Number.isSafeInteger(ticketId)||ticketId<1){
       await renderPanel(bot,callbackChatId,callback.message.message_id,"Некорректный номер обращения.",{inline_keyboard:[[{text:"↩️ К обращениям",callback_data:"org:tickets"}]]});
      }else{
       const {data:closed,error:closeError}=await admin.rpc("support_ticket_admin_close",{p_chat_id:callbackChatId,p_ticket_id:ticketId});
       if(closeError||!closed?.[0]){
        await renderPanel(bot,callbackChatId,callback.message.message_id,"Не удалось закрыть обращение. Проверь права и попробуй ещё раз.",{inline_keyboard:[[{text:"↩️ К обращениям",callback_data:"org:tickets"}]]});
       }else{
        if(closed[0].player_chat_id)try{await send(bot,String(closed[0].player_chat_id),"🔒 Обращение #"+ticketId+" закрыто администрацией ARQON. Если вопрос остался, создай новое обращение на сайте.")}catch{}
        await renderPanel(bot,callbackChatId,callback.message.message_id,"✅ Обращение #"+ticketId+" закрыто. Игрок получил уведомление.",{inline_keyboard:[[{text:"↩️ К обращениям",callback_data:"org:tickets"},{text:"↩️ К панели",callback_data:"org:overview"}]]});
       }
      }
     }else{
      await renderPanel(bot,callbackChatId,callback.message.message_id,"Раздел не найден.",{inline_keyboard:[[{text:"↩️ К панели",callback_data:"org:overview"}]]});
     }
    }
   }
   return json({ok:true});
  }
  const msg=update?.message,chat=msg?.chat?.id,txt=String(msg?.text??"").trim();
  if(!chat)return json({ok:true});
  const chatId=String(chat);
  if(msg?.chat?.type!=="private"){await send(bot,chatId,"Играть можно только в личном чате с @arqon_esports_bot.");return json({ok:true});}
  if(msg?.from?.username)await admin.from("telegram_accounts").update({telegram_username:msg.from.username,first_name:msg.from.first_name??null}).eq("chat_id",chatId);
  const start=txt.match(/^\/start\s+([a-f0-9]{40,80})$/i);
  if(start){
   const {data:link}=await admin.from("telegram_link_tokens").select("token,user_id,expires_at").eq("token",start[1]).gt("expires_at",new Date().toISOString()).maybeSingle();
   if(!link){await send(bot,chatId,"Код подключения недействителен или истёк. Создай новый код в профиле ARQON.");return json({ok:true})}
   const {error}=await admin.from("telegram_accounts").upsert({user_id:link.user_id,chat_id:chatId,telegram_username:msg?.from?.username??null,first_name:msg?.from?.first_name??null,linked_at:new Date().toISOString()},{onConflict:"user_id"});
   if(error)return json({error:"link_save_failed"},500);
   await admin.from("telegram_link_tokens").delete().eq("token",link.token);
   await setBotCommands(bot).catch(e=>console.warn("Bot commands setup failed",e));
   await send(bot,chatId,"<b>ＡＲＱＯＮ  ＥＳＰＯＲＴＳ</b>\n<i>YOUR GAME. YOUR LEGACY.</i>\n\n✅ <b>Telegram успешно подключён!</b>\nТеперь сюда будут приходить уведомления ARQON и ответы техподдержки.\n\nДобро пожаловать в команду 💜",menuMarkup(false,await getTelegramProfileUrl(admin,chatId)));
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
    if(profile?.arqon_id)await send(bot,chatId,"👤 <b>"+esc(profile.display_name||profile.steam_persona_name||"Мой профиль")+"</b> · ARQON #"+profile.arqon_id,{inline_keyboard:[[{text:"↗️ Открыть мой профиль на сайте",url:await getTelegramProfileUrl(admin,chatId)}],[{text:"↩️ Главное меню",callback_data:"menu"}]]});
    else await send(bot,chatId,"Игровой профиль ARQON ещё не создан.",backMenu);
   }
   return json({ok:true});
  }
  if(/^\/broadcast(?:@\w+)?(?:\s|$)/i.test(txt)){
   const owner=await isBroadcastOwner(admin,chatId,msg?.from?.username);
   if(!owner){await send(bot,chatId,"⛔ Эта команда доступна только владельцу бота.");return json({ok:true});}
   const messageText=txt.replace(/^\/broadcast(?:@\w+)?/i,"").trim();
   if(!messageText||messageText.length>3500){
    await send(bot,chatId,"Формат: <code>/broadcast Текст сообщения</code>\nСообщение должно содержать от 1 до 3500 символов.");
    return json({ok:true});
   }
   const {data:recipients,error}=await admin.from("telegram_accounts").select("chat_id").not("chat_id","is",null);
   if(error){await send(bot,chatId,"⛔ Не удалось получить список пользователей для рассылки.");return json({ok:true});}
   const unique=[...new Set((recipients||[]).map((x:any)=>String(x.chat_id||"")).filter((x:string)=>/^\d+$/.test(x)))];
   let sent=0,failed=0;
   const payload="📣 <b>ОБЪЯВЛЕНИЕ ARQON</b>\n\n"+esc(messageText);
   for(const recipient of unique){
    try{await send(bot,recipient,payload);sent++;}
    catch(e){failed++;console.warn("Broadcast delivery failed",recipient,e);}
   }
   await send(bot,chatId,"✅ <b>РАССЫЛКА ЗАВЕРШЕНА</b>\nПолучателей: "+unique.length+"\nДоставлено: "+sent+"\nНе доставлено: "+failed);
   return json({ok:true,sent,failed,total:unique.length});
  }
  if(/^\/givecoins(?:@\w+)?(?:\s|$)/i.test(txt)){
   const parts=txt.replace(/^\/givecoins(?:@\w+)?/i,"").trim().split(/\s+/);
   const username=(parts[0]||"").replace(/^@/,""),amount=Number(parts[1]);
   if(!username||!Number.isSafeInteger(amount)||amount<1||amount>1000000||parts.length!==2){
    await send(bot,chatId,"Формат: <code>/givecoins @username 100</code>\nКоличество — от 1 до 1 000 000 ARQON Coins. Команда доступна только организаторам.");
    return json({ok:true});
   }
   const {data:d,error}=await admin.rpc("telegram_admin_grant_coins",{p_chat_id:chatId,p_username:username,p_amount:amount});
   if(error){await send(bot,chatId,"⛔ "+esc(error.message||"Не удалось выдать койны."));return json({ok:true});}
   await send(bot,chatId,"✅ <b>КОЙНЫ ВЫДАНЫ</b>\nИгрок: <b>"+esc(d.player_name)+"</b> · ARQON #"+d.arqon_id+"\nНачислено: <b>+"+d.amount+" 🪙</b>\nНовый баланс: <b>"+d.balance+" 🪙</b>");
   try{await send(bot,String(d.target_chat_id),"🎁 <b>ТЕБЕ НАЧИСЛИЛИ ARQON COINS!</b>\nПолучено: <b>+"+d.amount+" 🪙</b>\nТекущий баланс: <b>"+d.balance+" 🪙</b>");}catch(e){console.warn("Coin grant notification failed",e);}
   return json({ok:true});
  }
  if(/^\/duel(?:@\w+)?(?:\s|$)/i.test(txt)){
   const duelParts=txt.replace(/^\/duel(?:@\w+)?/i,"").trim().split(/\s+/),rawName=duelParts[0]||"",username=rawName.startsWith("@")?rawName.slice(1):rawName,stake=Number(duelParts[1]);
   if(!username||!Number.isSafeInteger(stake)||stake<10||stake>1000000){await send(bot,chatId,"Формат: <code>/duel @username 50</code>. Минимальная ставка — 10 койнов.");return json({ok:true});}
   const {data:d,error}=await admin.rpc("telegram_shoot_action",{p_chat_id:chatId,p_action:"create",p_stake:stake,p_target_username:username});
   if(error){await send(bot,chatId,"⚠️ "+esc(error.message));return json({ok:true});}
   const challenge="⚔️ <b>ТЕБЯ ВЫЗВАЛИ НА SHOOT / SHIELD!</b>\nСоперник: ARQON #"+d.creator_arqon_id+"\nСтавка: <b>"+stake+" 🪙</b>\nБанк: <b>"+(stake*2)+" 🪙</b>\n\nПринять вызов?";
   const kb={inline_keyboard:[[{text:"✅ Принять дуэль",callback_data:"tgshoot:accept:"+d.id},{text:"❌ Отклонить",callback_data:"tgshoot:decline:"+d.id}]]};
   try{await send(bot,String(d.target_chat_id),challenge,kb);}catch(e){await admin.rpc("telegram_shoot_cancel",{p_chat_id:chatId,p_duel_id:d.id});await send(bot,chatId,"Не удалось доставить вызов игроку. Зарезервированная ставка возвращена. Возможно, игрок заблокировал бота.");return json({ok:true});}await send(bot,chatId,"✅ Вызов отправлен игроку @"+esc(username)+". Твоя ставка "+stake+" 🪙 зарезервирована. Ждём подтверждения.",{inline_keyboard:[[{text:"Отменить вызов и вернуть ставку",callback_data:"tgshoot:cancel:"+d.id}]]});return json({ok:true});
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
  await send(bot,chatId,"Не понял команду. Открой меню ARQON — там все основные разделы и быстрые переходы 💜",menuMarkup(false,await getTelegramProfileUrl(admin,chatId)));
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
