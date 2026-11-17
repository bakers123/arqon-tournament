import { createClient } from "npm:@supabase/supabase-js@2";

const SITE = "https://arqon-esports.ru";
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const escapeHtml = (value: unknown) =>
  String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  if (!supabaseUrl || !serviceRole || !botToken) {
    console.error("Social Telegram dispatcher is missing required project secrets.");
    return json({ error: "dispatcher_not_configured" }, 503);
  }

  const payload = await req.json().catch(() => ({}));
  const queueId = Number(payload?.queue_id);
  if (!Number.isSafeInteger(queueId) || queueId <= 0) return json({ error: "invalid_queue_id" }, 400);

  const admin = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });
  const { data: claimed, error: claimError } = await admin
    .rpc("claim_arqon_telegram_notification", { p_queue_id: queueId })
    .maybeSingle();

  if (claimError) {
    console.error("Could not claim social notification:", claimError.message);
    return json({ error: "claim_failed" }, 500);
  }
  if (!claimed) return json({ ok: true, skipped: true });

  const finish = async (status: "sent" | "skipped" | "failed", errorText?: string) => {
    const { error } = await admin
      .from("arqon_telegram_notification_queue")
      .update({
        status,
        locked_at: null,
        ...(status === "sent" ? { sent_at: new Date().toISOString() } : {}),
        last_error: errorText ? errorText.slice(0, 500) : null,
      })
      .eq("id", queueId);
    if (error) console.error("Could not update social notification queue:", error.message);
  };

  const { data: notification, error: notificationError } = await admin
    .from("user_notifications")
    .select("id,user_id,title,body,target_url,notification_type")
    .eq("id", claimed.notification_id)
    .eq("user_id", claimed.user_id)
    .maybeSingle();

  if (notificationError || !notification || !["follow", "friend_request", "friend_accepted"].includes(notification.notification_type)) {
    await finish("failed", "Notification row missing or not a social event.");
    return json({ error: "notification_not_found" }, 404);
  }

  const { data: preferences } = await admin
    .from("user_notification_preferences")
    .select("system_enabled")
    .eq("user_id", claimed.user_id)
    .maybeSingle();

  if (preferences?.system_enabled === false) {
    await finish("skipped");
    return json({ ok: true, skipped: true, reason: "notifications_disabled" });
  }

  const { data: telegramAccount, error: telegramAccountError } = await admin
    .from("telegram_accounts")
    .select("chat_id")
    .eq("user_id", claimed.user_id)
    .maybeSingle();

  if (telegramAccountError) {
    await finish("failed", "Could not read linked Telegram account.");
    return json({ error: "telegram_account_lookup_failed" }, 500);
  }
  if (!telegramAccount?.chat_id) {
    await finish("skipped");
    return json({ ok: true, skipped: true, reason: "telegram_not_linked" });
  }

  const message = "🔔 <b>" + escapeHtml(notification.title) + "</b>\n\n" + escapeHtml(notification.body);
  const keyboard = (() => {
    const path = typeof notification.target_url === "string" ? notification.target_url : "";
    if (!path.startsWith("/") || path.startsWith("//")) return undefined;
    try {
      const url = new URL(path, SITE);
      if (url.origin !== SITE) return undefined;
      return { inline_keyboard: [[{ text: "Открыть на ARQON", url: url.toString() }]] };
    } catch {
      return undefined;
    }
  })();

  try {
    const response = await fetch("https://api.telegram.org/bot" + botToken + "/sendMessage", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: telegramAccount.chat_id,
        text: message,
        parse_mode: "HTML",
        disable_web_page_preview: true,
        ...(keyboard ? { reply_markup: keyboard } : {}),
      }),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || result?.ok !== true) {
      await finish("failed", "Telegram API rejected the message.");
      console.error("Telegram delivery failed:", result?.error_code ?? response.status);
      return json({ error: "telegram_delivery_failed" }, 502);
    }
  } catch (error) {
    await finish("failed", error instanceof Error ? error.message : "Telegram request failed.");
    return json({ error: "telegram_delivery_failed" }, 502);
  }

  await finish("sent");
  return json({ ok: true, sent: true });
});
