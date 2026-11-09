# Supabase SQL Editor — çalıştırma sırası

Bu paket mevcut UniPakt veritabanını günceller; sıfırdan veritabanı kurulum paketi değildir.
Depodaki 20261101–20261106 birim migration'larının ve önceki platform şemasının
kurulmuş olması gerekir. Önce staging ortamında ve mevcut veritabanı yedeğiyle kontrol et.

Dosyaları ayrı ayrı, aşağıdaki sırayla SQL Editor'da çalıştır. Her dosya başarıyla
bittikten sonra sonrakine geç. Hata olursa sonraki dosyaya geçme.

1. `20261107_unit_workspace_foundation.sql`
2. `20261108_unit_workflows.sql`
3. `20261109_unit_record_details.sql`
4. `20261110_unit_private_files.sql`
5. `20261111_unit_shared_integrity.sql`
6. `20261112_unit_routing_and_documents.sql`

Her dosyanın kendi transaction bloğu vardır. Dosya içeriğini baştan sona çalıştır.
Daha önce uygulanmış dosyaların durumunu kontrol et; paketin sırası değiştirilmemelidir.

20261110 dosyası özel `unit-files` Storage kovasını ve erişim politikalarını kurar.
SQL'ler tamamlandıktan sonra yeni paneli ve üç JavaScript modülünü birlikte yayımla.
Gerçek Merkez, başkan, üye ve kulüp hesaplarıyla giriş/izin, bildirim ve dosya yükleme
kontrolü yap. Canlı Auth/Storage uçtan uca testi bu ortamda yapılmadı.

Bu SQL dosyalarını ayrıca GitHub reponun `supabase/migrations/` klasöründe sakla.
