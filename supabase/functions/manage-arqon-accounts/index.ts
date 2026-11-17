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
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json().catch(() => ({}));
    const action = typeof body.action === "string" ? body.action : "list";
    if (action === "list_steam_profiles") {
      const role = await userClient.rpc("current_organizer_role");
      if (role.error || !["owner", "admin", "editor"].includes(role.data)) {
        return response({ error: "Недостаточно прав для редактирования профилей." }, 403, headers);
      }
      const { data: profiles, error } = await admin.from("profiles")
        .select("user_id,arqon_id,display_name,game_nick,bio,avatar_url,cover_url,cs2_faceit_url,cs2_faceit_elo,dota2_profile_url,dota2_mmr,is_public,show_steam,looking_for_team,preferred_role,steam_persona_name,created_at")
        .order("created_at", { ascending: false })
        .limit(5000);
      if (error) throw error;
      const users = [];
      for (let page = 1; page <= 100; page++) {
        const { data, error: listError } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
        if (listError) throw listError;
        users.push(...(data.users || []));
        if ((data.users || []).length < 1000) break;
      }
      const emailMap = new Map(users.map(user => [user.id, user.email || null]));
      return response({ profiles: (profiles || []).map(profile => ({
        ...profile,
        email: emailMap.get(profile.user_id) || null
      })) }, 200, headers);
    }
    if (action === "upload_steam_profile_media") {
      const role = await userClient.rpc("current_organizer_role");
      if (role.error || !["owner", "admin", "editor"].includes(role.data)) {
        return response({ error: "Недостаточно прав для редактирования профилей." }, 403, headers);
      }
      const userId = typeof body.user_id === "string" ? body.user_id : "";
      const kind = body.kind === "cover" ? "cover" : body.kind === "avatar" ? "avatar" : "";
      const mime = typeof body.mime === "string" ? body.mime : "";
      const encoded = typeof body.base64 === "string" ? body.base64 : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId) || !kind) return response({ error: "Некорректный игрок или тип изображения." }, 400, headers);
      const allowedMimes = kind === "cover" ? ["image/jpeg", "image/png", "image/webp", "image/gif"] : ["image/jpeg", "image/png", "image/webp"];\n      if (!allowedMimes.includes(mime) || !encoded || encoded.length > 7_000_000) return response({ error: kind === "cover" ? "Для обложки допустимы JPG, PNG, WEBP и GIF размером до 5 МБ." : "Для аватара допустимы JPG, PNG и WEBP размером до 5 МБ." }, 400, headers);
      const { data: current, error: currentError } = await admin.from("profiles").select("user_id").eq("user_id", userId).maybeSingle();
      if (currentError) throw currentError;
      if (!current?.user_id) return response({ error: "Профиль игрока не найден." }, 404, headers);
      const binary = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
      if (binary.byteLength > 5 * 1024 * 1024) return response({ error: "Изображение больше 5 МБ." }, 400, headers);
      const ext = mime === "image/jpeg" ? "jpg" : mime === "image/png" ? "png" : mime === "image/gif" ? "gif" : "webp";
      const path = userId + "/" + kind + "-" + Date.now() + "-" + crypto.randomUUID().slice(0,8) + "." + ext;
      const { error: uploadError } = await admin.storage.from("player-media").upload(path, binary, { contentType: mime, upsert: false, cacheControl: "3600" });
      if (uploadError) throw uploadError;
      const { data: publicUrl } = admin.storage.from("player-media").getPublicUrl(path);
      return response({ url: publicUrl.publicUrl }, 200, headers);
    }
    if (action === "update_steam_profile") {
      const role = await userClient.rpc("current_organizer_role");
      if (role.error || !["owner", "admin", "editor"].includes(role.data)) {
        return response({ error: "Недостаточно прав для редактирования профилей." }, 403, headers);
      }
      const userId = typeof body.user_id === "string" ? body.user_id : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
        return response({ error: "Некорректный ID игрока." }, 400, headers);
      }
      const { data: current, error: currentError } = await admin.from("profiles")
        .select("steam_id").eq("user_id", userId).maybeSingle();
      if (currentError) throw currentError;
      if (!current?.user_id) return response({ error: "Профиль игрока не найден." }, 404, headers);
      const p = body.profile && typeof body.profile === "object" ? body.profile : {};
      const display_name = typeof p.display_name === "string" ? p.display_name.trim().replace(/\s+/g, " ") : "";
      const bio = typeof p.bio === "string" ? p.bio.trim() : "";
      const cs2_faceit_elo = p.cs2_faceit_elo === "" || p.cs2_faceit_elo === null ? null : Number(p.cs2_faceit_elo);
      const dota2_mmr = p.dota2_mmr === "" || p.dota2_mmr === null ? null : Number(p.dota2_mmr);
      const validUrl = value => value === null || (typeof value === "string" && value.length <= 2048 && value.startsWith("https://"));
      if (!display_name || display_name.length > 32) return response({ error: "Имя должно быть от 1 до 32 символов." }, 400, headers);
      if (typeof p.game_nick === 'string' && p.game_nick.trim().length > 32) return response({ error: "Игровой ник не должен превышать 32 символа." }, 400, headers);
      if (bio.length > 280) return response({ error: "Описание не должно превышать 280 символов." }, 400, headers);
      if (cs2_faceit_elo !== null && (!Number.isInteger(cs2_faceit_elo) || cs2_faceit_elo < 0 || cs2_faceit_elo > 5000)) return response({ error: "FACEIT ELO должен быть от 0 до 5000." }, 400, headers);
      if (dota2_mmr !== null && (!Number.isInteger(dota2_mmr) || dota2_mmr < 0 || dota2_mmr > 20000)) return response({ error: "Dota 2 MMR должен быть от 0 до 20000." }, 400, headers);
      const cs2_faceit_url = p.cs2_faceit_url || null;
      const dota2_profile_url = p.dota2_profile_url || null;
      const avatar_url = p.avatar_url || null;
      const cover_url = p.cover_url || null;
      if (![cs2_faceit_url, dota2_profile_url, avatar_url, cover_url].every(validUrl)) return response({ error: "Ссылки должны начинаться с https://." }, 400, headers);
      const update = {
        display_name, game_nick: typeof p.game_nick === 'string' ? p.game_nick.trim().slice(0,32) || null : null, bio, cs2_faceit_elo, cs2_faceit_url, dota2_mmr, dota2_profile_url,
        avatar_url, cover_url,
        is_public: p.is_public === true,
        show_steam: p.show_steam === true,
        looking_for_team: p.looking_for_team === true,
        preferred_role: typeof p.preferred_role === "string" ? p.preferred_role.trim().slice(0, 80) : ""
      };
      const { error } = await admin.from("profiles").update(update).eq("user_id", userId);
      if (error) throw error;
      return response({ ok: true, profile: update }, 200, headers);
    }

    const { data: ownerRole, error: ownerRoleError } = await userClient.rpc("current_organizer_role");
    if (ownerRoleError || ownerRole !== "owner") return response({ error: "Управлять аккаунтами может только владелец ARQON." }, 403, headers);
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