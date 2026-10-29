// UniPakt — entry check for events that collect registrations on UniPakt.
//
// Door staff have no panel account. A club (or UniPakt) keeps a list of staff
// (table event_staff) and gives one of them access to one event; the staff
// member gets an e-mail with a link and a 6-digit access code. The link opens
// /kontrol.html, which asks for the code and then checks registrations by QR
// (camera) or by typing the 6-character entry code.
//
// verify_jwt is off: staff calls carry no Supabase session. The "grant" action
// checks the panel user's session itself.
//
//   { action: "grant", staff_id, event_id }      Authorization: Bearer <panel session>
//        -> { ok, expires_at }                   (e-mails the staff member)
//   { action: "open",  token, access_code }      -> { event, staff, stats }
//   { action: "check", token, access_code, code } -> { result: ok|already|not_found|other_event, ... , stats }
//
// The link token and access code are stored only as hashes. 10 wrong access
// codes lock the grant; the club then sends a new one. A grant expires at the
// end of the event's last day (Istanbul time).
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://unipakt.com", "https://www.unipakt.com"]);
const corsFor = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://unipakt.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const CHECK_PAGE = "https://unipakt.com/kontrol.html";
const MAX_FAILED = 10;
const QR_PREFIX = "UP1:";   // QR content: UP1:<event id>:<CODE>

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const sha256 = async (text: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
};
const randomDigits = () => {
  const buf = new Uint32Array(1);
  let n: number;
  do { crypto.getRandomValues(buf); n = buf[0]; } while (n >= 4_294_000_000);
  return String(n % 1_000_000).padStart(6, "0");
};
const randomToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
};
const sessionIdOf = (jwt: string) => {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return /^[0-9a-f-]{36}$/i.test(String(payload.session_id ?? "")) ? String(payload.session_id) : "00000000-0000-0000-0000-000000000000";
  } catch { return "00000000-0000-0000-0000-000000000000"; }
};
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const codeHash = (tokenHash: string, code: string) => sha256(`unipakt-checkin:${tokenHash}:${code}`);
const trDate = (iso: string) => new Date(iso).toLocaleString("tr-TR", { timeZone: "Europe/Istanbul", day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
const maskEmail = (email: string) => {
  const [name, domain] = String(email || "").split("@");
  if (!domain) return "";
  return `${name.slice(0, 2)}${"•".repeat(Math.max(2, Math.min(6, name.length - 2)))}@${domain}`;
};

const grantEmail = (staffName: string, eventTitle: string, ownerName: string, link: string, code: string, expiresAt: string) => {
  const digits = code.split("").map((d) =>
    `<td style="width:44px;height:56px;background:#1E1E21;border-radius:12px;text-align:center;vertical-align:middle;font:700 26px/56px Arial,Helvetica,sans-serif;color:#F2F1EE;">${esc(d)}</td><td style="width:8px;"></td>`).join("");
  return `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"></head>
<body style="margin:0;padding:0;background:#0C0C0D;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0C0C0D;"><tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:540px;background:#161618;border:1px solid #2a2a2d;border-radius:22px;"><tr><td style="padding:36px 32px;font-family:Arial,Helvetica,sans-serif;color:#F2F1EE;">
  <div style="font:800 34px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:#FF5A1F;">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:#FF5A1F;">GİRİŞ KONTROLÜ</div>
  <h1 style="margin:32px 0 10px;font:800 25px/1.25 Arial,Helvetica,sans-serif;color:#F2F1EE;">Merhaba ${esc(staffName)},</h1>
  <p style="margin:0 0 22px;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;"><b style="color:#F2F1EE;">${esc(ownerName)}</b>, seni <b style="color:#F2F1EE;">${esc(eventTitle)}</b> etkinliğinde giriş kontrolü görevlisi olarak ekledi. Katılımcıların QR kodunu ya da 6 haneli kayıt kodunu kontrol edeceksin.</p>
  <p style="margin:0 0 10px;font:600 14px/1.4 Arial,Helvetica,sans-serif;color:#9A9995;">Erişim kodun</p>
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>${digits}</tr></table>
  <p style="margin:26px 0 0;"><a href="${esc(link)}" style="display:inline-block;padding:15px 28px;border-radius:999px;background:#FF5A1F;color:#0C0C0D;font:700 16px/1 Arial,Helvetica,sans-serif;text-decoration:none;">Kontrol sayfasını aç</a></p>
  <p style="margin:24px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Bağlantıyı açınca erişim kodunu isteyecek. Yetkin ${esc(trDate(expiresAt))} tarihine kadar geçerli. Bu bağlantıyı ve kodu kimseyle paylaşma.</p>
</td></tr></table>
<p style="margin:18px 0 0;font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6f6e6a;">Bu e-posta UniPakt üzerinden gönderildi. Bir hata olduğunu düşünüyorsan etkinliği düzenleyen kulüple iletişime geç.</p>
</td></tr></table></body></html>`;
};

const stats = async (eventId: string) => {
  const { count: total } = await supabase.from("event_registrations").select("id", { count: "exact", head: true }).eq("event_id", eventId);
  const { count: checked } = await supabase.from("event_registrations").select("id", { count: "exact", head: true }).eq("event_id", eventId).not("checked_in_at", "is", null);
  return { total: total ?? 0, checked: checked ?? 0 };
};

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsFor(origin), "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(origin) });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }); }
  const action = String(body.action ?? "");

  try {
    // ---------------- Club / UniPakt: give a staff member access to an event ----------------
    if (action === "grant") {
      const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
      const { data: authData } = jwt ? await supabase.auth.getUser(jwt) : { data: { user: null } };
      const user = authData.user;
      if (!user) return reply(401, { message: "Oturum geçersiz." });
      const { data: me } = await supabase.from("profiles").select("role, club_id").eq("id", user.id).maybeSingle();
      if (!me || !["club", "admin"].includes(me.role)) return reply(403, { message: "Bu işlem için panel yetkisi gerekli." });
      const { data: mfaOk } = await supabase.rpc("mfa_session_ok", { p_user: user.id, p_session: sessionIdOf(jwt) });
      if (!mfaOk) return reply(403, { message: "Önce iki adımlı doğrulamayı tamamla.", mfa_required: true });

      const staffId = String(body.staff_id ?? ""), eventId = String(body.event_id ?? "");
      if (!UUID.test(staffId) || !UUID.test(eventId)) return reply(400, { message: "Geçersiz istek." });
      const ownerClub = me.role === "admin" ? null : me.club_id;
      const { data: staff } = await supabase.from("event_staff").select("id, club_id, full_name, email").eq("id", staffId).maybeSingle();
      if (!staff || (staff.club_id ?? null) !== ownerClub) return reply(404, { message: "Görevli bulunamadı." });
      const { data: event } = await supabase.from("events").select("id, club_id, title, status").eq("id", eventId).maybeSingle();
      if (!event || (me.role !== "admin" && event.club_id !== me.club_id)) return reply(404, { message: "Etkinlik bulunamadı." });
      if (event.status !== "published") return reply(400, { message: "Yalnızca yayındaki etkinlikler için yetki verilebilir." });
      const { data: settings } = await supabase.from("event_registration_settings").select("enabled").eq("event_id", eventId).maybeSingle();
      if (!settings?.enabled) return reply(400, { message: "Bu etkinlik UniPakt üzerinden kayıt toplamıyor." });
      const { data: endsAt } = await supabase.rpc("event_ends_at", { p_event: eventId });
      if (!endsAt || new Date(endsAt).getTime() <= Date.now()) return reply(400, { message: "Etkinlik sona ermiş." });

      let ownerName = "UniPakt";
      if (event.club_id) ownerName = (await supabase.from("clubs").select("name").eq("id", event.club_id).maybeSingle()).data?.name || "Kulüp";

      const token = randomToken(), code = randomDigits();
      const tokenHash = await sha256(token);
      const { error } = await supabase.from("event_staff_grants").upsert({
        staff_id: staffId, event_id: eventId, link_token_hash: tokenHash, access_code_hash: await codeHash(tokenHash, code),
        failed_attempts: 0, expires_at: endsAt, created_at: new Date().toISOString(), last_used_at: null,
      }, { onConflict: "staff_id,event_id" });
      if (error) throw error;

      const link = `${CHECK_PAGE}#t=${token}`;
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}` },
        body: JSON.stringify({
          from: FROM_EMAIL, to: [staff.email],
          subject: `${event.title} · giriş kontrolü görevin`,
          html: grantEmail(staff.full_name, event.title, ownerName, link, code, endsAt),
          text: `Merhaba ${staff.full_name},\n\n${ownerName}, seni ${event.title} etkinliğinde giriş kontrolü görevlisi olarak ekledi.\n\nErişim kodun: ${code}\nKontrol sayfası: ${link}\n\nYetkin ${trDate(endsAt)} tarihine kadar geçerli. Bu bağlantıyı ve kodu kimseyle paylaşma.`,
        }),
      });
      if (!res.ok) {
        await supabase.from("event_staff_grants").delete().eq("staff_id", staffId).eq("event_id", eventId);
        console.error("grant mail failed", res.status);
        return reply(502, { message: "Yetki e-postası gönderilemedi. Biraz sonra tekrar dene." });
      }
      return reply(200, { ok: true, expires_at: endsAt });
    }

    // ---------------- Staff: open the check page / check a code ----------------
    if (action !== "open" && action !== "check") return reply(400, { message: "Geçersiz istek." });
    const token = String(body.token ?? "");
    const accessCode = String(body.access_code ?? "").replace(/\D/g, "");
    if (!token || token.length > 200) return reply(404, { error: "link", message: "Bağlantı geçersiz. E-postadaki bağlantıyı yeniden aç." });
    const tokenHash = await sha256(token);
    const { data: grant } = await supabase.from("event_staff_grants")
      .select("id, staff_id, event_id, access_code_hash, failed_attempts, expires_at").eq("link_token_hash", tokenHash).maybeSingle();
    if (!grant) return reply(404, { error: "link", message: "Bu bağlantı artık geçerli değil. Kulübünden yeni yetki iste." });
    if (new Date(grant.expires_at).getTime() <= Date.now()) return reply(403, { error: "expired", message: "Bu etkinlik için kontrol yetkinin süresi doldu." });
    if (grant.failed_attempts >= MAX_FAILED) return reply(403, { error: "locked", message: "Çok fazla hatalı erişim kodu girildi. Kulübünden yeni yetki iste." });
    if (accessCode.length !== 6 || grant.access_code_hash !== await codeHash(tokenHash, accessCode)) {
      const failed = grant.failed_attempts + 1;
      await supabase.from("event_staff_grants").update({ failed_attempts: failed }).eq("id", grant.id);
      const remaining = MAX_FAILED - failed;
      return reply(401, { error: remaining > 0 ? "wrong" : "locked", remaining,
        message: remaining > 0 ? `Erişim kodu yanlış. ${remaining} deneme hakkın kaldı.` : "Çok fazla hatalı erişim kodu girildi. Kulübünden yeni yetki iste." });
    }
    await supabase.from("event_staff_grants").update({ last_used_at: new Date().toISOString(), failed_attempts: 0 }).eq("id", grant.id);

    if (action === "open") {
      const { data: event } = await supabase.from("events").select("id, title, event_date, event_time, place, club_id").eq("id", grant.event_id).maybeSingle();
      const { data: staff } = await supabase.from("event_staff").select("full_name").eq("id", grant.staff_id).maybeSingle();
      let owner = "UniPakt";
      if (event?.club_id) owner = (await supabase.from("clubs").select("name").eq("id", event.club_id).maybeSingle()).data?.name || "Kulüp";
      return reply(200, {
        event: { id: event?.id, title: event?.title, date: event?.event_date, time: event?.event_time, place: event?.place, owner },
        staff: { name: staff?.full_name ?? "" }, expires_at: grant.expires_at, stats: await stats(grant.event_id),
      });
    }

    // check
    let raw = String(body.code ?? "").trim().toUpperCase();
    if (raw.startsWith(QR_PREFIX)) {
      const [, eventId, code] = raw.split(":");
      if (!eventId || eventId.toLowerCase() !== String(grant.event_id).toLowerCase()) {
        return reply(200, { result: "other_event", message: "Bu QR başka bir etkinliğe ait.", stats: await stats(grant.event_id) });
      }
      raw = code ?? "";
    }
    const code = raw.replace(/[^A-Z0-9]/g, "");
    if (code.length !== 6) return reply(200, { result: "not_found", message: "Kod 6 karakter olmalı.", stats: await stats(grant.event_id) });

    const now = new Date().toISOString();
    const { data: updated } = await supabase.from("event_registrations")
      .update({ checked_in_at: now, checked_in_by: grant.staff_id })
      .eq("event_id", grant.event_id).eq("code", code).is("checked_in_at", null)
      .select("full_name, email, code, checked_in_at").maybeSingle();
    if (updated) {
      return reply(200, { result: "ok", person: { name: updated.full_name, email: maskEmail(updated.email), code: updated.code }, checked_in_at: updated.checked_in_at, stats: await stats(grant.event_id) });
    }
    const { data: existing } = await supabase.from("event_registrations")
      .select("full_name, email, code, checked_in_at").eq("event_id", grant.event_id).eq("code", code).maybeSingle();
    if (existing) {
      return reply(200, { result: "already", person: { name: existing.full_name, email: maskEmail(existing.email), code: existing.code }, checked_in_at: existing.checked_in_at, stats: await stats(grant.event_id) });
    }
    return reply(200, { result: "not_found", message: "Bu kodla bir kayıt yok.", stats: await stats(grant.event_id) });
  } catch (error) {
    console.error("event-checkin failed", action, error instanceof Error ? error.message : error);
    return reply(502, { message: "İşlem şu an yapılamadı. Biraz sonra tekrar dene." });
  }
});
