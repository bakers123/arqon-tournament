import { createClient } from "npm:@supabase/supabase-js@2";
const cors = {"Access-Control-Allow-Origin":"https://arqon-esports.ru","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-telegram-bot-api-secret-token","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const esc=(v:unknown)=>String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");
async function send(token:string,chatId:string,text:string){const r=await fetch(`https://api.telegram.org/bot${token}/sendMessage`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:chatId,text,parse_mode:"HTML",disable_web_page_preview:true})});if(!r.ok)throw new Error("telegram_send_failed")}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"method_not_allowed"},405);
 const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,bot=Deno.env.get("TELEGRAM_BOT_TOKEN"),secret=Deno.env.get("TELEGRAM_WEBHOOK_SECRET");
 if(!bot||!secret)return json({error:"telegram_not_configured"},503);
 const admin=createClient(url,service,{auth:{persistSession:false}});
 if(new URL(req.url).searchParams.get("mode")==="webhook"){
  if(req.headers.get("x-telegram-bot-api-secret-token")!==secret)return json({error:"unauthorized_webhook"},401);
  const update=await req.json().catch(()=>({})),msg=update?.message,chat=msg?.chat?.id,txt=String(msg?.text??"");
  const match=txt.match(/^\/start\s+([a-f0-9]{40,80})$/i);
  if(!chat)return json({ok:true});
  if(!match){await send(bot,String(chat),"Чтобы подключить ARQON, открой профиль на arqon-esports.ru и нажми «Подключить Telegram».");return json({ok:true})}
  const {data:link}=await admin.from("telegram_link_tokens").select("token,user_id,expires_at").eq("token",match[1]).gt("expires_at",new Date().toISOString()).maybeSingle();
  if(!link){await send(bot,String(chat),"Код подключения недействителен или истёк. Создай новый код в профиле ARQON.");return json({ok:true})}
  const {error}=await admin.from("telegram_accounts").upsert({user_id:link.user_id,chat_id:String(chat),telegram_username:msg?.from?.username??null,first_name:msg?.from?.first_name??null,linked_at:new Date().toISOString()},{onConflict:"user_id"});
  if(error)return json({error:"link_save_failed"},500);
  await admin.from("telegram_link_tokens").delete().eq("token",link.token);
  await send(bot,String(chat),"✅ Telegram успешно подключён к ARQON! Теперь сюда будут приходить уведомления о предложениях команд и ответах игроков.");
  return json({ok:true});
 }
 const jwt=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");
 if(!jwt)return json({error:"missing_auth"},401);
 const auth=createClient(url,anon,{auth:{persistSession:false}});
 const {data:userData,error:authErr}=await auth.auth.getUser(jwt);
 if(authErr||!userData.user)return json({error:"unauthorized"},401);
 const actor=userData.user.id,body=await req.json().catch(()=>({})),offerId=String(body?.offer_id??""),event=String(body?.event??"");
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