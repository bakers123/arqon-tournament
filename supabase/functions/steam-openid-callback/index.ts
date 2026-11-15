import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
async function syncSteamProfile(admin:any,steamId:string,userId:string){
  try{
    const response=await fetch(`https://steamcommunity.com/profiles/${steamId}?xml=1`,{headers:{"User-Agent":"ARQON-Esports/1.0"},signal:AbortSignal.timeout(7000)});
    if(!response.ok)return;
    const xml=await response.text();
    const extract=(tag:string)=>{
      const match=xml.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`,"i"));
      if(!match)return null;
      return match[1].replace(/^<!\\[CDATA\\[/,"").replace(/\\]\\]>$/,"").trim();
    };
    const persona=extract("steamID");
    const avatar=extract("avatarFull")||extract("avatarMedium")||extract("avatarIcon");
    const safeName=persona?.replace(/<[^>]*>/g,"").trim().slice(0,128)||null;
    const safeAvatar=avatar&&/^https:\\/\\//i.test(avatar)&&avatar.length<=2048?avatar:null;
    const patch:Record<string,string>={};
    if(safeName)patch.steam_persona_name=safeName;
    if(safeAvatar)patch.steam_avatar_url=safeAvatar;
    if(Object.keys(patch).length)await admin.from("profiles").update(patch).eq("user_id",userId);
  }catch(error){console.warn("Steam public profile sync skipped:",error)}
}
function redirect(origin:string,status:string,fragment?:Record<string,string>){
  const target=new URL("/players/",origin);
  target.searchParams.set("steam",status);
  if(fragment) target.hash=new URLSearchParams(fragment).toString();
  return new Response(null,{status:303,headers:{Location:target.toString(),"Cache-Control":"no-store, max-age=0",Pragma:"no-cache","Referrer-Policy":"no-referrer"}});
}
Deno.serve(async(req:Request)=>{
  if(req.method!=="GET") return new Response("Method not allowed",{status:405});
  const url=Deno.env.get("SUPABASE_URL");
  const secretKeys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");
  const serviceKey=secretKeys.default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!serviceKey) return new Response("Server configuration incomplete",{status:500});
  const requestUrl=new URL(req.url);
  const state=requestUrl.searchParams.get("state")||"";
  if(!/^[0-9a-f-]{36}$/i.test(state)) return new Response("Invalid state",{status:400});
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const {data:pending,error:pendingError}=await admin.from("steam_openid_states").select("user_id,return_origin,expires_at,consumed_at").eq("state",state).maybeSingle();
  if(pendingError||!pending||pending.consumed_at||new Date(pending.expires_at).getTime()<=Date.now()) return new Response("Steam verification expired. Return to ARQON and try again.",{status:400});
  const origin=pending.return_origin;
  const allowedOrigins=new Set(["https://arqon-esports.ru","https://www.arqon-esports.ru"]);
  if(!allowedOrigins.has(origin)) return new Response("Invalid return origin",{status:400});
  const params=requestUrl.searchParams;
  const claimedId=params.get("openid.claimed_id")||"";
  const identity=params.get("openid.identity")||"";
  const steamMatch=claimedId.match(/^https?:\/\/steamcommunity\.com\/openid\/id\/([0-9]{17})$/);
  const requiredSigned=["claimed_id","identity","return_to","response_nonce","assoc_handle","op_endpoint"];
  const signed=(params.get("openid.signed")||"").split(",");
  const nonce=params.get("openid.response_nonce")||"";
  const nonceTime=Date.parse(nonce.slice(0,20));
  const callback=new URL("/functions/v1/steam-openid-callback",url);
  callback.searchParams.set("state",state);
  if(params.get("openid.ns")!=="http://specs.openid.net/auth/2.0"||
    params.get("openid.mode")!=="id_res"||
    params.get("openid.op_endpoint")!=="https://steamcommunity.com/openid/login"||
    params.get("openid.return_to")!==callback.toString()||
    !steamMatch||identity!==claimedId||
    requiredSigned.some(field=>!signed.includes(field))||
    !Number.isFinite(nonceTime)||Math.abs(Date.now()-nonceTime)>600000) return redirect(origin,"error");
  const verification=new URLSearchParams();
  for(const [key,value] of params.entries()) if(key.startsWith("openid.")) verification.set(key,value);
  verification.set("openid.mode","check_authentication");
  let verified=false;
  try{
    const response=await fetch("https://steamcommunity.com/openid/login",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:verification.toString()});
    const body=await response.text();
    verified=response.ok&&/(?:^|\n)is_valid:true(?:\r?\n|$)/.test(body);
  }catch{verified=false;}
  if(!verified) return redirect(origin,"error");
  const steamId=steamMatch[1];
  const {data:consumed,error:consumeError}=await admin.from("steam_openid_states")
    .update({consumed_at:new Date().toISOString(),response_nonce:nonce})
    .eq("state",state).is("consumed_at",null).gt("expires_at",new Date().toISOString())
    .select("user_id").maybeSingle();
  if(consumeError||!consumed) return redirect(origin,"error");
  if(consumed.user_id){
    const {data:existing,error:existingError}=await admin.from("profiles").select("user_id").eq("steam_id",steamId).maybeSingle();
    if(existingError) return redirect(origin,"error");
    if(existing && existing.user_id!==consumed.user_id) return redirect(origin,"already_linked");
    const {data:updated,error:updateError}=await admin.from("profiles").update({steam_id:steamId})
      .eq("user_id",consumed.user_id).is("steam_id",null).select("user_id").maybeSingle();
    if(updateError||!updated) return redirect(origin,"already_linked");
    await syncSteamProfile(admin,steamId,consumed.user_id);\n    return redirect(origin,"linked");
  }
  const {data:profile,error:profileError}=await admin.from("profiles").select("user_id").eq("steam_id",steamId).maybeSingle();
  if(profileError||!profile) return redirect(origin,"not_found");
  await syncSteamProfile(admin,steamId,profile.user_id);\n  const {data:userResult,error:userError}=await admin.auth.admin.getUserById(profile.user_id);
  const user=userResult?.user;
  if(userError||!user||!user.email||!user.email_confirmed_at) return redirect(origin,"email_required");
  const {data:generated,error:generateError}=await admin.auth.admin.generateLink({type:"magiclink",email:user.email});
  const tokenHash=generated?.properties?.hashed_token;
  if(generateError||!tokenHash) return redirect(origin,"error");
  const {data:verifiedOtp,error:otpError}=await admin.auth.verifyOtp({token_hash:tokenHash,type:"magiclink"});
  const session=verifiedOtp?.session;
  if(otpError||!session?.access_token||!session?.refresh_token) return redirect(origin,"error");
  return redirect(origin,"signed_in",{
    access_token:session.access_token,
    refresh_token:session.refresh_token,
    token_type:session.token_type||"bearer",
    expires_in:String(session.expires_in||3600),
    expires_at:String(session.expires_at||Math.floor(Date.now()/1000)+3600),
    type:"magiclink"
  });
});