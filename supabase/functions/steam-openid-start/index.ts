import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const allowedOrigins = new Set(["https://arqon-esports.ru","https://www.arqon-esports.ru"]);
function cors(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin) ? origin : "https://arqon-esports.ru";
  return {"Access-Control-Allow-Origin":allowed,"Access-Control-Allow-Headers":"authorization, apikey, x-client-info, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin","Cache-Control":"no-store"};
}
async function hashIp(ip:string) {
  const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(ip));
  return Array.from(new Uint8Array(digest)).map((value)=>value.toString(16).padStart(2,"0")).join("");
}
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const headers = cors(origin);
  if (req.method === "OPTIONS") return new Response("ok",{headers});
  if (req.method !== "POST") return Response.json({error:"Method not allowed"},{status:405,headers});
  if (!origin || !allowedOrigins.has(origin)) return Response.json({error:"Origin not allowed"},{status:403,headers});
  try {
    const url=Deno.env.get("SUPABASE_URL");
    const publishableKeys=JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")||"{}");
    const publishableKey=publishableKeys.default||Deno.env.get("SUPABASE_ANON_KEY");
    const secretKeys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");
    const serviceKey=secretKeys.default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!url||!publishableKey||!serviceKey) return Response.json({error:"Server configuration incomplete"},{status:500,headers});
    const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const now=new Date();
    await admin.from("steam_openid_states").delete().lt("expires_at",now.toISOString());
    const body=await req.json().catch(()=>({}));
    const mode=typeof body.mode==="string"?body.mode:"";
    if(mode!=="login"&&mode!=="register"&&mode!=="link") return Response.json({error:"Invalid authentication mode"},{status:400,headers});
    const forwarded=req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")?.split(",")[0].trim()||req.headers.get("x-real-ip")||"";
    if(mode!=="link"){
      if(!forwarded) return Response.json({error:"Не удалось определить IP-адрес. Попробуй позже."},{status:503,headers});
      const ipHash=await hashIp(forwarded);
      const {data:limitRows,error:rateError}=await admin.rpc("consume_auth_ip_attempt",{p_ip_hash:ipHash});
      if(rateError) throw rateError;
      const limit=Array.isArray(limitRows)?limitRows[0]:limitRows;
      if(!limit?.allowed){
        const retryAfter=Math.max(1,Number(limit?.retry_after_seconds)||900);
        return Response.json({error:"С этого IP уже выполнено 3 попытки входа или регистрации. Подожди 15 минут и попробуй снова.",retry_after_seconds:retryAfter},{status:429,headers:{...headers,"Retry-After":String(retryAfter)}});
      }
    }
    const ipHash=forwarded?await hashIp(forwarded):null;
    let userId:string|null=null;
    const authorization=req.headers.get("Authorization");
    if(authorization){
      if(!authorization.startsWith("Bearer ")) return Response.json({error:"Invalid authorization"},{status:401,headers});
      const userClient=createClient(url,publishableKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
      const {data:{user},error}=await userClient.auth.getUser(authorization.slice(7));
      if(error||!user) return Response.json({error:"Invalid session"},{status:401,headers});
      userId=user.id;
      const {data:profile,error:profileError}=await admin.from("profiles").select("steam_id").eq("user_id",user.id).maybeSingle();
      if(profileError||!profile) return Response.json({error:"Profile not found"},{status:404,headers});
      if(profile.steam_id) return Response.json({error:"Steam is already linked to this ARQON account"},{status:409,headers});
    }
    const state=crypto.randomUUID();
    const {error:insertError}=await admin.from("steam_openid_states").insert({state,user_id:userId,request_ip_hash:ipHash,return_origin:origin,expires_at:new Date(Date.now()+600000).toISOString()});
    if(insertError) throw insertError;
    const callback=new URL("/functions/v1/steam-openid-callback",url);
    callback.searchParams.set("state",state);
    const steam=new URL("https://steamcommunity.com/openid/login");
    steam.searchParams.set("openid.ns","http://specs.openid.net/auth/2.0");
    steam.searchParams.set("openid.mode","checkid_setup");
    steam.searchParams.set("openid.return_to",callback.toString());
    steam.searchParams.set("openid.realm",new URL("/",url).toString());
    steam.searchParams.set("openid.identity","http://specs.openid.net/auth/2.0/identifier_select");
    steam.searchParams.set("openid.claimed_id","http://specs.openid.net/auth/2.0/identifier_select");
    return Response.json({url:steam.toString(),mode:userId?"link":"login"},{headers});
  } catch {
    return Response.json({error:"Could not start Steam verification"},{status:500,headers});
  }
});