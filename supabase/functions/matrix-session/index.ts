// Creates a private Matrix device session for the authenticated UniPakt panel account.
// Synapse credentials stay in Edge Function secrets; the browser receives only its
// per-device Matrix access token and uses Matrix SDK's E2EE implementation.
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://unipakt.com", "https://www.unipakt.com"]);
const corsFor = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://unipakt.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const reply = (status: number, body: unknown, origin: string | null) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsFor(origin), "Content-Type": "application/json" } });

const encodeBase64Url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
const matrixPassword = async (secret: string, accountKey: string) => {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`unipakt-matrix-v1:${accountKey}`)));
  return encodeBase64Url(digest);
};

// The JWT's session_id; a 2FA account's session must have been verified (see the `mfa` function).
const sessionIdOf = (jwt: string) => {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return /^[0-9a-f-]{36}$/i.test(String(payload.session_id ?? "")) ? String(payload.session_id) : "00000000-0000-0000-0000-000000000000";
  } catch { return "00000000-0000-0000-0000-000000000000"; }
};

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(origin) });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." }, origin);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return reply(401, { message: "Oturum geçersiz." }, origin);
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData } = await supabase.auth.getUser(token);
  const user = authData.user;
  if (!user) return reply(401, { message: "Oturum geçersiz." }, origin);

  const { data: profile, error: profileError } = await supabase.from("profiles").select("role,club_id").eq("id", user.id).maybeSingle();
  if (profileError || !profile || !["club", "admin"].includes(profile.role)) {
    return reply(403, { message: "Bu hesap mesajlaşmaya yetkili değil." }, origin);
  }
  const { data: mfaOk } = await supabase.rpc("mfa_session_ok", { p_user: user.id, p_session: sessionIdOf(token) });
  if (!mfaOk) return reply(403, { message: "Önce iki adımlı doğrulamayı tamamla.", mfa_required: true }, origin);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }, origin); }
  const deviceId = String(body.device_id ?? "");
  if (!/^[A-Za-z0-9._=-]{1,32}$/.test(deviceId)) return reply(400, { message: "Cihaz kimliği geçersiz." }, origin);

  const homeserver = Deno.env.get("MATRIX_HOMESERVER_URL")?.replace(/\/+$/, "");
  const serverName = Deno.env.get("MATRIX_SERVER_NAME");
  const adminToken = Deno.env.get("MATRIX_ADMIN_ACCESS_TOKEN");
  const derivationSecret = Deno.env.get("MATRIX_ACCOUNT_DERIVATION_SECRET");
  if (!homeserver || !serverName || !adminToken || !derivationSecret) {
    return reply(503, { message: "Mesajlaşma sunucusu henüz yapılandırılmadı." }, origin);
  }

  if (profile.role === "club" && !/^[0-9a-f-]{36}$/i.test(String(profile.club_id ?? ""))) {
    return reply(403, { message: "Kulüp hesabının kulüp bağlantısı eksik." }, origin);
  }
  const accountKey = profile.role === "admin" ? "unipakt-support" : `club-${profile.club_id}`;
  const localpart = profile.role === "admin" ? "unipakt" : `club_${String(profile.club_id).replaceAll("-", "")}`;
  const userId = `@${localpart}:${serverName}`;
  const password = await matrixPassword(derivationSecret, accountKey);
  const headers = { Authorization: `Bearer ${adminToken}`, "Content-Type": "application/json" };
  const adminUrl = `${homeserver}/_synapse/admin/v2/users/${encodeURIComponent(userId)}`;

  try {
    const account = await fetch(adminUrl, { headers });
    if (account.status === 404) {
      const displayname = profile.role === "admin"
        ? "UniPakt"
        : ((await supabase.from("clubs").select("name").eq("id", profile.club_id).maybeSingle()).data?.name || "Kulüp");
      const created = await fetch(adminUrl, { method: "PUT", headers, body: JSON.stringify({ password, admin: false, displayname }) });
      if (!created.ok) return reply(502, { message: "Mesajlaşma hesabı açılamadı." }, origin);
    } else if (!account.ok) {
      return reply(502, { message: "Mesajlaşma sunucusuna ulaşılamadı." }, origin);
    }

    const loginMatrix = () => fetch(`${homeserver}/_matrix/client/v3/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        type: "m.login.password", user: userId, password, device_id: deviceId,
        initial_device_display_name: "UniPakt Panel",
      }),
    });
    let login = await loginMatrix();
    let session = await login.json().catch(() => ({}));
    // If the deterministic password secret was rotated after this Matrix user
    // was first created, repair the account password once and retry.
    if (!login.ok && session.errcode === "M_FORBIDDEN") {
      const repaired = await fetch(adminUrl, {
        method: "PUT", headers,
        body: JSON.stringify({ password, logout_devices: false }),
      });
      if (repaired.ok) {
        login = await loginMatrix();
        session = await login.json().catch(() => ({}));
      } else {
        const repairError = await repaired.json().catch(() => ({}));
        console.error("Matrix account password repair failed", repaired.status, repairError.errcode || "unknown");
      }
    }
    if (!login.ok || !session.access_token) {
      console.error("Matrix login failed", login.status, session.errcode || "unknown");
      return reply(502, { message: "Güvenli mesajlaşma oturumu açılamadı." }, origin);
    }
    return reply(200, {
      base_url: homeserver,
      user_id: session.user_id,
      device_id: session.device_id,
      access_token: session.access_token,
    }, origin);
  } catch {
    return reply(502, { message: "Mesajlaşma sunucusuna ulaşılamadı." }, origin);
  }
});
