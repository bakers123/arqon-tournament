import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "https://arqon-esports.ru",
  "https://www.arqon-esports.ru",
  "https://arqon-esports.online",
  "https://www.arqon-esports.online",
]);

function cors(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin) ? origin : "https://arqon-esports.ru";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
    "Cache-Control": "no-store",
  };
}

Deno.serve(async (req: Request) => {
  const originHeader = req.headers.get("Origin");
  const headers = cors(originHeader);
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers });
  if (!originHeader || !allowedOrigins.has(originHeader)) {
    return Response.json({ error: "Origin not allowed" }, { status: 403, headers });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}");
    const publishableKey = publishableKeys.default || Deno.env.get("SUPABASE_ANON_KEY");
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const serviceKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !publishableKey || !serviceKey) {
      return Response.json({ error: "Server configuration incomplete" }, { status: 500, headers });
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    let userId: string | null = null;
    const authorization = req.headers.get("Authorization");
    if (authorization) {
      if (!authorization.startsWith("Bearer ")) {
        return Response.json({ error: "Invalid authorization" }, { status: 401, headers });
      }
      const userClient = createClient(url, publishableKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: { user }, error: userError } = await userClient.auth.getUser(authorization.slice(7));
      if (userError || !user) return Response.json({ error: "Invalid session" }, { status: 401, headers });
      userId = user.id;

      const { data: profile, error: profileError } = await admin
        .from("profiles").select("steam_id").eq("user_id", user.id).maybeSingle();
      if (profileError || !profile) return Response.json({ error: "Profile not found" }, { status: 404, headers });
      if (profile.steam_id) {
        return Response.json({ error: "Steam is already linked to this ARQON account" }, { status: 409, headers });
      }
    }

    const state = crypto.randomUUID();
    const { error: insertError } = await admin.from("steam_openid_states").insert({
      state,
      user_id: userId,
      return_origin: originHeader,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });
    if (insertError) throw insertError;

    const callback = new URL("/functions/v1/steam-openid-callback", url);
    callback.searchParams.set("state", state);
    const realm = new URL("/", url).toString();
    const steam = new URL("https://steamcommunity.com/openid/login");
    steam.searchParams.set("openid.ns", "http://specs.openid.net/auth/2.0");
    steam.searchParams.set("openid.mode", "checkid_setup");
    steam.searchParams.set("openid.return_to", callback.toString());
    steam.searchParams.set("openid.realm", realm);
    steam.searchParams.set("openid.identity", "http://specs.openid.net/auth/2.0/identifier_select");
    steam.searchParams.set("openid.claimed_id", "http://specs.openid.net/auth/2.0/identifier_select");

    return Response.json({ url: steam.toString(), mode: userId ? "link" : "login" }, { headers, status: 200 });
  } catch (_error) {
    return Response.json({ error: "Could not start Steam verification" }, { status: 500, headers });
  }
});