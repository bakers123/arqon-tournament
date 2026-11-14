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
  };
}

Deno.serve(async (req: Request) => {
  const headers = cors(req.headers.get("Origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405, headers });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ error: "Authentication required" }, { status: 401, headers });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}");
    const publishableKey = publishableKeys.default || Deno.env.get("SUPABASE_ANON_KEY");
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const secretKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !publishableKey || !secretKey) {
      return Response.json({ error: "Server auth configuration is incomplete" }, { status: 500, headers });
    }

    const userClient = createClient(url, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = authorization.slice(7);
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) {
      return Response.json({ error: "Invalid session" }, { status: 401, headers });
    }

    const { data: role, error: roleError } = await userClient.rpc("current_organizer_role");
    if (roleError || !["owner", "admin"].includes(role)) {
      return Response.json({ error: "Only an owner or admin can provision the judge account" }, { status: 403, headers });
    }

    const body = await req.json().catch(() => ({}));
    const username = typeof body.username === "string" ? body.username.trim().toLowerCase() : "";
    if (!/^[a-z0-9_-]{3,24}$/.test(username)) {
      return Response.json({ error: "Username must be 3–24 characters: lowercase letters, numbers, _ or -" }, { status: 400, headers });
    }
    const password = typeof body.password === "string" ? body.password : "";
    if (password.length < 12 || password.length > 72) {
      return Response.json({ error: "Password must contain 12–72 characters" }, { status: 400, headers });
    }

    const email = `${username}@arqon-esports.ru`;
    const createResponse = await fetch(`${url}/auth/v1/admin/users`, {
      method: "POST",
      headers: { "apikey": secretKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        user_metadata: { username, display_name: username },
      }),
    });

    const created = await createResponse.json().catch(() => ({}));
    if (!createResponse.ok) {
      const message = String(created.msg || created.message || created.error_description || created.error || "");
      if (createResponse.status === 422 || /already|exists|registered/i.test(message)) {
        return Response.json({ error: "Judge account already exists. Use the password reset flow instead of creating a duplicate." }, { status: 409, headers });
      }
      return Response.json({ error: "Could not create the judge account", details: message || `Auth returned ${createResponse.status}` }, { status: 502, headers });
    }

    const userId = created.id || created.user?.id;
    if (!userId) {
      return Response.json({ error: "Auth created a user but did not return its ID; role assignment requires manual verification." }, { status: 502, headers });
    }

    const roleResponse = await fetch(`${url}/rest/v1/rpc/assign_bracket_judge_role`, {
      method: "POST",
      headers: { "apikey": secretKey, "Content-Type": "application/json" },
      body: JSON.stringify({ p_user_id: userId }),
    });

    if (!roleResponse.ok) {
      await fetch(`${url}/auth/v1/admin/users/${userId}`, {
        method: "DELETE",
        headers: { "apikey": secretKey },
      }).catch(() => null);
      return Response.json({ error: "Judge role assignment failed; the newly created Auth user was rolled back." }, { status: 502, headers });
    }

    return Response.json({ success: true, username }, { status: 201, headers });
  } catch (_error) {
    return Response.json({ error: "Unexpected server error" }, { status: 500, headers });
  }
});
