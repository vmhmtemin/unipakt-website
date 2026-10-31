// UniPakt — registration for events that collect registrations on UniPakt, with
// e-mail verification. The visitor fills the form on the event page; we e-mail a
// 6-digit code; the registration (and its entry code + QR) exists only after the
// code is entered.
//
// verify_jwt is off: visitors have no account.
//
//   { action: "start",  event_id, full_name, email, answers, consent, hp }
//        -> { pending_id, email (masked), resend_in }
//   { action: "resend", pending_id }  -> { email (masked), resend_in }
//   { action: "verify", pending_id, code } -> { status: confirmed|waitlist, code?, position?, full_name, event_title }
//        wrong code -> 401 { error: "wrong", remaining }
//   Every confirmed registration gets its ticket by e-mail (code, QR image, link
//   /etkinlik/?id=…#bilet=TOKEN that opens the ticket on any device).
//   { action: "ticket", token }                  -> { event_id, code, full_name, status, event_title }
//   Waiting list: when a seat frees up the next person gets a timed offer by e-mail
//   (/etkinlik/?id=…#teklif=TOKEN).
//   { action: "offer", token }                   -> { event_id, full_name, event_title, expires_at }
//   { action: "offer_accept" | "offer_decline", token }
//   Cancelling (code e-mailed to the registered address):
//   { action: "cancel_start", event_id, email | code } -> { cancel_id, email (masked) }
//   { action: "cancel_resend", cancel_id } / { action: "cancel_verify", cancel_id, code }
//   { action: "no_reminders", registration_id, sig } -> hatırlatma e-postalarını kapatır (hatırlatma e-postasındaki bağlantı)
//   start ayrıca no_reminders: true alabilir (formdaki "hatırlatma istemiyorum" kutusu)
//   { action: "sweep", event_id? }  expired offers out, freed seats offered (cron every 10 min);
//        without event_id also sends the due reminder e-mails (1 day / 2 hours before, per club setting)
//
// Limits: the code lives 15 minutes, 5 wrong tries end it, a new code at most every
// 60 seconds and 5 codes per registration. start_event_registration (database)
// also limits attempts per network (hashed IP) and per event.
import { createClient } from "npm:@supabase/supabase-js@2";
import QRCode from "npm:qrcode@1.5.4";

const allowedOrigins = new Set(["https://unipakt.com", "https://www.unipakt.com"]);
const corsFor = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://unipakt.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const SITE = "https://unipakt.com";
const CODE_MINUTES = 15;
const MAX_WRONG = 5;
const MAX_SENDS = 5;
const RESEND_SECONDS = 60;

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
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
const codeHash = (pendingId: string, code: string) => sha256(`unipakt-reg:${pendingId}:${code}`);
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
// Hatırlatma e-postasındaki "hatırlatma istemiyorum" bağlantısı: kayıt kimliği + sunucu sırrıyla imza.
const noRemindSig = async (regId: string) =>
  (await sha256(`unipakt-noremind:${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}:${regId}`)).slice(0, 32);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const maskEmail = (email: string) => {
  const [name, domain] = String(email || "").split("@");
  if (!domain) return "";
  return `${name.slice(0, 2)}${"•".repeat(Math.max(2, Math.min(6, name.length - 2)))}@${domain}`;
};

const codeEmail = (name: string, eventTitle: string, code: string) => {
  const digits = code.split("").map((d) =>
    `<td style="width:44px;height:56px;background:#1E1E21;border-radius:12px;text-align:center;vertical-align:middle;font:700 26px/56px Arial,Helvetica,sans-serif;color:#F2F1EE;">${esc(d)}</td><td style="width:8px;"></td>`).join("");
  return `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"></head>
<body style="margin:0;padding:0;background:#0C0C0D;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0C0C0D;"><tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:540px;background:#161618;border:1px solid #2a2a2d;border-radius:22px;"><tr><td style="padding:36px 32px;font-family:Arial,Helvetica,sans-serif;color:#F2F1EE;">
  <div style="font:800 34px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:${B.dark};">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:${B.dark};">ETKİNLİK KAYDI</div>
  <h1 style="margin:32px 0 10px;font:800 25px/1.25 Arial,Helvetica,sans-serif;color:#F2F1EE;">Merhaba ${esc(name)},</h1>
  <p style="margin:0 0 22px;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;"><b style="color:#F2F1EE;">${esc(eventTitle)}</b> kaydını tamamlamak için bu kodu kayıt ekranına yaz.</p>
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>${digits}</tr></table>
  <p style="margin:24px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Kod ${CODE_MINUTES} dakika geçerli. Kaydı sen başlatmadıysan bu e-postayı yok sayabilirsin; kod girilmezse kayıt oluşmaz.</p>
</td></tr></table>
<p style="margin:18px 0 0;font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6f6e6a;">Bu e-posta UniPakt üzerinden gönderildi.</p>
</td></tr></table></body></html>`;
};

// New code for a pending registration: store its hash, e-mail it.
const sendCode = async (p: { id: string; email: string; full_name: string; sends: number }, eventTitle: string) => {
  const code = randomDigits();
  const now = new Date();
  const { error } = await supabase.from("event_registration_pending").update({
    code_hash: await codeHash(p.id, code), attempts: 0, sends: p.sends + 1, last_sent_at: now.toISOString(),
    expires_at: new Date(now.getTime() + CODE_MINUTES * 60_000).toISOString(),
  }).eq("id", p.id);
  if (error) throw error;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}` },
    body: JSON.stringify({
      from: FROM_EMAIL, to: [p.email],
      subject: `${code} · ${eventTitle} kayıt doğrulama kodun`,
      html: codeEmail(p.full_name, eventTitle, code),
      text: `Merhaba ${p.full_name},\n\n${eventTitle} kaydını tamamlamak için doğrulama kodun: ${code}\n\nKod ${CODE_MINUTES} dakika geçerli. Kaydı sen başlatmadıysan bu e-postayı yok sayabilirsin.`,
    }),
  });
  if (!res.ok) { console.error("register mail failed", res.status); return false; }
  return true;
};

const eventTitleOf = async (eventId: string) =>
  (await supabase.from("events").select("title").eq("id", eventId).maybeSingle()).data?.title || "Etkinlik";

const randomToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
};
const tokenHash = (kind: string, token: string) => sha256(`unipakt-${kind}:${token}`);
const MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const dayText = (d: string) => { const [y, m, day] = String(d || "").split("-").map(Number); return y ? `${day} ${MONTHS[m - 1]} ${y}` : ""; };
const trTime = (iso: string) => new Date(iso).toLocaleString("tr-TR", { timeZone: "Europe/Istanbul", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" });
type Ev = { id: string; title: string; event_date: string; event_time: string | null; place: string | null; city: string | null };
const eventOf = async (id: string): Promise<Ev> =>
  ((await supabase.from("events").select("id, title, event_date, event_time, place, city").eq("id", id).maybeSingle()).data as Ev)
  || { id, title: "Etkinlik", event_date: "", event_time: null, place: null, city: null };
const whenWhere = (ev: Ev) => [dayText(ev.event_date) + (ev.event_time ? ` · ${String(ev.event_time).slice(0, 5)}` : ""), [ev.place, ev.city].filter(Boolean).join(", ")].filter(Boolean);

const mail = async (to: string, subject: string, html: string, text: string, attachments?: unknown[]) => {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}` },
    body: JSON.stringify({ from: FROM_EMAIL, to: [to], subject, html, text, ...(attachments ? { attachments } : {}) }),
  });
  if (!res.ok) console.error("mail failed", subject.slice(0, 40), res.status);
  return res.ok;
};
// Shared frame of all e-mails (same look as the ticket the site downloads).
const frame = (kicker: string, inner: string) => `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"></head>
<body style="margin:0;padding:0;background:#0C0C0D;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0C0C0D;"><tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:540px;background:#161618;border:1px solid #2a2a2d;border-radius:22px;"><tr><td style="padding:34px 32px;font-family:Arial,Helvetica,sans-serif;color:#F2F1EE;">
  <div style="font:800 32px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:${B.dark};">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:${B.dark};">${esc(kicker)}</div>
  ${inner}
</td></tr></table>
<p style="margin:18px 0 0;font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6f6e6a;">Bu e-posta UniPakt üzerinden gönderildi. Sorun olursa etkinliği düzenleyen kulüple iletişime geç.</p>
</td></tr></table></body></html>`;
const button = (href: string, label: string) => `<a href="${esc(href)}" style="display:inline-block;padding:15px 28px;border-radius:999px;${B.btn}font:700 16px/1 Arial,Helvetica,sans-serif;text-decoration:none;">${esc(label)}</a>`;
const eventBlock = (ev: Ev) => `<h1 style="margin:28px 0 8px;font:800 26px/1.2 Arial,Helvetica,sans-serif;color:#F2F1EE;">${esc(ev.title)}</h1>
  <p style="margin:0;font:400 15px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">${whenWhere(ev).map(esc).join("<br>")}</p>`;

// Ticket: e-mailed for every confirmed registration (also after accepting an offer).
const sendTicket = async (reg: { id: string; event_id: string; code: string; full_name: string; email: string }) => {
  const token = randomToken();
  await supabase.from("event_registrations").update({ ticket_token_hash: await tokenHash("ticket", token) }).eq("id", reg.id);
  const ev = await eventOf(reg.event_id);
  const link = `${SITE}/etkinlik/?id=${ev.id}#bilet=${token}`;
  let attachments: unknown[] | undefined;
  try {
    const png = await QRCode.toDataURL(`UP1:${ev.id}:${reg.code}`, { margin: 2, width: 720, errorCorrectionLevel: "M" });
    attachments = [{ filename: `UniPakt-bilet-${reg.code}.png`, content: png.split(",")[1] }];
  } catch (error) { console.error("qr failed", error); }
  const letters = reg.code.split("").map((c) =>
    `<td style="width:46px;height:58px;background:#F2F1EE;border-radius:10px;text-align:center;vertical-align:middle;font:800 28px/58px Arial,Helvetica,sans-serif;color:#0C0C0D;">${esc(c)}</td><td style="width:6px;"></td>`).join("");
  const html = frame("ETKİNLİK BİLETİ", `${eventBlock(ev)}
  <div style="margin:26px -32px;border-top:2px dashed #3a3a3e;"></div>
  <p style="margin:0 0 4px;font:600 13px/1.4 Arial,Helvetica,sans-serif;color:#9A9995;">Katılımcı</p>
  <p style="margin:0 0 18px;font:700 19px/1.3 Arial,Helvetica,sans-serif;color:#F2F1EE;">${esc(reg.full_name)}</p>
  <p style="margin:0 0 10px;font:600 13px/1.4 Arial,Helvetica,sans-serif;color:#9A9995;">Giriş kodun</p>
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>${letters}</tr></table>
  <p style="margin:26px 0 0;">${button(link, "Biletimi aç (QR)")}</p>
  <p style="margin:22px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Girişte QR'ı ya da bu kodu göster. QR ekte de var. Katılamayacaksan biletini açıp “Kaydımı iptal et” ile yerini başkasına bırakabilirsin.</p>`);
  const text = `${ev.title}\n${whenWhere(ev).join("\n")}\n\nKatılımcı: ${reg.full_name}\nGiriş kodun: ${reg.code}\n\nBiletini aç (QR): ${link}\n\nKatılamayacaksan biletini açıp “Kaydımı iptal et” ile yerini başkasına bırakabilirsin.`;
  return mail(reg.email, `Biletin: ${ev.title}`, html, text, attachments);
};

const sendWaitlistMail = async (reg: { event_id: string; full_name: string; email: string }, position: number) => {
  const ev = await eventOf(reg.event_id);
  const link = `${SITE}/etkinlik/?id=${ev.id}`;
  const html = frame("BEKLEME LİSTESİ", `${eventBlock(ev)}
  <p style="margin:24px 0 0;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">Merhaba ${esc(reg.full_name)}, kontenjan dolu olduğu için <b style="color:#F2F1EE;">bekleme listesine</b> alındın${position ? ` (sıran: <b style="color:#F2F1EE;">${position}</b>)` : ""}.</p>
  <p style="margin:12px 0 0;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">Yer açılınca bu adrese bir e-posta gelecek; belirtilen süre içinde onaylarsan biletin hemen gönderilir.</p>
  <p style="margin:24px 0 0;">${button(link, "Etkinlik sayfası")}</p>`);
  return mail(reg.email, `Bekleme listesindesin: ${ev.title}`, html,
    `${ev.title}\n\nKontenjan dolu olduğu için bekleme listesine alındın${position ? ` (sıran: ${position})` : ""}. Yer açılınca e-posta gelecek.\n\n${link}`);
};

const sendOffer = async (registrationId: string) => {
  const { data: reg } = await supabase.from("event_registrations").select("id, event_id, full_name, email, status, offer_expires_at").eq("id", registrationId).maybeSingle();
  if (!reg || reg.status !== "offered") return false;
  const token = randomToken();
  await supabase.from("event_registrations").update({ offer_token_hash: await tokenHash("offer", token) }).eq("id", reg.id);
  const ev = await eventOf(reg.event_id);
  const link = `${SITE}/etkinlik/?id=${ev.id}#teklif=${token}`;
  const until = trTime(reg.offer_expires_at);
  const html = frame("YER AÇILDI", `${eventBlock(ev)}
  <p style="margin:24px 0 0;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">Merhaba ${esc(reg.full_name)}, bekleme listesinde sıra sana geldi. Yerini <b style="color:#F2F1EE;">${esc(until)}</b> tarihine kadar onaylarsan biletin hemen gönderilir; onaylamazsan yer sıradaki kişiye geçer.</p>
  <p style="margin:24px 0 0;">${button(link, "Yerimi onayla")}</p>
  <p style="margin:18px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Katılamayacaksan aynı sayfadan “Yeri bırak” diyebilirsin.</p>`);
  return mail(reg.email, `Yer açıldı: ${ev.title} — ${until}'e kadar onayla`, html,
    `${ev.title}\n\nBekleme listesinde sıra sana geldi. ${until} tarihine kadar onayla: ${link}`);
};

// Run the queue (one event or all) and e-mail new offers; also retries offers whose mail failed.
const runSweep = async (eventId?: string) => {
  const { data } = await supabase.rpc("registration_sweep", eventId ? { p_event: eventId } : {});
  const ids = new Set<string>((data ?? []).map((r: { registration_id: string }) => r.registration_id));
  let q = supabase.from("event_registrations").select("id").eq("status", "offered").is("offer_token_hash", null).limit(50);
  if (eventId) q = q.eq("event_id", eventId);
  ((await q).data ?? []).forEach((r: { id: string }) => ids.add(r.id));
  for (const id of ids) await sendOffer(id);
  return ids.size;
};

// Hatırlatma (kulübün kayıt ayarında seçtiği: 1 gün / 2 saat önce). Bilet bağlantısı
// yeniden üretilmez (ilk e-postadaki bağlantı çalışmaya devam etsin); kod ve QR ekte.
const sendReminder = async (r: { id: string; event_id: string; kind: string; code: string; full_name: string; email: string }) => {
  const ev = await eventOf(r.event_id);
  const soon = r.kind === "2h" ? "2 saat sonra başlıyor" : "Yarın görüşüyoruz";
  let attachments: unknown[] | undefined;
  try {
    const png = await QRCode.toDataURL(`UP1:${ev.id}:${r.code}`, { margin: 2, width: 720, errorCorrectionLevel: "M" });
    attachments = [{ filename: `UniPakt-bilet-${r.code}.png`, content: png.split(",")[1] }];
  } catch (error) { console.error("qr failed", error); }
  const page = `${SITE}/etkinlik/?id=${ev.id}`;
  const cancel = `${page}#iptal=${r.code}`;
  const stop = `${page}#hatirlatma=${r.id}.${await noRemindSig(r.id)}`;
  const letters = r.code.split("").map((c) =>
    `<td style="width:46px;height:58px;background:#F2F1EE;border-radius:10px;text-align:center;vertical-align:middle;font:800 28px/58px Arial,Helvetica,sans-serif;color:#0C0C0D;">${esc(c)}</td><td style="width:6px;"></td>`).join("");
  const html = frame(soon.toLocaleUpperCase("tr-TR"), `${eventBlock(ev)}
  <p style="margin:22px 0 18px;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">Merhaba ${esc(r.full_name)}, kaydın hazır. Girişte QR'ı (ekte) ya da bu kodu göster.</p>
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>${letters}</tr></table>
  <p style="margin:26px 0 0;">${button(page, "Etkinlik sayfası")}</p>
  <p style="margin:22px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Gelemeyeceksen <a href="${esc(cancel)}" style="color:${B.dark};">kaydını iptal et</a>; yerin bekleyen birine geçsin.</p>
  <p style="margin:10px 0 0;font:400 13px/1.6 Arial,Helvetica,sans-serif;color:#7C7A75;">Bu etkinlik için hatırlatma almak istemiyorsan <a href="${esc(stop)}" style="color:#9A9995;">hatırlatmaları kapat</a>.</p>`);
  const text = `${ev.title}\n${whenWhere(ev).join("\n")}\n\nMerhaba ${r.full_name}, girişte QR'ı (ekte) ya da bu kodu göster: ${r.code}\n\nEtkinlik sayfası: ${page}\nGelemeyeceksen kaydını iptal et: ${cancel}\nHatırlatmaları kapat: ${stop}`;
  return mail(r.email, `${soon}: ${ev.title}`, html, text, attachments);
};
const runReminders = async () => {
  const { data, error } = await supabase.rpc("due_registration_reminders", { p_limit: 200 });
  if (error) { console.error("reminders failed", error.message); return 0; }
  let sent = 0;
  for (const r of data ?? []) if (await sendReminder(r)) sent++;
  return sent;
};

const cancelEmail = (name: string, ev: Ev, code: string) => {
  const digits = code.split("").map((d) =>
    `<td style="width:44px;height:56px;background:#1E1E21;border-radius:12px;text-align:center;vertical-align:middle;font:700 26px/56px Arial,Helvetica,sans-serif;color:#F2F1EE;">${esc(d)}</td><td style="width:8px;"></td>`).join("");
  return frame("KAYIT İPTALİ", `${eventBlock(ev)}
  <p style="margin:24px 0 18px;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">Merhaba ${esc(name)}, kaydını iptal etmek için bu kodu iptal ekranına yaz.</p>
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>${digits}</tr></table>
  <p style="margin:24px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Kod ${CODE_MINUTES} dakika geçerli. İptali sen istemediysen bu e-postayı yok say; kaydın aynen duruyor.</p>`);
};
const sendCancelCode = async (c: { id: string; sends: number }, reg: { full_name: string; email: string; event_id: string }) => {
  const code = randomDigits();
  const now = new Date();
  await supabase.from("event_registration_cancels").update({
    code_hash: await codeHash(c.id, code), attempts: 0, sends: c.sends + 1, last_sent_at: now.toISOString(),
    expires_at: new Date(now.getTime() + CODE_MINUTES * 60_000).toISOString(),
  }).eq("id", c.id);
  const ev = await eventOf(reg.event_id);
  return mail(reg.email, `${code} · ${ev.title} kayıt iptal kodun`, cancelEmail(reg.full_name, ev, code),
    `${ev.title}\n\nKaydını iptal etmek için kod: ${code}\nKod ${CODE_MINUTES} dakika geçerli. İptali sen istemediysen bu e-postayı yok say.`);
};

Deno.serve(async (req) => {
  await loadBrand();
  const origin = req.headers.get("Origin");
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsFor(origin), "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(origin) });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }); }
  const action = String(body.action ?? "");

  try {
    if (action === "start") {
      const eventId = String(body.event_id ?? "");
      if (!UUID.test(eventId)) return reply(400, { message: "Geçersiz istek." });
      // Bot trap: the hidden field is filled → pretend it worked, do nothing.
      if (String(body.hp ?? "").trim()) return reply(200, { pending_id: crypto.randomUUID(), email: maskEmail(String(body.email ?? "")), resend_in: RESEND_SECONDS });
      const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || req.headers.get("cf-connecting-ip") || "";
      const { data, error } = await supabase.rpc("start_event_registration", {
        p_event: eventId, p_full_name: String(body.full_name ?? ""), p_email: String(body.email ?? ""),
        p_answers: body.answers && typeof body.answers === "object" ? body.answers : {}, p_consent: body.consent === true,
        p_ip_hash: ip ? await sha256(`unipakt-reg-ip:${ip}`) : null,
        p_no_reminders: body.no_reminders === true,
      });
      if (error) return reply(400, { message: error.message });
      const p = { id: data.pending_id as string, email: data.email as string, full_name: data.full_name as string, sends: 0 };
      if (!await sendCode(p, data.event_title)) {
        await supabase.from("event_registration_pending").delete().eq("id", p.id);
        return reply(502, { message: "Doğrulama e-postası gönderilemedi. E-posta adresini kontrol edip tekrar dene." });
      }
      return reply(200, { pending_id: p.id, email: maskEmail(p.email), resend_in: RESEND_SECONDS });
    }

    if (action === "no_reminders") {
      const id = String(body.registration_id ?? ""), sig = String(body.sig ?? "");
      if (!UUID.test(id) || !/^[0-9a-f]{32}$/.test(sig) || sig !== await noRemindSig(id)) return reply(400, { message: "Bağlantı geçersiz." });
      const { data, error } = await supabase.from("event_registrations").update({ no_reminders: true }).eq("id", id).select("event_id").maybeSingle();
      if (error || !data) return reply(404, { message: "Kayıt bulunamadı." });
      const ev = await eventOf(data.event_id);
      return reply(200, { event_id: data.event_id, event_title: ev.title });
    }

    if (action === "sweep") {
      const eventId = String(body.event_id ?? "");
      if (UUID.test(eventId)) return reply(200, { offered: await runSweep(eventId) });
      const offered = await runSweep();
      return reply(200, { offered, reminded: await runReminders() });
    }

    if (action === "ticket" || action === "offer" || action === "offer_accept" || action === "offer_decline") {
      const token = String(body.token ?? "");
      if (!token || token.length > 100) return reply(404, { error: "link", message: "Bağlantı geçersiz." });
      const kind = action === "ticket" ? "ticket" : "offer";
      const { data: reg } = await supabase.from("event_registrations")
        .select("id, event_id, code, full_name, email, status, offer_expires_at")
        .eq(kind === "ticket" ? "ticket_token_hash" : "offer_token_hash", await tokenHash(kind, token)).maybeSingle();
      if (!reg) return reply(404, { error: "link", message: kind === "ticket" ? "Bu bilet bağlantısı geçersiz ya da kayıt iptal edilmiş." : "Bu teklifin süresi dolmuş ya da kullanılmış." });
      const title = await eventTitleOf(reg.event_id);
      if (action === "ticket") return reply(200, { event_id: reg.event_id, code: reg.code, full_name: reg.full_name, status: reg.status, event_title: title });
      if (reg.status !== "offered" || new Date(reg.offer_expires_at).getTime() <= Date.now()) return reply(410, { error: "expired", message: "Bu teklifin süresi dolmuş." });
      if (action === "offer") return reply(200, { event_id: reg.event_id, full_name: reg.full_name, event_title: title, expires_at: reg.offer_expires_at });
      if (action === "offer_decline") {
        await supabase.from("event_registrations").delete().eq("id", reg.id);
        await runSweep(reg.event_id);
        return reply(200, { ok: true });
      }
      const { data, error } = await supabase.rpc("accept_registration_offer", { p_registration: reg.id });
      if (error) return reply(400, { message: error.message });
      await sendTicket({ id: reg.id, event_id: reg.event_id, code: data.code, full_name: data.full_name, email: reg.email });
      return reply(200, { status: "confirmed", code: data.code, full_name: data.full_name, event_title: data.event_title, event_id: reg.event_id });
    }

    if (action === "cancel_start") {
      const eventId = String(body.event_id ?? "");
      if (!UUID.test(eventId)) return reply(400, { message: "Geçersiz istek." });
      const email = String(body.email ?? "").trim().toLowerCase();
      const code = String(body.code ?? "").trim().toUpperCase();
      let q = supabase.from("event_registrations").select("id, event_id, full_name, email").eq("event_id", eventId);
      if (/^[A-Z0-9]{6}$/.test(code)) q = q.eq("code", code);
      else if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) q = q.ilike("email", email.replace(/[%_\\]/g, "\\$&"));
      else return reply(400, { message: "Kayıtlı e-posta adresini yaz." });
      const { data: reg } = await q.maybeSingle();
      // E-postayla başlatılınca kayıt olup olmadığı söylenmez.
      if (!reg) return reply(200, { cancel_id: crypto.randomUUID(), email: email ? maskEmail(email) : "", resend_in: RESEND_SECONDS });
      const recent = (await supabase.from("event_registration_cancels").select("id", { count: "exact", head: true })
        .eq("registration_id", reg.id).gt("created_at", new Date(Date.now() - 3600_000).toISOString())).count ?? 0;
      if (recent >= 5) return reply(429, { message: "Çok fazla iptal isteği yapıldı. Biraz sonra tekrar dene." });
      const { data: c, error } = await supabase.from("event_registration_cancels").insert({ registration_id: reg.id }).select("id, sends").single();
      if (error) throw error;
      if (!await sendCancelCode(c, reg)) return reply(502, { message: "E-posta gönderilemedi. Biraz sonra tekrar dene." });
      return reply(200, { cancel_id: c.id, email: maskEmail(reg.email), resend_in: RESEND_SECONDS });
    }

    if (action === "cancel_resend" || action === "cancel_verify") {
      const cancelId = String(body.cancel_id ?? "");
      if (!UUID.test(cancelId)) return reply(400, { message: "Geçersiz istek." });
      const { data: c } = await supabase.from("event_registration_cancels")
        .select("id, registration_id, code_hash, attempts, sends, last_sent_at, expires_at").eq("id", cancelId).maybeSingle();
      // Unknown id (also the decoy from cancel_start): behave like a wrong code.
      if (!c) return action === "cancel_resend" ? reply(200, { resend_in: RESEND_SECONDS }) : reply(401, { error: "wrong", message: "Kod yanlış ya da süresi dolmuş." });
      const { data: reg } = await supabase.from("event_registrations").select("id, event_id, full_name, email").eq("id", c.registration_id).maybeSingle();
      if (!reg) return reply(404, { error: "gone", message: "Bu kayıt zaten iptal edilmiş." });
      if (action === "cancel_resend") {
        const wait = c.last_sent_at ? Math.ceil(RESEND_SECONDS - (Date.now() - new Date(c.last_sent_at).getTime()) / 1000) : 0;
        if (wait > 0) return reply(429, { error: "wait", resend_in: wait, message: `Yeni kod için ${wait} saniye bekle.` });
        if (c.sends >= MAX_SENDS) return reply(429, { error: "limit", message: "Çok fazla kod istendi. Biraz sonra tekrar dene." });
        if (!await sendCancelCode(c, reg)) return reply(502, { message: "E-posta gönderilemedi. Biraz sonra tekrar dene." });
        return reply(200, { resend_in: RESEND_SECONDS });
      }
      const code = String(body.code ?? "").replace(/\D/g, "");
      if (new Date(c.expires_at).getTime() <= Date.now()) return reply(410, { error: "expired", message: "Kodun süresi doldu. Yeni kod iste." });
      if (c.attempts >= MAX_WRONG) return reply(429, { error: "locked", message: "Çok fazla yanlış kod girildi. Yeni kod iste." });
      if (code.length !== 6 || !c.code_hash || c.code_hash !== await codeHash(c.id, code)) {
        const attempts = c.attempts + 1;
        await supabase.from("event_registration_cancels").update({ attempts }).eq("id", c.id);
        const remaining = Math.max(0, MAX_WRONG - attempts);
        return reply(401, { error: "wrong", remaining, message: remaining ? `Kod yanlış. ${remaining} deneme hakkın kaldı.` : "Kod yanlış. Yeni kod iste." });
      }
      await supabase.from("event_registrations").delete().eq("id", reg.id);
      await runSweep(reg.event_id);
      return reply(200, { ok: true });
    }

    const pendingId = String(body.pending_id ?? "");
    if (!UUID.test(pendingId)) return reply(400, { message: "Geçersiz istek." });
    const { data: p } = await supabase.from("event_registration_pending")
      .select("id, event_id, email, full_name, code_hash, attempts, sends, last_sent_at, expires_at").eq("id", pendingId).maybeSingle();
    if (!p) return reply(404, { error: "gone", message: "Doğrulama süresi doldu. Formu yeniden gönder." });

    if (action === "resend") {
      const wait = p.last_sent_at ? Math.ceil(RESEND_SECONDS - (Date.now() - new Date(p.last_sent_at).getTime()) / 1000) : 0;
      if (wait > 0) return reply(429, { error: "wait", resend_in: wait, message: `Yeni kod için ${wait} saniye bekle.` });
      if (p.sends >= MAX_SENDS) return reply(429, { error: "limit", message: "Çok fazla kod istendi. Formu yeniden gönder." });
      if (!await sendCode(p, await eventTitleOf(p.event_id))) return reply(502, { message: "E-posta gönderilemedi. Biraz sonra tekrar dene." });
      return reply(200, { email: maskEmail(p.email), resend_in: RESEND_SECONDS });
    }

    if (action === "verify") {
      const code = String(body.code ?? "").replace(/\D/g, "");
      if (new Date(p.expires_at).getTime() <= Date.now()) return reply(410, { error: "expired", message: "Kodun süresi doldu. “Kodu tekrar gönder” ile yeni kod iste." });
      if (p.attempts >= MAX_WRONG) return reply(429, { error: "locked", message: "Çok fazla yanlış kod girildi. “Kodu tekrar gönder” ile yeni kod iste." });
      if (code.length !== 6 || !p.code_hash || p.code_hash !== await codeHash(p.id, code)) {
        const attempts = p.attempts + 1;
        await supabase.from("event_registration_pending").update({ attempts }).eq("id", p.id);
        const remaining = Math.max(0, MAX_WRONG - attempts);
        return reply(401, { error: "wrong", remaining, message: remaining ? `Kod yanlış. ${remaining} deneme hakkın kaldı.` : "Kod yanlış. Yeni kod iste." });
      }
      const { data, error } = await supabase.rpc("confirm_event_registration", { p_pending: p.id });
      if (error) return reply(400, { message: error.message });
      if (data.status === "waitlist") {
        await sendWaitlistMail({ event_id: p.event_id, full_name: p.full_name, email: p.email }, data.position);
        return reply(200, { status: "waitlist", position: data.position, full_name: data.full_name, event_title: data.event_title });
      }
      await sendTicket({ id: data.registration_id, event_id: p.event_id, code: data.code, full_name: data.full_name, email: p.email });
      return reply(200, { status: "confirmed", code: data.code, full_name: data.full_name, event_title: data.event_title });
    }

    return reply(400, { message: "Geçersiz istek." });
  } catch (error) {
    console.error("event-register", error);
    return reply(500, { message: "Bir şeyler ters gitti. Biraz sonra tekrar dene." });
  }
});
