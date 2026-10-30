// UniPakt Panel — kulüp ekibi. Kulüp başkanı (profiles.role = 'club') panele ek hesap
// davet eder; davet edilen kişi (role = 'member') yalnızca başkanın seçtiği yetkileri
// kullanır (profiles.permissions, sunucuda has_perm() ile zorlanır).
//
//   { action: "list" }  -> { members: [{ id, email, full_name, title, permissions, joined, invited_at }] }
//   { action: "invite", email, full_name, title, permissions }  -> hesabı açar, davet e-postası gönderir
//   { action: "update", id, title, permissions }
//   { action: "resend", id }  -> yeni davet bağlantısı
//   { action: "remove", id }  -> hesabı siler
//
// Davet bağlantısı bir şifre belirleme bağlantısıdır (panel.html#…type=recovery):
// kişi şifresini belirler, sonra kendi e-postası ve şifresiyle giriş yapar.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const PANEL = "https://unipakt.com/panel.html";
const PERMS = ["events", "registrations", "announcements", "tasks", "support", "chat"];
const PERM_TEXT: Record<string, string> = {
  events: "Etkinlikler", registrations: "Kayıtlar ve giriş", announcements: "Duyurular",
  tasks: "Görevler", support: "Destek", chat: "Mesajlar",
};
const MAX_MEMBERS = 15;

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const sessionIdOf = (jwt: string) => {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return /^[0-9a-f-]{36}$/i.test(String(payload.session_id ?? "")) ? String(payload.session_id) : "00000000-0000-0000-0000-000000000000";
  } catch { return "00000000-0000-0000-0000-000000000000"; }
};
const cleanPerms = (value: unknown) => Array.isArray(value) ? PERMS.filter((p) => value.includes(p)) : null;
const cleanTitle = (value: unknown) => String(value ?? "").replace(/\s+/g, " ").trim().slice(0, 60);

const inviteMail = (clubName: string, inviter: string, name: string, title: string, perms: string[], link: string) => {
  const list = perms.map((p) => PERM_TEXT[p]).join(", ") || "—";
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"></head>
<body style="margin:0;padding:0;background:#0C0C0D;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0C0C0D;"><tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:540px;background:#161618;border:1px solid #2a2a2d;border-radius:22px;"><tr><td style="padding:34px 32px;font-family:Arial,Helvetica,sans-serif;color:#F2F1EE;">
  <div style="font:800 32px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:#19C7B5;">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:#19C7B5;">PANEL DAVETİ</div>
  <h1 style="margin:28px 0 10px;font:800 25px/1.25 Arial,Helvetica,sans-serif;color:#F2F1EE;">Merhaba ${esc(name)}, ${esc(clubName)} ekibine davet edildin.</h1>
  <p style="margin:0;font:400 15px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">${esc(inviter)} seni UniPakt Panel'e <b style="color:#F2F1EE;">${esc(title)}</b> olarak ekledi.</p>
  <p style="margin:16px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Yetkilerin: ${esc(list)}</p>
  <p style="margin:26px 0 0;"><a href="${esc(link)}" style="display:inline-block;padding:15px 28px;border-radius:999px;background:#19C7B5;color:#0C0C0D;font:700 16px/1 Arial,Helvetica,sans-serif;text-decoration:none;">Şifremi belirle</a></p>
  <p style="margin:22px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Şifreni belirledikten sonra bu e-posta adresi ve şifrenle <a href="${PANEL}" style="color:#19C7B5;">unipakt.com/panel.html</a> adresinden giriş yaparsın. Bağlantının süresi geçerse giriş ekranındaki “Şifremi unuttum” ile yenisini alabilirsin.</p>
</td></tr></table>
<p style="margin:18px 0 0;font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6f6e6a;">Bu daveti beklemiyorsan e-postayı yok sayabilirsin; şifre belirlemedikçe hesap kullanılamaz.</p>
</td></tr></table></body></html>`;
  const text = `Merhaba ${name},\n\n${inviter} seni UniPakt Panel'e ${clubName} ekibinden ${title} olarak ekledi.\nYetkilerin: ${list}\n\nŞifreni belirle: ${link}\n\nSonra bu e-posta adresi ve şifrenle ${PANEL} adresinden giriş yaparsın. Bağlantının süresi geçerse giriş ekranındaki “Şifremi unuttum” ile yenisini alabilirsin.\n\nBu daveti beklemiyorsan e-postayı yok sayabilirsin.`;
  return { html, text };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: caller } = await admin.auth.getUser(token);
  if (!caller?.user) return reply(401, { message: "Oturum geçersiz." });
  const { data: me } = await admin.from("profiles").select("role, club_id, full_name").eq("id", caller.user.id).maybeSingle();
  if (me?.role !== "club" || !me.club_id) return reply(403, { message: "Ekibi yalnızca kulüp başkanı yönetebilir." });
  const { data: mfaOk } = await admin.rpc("mfa_session_ok", { p_user: caller.user.id, p_session: sessionIdOf(token) });
  if (!mfaOk) return reply(403, { message: "Önce iki adımlı doğrulamayı tamamla.", mfa_required: true });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }); }
  const action = String(body.action ?? "");
  const clubId = me.club_id as string;

  const sendInvite = async (userId: string, email: string, name: string, title: string, perms: string[]) => {
    const { data: link, error } = await admin.auth.admin.generateLink({ type: "recovery", email, options: { redirectTo: PANEL } });
    if (error || !link?.properties?.action_link) { console.error("link failed", error?.message); return false; }
    const clubName = (await admin.from("clubs").select("name").eq("id", clubId).maybeSingle()).data?.name || "Kulüp";
    const inviter = String(me.full_name || "").trim() || `${clubName} başkanı`;
    const { html, text } = inviteMail(clubName, inviter, name, title, perms, link.properties.action_link);
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}` },
      body: JSON.stringify({ from: FROM_EMAIL, to: [email], subject: `${clubName} ekibine davet edildin — UniPakt Panel`, html, text }),
    });
    if (!res.ok) console.error("invite mail failed", res.status, userId);
    return res.ok;
  };
  // İşlem kaydı (başkanın Ekip sayfasındaki değişiklikler).
  const log = (action: string, target: string) =>
    admin.rpc("log_activity", { p_action: action, p_target: target, p_actor: caller.user.id }).then(() => {}, () => {});
  const memberOf = async (id: unknown) => {
    if (!/^[0-9a-f-]{36}$/i.test(String(id ?? ""))) return null;
    const { data } = await admin.from("profiles").select("id, full_name, member_title, permissions")
      .eq("id", String(id)).eq("club_id", clubId).eq("role", "member").maybeSingle();
    return data;
  };

  if (action === "list") {
    const { data: rows, error } = await admin.from("profiles").select("id, full_name, member_title, permissions, created_at")
      .eq("club_id", clubId).eq("role", "member").order("created_at");
    if (error) return reply(500, { message: "Ekip okunamadı." });
    const members = [];
    for (const row of rows ?? []) {
      const { data } = await admin.auth.admin.getUserById(row.id);
      members.push({
        id: row.id, email: data?.user?.email ?? "", full_name: row.full_name ?? "", title: row.member_title ?? "",
        permissions: row.permissions ?? [], joined: Boolean(data?.user?.last_sign_in_at), invited_at: row.created_at,
      });
    }
    return reply(200, { members });
  }

  if (action === "invite") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const name = String(body.full_name ?? "").replace(/\s+/g, " ").trim();
    const title = cleanTitle(body.title);
    const perms = cleanPerms(body.permissions);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return reply(400, { message: "Geçerli bir e-posta yaz." });
    if (name.length < 2 || name.length > 120) return reply(400, { message: "Ad soyad 2–120 karakter olmalı." });
    if (!title) return reply(400, { message: "Bir rol seç ya da yaz." });
    if (!perms || !perms.length) return reply(400, { message: "En az bir yetki seç." });
    const { count } = await admin.from("profiles").select("id", { count: "exact", head: true }).eq("club_id", clubId).eq("role", "member");
    if ((count ?? 0) >= MAX_MEMBERS) return reply(400, { message: `Bir kulüp en fazla ${MAX_MEMBERS} ekip hesabı açabilir.` });

    const { data: created, error } = await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: { full_name: name } });
    if (error || !created?.user) {
      const taken = /already|registered|exists/i.test(error?.message ?? "");
      return reply(400, { message: taken ? "Bu e-posta adresiyle zaten bir UniPakt hesabı var." : "Hesap açılamadı." });
    }
    const userId = created.user.id;
    const { error: profileError } = await admin.from("profiles").insert({
      id: userId, role: "member", club_id: clubId, full_name: name, member_title: title, permissions: perms, invited_by: caller.user.id,
    });
    if (profileError) { await admin.auth.admin.deleteUser(userId); return reply(500, { message: "Hesap açılamadı." }); }
    if (!(await sendInvite(userId, email, name, title, perms))) {
      await admin.auth.admin.deleteUser(userId);   // davet gitmediyse yarım hesap kalmasın
      return reply(502, { message: "Davet e-postası gönderilemedi. Biraz sonra tekrar dene." });
    }
    await log("Ekip üyesi davet etti", `${name} · ${title}`);
    return reply(200, { ok: true, id: userId });
  }

  if (action === "update") {
    const member = await memberOf(body.id);
    if (!member) return reply(404, { message: "Ekip üyesi bulunamadı." });
    const title = cleanTitle(body.title);
    const perms = cleanPerms(body.permissions);
    if (!title) return reply(400, { message: "Bir rol seç ya da yaz." });
    if (!perms || !perms.length) return reply(400, { message: "En az bir yetki seç." });
    const { error } = await admin.from("profiles").update({ member_title: title, permissions: perms }).eq("id", member.id);
    if (error) return reply(500, { message: "Kaydedilemedi." });
    await log("Ekip üyesinin yetkilerini değiştirdi", `${member.full_name || ""} · ${title}`);
    return reply(200, { ok: true });
  }

  if (action === "resend") {
    const member = await memberOf(body.id);
    if (!member) return reply(404, { message: "Ekip üyesi bulunamadı." });
    const { data } = await admin.auth.admin.getUserById(member.id);
    const email = data?.user?.email;
    if (!email) return reply(404, { message: "Ekip üyesi bulunamadı." });
    if (!(await sendInvite(member.id, email, member.full_name || "", member.member_title || "Ekip üyesi", member.permissions || [])))
      return reply(502, { message: "Davet e-postası gönderilemedi." });
    return reply(200, { ok: true });
  }

  if (action === "remove") {
    const member = await memberOf(body.id);
    if (!member) return reply(404, { message: "Ekip üyesi bulunamadı." });
    const { error } = await admin.auth.admin.deleteUser(member.id);   // profil satırı da birlikte silinir
    if (error) return reply(500, { message: "Hesap silinemedi." });
    await log("Ekip üyesini kaldırdı", `${member.full_name || ""} · ${member.member_title || ""}`);
    return reply(200, { ok: true });
  }

  return reply(400, { message: "Bilinmeyen işlem." });
});
