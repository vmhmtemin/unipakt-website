// UniPakt Panel — optional two-step verification (2FA) by e-mail code.
//
// Called by panel.html with the user's Supabase session (Authorization: Bearer …).
// Everything is tied to the JWT's session_id, so a code requested in one browser
// session can only be used in that same session.
//
//   { action: "status" }                         -> { enabled, verified, email }
//   { action: "trust", device_token }            -> { verified }   30-day trusted browser
//   { action: "send", purpose }                  -> { sent: true, email }
//   { action: "verify", purpose, code }          -> { ok, device_token? }  |  400 { error: "wrong", remaining }
//
// purpose: "enable"  — turn 2FA on (account page)
//          "login"   — verify a new session of a 2FA account
//          "disable" — turn 2FA off (needs a verified session)
//
// Codes: 6 digits, valid for 10 minutes, 5 attempts, stored only as a hash.
// Sending: at most one code per 45 seconds and 8 per hour per account.
// Mail goes out from destek@auth.unipakt.com through Resend (RESEND_API_KEY).
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://unipakt.com", "https://www.unipakt.com"]);
const corsFor = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://unipakt.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

const FROM_EMAIL = "UniPakt Panel <destek@auth.unipakt.com>";
const CODE_TTL_MS = 10 * 60 * 1000;
const TRUST_DAYS = 30;
const MAX_ATTEMPTS = 5;
const RESEND_GAP_MS = 45 * 1000;
const MAX_CODES_PER_HOUR = 8;
const PURPOSES = new Set(["enable", "login", "disable"]);

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
const randomCode = () => {
  // Uniform 000000–999999 without modulo bias.
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
    return typeof payload.session_id === "string" && /^[0-9a-f-]{36}$/i.test(payload.session_id) ? payload.session_id : "";
  } catch { return ""; }
};
const maskEmail = (email: string) => {
  const [name, domain] = String(email || "").split("@");
  if (!domain) return "";
  const shown = name.length <= 2 ? name.slice(0, 1) : name.slice(0, 2);
  return `${shown}${"•".repeat(Math.max(2, Math.min(6, name.length - shown.length)))}@${domain}`;
};
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

const PURPOSE_TEXT: Record<string, { subject: string; lead: string }> = {
  enable: { subject: "İki adımlı doğrulamayı açma kodun", lead: "UniPakt Panel hesabında iki adımlı doğrulamayı açmak için bu kodu gir." },
  login: { subject: "UniPakt Panel giriş kodun", lead: "UniPakt Panel'e bu tarayıcıdan giriş yapmak için bu kodu gir." },
  disable: { subject: "İki adımlı doğrulamayı kapatma kodun", lead: "UniPakt Panel hesabında iki adımlı doğrulamayı kapatmak için bu kodu gir." },
};

const emailHtml = (purpose: string, code: string) => {
  const t = PURPOSE_TEXT[purpose];
  const digits = code.split("").map((d) =>
    `<td style="width:46px;height:58px;background:#1E1E21;border-radius:12px;text-align:center;vertical-align:middle;font:700 28px/58px Arial,Helvetica,sans-serif;color:#F2F1EE;">${esc(d)}</td><td style="width:8px;"></td>`).join("");
  return `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"></head>
<body style="margin:0;padding:0;background:#0C0C0D;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0C0C0D;"><tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:#161618;border:1px solid #2a2a2d;border-radius:22px;"><tr><td style="padding:36px 32px;font-family:Arial,Helvetica,sans-serif;color:#F2F1EE;">
  <div style="font:800 34px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:${B.dark};">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:${B.dark};">PANEL</div>
  <h1 style="margin:32px 0 10px;font:800 26px/1.2 Arial,Helvetica,sans-serif;color:#F2F1EE;">Doğrulama kodun</h1>
  <p style="margin:0 0 26px;font:400 16px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">${esc(t.lead)}</p>
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>${digits}</tr></table>
  <p style="margin:26px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Kod 10 dakika geçerli. Bu isteği sen yapmadıysan bu e-postayı yok sayabilirsin; şifreni değiştirmeni öneririz.</p>
</td></tr></table>
<p style="margin:18px 0 0;font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6f6e6a;">Bu e-posta UniPakt Panel hesabının güvenliği için gönderildi. Lütfen yanıtlama.</p>
</td></tr></table></body></html>`;
};

const sendMail = async (to: string, purpose: string, code: string) => {
  const t = PURPOSE_TEXT[purpose];
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}` },
    body: JSON.stringify({
      from: FROM_EMAIL, to: [to], subject: `${t.subject}: ${code}`,
      html: emailHtml(purpose, code),
      text: `${t.lead}\n\nKod: ${code}\n\nKod 10 dakika geçerli. Bu isteği sen yapmadıysan bu e-postayı yok sayabilirsin.`,
    }),
  });
  if (!res.ok) throw new Error(`resend ${res.status}`);
};

const isEnabled = async (userId: string) =>
  !!(await supabase.from("mfa_settings").select("user_id").eq("user_id", userId).maybeSingle()).data;
const isVerified = async (userId: string, sessionId: string) =>
  !!(await supabase.from("mfa_verified_sessions").select("session_id").eq("session_id", sessionId).eq("user_id", userId).maybeSingle()).data;
const markVerified = (userId: string, sessionId: string) =>
  supabase.from("mfa_verified_sessions").upsert({ session_id: sessionId, user_id: userId });
const issueDeviceToken = async (userId: string, userAgent: string) => {
  const token = randomToken();
  await supabase.from("mfa_trusted_devices").insert({
    user_id: userId, token_hash: await sha256(token), label: userAgent.slice(0, 160),
    expires_at: new Date(Date.now() + TRUST_DAYS * 86400000).toISOString(), last_used_at: new Date().toISOString(),
  });
  return token;
};

Deno.serve(async (req) => {
  await loadBrand();
  const origin = req.headers.get("Origin");
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsFor(origin), "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(origin) });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply(401, { message: "Oturum geçersiz." });
  const { data: authData } = await supabase.auth.getUser(jwt);
  const user = authData.user;
  const sessionId = sessionIdOf(jwt);
  if (!user || !sessionId) return reply(401, { message: "Oturum geçersiz." });

  const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (!profile || !["club", "admin", "member"].includes(profile.role)) return reply(403, { message: "Bu hesaba panel yetkisi verilmemiş." });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }); }
  const action = String(body.action ?? "");
  const userAgent = req.headers.get("User-Agent") ?? "";

  try {
    const enabled = await isEnabled(user.id);

    if (action === "status") {
      const verified = !enabled || await isVerified(user.id, sessionId);
      return reply(200, { enabled, verified, email: maskEmail(user.email ?? "") });
    }

    if (action === "trust") {
      if (!enabled) return reply(200, { verified: true });
      const token = String(body.device_token ?? "");
      if (!token || token.length > 200) return reply(200, { verified: false });
      const { data: device } = await supabase.from("mfa_trusted_devices").select("id, expires_at")
        .eq("user_id", user.id).eq("token_hash", await sha256(token)).maybeSingle();
      if (!device || new Date(device.expires_at).getTime() < Date.now()) return reply(200, { verified: false });
      await markVerified(user.id, sessionId);
      await supabase.from("mfa_trusted_devices").update({ last_used_at: new Date().toISOString() }).eq("id", device.id);
      return reply(200, { verified: true });
    }

    const purpose = String(body.purpose ?? "");
    if (!PURPOSES.has(purpose)) return reply(400, { message: "Geçersiz istek." });
    if (purpose === "enable" && enabled) return reply(409, { message: "İki adımlı doğrulama zaten açık." });
    if (purpose !== "enable" && !enabled) return reply(409, { message: "İki adımlı doğrulama kapalı." });
    if (purpose === "disable" && !(await isVerified(user.id, sessionId))) return reply(403, { message: "Önce bu oturumu doğrula." });

    if (action === "send") {
      if (!user.email) return reply(400, { message: "Hesapta e-posta adresi yok." });
      const hourAgo = new Date(Date.now() - 3600000).toISOString();
      const { data: recent } = await supabase.from("mfa_codes").select("created_at")
        .eq("user_id", user.id).gte("created_at", hourAgo).order("created_at", { ascending: false });
      if (recent && recent.length) {
        const wait = RESEND_GAP_MS - (Date.now() - new Date(recent[0].created_at).getTime());
        if (wait > 0) return reply(429, { message: `Yeni kod için ${Math.ceil(wait / 1000)} saniye bekle.`, retry_after: Math.ceil(wait / 1000) });
        if (recent.length >= MAX_CODES_PER_HOUR) return reply(429, { message: "Çok fazla kod istendi. Bir saat sonra tekrar dene." });
      }
      // Older unused codes of this session and purpose stop working.
      await supabase.from("mfa_codes").update({ used_at: new Date().toISOString() })
        .eq("user_id", user.id).eq("session_id", sessionId).eq("purpose", purpose).is("used_at", null);
      await supabase.from("mfa_codes").delete().lt("expires_at", new Date(Date.now() - 86400000).toISOString());
      const code = randomCode();
      const { error } = await supabase.from("mfa_codes").insert({
        user_id: user.id, session_id: sessionId, purpose,
        code_hash: await sha256(`${user.id}:${purpose}:${code}`),
        expires_at: new Date(Date.now() + CODE_TTL_MS).toISOString(),
      });
      if (error) throw error;
      await sendMail(user.email, purpose, code);
      return reply(200, { sent: true, email: maskEmail(user.email) });
    }

    if (action === "verify") {
      const code = String(body.code ?? "").replace(/\D/g, "");
      if (code.length !== 6) return reply(400, { error: "wrong", message: "Kod 6 haneli olmalı." });
      const { data: row } = await supabase.from("mfa_codes").select("id, code_hash, attempts, expires_at")
        .eq("user_id", user.id).eq("session_id", sessionId).eq("purpose", purpose).is("used_at", null)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (!row || new Date(row.expires_at).getTime() < Date.now()) return reply(400, { error: "expired", message: "Kodun süresi doldu. Yeni kod iste." });
      if (row.attempts >= MAX_ATTEMPTS) return reply(400, { error: "locked", message: "Çok fazla yanlış deneme. Yeni kod iste." });
      if (row.code_hash !== await sha256(`${user.id}:${purpose}:${code}`)) {
        const attempts = row.attempts + 1;
        await supabase.from("mfa_codes").update({ attempts, ...(attempts >= MAX_ATTEMPTS ? { used_at: new Date().toISOString() } : {}) }).eq("id", row.id);
        const remaining = MAX_ATTEMPTS - attempts;
        return reply(400, { error: remaining > 0 ? "wrong" : "locked", remaining,
          message: remaining > 0 ? `Kod yanlış. ${remaining} deneme hakkın kaldı.` : "Çok fazla yanlış deneme. Yeni kod iste." });
      }
      await supabase.from("mfa_codes").update({ used_at: new Date().toISOString() }).eq("id", row.id);

      if (purpose === "disable") {
        await supabase.from("mfa_settings").delete().eq("user_id", user.id);
        await supabase.from("mfa_trusted_devices").delete().eq("user_id", user.id);
        await supabase.from("mfa_verified_sessions").delete().eq("user_id", user.id);
        return reply(200, { ok: true });
      }
      if (purpose === "enable") {
        await supabase.from("mfa_settings").upsert({ user_id: user.id });
        // Other open sessions of this account have to verify from now on.
        await supabase.from("mfa_verified_sessions").delete().eq("user_id", user.id);
      }
      await markVerified(user.id, sessionId);
      return reply(200, { ok: true, device_token: await issueDeviceToken(user.id, userAgent), trust_days: TRUST_DAYS });
    }

    return reply(400, { message: "Geçersiz istek." });
  } catch (error) {
    console.error("mfa failed", action, error instanceof Error ? error.message : error);
    return reply(502, { message: "Doğrulama şu an yapılamadı. Biraz sonra tekrar dene." });
  }
});
