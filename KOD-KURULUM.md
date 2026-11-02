# Kod paketi kurulumu

Bu paketteki kaynak dosyaları mevcut reponun köküne, aynı klasör yollarını koruyarak aktarın.
Önce hedef dalı ve mevcut değişiklikleri karşılaştırın; yalnızca bu paketteki kaynak dosyalarını
PR kapsamına alın.

SQL migration dosyaları bu GitHub kod tesliminin parçası değildir ve repoya eklenmemelidir.
Altı SQL dosyası ayrı teslim edilmiştir; uygulama sırası `SQL-CALISTIRMA-SIRASI.md` içinde
yazılıdır. SQL dosyalarını canlı veritabanında çalıştırmak bu kod PR'ından ayrı bir işlemdir.
Önce staging üzerinde ve gerçek Merkez, başkan, üye ve kulüp hesaplarıyla doğrulayın.

Depodaki kurulum akışına göre `pnpm install --frozen-lockfile`, `pnpm test`,
`pnpm run build:matrix` ve `pnpm run build:qr` komutlarıyla doğrulayın.
Kapsam ve ortam sınırları: `docs/unit-workspace-renewal.md`.
