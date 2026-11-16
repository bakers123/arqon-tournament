import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://arqon-esports.ru", "https://www.arqon-esports.ru"]);
function cors(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin) ? origin : "https://arqon-esports.ru";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Expose-Headers": "Retry-After",
    "Vary": "Origin",
    "Cache-Control": "no-store"
  };
}
function response(body: unknown, status: number, headers: Record<string,string>) {
  return Response.json(body, { status, headers });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const headers = cors(origin);
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405, headers);
  if (!origin || !allowedOrigins.has(origin)) return response({ error: "Origin not allowed" }, 403, headers);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}");
    const publishableKey = publishableKeys.default || Deno.env.get("SUPABASE_ANON_KEY");
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const serviceKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !publishableKey || !serviceKey) return response({ error: "Server configuration incomplete" }, 500, headers);

    const authorization = req.headers.get("Authorization") || "";
    if (!authorization.startsWith("Bearer ")) return response({ error: "Требуется вход владельца." }, 401, headers);
    const token = authorization.slice(7);
    const userClient = createClient(url, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return response({ error: "Сессия недействительна." }, 401, headers);
    const { data: role, error: roleError } = await userClient.rpc("current_organizer_role");
    if (roleError || role !== "owner") return response({ error: "Управлять аккаунтами может только владелец ARQON." }, 403, headers);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json().catch(() => ({}));
    const action = typeof body.action === "string" ? body.action : "list";

    if (action === "list") {
      const users = [];
      for (let page = 1; page <= 100; page++) {
        const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
        if (error) throw error;
        const batch = data.users || [];
        users.push(...batch);
        if (batch.length < 1000) break;
      }
      if (users.length >= 100000) throw new Error("Слишком много аккаунтов для одной загрузки.");
      const ids = users.map(user => user.id);
      const roleMap = new Map<string,string>();
      for (let offset = 0; offset < ids.length; offset += 500) {
        const { data, error } = await admin.rpc("get_organizer_roles_for_users", { p_user_ids: ids.slice(offset, offset + 500) });
        if (error) throw error;
        for (const row of data || []) roleMap.set(row.user_id, row.role);
      }
      const profiles = new Map<string, any>();
      for (let offset = 0; offset < ids.length; offset += 500) {
        const { data, error } = await admin.from("profiles").select("user_id,display_name,arqon_id").in("user_id", ids.slice(offset, offset + 500));
        if (error) throw error;
        for (const row of data || []) profiles.set(row.user_id, row);
      }
      return response({
        users: users.map(user => ({
          id: user.id,
          email: user.email || null,
          created_at: user.created_at,
          last_sign_in_at: user.last_sign_in_at,
          email_confirmed_at: user.email_confirmed_at,
          banned_until: user.banned_until,
          is_anonymous: !!user.is_anonymous,
          organizer_role: roleMap.get(user.id) || null,
          display_name: profiles.get(user.id)?.display_name || null,
          arqon_id: profiles.get(user.id)?.arqon_id || null
        }))
      }, 200, headers);
    }

    const userId = typeof body.user_id === "string" ? body.user_id : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
      return response({ error: "Некорректный ID аккаунта." }, 400, headers);
    }
    if (userId === authData.user.id) return response({ error: "Нельзя заблокировать или удалить собственный аккаунт владельца." }, 403, headers);

    const { data: roles, error: targetRoleError } = await admin.rpc("get_organizer_roles_for_users", { p_user_ids: [userId] });
    if (targetRoleError) throw targetRoleError;
    if ((roles || []).length) return response({ error: "Аккаунты организаторов и судей защищены. Сначала отдельно измените их права доступа." }, 403, headers);

    if (action === "ban" || action === "unban") {
      const { data, error } = await admin.auth.admin.updateUserById(userId, {
        ban_duration: action === "ban" ? "876000h" : "none"
      });
      if (error) throw error;
      return response({ ok: true, banned_until: data.user?.banned_until || null }, 200, headers);
    }
    if (action === "delete") {
      const { error } = await admin.auth.admin.deleteUser(userId, false);
      if (error) throw error;
      return response({ ok: true }, 200, headers);
    }
    return response({ error: "Неизвестное действие." }, 400, headers);
  } catch (error) {
    console.error("account-management error", error);
    return response({ error: error instanceof Error ? error.message : "Внутренняя ошибка управления аккаунтами." }, 500, headers);
  }
});