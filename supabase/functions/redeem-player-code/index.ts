import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Expose-Headers": "Retry-After",
};

function respond(body: Record<string, unknown>, status: number, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, ...extraHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond({ error: "Authentication required" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return respond({ error: "Server configuration incomplete" }, 500);

  try {
    const token = authorization.slice(7);
    const client = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError || !user) return respond({ error: "Invalid session" }, 401);

    const body = await req.json().catch(() => ({}));
    const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";

    // The database increments the attempt counter even for malformed or incorrect codes.
    // This prevents callers from bypassing throttling by changing the client or URL.
    const { data, error } = await client.rpc("redeem_player_access_code", {
      p_code: code,
    });

    if (error || !data || typeof data !== "object") {
      return respond({ error: "Unable to process access code" }, 500);
    }

    if (data.ok === true && typeof data.player_name === "string") {
      return respond({ player_name: data.player_name }, 200);
    }

    if (data.error === "rate_limited") {
      const retryAfter = Math.max(1, Number(data.retry_after_seconds) || 900);
      return respond(
        { error: "Too many attempts. Try again later.", retry_after_seconds: retryAfter },
        429,
        { "Retry-After": String(retryAfter) },
      );
    }

    if (data.error === "session_already_linked") {
      return respond({ error: "This session is already linked to another player." }, 409);
    }

    return respond({ error: "Invalid or already used access code" }, 400);
  } catch (_error) {
    return respond({ error: "Unexpected server error" }, 500);
  }
});
