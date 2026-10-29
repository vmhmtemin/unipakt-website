// UniPakt Panel — kulüp başkanı hesaplarını yöneten Edge Function.
// Yalnızca UniPakt yetkilisi (profiles.role = 'admin') çağırabilir.
// Hesap açmak servis anahtarı gerektirir; o anahtar tarayıcıya verilemediği
// için bu iş burada, sunucuda yapılır.
//
//   { action: "list" }                                  -> { accounts: [{ club_id, email }] }
//   { action: "set", club_id, email, password? }        -> hesabı açar ya da günceller
//   { action: "remove", club_id }                       -> kulübün hesabını siler
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// The JWT's session_id; a 2FA account's session must have been verified (see the `mfa` function).
const sessionIdOf = (jwt: string) => {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return /^[0-9a-f-]{36}$/i.test(String(payload.session_id ?? "")) ? String(payload.session_id) : "00000000-0000-0000-0000-000000000000";
  } catch { return "00000000-0000-0000-0000-000000000000"; }
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Çağıran kim? Oturum anahtarını doğrula, sonra rolüne bak.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: caller } = await admin.auth.getUser(token);
  if (!caller?.user) return reply(401, { message: "Oturum geçersiz." });
  const { data: me } = await admin.from("profiles").select("role").eq("id", caller.user.id).maybeSingle();
  if (me?.role !== "admin") return reply(403, { message: "Bu işlem yalnızca UniPakt yetkilisine açık." });
  const { data: mfaOk } = await admin.rpc("mfa_session_ok", { p_user: caller.user.id, p_session: sessionIdOf(token) });
  if (!mfaOk) return reply(403, { message: "Önce iki adımlı doğrulamayı tamamla.", mfa_required: true });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }); }
  const action = String(body.action ?? "");

  if (action === "list") {
    const { data: rows, error } = await admin.from("profiles").select("id, club_id").eq("role", "club");
    if (error) return reply(500, { message: error.message });
    const accounts = [];
    for (const row of rows ?? []) {
      const { data } = await admin.auth.admin.getUserById(row.id);
      accounts.push({ club_id: row.club_id, email: data?.user?.email ?? "" });
    }
    return reply(200, { accounts });
  }

  const clubId = String(body.club_id ?? "");
  const { data: club } = await admin.from("clubs").select("id").eq("id", clubId).maybeSingle();
  if (!club) return reply(404, { message: "Kulüp bulunamadı." });
  const { data: existing } = await admin.from("profiles").select("id").eq("club_id", clubId).eq("role", "club");

  if (action === "remove") {
    for (const row of existing ?? []) {
      const { error } = await admin.auth.admin.deleteUser(row.id);   // profil satırı da birlikte silinir
      if (error) return reply(500, { message: error.message });
    }
    return reply(200, { ok: true });
  }

  if (action === "set") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply(400, { message: "Geçerli bir e-posta gir." });
    if (password && password.length < 8) return reply(400, { message: "Şifre en az 8 karakter olmalı." });

    if (existing && existing.length) {
      const changes: Record<string, unknown> = { email, email_confirm: true };
      if (password) changes.password = password;
      const { error } = await admin.auth.admin.updateUserById(existing[0].id, changes);
      if (error) return reply(400, { message: error.message });
      return reply(200, { ok: true, email });
    }

    if (!password) return reply(400, { message: "Yeni hesap için şifre gerekli." });
    const { data: created, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (error || !created?.user) return reply(400, { message: error?.message ?? "Hesap açılamadı." });
    const { error: profileError } = await admin.from("profiles").insert({ id: created.user.id, role: "club", club_id: clubId });
    if (profileError) {
      await admin.auth.admin.deleteUser(created.user.id);   // yarım kalmasın
      return reply(500, { message: profileError.message });
    }
    return reply(200, { ok: true, email });
  }

  return reply(400, { message: "Bilinmeyen işlem." });
});
