// UniPakt — sitede yayınlanan bir kulübe iki e-posta gönderir:
//   1) KVKK onay talebi
//   2) UniPakt WhatsApp topluluğuna katılma daveti (KVKK e-postası gittikten sonra)
// Yalnızca veritabanı tetikleyicisi clubs_kvkk_notice_webhook() çağırır; Vault'taki
// `notification_function_key` anahtarını `apikey` başlığında yollar.
//
// Güvenlik ve tekrar koruması:
//  - Anahtarsız istek 401 alır (anahtar veritabanında, verify_notification_key ile doğrulanır).
//  - İstek gövdesinden yalnızca kulüp id'si alınır; ad ve e-posta veritabanından okunur.
//  - kvkk_notice_sent_at önce atomik olarak doldurulur, sonra e-posta gönderilir. Böylece
//    aynı kulübe iki kez gitmez. Gönderim başarısız olursa damga geri alınır.
//  - Her e-posta tek alıcılıdır; kulüpler birbirinin adresini görmez.
//  - Yanıtta e-posta adresi yer almaz.
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;

const FROM_EMAIL = "UniPakt <bildirim@unipakt.com>";
const REPLY_TO = "iletisim@unipakt.com";
const SUBJECT = "KVKK Gereğince — İletişim Bilgileriniz ve Logonuzun Yayınlanması İçin Onayınız";
const INVITE_SUBJECT = "UniPakt Topluluğuna Katılın";
const COMMUNITY_URL = "https://chat.whatsapp.com/ItC2KuzVE6XI8jixFdm9QB";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const esc = (v: unknown) =>
  String(v ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");

// Metin ve tasarım, 12 Ekim 2026'da kulüplere elle gönderilen onaylı e-postayla aynıdır.
function buildHtml(club: string): string {
  const c = esc(club);
  const P = 'style="margin:0 0 24px;"';
  const A = 'style="color:#fff;text-decoration:underline;font-weight:700;"';
  return `<!doctype html>
<html lang="tr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#000;font-family:Arial,Helvetica,sans-serif;color:#fff;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#000;"><tr><td align="center" style="padding:52px 20px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:1180px;background:#090909;border:1px solid #303030;border-radius:38px;overflow:hidden;">
<tr><td style="padding:62px 58px 56px;border-bottom:1px solid #303030;">
<div style="font-size:42px;line-height:1;font-weight:800;letter-spacing:-2px;">UniPakt.</div>
<div style="margin-top:26px;font-size:25px;line-height:1.25;color:#8e8e8e;font-weight:500;">KVKK Onayı</div>
</td></tr>
<tr><td style="padding:70px 58px 62px;">
<div style="font-size:48px;line-height:1.08;font-weight:800;letter-spacing:-1.5px;margin-bottom:34px;">Yayın Onayınızı Bekliyoruz</div>
<div style="font-size:25px;line-height:1.65;color:#d0d0d0;max-width:930px;">
<p ${P}>Merhaba ${c},</p>
<p ${P}>UniPakt ağında yer aldığınız için teşekkür ederiz.</p>
<p ${P}>KVKK gereğince, kulübünüze ait aşağıdaki bilgileri yayınlayabilmek için onayınıza ihtiyacımız var:</p>
<ul style="margin:0 0 24px;padding-left:34px;">
<li style="margin-bottom:10px;"><strong style="color:#fff;">Sosyal medya hesaplarımızda:</strong> kulübünüzün logosu ve iletişim bilgileri</li>
<li><strong style="color:#fff;">Web sitemizde (unipakt.com):</strong> kulübünüzün iletişim bilgileri (e-posta adresi ve sosyal medya hesapları)</li>
</ul>
<p ${P}>Onay vermek için lütfen <strong style="color:#fff;">kulübünüzün resmi e-posta adresinden</strong> <a href="mailto:iletisim@unipakt.com" ${A}>iletisim@unipakt.com</a> adresine yeni bir e-posta gönderin. Bu e-posta otomatik bildirim adresimizden gönderildiği için yanıtlamayın. Örnek metin:</p>
<div style="margin:0 0 24px;padding:24px 28px;border-left:3px solid #8e8e8e;background:#111;color:#fff;font-style:italic;">“${c} olarak, kulübümüzün logosunun ve iletişim bilgilerinin UniPakt'ın sosyal medya hesaplarında, iletişim bilgilerimizin ise unipakt.com web sitesinde yayınlanmasını onaylıyoruz.”</div>
<p ${P}>Onayınızı dilediğiniz zaman aynı adrese yazarak geri çekebilirsiniz. Bu durumda ilgili bilgileri yayından ve 3. şahıs ortakların veritabanlarından kaldırırız.</p>
<p ${P}>Kulüp verileri Supabase tarafından Frankfurt/Almanya'daki sunucularda, Resend tarafından ise AWS altyapısıyla korunan ABD, İrlanda, Brezilya ve Japonya'daki sunucularda saklanmaktadır.</p>
<p ${P}>Sorularınız için <a href="mailto:iletisim@unipakt.com" ${A}>iletisim@unipakt.com</a> adresinden bize ulaşabilirsiniz.</p>
<p style="margin:0;">Sevgiler,<br>UniPakt Ekibi</p>
</div>
</td></tr>
<tr><td style="padding:34px 58px 42px;border-top:1px solid #303030;">
<div style="font-size:18px;line-height:1.6;color:#666;">Bu e-posta UniPakt bildirim sisteminden otomatik olarak gönderilmiştir. Yanıtlamayın veya başkasıyla paylaşmayın.</div>
</td></tr>
</table></td></tr></table>
</body></html>`;
}

function buildText(club: string): string {
  return `Merhaba ${club},

UniPakt ağında yer aldığınız için teşekkür ederiz.

KVKK gereğince, kulübünüze ait aşağıdaki bilgileri yayınlayabilmek için onayınıza ihtiyacımız var:

- Sosyal medya hesaplarımızda: kulübünüzün logosu ve iletişim bilgileri
- Web sitemizde (unipakt.com): kulübünüzün iletişim bilgileri (e-posta adresi ve sosyal medya hesapları)

Onay vermek için lütfen kulübünüzün resmi e-posta adresinden iletisim@unipakt.com adresine yeni bir e-posta gönderin. Bu e-posta otomatik bildirim adresimizden gönderildiği için yanıtlamayın. Örnek metin:

"${club} olarak, kulübümüzün logosunun ve iletişim bilgilerinin UniPakt'ın sosyal medya hesaplarında, iletişim bilgilerimizin ise unipakt.com web sitesinde yayınlanmasını onaylıyoruz."

Onayınızı dilediğiniz zaman aynı adrese yazarak geri çekebilirsiniz. Bu durumda ilgili bilgileri yayından ve 3. şahıs ortakların veritabanlarından kaldırırız.

Kulüp verileri Supabase tarafından Frankfurt/Almanya'daki sunucularda, Resend tarafından ise AWS altyapısıyla korunan ABD, İrlanda, Brezilya ve Japonya'daki sunucularda saklanmaktadır.

Sorularınız için iletisim@unipakt.com adresinden bize ulaşabilirsiniz.

Sevgiler,
UniPakt Ekibi`;
}

// Topluluk daveti. Metin, 19 Ekim 2026'da Mehmet'in onayladığı önizlemeyle aynıdır.
function buildInviteHtml(club: string): string {
  const c = esc(club);
  return `<!doctype html>
<html lang="tr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#000;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
<div style="max-width:620px;margin:40px auto;padding:0 20px;">
<div style="border:1px solid #292929;border-radius:20px;overflow:hidden;background:#090909;">
<div style="padding:28px 30px;border-bottom:1px solid #292929;">
<div style="font-size:22px;font-weight:700;letter-spacing:-0.5px;">UniPakt<span style="color:#777;">.</span></div>
<div style="margin-top:7px;color:#888;font-size:13px;">Topluluk Daveti</div>
</div>
<div style="padding:32px 30px;">
<h1 style="margin:0 0 18px;font-size:25px;line-height:1.25;color:#fff;">UniPakt Topluluğuna Katılın</h1>
<div style="color:#cfcfcf;font-size:16px;line-height:1.7;">
<p style="margin:0 0 14px;">Merhaba <strong style="color:#fff;">${c}</strong> ekibi,</p>
<p style="margin:0 0 14px;">UniPakt ağındaki kulüpler arasındaki iletişimi daha hızlı ve kolay hale getirmek için bir WhatsApp topluluğu açtık. Ortak etkinlik fırsatları, duyurular ve kulüpler arası iş birlikleri artık burada da paylaşılacak.</p>
<p style="margin:0 0 14px;">Kulübünüzden en az bir yetkilinin topluluğa katılmasını rica ediyoruz.</p>
</div>
<div style="margin:24px 0 18px;"><a href="${COMMUNITY_URL}" style="display:inline-block;background:#fff;color:#000;text-decoration:none;font-weight:600;padding:13px 20px;border-radius:10px;">Topluluğa Katıl</a></div>
<p style="margin:0 0 18px;color:#8a8a8a;font-size:13px;line-height:1.6;word-break:break-all;">Buton çalışmazsa: <a href="${COMMUNITY_URL}" style="color:#bdbdbd;">${COMMUNITY_URL}</a></p>
<p style="margin:0;color:#cfcfcf;font-size:16px;line-height:1.7;">Görüşmek üzere,<br>UniPakt Ekibi</p>
</div>
<div style="padding:20px 30px;border-top:1px solid #292929;color:#666;font-size:12px;line-height:1.6;">Bu e-posta UniPakt bildirim sisteminden gönderilmiştir · unipakt.com</div>
</div>
</div>
</body></html>`;
}

function buildInviteText(club: string): string {
  return `Merhaba ${club} ekibi,

UniPakt ağındaki kulüpler arasındaki iletişimi daha hızlı ve kolay hale getirmek için bir WhatsApp topluluğu açtık. Ortak etkinlik fırsatları, duyurular ve kulüpler arası iş birlikleri artık burada da paylaşılacak.

Kulübünüzden en az bir yetkilinin topluluğa katılmasını rica ediyoruz:
${COMMUNITY_URL}

Görüşmek üzere,
UniPakt Ekibi
unipakt.com`;
}

async function sendEmail(to: string, subject: string, html: string, text: string): Promise<boolean> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${RESEND_API_KEY}` },
    body: JSON.stringify({ from: FROM_EMAIL, to: [to], reply_to: REPLY_TO, subject, html, text }),
  });
  if (!res.ok) console.error(`Resend error (${subject}):`, await res.json().catch(() => ({})));
  return res.ok;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST gerekli." });

  // 1) Bu anahtarı yalnızca veritabanı tetikleyicisi bilir.
  const { data: keyOk, error: keyError } = await supabase.rpc("verify_notification_key", {
    p_key: req.headers.get("apikey") ?? "",
  });
  if (keyError) {
    console.error("Key check failed:", keyError.message);
    return json(500, { error: "Doğrulama yapılamadı." });
  }
  if (keyOk !== true) return json(401, { error: "Yetkisiz." });

  const payload = await req.json().catch(() => null);
  const clubId = String(payload?.club_id ?? "");
  if (!UUID_RE.test(clubId)) return json(400, { error: "Geçersiz kulüp." });

  // 2) Damgayı atomik olarak al: yalnızca henüz gönderilmemiş, görünür ve e-postası olan kulüp.
  const { data: club, error: claimError } = await supabase
    .from("clubs")
    .update({ kvkk_notice_sent_at: new Date().toISOString() })
    .eq("id", clubId)
    .eq("visible", true)
    .is("kvkk_notice_sent_at", null)
    .not("email", "is", null)
    .neq("email", "")
    .select("id,name,email")
    .maybeSingle();
  if (claimError) {
    console.error("Claim failed:", claimError.message);
    return json(500, { error: "Kulüp okunamadı." });
  }
  if (!club) return json(200, { success: true, skipped: true });

  // 3) Tek alıcılı e-postalar: önce KVKK onay talebi, sonra topluluk daveti.
  const kvkkSent = await sendEmail(club.email, SUBJECT, buildHtml(club.name), buildText(club.name));
  if (!kvkkSent) {
    // Gönderilemedi: damgayı geri al ki sonraki düzenlemede yeniden denensin.
    await supabase.from("clubs").update({ kvkk_notice_sent_at: null }).eq("id", club.id);
    return json(502, { error: "E-posta gönderilemedi." });
  }

  // Davet başarısız olsa da KVKK damgası kalır; KVKK e-postası tekrar gönderilmez.
  const inviteSent = await sendEmail(club.email, INVITE_SUBJECT, buildInviteHtml(club.name), buildInviteText(club.name));
  return json(200, { success: true, sent: inviteSent ? 2 : 1 });
});
