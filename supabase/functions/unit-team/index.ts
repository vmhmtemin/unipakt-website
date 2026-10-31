// UniPakt Panel — birimler (Halkla İlişkiler, Sosyal Medya, …).
// Merkez Yönetim (profiles.role = 'admin') her birimi yönetir. Birim hesabı (role = 'unit')
// kendi biriminde, yetkisine göre ekip kurar (team) ve rol açar (roles); başkanın her yetkisi var.
// Birimden çıkarılan kişi silinmez: pasife alınır, hesabının girişi kapatılır; geri alınabilir.
//
//   { action: "emails", unit_id }                                   -> { emails: { <id>: e-posta } }
//   { action: "invite", unit_id, email, full_name, role_id, permissions }
//   { action: "update", id, role_id, permissions }
//   { action: "set_head", unit_id, id, old_role_id }                 -> başkan değişimi (eski başkan old_role_id rolüne geçer)
//   { action: "deactivate", id } / { action: "reactivate", id } / { action: "resend", id }
//   { action: "change_email", id, email }                            -> yalnız Merkez Yönetim
//   { action: "role_save", unit_id, id?, name, permissions } / { action: "role_delete", id }
//   { action: "unit_save", id?, name } / { action: "unit_delete", id }  -> yalnız Merkez Yönetim
//
// Davet bağlantısı şifre belirleme bağlantısıdır; kişi şifresini belirleyip e-postası ve şifresiyle girer.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const BRAND_DB = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
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
    const { data } = await BRAND_DB.from("site_theme").select("colors, angle, on_dark, on_accent").eq("id", 1).maybeSingle();
    const hex = /^#[0-9A-Fa-f]{6}$/;
    if (data && Array.isArray(data.colors) && data.colors.length && data.colors.every((c: string) => hex.test(c)) && hex.test(data.on_dark) && hex.test(data.on_accent)) B = brandOf(data as BrandRow);
  } catch (_) { /* varsayılan kalır */ }
};

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const PANEL = "https://unipakt.com/panel.html";
const PERMS = ["team", "roles", "chat"];
const PERM_TEXT: Record<string, string> = { team: "Ekip yönetimi", roles: "Rol yönetimi", chat: "Mesajlar" };
const MAX_MEMBERS = 40;
const UUID = /^[0-9a-f-]{36}$/i;
const BAN = "876000h";   // pasif hesap: giriş kapalı (~100 yıl)

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const sessionIdOf = (jwt: string) => {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return /^[0-9a-f-]{36}$/i.test(String(payload.session_id ?? "")) ? String(payload.session_id) : "00000000-0000-0000-0000-000000000000";
  } catch { return "00000000-0000-0000-0000-000000000000"; }
};
const cleanPerms = (value: unknown) => Array.isArray(value) ? PERMS.filter((p) => value.includes(p)) : [];
const cleanName = (value: unknown, max: number) => String(value ?? "").replace(/\s+/g, " ").trim().slice(0, max);

const inviteMail = (unitName: string, inviter: string, name: string, role: string, perms: string[], link: string) => {
  const list = perms.map((p) => PERM_TEXT[p]).join(", ") || "—";
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"></head>
<body style="margin:0;padding:0;background:#0C0C0D;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0C0C0D;"><tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:540px;background:#161618;border:1px solid #2a2a2d;border-radius:22px;"><tr><td style="padding:34px 32px;font-family:Arial,Helvetica,sans-serif;color:#F2F1EE;">
  <div style="font:800 32px/1 Arial,Helvetica,sans-serif;letter-spacing:-1px;color:#F2F1EE;">UniPakt<span style="color:${B.dark};">.</span></div>
  <div style="margin-top:8px;font:700 13px/1 Arial,Helvetica,sans-serif;letter-spacing:2px;color:${B.dark};">BİRİM DAVETİ</div>
  <h1 style="margin:28px 0 10px;font:800 25px/1.25 Arial,Helvetica,sans-serif;color:#F2F1EE;">Merhaba ${esc(name)}, UniPakt ${esc(unitName)} birimine katıldın.</h1>
  <p style="margin:0;font:400 15px/1.6 Arial,Helvetica,sans-serif;color:#C9C8C4;">${esc(inviter)} seni UniPakt Panel'e <b style="color:#F2F1EE;">${esc(role)}</b> olarak ekledi.</p>
  <p style="margin:16px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Yetkilerin: ${esc(list)}</p>
  <p style="margin:26px 0 0;"><a href="${esc(link)}" style="display:inline-block;padding:15px 28px;border-radius:999px;${B.btn}font:700 16px/1 Arial,Helvetica,sans-serif;text-decoration:none;">Şifremi belirle</a></p>
  <p style="margin:22px 0 0;font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#9A9995;">Şifreni belirledikten sonra bu e-posta adresi ve şifrenle <a href="${PANEL}" style="color:${B.dark};">unipakt.com/panel.html</a> adresinden giriş yaparsın. Bağlantının süresi geçerse giriş ekranındaki “Şifremi unuttum” ile yenisini alabilirsin.</p>
</td></tr></table>
<p style="margin:18px 0 0;font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6f6e6a;">Bu daveti beklemiyorsan e-postayı yok sayabilirsin; şifre belirlemedikçe hesap kullanılamaz.</p>
</td></tr></table></body></html>`;
  const text = `Merhaba ${name},\n\n${inviter} seni UniPakt Panel'e ${unitName} biriminden ${role} olarak ekledi.\nYetkilerin: ${list}\n\nŞifreni belirle: ${link}\n\nSonra bu e-posta adresi ve şifrenle ${PANEL} adresinden giriş yaparsın.\n\nBu daveti beklemiyorsan e-postayı yok sayabilirsin.`;
  return { html, text };
};

type Member = { user_id: string; unit_id: string; role_id: string; is_head: boolean; permissions: string[]; status: string };
type Role = { id: string; unit_id: string; name: string; permissions: string[]; is_head: boolean; preset: boolean };

Deno.serve(async (req) => {
  await loadBrand();
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { message: "Yalnızca POST." });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: caller } = await db.auth.getUser(token);
  if (!caller?.user) return reply(401, { message: "Oturum geçersiz." });
  const uid = caller.user.id;
  const { data: me } = await db.from("profiles").select("role, full_name, username").eq("id", uid).maybeSingle();
  if (!me || !["admin", "unit"].includes(me.role)) return reply(403, { message: "Birimleri yalnızca Merkez Yönetim ve birim üyeleri yönetebilir." });
  const { data: mfaOk } = await db.rpc("mfa_session_ok", { p_user: uid, p_session: sessionIdOf(token) });
  if (!mfaOk) return reply(403, { message: "Önce iki adımlı doğrulamayı tamamla.", mfa_required: true });

  const isAdmin = me.role === "admin";
  let mine: Member | null = null;
  let myPerms: string[] = [];
  if (!isAdmin) {
    mine = (await db.from("unit_members").select("*").eq("user_id", uid).eq("status", "active").maybeSingle()).data as Member | null;
    if (!mine) return reply(403, { message: "Aktif bir birim üyeliğin yok." });
    const role = (await db.from("unit_roles").select("permissions").eq("id", mine.role_id).maybeSingle()).data;
    myPerms = mine.is_head ? [...PERMS] : [...new Set([...(role?.permissions ?? []), ...(mine.permissions ?? [])])];
  }
  const can = (unitId: string, perm: "team" | "roles") => isAdmin || (mine?.unit_id === unitId && myPerms.includes(perm));
  const isHeadOf = (unitId: string) => isAdmin || (mine?.unit_id === unitId && mine.is_head);
  const deny = () => reply(403, { message: "Bu işlem için yetkin yok." });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { message: "Geçersiz istek." }); }
  const action = String(body.action ?? "");
  const inviter = String(me.full_name || me.username || "").trim() || (isAdmin ? "UniPakt Merkez Yönetim" : "Birim başkanı");
  const log = (what: string, target: string) =>
    db.rpc("log_activity", { p_action: what, p_target: target, p_actor: uid }).then(() => {}, () => {});

  const unitOf = async (id: unknown) => UUID.test(String(id ?? "")) ? (await db.from("units").select("id, name").eq("id", String(id)).maybeSingle()).data : null;
  const roleOf = async (id: unknown) => UUID.test(String(id ?? "")) ? (await db.from("unit_roles").select("*").eq("id", String(id)).maybeSingle()).data as Role | null : null;
  const memberOf = async (id: unknown) => UUID.test(String(id ?? "")) ? (await db.from("unit_members").select("*").eq("user_id", String(id)).maybeSingle()).data as Member | null : null;
  const nameOf = async (id: string) => (await db.from("profiles").select("full_name").eq("id", id).maybeSingle()).data?.full_name || "";
  const headRoleOf = async (unitId: string) => (await db.from("unit_roles").select("*").eq("unit_id", unitId).eq("is_head", true).maybeSingle()).data as Role | null;
  const currentHead = async (unitId: string) => (await db.from("unit_members").select("user_id").eq("unit_id", unitId).eq("is_head", true).eq("status", "active").maybeSingle()).data;

  const sendInvite = async (email: string, name: string, unitName: string, role: string, perms: string[]) => {
    const { data: link, error } = await db.auth.admin.generateLink({ type: "recovery", email, options: { redirectTo: PANEL } });
    if (error || !link?.properties?.action_link) { console.error("link failed", error?.message); return false; }
    const { html, text } = inviteMail(unitName, inviter, name, role, perms, link.properties.action_link);
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}` },
      body: JSON.stringify({ from: FROM_EMAIL, to: [email], subject: `UniPakt ${unitName} birimine eklendin — UniPakt Panel`, html, text }),
    });
    if (!res.ok) console.error("invite mail failed", res.status);
    return res.ok;
  };
  // Başkan olmayan biri başkana dokunamaz, başkan rolü veremez, kendinde olmayan yetkiyi veremez.
  const permsAllowed = (perms: string[]) => isAdmin || mine!.is_head || perms.every((p) => myPerms.includes(p));

  // ---- Birimler (yalnız Merkez Yönetim) ----
  if (action === "unit_save") {
    if (!isAdmin) return deny();
    const name = cleanName(body.name, 60);
    if (name.length < 2) return reply(400, { message: "Birim adı en az 2 karakter olmalı." });
    if (body.id) {
      const unit = await unitOf(body.id);
      if (!unit) return reply(404, { message: "Birim bulunamadı." });
      const { error } = await db.from("units").update({ name }).eq("id", unit.id);
      if (error) return reply(400, { message: /unique|duplicate/i.test(error.message) ? "Bu adda bir birim zaten var." : "Kaydedilemedi." });
      await log("Birimin adını değiştirdi", `${unit.name} → ${name}`);
      return reply(200, { ok: true, id: unit.id });
    }
    const { data: last } = await db.from("units").select("sort").order("sort", { ascending: false }).limit(1).maybeSingle();
    const { data, error } = await db.from("units").insert({ name, sort: (last?.sort ?? 0) + 1 }).select("id").single();
    if (error) return reply(400, { message: /unique|duplicate/i.test(error.message) ? "Bu adda bir birim zaten var." : "Birim açılamadı." });
    await log("Birim açtı", name);
    return reply(200, { ok: true, id: data.id });
  }
  if (action === "unit_delete") {
    if (!isAdmin) return deny();
    const unit = await unitOf(body.id);
    if (!unit) return reply(404, { message: "Birim bulunamadı." });
    const { count } = await db.from("unit_members").select("user_id", { count: "exact", head: true }).eq("unit_id", unit.id);
    if (count) return reply(400, { message: "Bu birimde kayıtlı kişiler var (pasifler dahil). Önce onları başka birime taşı." });
    const { error } = await db.from("units").delete().eq("id", unit.id);
    if (error) return reply(500, { message: "Silinemedi." });
    await log("Birimi sildi", unit.name);
    return reply(200, { ok: true });
  }

  // ---- Roller ----
  if (action === "role_save") {
    const name = cleanName(body.name, 40);
    const perms = cleanPerms(body.permissions);
    if (name.length < 2) return reply(400, { message: "Rol adı en az 2 karakter olmalı." });
    if (body.id) {
      const role = await roleOf(body.id);
      if (!role || !can(role.unit_id, "roles")) return deny();
      if (role.is_head) return reply(400, { message: "Birim Başkanı rolünün yetkileri sabittir (hepsi)." });
      if (!permsAllowed(perms)) return reply(403, { message: "Kendinde olmayan bir yetkiyi role veremezsin." });
      const { error } = await db.from("unit_roles").update({ name, permissions: perms }).eq("id", role.id);
      if (error) return reply(400, { message: /unique|duplicate/i.test(error.message) ? "Bu adda bir rol zaten var." : "Kaydedilemedi." });
      await log("Birim rolünü düzenledi", name);
      return reply(200, { ok: true, id: role.id });
    }
    const unit = await unitOf(body.unit_id);
    if (!unit || !can(unit.id, "roles")) return deny();
    if (!permsAllowed(perms)) return reply(403, { message: "Kendinde olmayan bir yetkiyi role veremezsin." });
    const { data, error } = await db.from("unit_roles").insert({ unit_id: unit.id, name, permissions: perms, sort: 50 }).select("id").single();
    if (error) return reply(400, { message: /unique|duplicate/i.test(error.message) ? "Bu adda bir rol zaten var." : "Rol eklenemedi." });
    await log("Birime rol ekledi", `${unit.name} · ${name}`);
    return reply(200, { ok: true, id: data.id });
  }
  if (action === "role_delete") {
    const role = await roleOf(body.id);
    if (!role || !can(role.unit_id, "roles")) return deny();
    if (role.preset) return reply(400, { message: "Hazır roller silinemez; adını ya da yetkilerini değiştirebilirsin." });
    const { count } = await db.from("unit_members").select("user_id", { count: "exact", head: true }).eq("role_id", role.id);
    if (count) return reply(400, { message: "Bu rolde kişiler var. Önce onlara başka rol ver." });
    const { error } = await db.from("unit_roles").delete().eq("id", role.id);
    if (error) return reply(500, { message: "Silinemedi." });
    await log("Birim rolünü sildi", role.name);
    return reply(200, { ok: true });
  }

  // ---- E-postalar (yalnız ekibi yönetebilenler) ----
  if (action === "emails") {
    const unit = await unitOf(body.unit_id);
    if (!unit || !can(unit.id, "team")) return deny();
    const { data: rows } = await db.from("unit_members").select("user_id").eq("unit_id", unit.id);
    const emails: Record<string, string> = {};
    for (const r of rows ?? []) emails[r.user_id] = (await db.auth.admin.getUserById(r.user_id)).data?.user?.email ?? "";
    return reply(200, { emails });
  }

  // ---- Kişi ekleme ----
  if (action === "invite") {
    const unit = await unitOf(body.unit_id);
    if (!unit || !can(unit.id, "team")) return deny();
    const role = await roleOf(body.role_id);
    if (!role || role.unit_id !== unit.id) return reply(400, { message: "Bir rol seç." });
    const perms = cleanPerms(body.permissions);
    if (role.is_head && !isHeadOf(unit.id)) return reply(403, { message: "Başkanı yalnızca Merkez Yönetim ya da mevcut başkan atayabilir." });
    if (!permsAllowed([...role.permissions, ...perms]) && !role.is_head) return reply(403, { message: "Kendinde olmayan bir yetkiyi veremezsin." });
    if (role.is_head) {
      const head = await currentHead(unit.id);
      if (head) return reply(409, { message: `${unit.name} biriminin zaten bir başkanı var.`, head_exists: true, head_id: head.user_id });
    }
    const email = String(body.email ?? "").trim().toLowerCase();
    const name = cleanName(body.full_name, 120);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return reply(400, { message: "Geçerli bir e-posta yaz." });
    if (name.length < 2) return reply(400, { message: "Ad soyad en az 2 karakter olmalı." });
    const { count } = await db.from("unit_members").select("user_id", { count: "exact", head: true }).eq("unit_id", unit.id).eq("status", "active");
    if ((count ?? 0) >= MAX_MEMBERS) return reply(400, { message: `Bir birimde en fazla ${MAX_MEMBERS} aktif kişi olabilir.` });

    const { data: created, error } = await db.auth.admin.createUser({ email, email_confirm: true, user_metadata: { full_name: name } });
    if (error || !created?.user) {
      const taken = /already|registered|exists/i.test(error?.message ?? "");
      return reply(400, { message: taken ? "Bu e-posta adresiyle zaten bir UniPakt hesabı var. Bir kişi yalnızca bir birimde olabilir." : "Hesap açılamadı." });
    }
    const userId = created.user.id;
    const undo = async () => { await db.from("unit_members").delete().eq("user_id", userId); await db.auth.admin.deleteUser(userId); };
    const { error: pErr } = await db.from("profiles").insert({ id: userId, role: "unit", full_name: name, invited_by: uid });
    if (pErr) { await undo(); return reply(500, { message: "Hesap açılamadı." }); }
    const { error: mErr } = await db.from("unit_members").insert({
      user_id: userId, unit_id: unit.id, role_id: role.id, is_head: role.is_head, permissions: perms, added_by: uid,
    });
    if (mErr) { await undo(); return reply(400, { message: /one_head/.test(mErr.message) ? "Bu birimin zaten bir başkanı var." : "Hesap açılamadı." }); }
    const effective = role.is_head ? PERMS : [...new Set([...role.permissions, ...perms])];
    if (!(await sendInvite(email, name, unit.name, role.name, effective))) {
      await undo();
      return reply(502, { message: "Davet e-postası gönderilemedi. Biraz sonra tekrar dene." });
    }
    await log("Birime kişi ekledi", `${unit.name} · ${name} · ${role.name}`);
    return reply(200, { ok: true, id: userId });
  }

  // ---- Bundan sonrası mevcut bir kişi üzerinde ----
  const member = await memberOf(body.id);
  if (!member) return reply(404, { message: "Kişi bulunamadı." });
  if (!can(member.unit_id, "team")) return deny();
  if (member.is_head && !isHeadOf(member.unit_id)) return reply(403, { message: "Başkanla ilgili değişiklikleri yalnızca Merkez Yönetim ya da başkanın kendisi yapabilir." });
  const unit = (await unitOf(member.unit_id))!;
  const who = await nameOf(member.user_id);

  if (action === "update") {
    const role = await roleOf(body.role_id);
    if (!role || role.unit_id !== member.unit_id) return reply(400, { message: "Bir rol seç." });
    if (role.is_head && !member.is_head) return reply(400, { message: "Başkan atamak için “Başkanı değiştir” ekranını kullan." });
    if (member.is_head && !role.is_head) return reply(400, { message: "Başkanın rolünü değiştirmek için “Başkanı değiştir” ekranını kullan." });
    const perms = cleanPerms(body.permissions);
    if (!permsAllowed([...role.permissions, ...perms])) return reply(403, { message: "Kendinde olmayan bir yetkiyi veremezsin." });
    const { error } = await db.from("unit_members").update({ role_id: role.id, permissions: perms }).eq("user_id", member.user_id);
    if (error) return reply(500, { message: "Kaydedilemedi." });
    await log("Birim üyesinin rolünü değiştirdi", `${unit.name} · ${who} · ${role.name}`);
    return reply(200, { ok: true });
  }

  if (action === "set_head") {
    if (!isHeadOf(member.unit_id)) return reply(403, { message: "Başkanı yalnızca Merkez Yönetim ya da mevcut başkan değiştirebilir." });
    if (member.status !== "active") return reply(400, { message: "Pasif bir kişi başkan yapılamaz. Önce aktif et." });
    if (member.is_head) return reply(400, { message: "Bu kişi zaten başkan." });
    const headRole = await headRoleOf(member.unit_id);
    if (!headRole) return reply(500, { message: "Birimin başkan rolü bulunamadı." });
    const head = await currentHead(member.unit_id);
    if (head) {
      const oldRole = await roleOf(body.old_role_id);
      if (!oldRole || oldRole.unit_id !== member.unit_id || oldRole.is_head) return reply(400, { message: "Eski başkanın yeni rolünü seç." });
      const { error } = await db.from("unit_members").update({ is_head: false, role_id: oldRole.id }).eq("user_id", head.user_id);
      if (error) return reply(500, { message: "Başkan değiştirilemedi." });
    }
    const { error } = await db.from("unit_members").update({ is_head: true, role_id: headRole.id }).eq("user_id", member.user_id);
    if (error) return reply(500, { message: "Başkan değiştirilemedi." });
    await log("Birim başkanını değiştirdi", `${unit.name} · ${who}`);
    return reply(200, { ok: true });
  }

  if (action === "deactivate") {
    if (member.user_id === uid) return reply(400, { message: "Kendini pasife alamazsın." });
    if (member.status === "passive") return reply(200, { ok: true });
    let patch: Record<string, unknown> = { status: "passive", passive_at: new Date().toISOString(), is_head: false };
    if (member.is_head) {
      const plain = (await db.from("unit_roles").select("id").eq("unit_id", member.unit_id).eq("preset", true).eq("is_head", false).order("sort", { ascending: false }).limit(1).maybeSingle()).data;
      if (plain) patch = { ...patch, role_id: plain.id };
    }
    const { error } = await db.from("unit_members").update(patch).eq("user_id", member.user_id);
    if (error) return reply(500, { message: "Pasife alınamadı." });
    await db.auth.admin.updateUserById(member.user_id, { ban_duration: BAN });
    await log("Birim üyesini pasife aldı", `${unit.name} · ${who}`);
    return reply(200, { ok: true });
  }

  if (action === "reactivate") {
    if (member.status === "active") return reply(200, { ok: true });
    const { error } = await db.from("unit_members").update({ status: "active", passive_at: null }).eq("user_id", member.user_id);
    if (error) return reply(500, { message: "Aktif edilemedi." });
    await db.auth.admin.updateUserById(member.user_id, { ban_duration: "none" });
    await log("Birim üyesini yeniden aktif etti", `${unit.name} · ${who}`);
    return reply(200, { ok: true });
  }

  if (action === "resend") {
    if (member.status !== "active") return reply(400, { message: "Pasif kişiye davet gönderilemez." });
    const email = (await db.auth.admin.getUserById(member.user_id)).data?.user?.email;
    if (!email) return reply(404, { message: "Kişi bulunamadı." });
    const role = await roleOf(member.role_id);
    const effective = member.is_head ? PERMS : [...new Set([...(role?.permissions ?? []), ...member.permissions])];
    if (!(await sendInvite(email, who, unit.name, role?.name || "Üye", effective))) return reply(502, { message: "Davet e-postası gönderilemedi." });
    return reply(200, { ok: true });
  }

  if (action === "change_email") {
    if (!isAdmin) return reply(403, { message: "Başkasının e-postasını yalnızca Merkez Yönetim değiştirebilir. Kişi kendi e-postasını Hesap sayfasından değiştirir." });
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return reply(400, { message: "Geçerli bir e-posta yaz." });
    const { error } = await db.auth.admin.updateUserById(member.user_id, { email, email_confirm: true });
    if (error) return reply(400, { message: /already|registered|exists/i.test(error.message) ? "Bu e-posta başka bir hesapta kayıtlı." : "E-posta değiştirilemedi." });
    await log("Birim üyesinin e-postasını değiştirdi", `${unit.name} · ${who}`);
    return reply(200, { ok: true });
  }

  return reply(400, { message: "Bilinmeyen işlem." });
});
