// UniPakt — sends an e-mail for every new row in public.notifications.
// Called only by the database trigger send_notification_email_webhook(), which
// sends the Vault secret `notification_function_key` in the `apikey` header.
//
// Security:
//  - Requests without that key are rejected (401). The key is checked inside the
//    database (verify_notification_key), so it never has to be copied anywhere.
//  - The notification is re-read from the database by id; title, body and
//    recipient in the request body are never trusted.
//  - The response never contains e-mail addresses.
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Marka rengi (panel › Marka rengi): site_theme satırından okunur, 1 dakika önbellekte tutulur;
// okunamazsa varsayılan kalır. E-postalarda B.dark (koyu zeminde vurgu) ve B.btn (düğme) kullanılır.
type BrandRow = { colors: string[]; angle: number; on_dark: string; on_accent: string };
const brandOf = (t: BrandRow) => {
  const cols = t.colors.length > 1 ? t.colors : [t.colors[0], t.colors[0]];
  return { dark: t.on_dark, btn: `background:${t.colors[0]};background-image:linear-gradient(${t.angle}deg,${cols.join(",")});color:${t.on_accent};` };
};
let B = brandOf({ colors: ["#8F244D", "#A94B86"], angle: 135, on_dark: "#A94B86", on_accent: "#FFFFFF" });
let brandAt = 0;
const loadBrand = async () => {
  if (Date.now() - brandAt < 60_000) return;
  brandAt = Date.now();
  try {
    const { data } = await supabase.from("site_theme").select("colors, angle, on_dark, on_accent").eq("id", 1).maybeSingle();
    const hex = /^#[0-9A-Fa-f]{6}$/;
    if (data && Array.isArray(data.colors) && data.colors.length && data.colors.every((c: string) => hex.test(c)) && hex.test(data.on_dark) && hex.test(data.on_accent)) B = brandOf(data as BrandRow);
  } catch (_) { /* varsayılan kalır */ }
};

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const PANEL_URL = "https://unipakt.com/panel.html";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function esc(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function notificationType(type: string): string {
  const labels: Record<string, string> = {
    partnership_application: "Ortaklık Başvurusu",
    partnership_decision: "Ortaklık Sonucu",
    event_approval: "Etkinlik Başvurusu",
    event_edit_decision: "Etkinlik Düzenleme Sonucu",
    event_visibility_decision: "Etkinlik Görünürlük Sonucu",
    event_visibility_request: "Etkinlik Görünürlük Talebi",
    event_edit_request: "Etkinlik Düzenleme Talebi",
    task_assigned: "Yeni Görev",
    task_review: "Görev Sonucu",
    announcement_decision: "Duyuru Sonucu",
    event_removed: "Etkinlik Kaldırıldı",
    event_published: "Etkinlik Yayında",
    event_submission_decision: "Etkinlik Başvurusu Sonucu",
    calendar_decision: "Takvim Talebi Sonucu",
    event_unpublished: "Etkinlik Yayından Kaldırıldı",
    partner_removed: "Ortaklık Kaldırıldı",
    registration_full: "Kontenjan Doldu",
    registration_digest: "Günlük Kayıt Özeti",
  };
  return labels[type] || "UniPakt Bildirimi";
}

// Kulüp bildirimleri başkana ve bu konuda yetkisi olan ekip üyelerine gider.
function permFor(type: string): string | null {
  if (type.startsWith("registration_")) return "registrations";
  if (type.startsWith("task_")) return "tasks";
  if (type.startsWith("announcement_")) return "announcements";
  if (type.startsWith("support")) return "support";
  if (type.startsWith("event_") || type.startsWith("partner") || type.startsWith("calendar_")) return "events";
  return null;
}

function buildHtml(notification: any): string {
  const title = esc(notification.title);
  const body = esc(notification.body).replace(/\n/g, "<br>");
  const type = esc(notificationType(notification.type));

  return `
<!doctype html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background:#000000;color:#ffffff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
  <div style="max-width:620px;margin:40px auto;padding:0 20px;">
    <div style="border:1px solid #292929;border-radius:20px;overflow:hidden;background:#090909;">
      <div style="padding:28px 30px;border-bottom:1px solid #292929;">
        <div style="font-size:22px;font-weight:700;letter-spacing:-0.5px;">UniPakt<span style="color:${B.dark};">.</span></div>
        <div style="margin-top:7px;color:${B.dark};font-size:13px;font-weight:600;">${type}</div>
      </div>
      <div style="padding:32px 30px;">
        <h1 style="margin:0 0 18px;font-size:25px;line-height:1.25;color:#ffffff;">${title}</h1>
        <div style="color:#cfcfcf;font-size:16px;line-height:1.7;">${body}</div>
        <div style="margin-top:30px;">
          <a href="${PANEL_URL}" style="display:inline-block;${B.btn}text-decoration:none;font-weight:600;padding:13px 20px;border-radius:10px;">UniPakt Paneli</a>
        </div>
      </div>
      <div style="padding:20px 30px;border-top:1px solid #292929;color:#666;font-size:12px;line-height:1.6;">
        Bu e-posta UniPakt.Panel bildirim sisteminden otomatik olarak gönderilmiştir. Yanıtlamayın veya başkasıyla paylaşmayın.
      </div>
    </div>
  </div>
</body>
</html>
`;
}

async function sendEmail(to: string, notification: any): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${RESEND_API_KEY}` },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [to],
      subject: `UniPakt — ${notification.title}`,
      html: buildHtml(notification),
    }),
  });
  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    console.error("Resend error:", data);
    throw new Error("Resend e-posta gönderimi başarısız.");
  }
}

Deno.serve(async (req) => {
  await loadBrand();
  if (req.method !== "POST") return json(405, { error: "POST gerekli." });

  // 1) Only the database trigger knows this key.
  const key = req.headers.get("apikey") ?? "";
  const { data: keyOk, error: keyError } = await supabase.rpc("verify_notification_key", { p_key: key });
  if (keyError) {
    console.error("Key check failed:", keyError.message);
    return json(500, { error: "Doğrulama yapılamadı." });
  }
  if (keyOk !== true) return json(401, { error: "Yetkisiz." });

  try {
    const payload = await req.json().catch(() => null);
    const id = String(payload?.record?.id ?? "");
    if (!UUID_RE.test(id)) return json(400, { error: "Geçersiz bildirim." });

    // 2) Use the stored notification, never the request body.
    const { data: notification, error: nError } = await supabase
      .from("notifications")
      .select("id,type,title,body,recipient_club_id,recipient_role")
      .eq("id", id)
      .maybeSingle();
    if (nError) throw nError;
    if (!notification) return json(404, { error: "Bildirim bulunamadı." });

    const found = new Set<string>();
    const add = (email?: string | null) => { const e = String(email ?? "").trim().toLowerCase(); if (e) found.add(e); };

    if (notification.recipient_club_id) {
      const { data: club, error } = await supabase
        .from("clubs")
        .select("email")
        .eq("id", notification.recipient_club_id)
        .maybeSingle();
      if (error) throw error;
      add(club?.email);
      const perm = permFor(String(notification.type ?? ""));
      const { data: people, error: pError } = await supabase
        .from("profiles")
        .select("id, role, permissions")
        .eq("club_id", notification.recipient_club_id)
        .in("role", ["club", "member"]);
      if (pError) throw pError;
      for (const person of people ?? []) {
        if (person.role === "member" && !(perm && Array.isArray(person.permissions) && person.permissions.includes(perm))) continue;
        const { data } = await supabase.auth.admin.getUserById(person.id);
        add(data?.user?.email);
      }
    } else if (notification.recipient_role === "admin") {
      const { data: admins, error } = await supabase.from("profiles").select("id").eq("role", "admin");
      if (error) throw error;
      for (const admin of admins ?? []) {
        const { data } = await supabase.auth.admin.getUserById(admin.id);
        add(data?.user?.email);
      }
    }
    const recipients = [...found];

    if (!recipients.length) return json(200, { success: true, skipped: true });

    for (const to of recipients) await sendEmail(to, notification);
    return json(200, { success: true, sent: recipients.length });
  } catch (error) {
    console.error("send-email-notifications error:", error);
    return json(500, { error: "Bildirim e-postası gönderilemedi." });
  }
});
