import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function redirect(origin: string, status: string) {
  const target = new URL("/players/", origin);
  target.searchParams.set("steam", status);
  return Response.redirect(target.toString(), 303);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return new Response("Method not allowed", { status: 405 });

  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
  const serviceKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return new Response("Server configuration incomplete", { status: 500 });

  const requestUrl = new URL(req.url);
  const state = requestUrl.searchParams.get("state") || "";
  if (!/^[0-9a-f-]{36}$/i.test(state)) return new Response("Invalid state", { status: 400 });

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: pending, error: pendingError } = await admin.from("steam_openid_states")
    .select("user_id,return_origin,expires_at,consumed_at")
    .eq("state", state)
    .maybeSingle();

  if (pendingError || !pending || pending.consumed_at || new Date(pending.expires_at).getTime() <= Date.now()) {
    return new Response("Steam verification expired. Return to ARQON and try again.", { status: 400 });
  }

  const origin = pending.return_origin;
  const allowedOrigins = new Set([
    "https://arqon-esports.ru",
    "https://www.arqon-esports.ru",
    "https://arqon-esports.online",
    "https://www.arqon-esports.online",
  ]);
  if (!allowedOrigins.has(origin)) return new Response("Invalid return origin", { status: 400 });

  const params = requestUrl.searchParams;
  const claimedId = params.get("openid.claimed_id") || "";
  const identity = params.get("openid.identity") || "";
  const steamMatch = claimedId.match(/^https?:\/\/steamcommunity\.com\/openid\/id\/([0-9]{17})$/);
  const requiredSigned = ["claimed_id", "identity", "return_to", "response_nonce", "assoc_handle", "op_endpoint"];
  const signed = (params.get("openid.signed") || "").split(",");
  const nonce = params.get("openid.response_nonce") || "";
  const nonceTime = Date.parse(nonce.slice(0, 20));
  const callback = new URL("/functions/v1/steam-openid-callback", url);
  callback.searchParams.set("state", state);

  if (
    params.get("openid.ns") !== "http://specs.openid.net/auth/2.0" ||
    params.get("openid.mode") !== "id_res" ||
    params.get("openid.op_endpoint") !== "https://steamcommunity.com/openid/login" ||
    params.get("openid.return_to") !== callback.toString() ||
    !steamMatch ||
    identity !== claimedId ||
    requiredSigned.some((field) => !signed.includes(field)) ||
    !Number.isFinite(nonceTime) ||
    Math.abs(Date.now() - nonceTime) > 10 * 60 * 1000
  ) {
    return redirect(origin, "error");
  }

  const verification = new URLSearchParams();
  for (const [key, value] of params.entries()) {
    if (key.startsWith("openid.")) verification.set(key, value);
  }
  verification.set("openid.mode", "check_authentication");

  let verified = false;
  try {
    const response = await fetch("https://steamcommunity.com/openid/login", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: verification.toString(),
    });
    const body = await response.text();
    verified = response.ok && /(?:^|\n)is_valid:true(?:\r?\n|$)/.test(body);
  } catch {
    verified = false;
  }
  if (!verified) return redirect(origin, "error");

  const steamId = steamMatch[1];
  const { data: consumed, error: consumeError } = await admin.schema("private")
    .from("steam_openid_states")
    .update({ consumed_at: new Date().toISOString(), response_nonce: nonce })
    .eq("state", state)
    .is("consumed_at", null)
    .gt("expires_at", new Date().toISOString())
    .select("user_id")
    .maybeSingle();

  if (consumeError || !consumed) return redirect(origin, "error");

  const { data: updated, error: updateError } = await admin.from("profiles")
    .update({ steam_id: steamId })
    .eq("user_id", consumed.user_id)
    .is("steam_id", null)
    .select("user_id")
    .maybeSingle();

  if (updateError || !updated) return redirect(origin, "error");
  return redirect(origin, "linked");
});