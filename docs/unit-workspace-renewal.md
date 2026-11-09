# Birim çalışma alanları — teslim ve uygulama notu

Temel sürüm: `669cde2` (PR #38 bu sürümde zaten birleştirilmişti).
Çalışma dalı: `feature/unit-workspace-renewal`.
Bu paket kaynak kod değişikliğidir; GitHub'a gönderilmedi ve canlı veritabanına uygulanmadı.
Merkez ve Kulüp panelleri korunur. Mevcut hesaplar, görevler, adaylar, kulüpler ve onay kayıtları topluca silinmez.

## Mimari ve erişim

Uygulama statik HTML/JavaScript, Supabase Auth, PostgreSQL RPC ve Storage kullanır.
Mevcut `unit_workspace()` okuma kapısı ve MFA kontrollü `uw(action, data)` işlem kapısı korunur.
Birim sayfaları `panel.html` içindedir; dosya ekleri `unit-files.js` üzerinden yüklenir.

- Merkez: bütün birim kayıtlarını okur ve yönetir; bütçe kararlarını verir.
- Başkan: kendi birimini yönetir, ekibe görev atar, kayıt arşivler ve kendi ekibine duyuru yayımlar.
- Üye: mevcut operasyon izinleriyle yazar; görevlerde atama ve tarih değiştirme ayrıca sınırlıdır.
- Denetim izni olmayan Denetim üyesi, yeni denetim iş akışlarında yalnız kendisine atanan kayıtları görür.
- Birime yöneltilen bulgu veya talep yalnız hedef birime açılır. Hedef birim yanıt verir; denetim kararını değiştiremez.
- YK, aktif birim başkanlarıdır. Eski `board` üyeliği karar yetkisi sağlamaz.
- Materyal/yayın kararlarını inceleyen başkanlar ilgili içerik ve geçmişi okuyabilir; başka birimin içeriğini düzenleyemez.
- Mesajlar gönderen/alıcı kapsamıyla, belgeler ilgili birimle, dosyalar bağlı kaydın erişimiyle sınırlandırılır.
- Yeni tabloların doğrudan istemci erişimi kapalıdır. Özel yardımcı RPC'ler authenticated/anon rollerine açılmaz.

## Gereksinimlerin uygulamadaki karşılığı

| Alan | Uygulama |
| --- | --- |
| Sol menü | UniPakt → Etkinlik İşlemleri → Birim İşleri; birimlere göre açılır gruplar ve Ortak Birim İşleri. |
| Birim Sayfaları | Merkez için sayfa/üye/izin görünümü. Yetki yönetimi mevcut Birim Yönetimi'nde korunur. |
| Görevler | Öncelik, ilerleme, sorumlu, son tarih, ek, yorum, tamamlama ve inceleme, yeniden atama, arşiv ve değişiklik geçmişi. |
| Merkez'e Bildirim | Kayıtlı kişi/kulüp araması, başkanlar/birim alıcı grupları, etkinlik ilişkisi, ek, durum ve yanıt. Kulüp veya kişisel alıcı mevcut panel bildiriminde teslim alır. |
| Bildirimler | Okundu/gizleme, görev/karar/yanıt ve son tarih uyarıları. Yeni görev ve iş akışı bildirimlerinde kayıt kimliği üzerinden açma. |
| Duyurular | Merkez'in seçili birimlere, başkanın kendi birimine yayını; gönderen, ek, tarih ve hesap bazlı okundu bilgisi. |
| Belgeler | Birime özel erişim, dosya/bağlantı ekleme ve güncelleme; etkinlik/görev/kampanya/birim kaydı ilişkisi. |
| Destek | Başvuru, yanıt, kapatma/yeniden açma ve ek bağlantısı; mevcut talebe özel dosya yükleme. |
| İşlem Kaydı | Kullanıcı ve zamanla işlem logları; görev, yerel içerik/kampanya/firma/kulüp ve yeni kayıtların sürüm geçmişi. |
| Sosyal Medya | Mevcut talep kutusu ve kulüp duyurusu kabul akışı; platform metinleri, hashtag, CTA, alt metin, tasarım, sorumlu ve zaman; metin önizlemesi, revizyon, YK onayı, planlama, yayın bağlantısı/gerçek tarih, arşiv ve manuel performans. |
| Sosyal Medya kaynakları | Şablon kayıtları, materyal onayı, marka kiti ve ortak belgeler. |
| PR | Kampanya temel kaydı + hedef kitle/sorumlu/tarih/ilişki/bütçe alanları; talep kutusu, eksik bilgi/ret, kampanya veya göreve dönüştürme; sürümlü materyaller, YK kararı ve Sosyal Medya'ya iletme. |
| PR bütçe | Tutar, para birimi, gerekçe, kampanya/etkinlik ilişkisi, Merkez kararı ve karar geçmişi. |
| Sponsorluk | Firma listesi ve temas geçmişi; şehir/telefon/takip/dosya; arşiv, aynı isim uyarısı, görüşme/takip kayıtları, teklif/anlaşma, ayni destek, koşullar, başlangıç/bitiş ve yenileme bilgisi. |
| Sponsorluk paketleri | Etkinlik ilişkisi, kapsam, toplam/kalan kontenjan kontrolü, firmaya bağlı teklifler ve destek/bütçe kararları. |
| Kulüp İlişkileri | Aktif/aday kayıtları, üniversite/şehir/iletişim/sorumlu/takip; Meet zamanı/katılımcı/bağlantı/amaç/hazırlık/sonuç; 45 günlük temassızlık uyarısı. |
| Aday kabulü | Aynı UUID ile kulübe geçiş veya aynı ad+üniversitedeki mevcut kulübe bağlama; aday ve görüşme geçmişi korunur. Tekrarlanan kabul kopya oluşturmaz. |
| Kulüp talepleri | Başvuru kararları ve hedef birime yönlendirme; hedef birimin yanıtı aynı geçmişte kalır. |
| Kulüp etkinlikleri | İş birlikleri ve taslak/planlanan/yayımlanan özel duyurular; bir veya birden fazla hedef kulübe panel bildirimi. |
| Denetim | Merkez etkinlikleri dahil tüm etkinlikler; mevcut atama/kontrol akışı; birim/etkinlik planı, kontrol listesi, bulgu, önem/kanıt/sorumlu/son tarih, düzeltici görev, birim yanıtı ve rapor. |
| Genel bakış | Mevcut birim sayaçları ve açık/geciken/yaklaşan/atanmamış/onay/bilgi bekleyen kayıt sayıları. |
| Takvim | Gün/hafta/ay/yıl aralığında sıralı gündem; birim/durum/platform/sorumlu filtreleri ve aynı saat uyarısı. Eski etkinlik ay görünümü de korunur. |
| Raporlar | Tarih ve birime göre durum/tutar/performans; kategori, şehir, üniversite, önem ve birim dağılımları. |
| Uzun listeler | Yeni iş akışı ve yerel kayıt listelerinde sunucuda 20'li sayfalama, arama ve filtre. Görevlerde arayüz sayfalaması; eski ortak okuma yapısı korunur. |

## Migration sırası

Bu SQL dosyaları kod PR'ına veya GitHub reponun migration klasörüne dahil edilmeyecektir.
Veritabanı güncellemesi ayrı teslim edilen SQL dosyalarıyla yapılır. Mevcut depodaki önceki
migration'lar kurulmuş olmalıdır. Dosya sırası:

1. `20261107_unit_workspace_foundation.sql`
2. `20261108_unit_workflows.sql`
3. `20261109_unit_record_details.sql`
4. `20261110_unit_private_files.sql`
5. `20261111_unit_shared_integrity.sql`
6. `20261112_unit_routing_and_documents.sql`

SQL'leri önce staging üzerinde, belirtilen sırada uygulayın ve gerçek Merkez, başkan, üye ve
kulüp hesaplarıyla deneyin. Kod PR'ı SQL dosyalarını içermez; migration uygulaması tamamlandıktan
sonra panel ve üç JavaScript modülünü birlikte yayımlayın.
`schema.sql` ilk kurulum tabanıdır; tek başına bu migration'ların yerine geçmez.
Üretime gönderim mevcut projenin onaylı dağıtım sürecinden yapılmalıdır.

Yeni tablolar iş akışları, sürümler, ayrıntı alanları, dönüşüm eşlemeleri ve bildirim tekilleştirmesini tutar.
Storage'da `unit-files` özel kovası açılır: en fazla 10 MB; PDF, JPEG/PNG/WebP, TXT, DOCX/XLSX/PPTX.
Dosya bağlantısı kalıcı kayıt yolunu taşır; erişimde 5 dakikalık imzalı URL üretilir.
Dosya yüklemek için önce üst kayıt oluşturulur, ardından Düzenle formundan yüklenir ve kaydedilir.

Aday kabulü otomatik giriş hesabı oluşturmaz ve kulübü kamuya açık siteye otomatik yayımlamaz
(`visible=false`). Hesap açma ve kamuya görünürlük mevcut Merkez işlemleriyle yönetilir.

## Doğrulama

- `pnpm test`: gerçek birim migration'larını PGlite PostgreSQL'e uygular; rol/MFA, görev,
  mesaj gizliliği, kişi bazlı bildirim RLS, aday kabulü, geçmiş, dönüşüm, bütçe,
  denetim yanıtı, arşiv, belge kapsamı, dosya erişimi, sayfalama ve tekrar uygulamayı sınar.
- `CHROMIUM_PATH=/tmp/unipakt-chromium pnpm test:browser`: Chromium'da gerçek panelin demo
  akışı; görev/yorum/başkan tamamlama/Merkez onayı, yetkisiz görünüm, mesaj/yanıt kalıcılığı,
  stüdyo alanları, aday kabulü, takvim/rapor, doğrudan birim rotası ve mobil taşma.
- `pnpm run build:matrix` ve `pnpm run build:qr`.
- `tools/build_pages.py`: testte uzak tema/etkinlik sorguları yerel varsayılanlarla değiştirilir;
  statik yayın paketinde panel ve üç modülün bulunması, bağımlılıkların dışarıda kalması kontrol edilir.
- `git diff --check`; yeni JavaScript modülleri için `node --check`.

## Repo ve doğrulama sınırları

- Canlı Supabase Auth/MFA sağlayıcısı, e-posta Edge Function'ları ve gerçek Storage upload/sign
  istekleri bu ortamda uçtan uca denenmedi. PostgreSQL erişim kuralları test edildi;
  üretime geçiş öncesinde staging kontrolü gerekir.
- PGlite testleri platform/auth/storage temel tabloları için fixture kullanır; bütün üretim
  şemasının kopyası değildir. Mevcut üretim migration durumu ayrıca doğrulanmalıdır.
- Instagram/LinkedIn vb. yayınlama veya istatistik API'si eklenmedi. Yayın işaretleme,
  canlı bağlantı ve performans girişleri manuel işler; prompttaki manuel veri seçeneği kullanılır.
- Meet bağlantısı kaydedilir; Google hesabında otomatik toplantı oluşturulmaz.
- Yaklaşan tarih uyarıları panel verisi yenilenirken oluşturulur; kapalı panel için cron,
  tarayıcı push veya e-posta zamanlayıcısı kurulmaz.
- Aynı isimli kayıtlar uyarılır ve arşivlenebilir; otomatik veri birleştirme/silme yapılmaz.
  Aday kabulündeki tam ad+üniversite eşleşmesi ayrı ve kimliği koruyan bir işlemdir.
- Paketlerin kalan kontenjanı manuel yönetilir; değer aralığı doğrulanır, otomatik rezervasyon yoktur.
- Takvim/rapor sorguları en fazla bir yıllık aralık ve kaynak başına 1000 kayıtla sınırlıdır;
  yoğun aralıkta kullanıcıya daraltma uyarısı gösterilir. Süre özeti son güncelleme üzerinden
  hesaplanır; eski kayıtlarda geriye dönük durum tarihçesi türetilmez.
- Eski görev/ortak veri okuyucuları tek yanıtta çalışır. Yeni liste sayfalaması, bütün eski
  backend'i baştan yazmak anlamına gelmez.
- Yazılım/Dijital ile Proje Geliştirme için ayrı iş akışı tanımı promptta yoktur;
  mevcut ekip yönetimi ve ortak işlevler korunur.
- PR #38'in başlangıçta birleştirilmiş olması geri alınmadı; başka PR kapatılmadı veya birleştirilmedi.

## Mehmet için dosya uygulama

Teslim ZIP'inde `files/` altında yalnız değişen dosyalar, `changes.patch` içinde temel sürüme
karşı tam fark ve `manifest.json` içinde SHA-256 değerleri bulunur. İki uygulama yönteminden
birini seçin: yama uygulama **veya** dosyaları aynı yollarına kopyalama.

```bash
git switch -c feature/unit-workspace-renewal
git apply --check /paket/changes.patch
git apply /paket/changes.patch
pnpm install --frozen-lockfile
pnpm test
pnpm run build:matrix
pnpm run build:qr
pnpm exec playwright install chromium
pnpm test:browser
```

Yama kontrolü başarısızsa güncel dal temel sürümden farklıdır; dosyaları körlemesine
üzerine yazmadan farkları birleştirin. Kontrollerden sonra kendi hesabınızla commit/push yapın.
Kodun GitHub'a gönderilmesi migration'ları kendiliğinden canlıya uygulamaz.
