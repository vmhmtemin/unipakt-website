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
//   { action: "verify", pending_id, code } -> { code, full_name, event_title }
//        wrong code -> 401 { error: "wrong", remaining }
//
// Limits: the code lives 15 minutes, 5 wrong tries end it, a new code at most every
// 60 seconds and 5 codes per registration. start_event_registration (database)
// also limits attempts per network (hashed IP) and per event.
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://unipakt.com", "https://www.unipakt.com"]);
const corsFor = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://unipakt.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const CODE_MINUTES = 15;
const MAX_WRONG = 5;
const MAX_SENDS = 5;
const RESEND_SECONDS = 60;

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
const codeHash = (pendingId: string, code: string) => sha256(`unipakt-reg:${pendingId}:${code}`);
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
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
  <div style="font:800 34px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:#FF5A1F;">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:#FF5A1F;">ETKİNLİK KAYDI</div>
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
      });
      if (error) return reply(400, { message: error.message });
      const p = { id: data.pending_id as string, email: data.email as string, full_name: data.full_name as string, sends: 0 };
      if (!await sendCode(p, data.event_title)) {
        await supabase.from("event_registration_pending").delete().eq("id", p.id);
        return reply(502, { message: "Doğrulama e-postası gönderilemedi. E-posta adresini kontrol edip tekrar dene." });
      }
      return reply(200, { pending_id: p.id, email: maskEmail(p.email), resend_in: RESEND_SECONDS });
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
      return reply(200, { code: data.code, full_name: data.full_name, event_title: data.event_title });
    }

    return reply(400, { message: "Geçersiz istek." });
  } catch (error) {
    console.error("event-register", error);
    return reply(500, { message: "Bir şeyler ters gitti. Biraz sonra tekrar dene." });
  }
});
