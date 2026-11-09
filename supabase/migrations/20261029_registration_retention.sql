-- KVKK saklama süresi: etkinlik kayıtları etkinlik bittikten 6 ay sonra silinir;
-- süresi dolmuş görevli yetkileri (bağlantı + erişim kodu özeti) 30 gün sonra silinir.
-- Her gece 03:40'ta çalışır (mevcut unipakt-retention işinden ayrı).
select cron.schedule('unipakt-registration-retention', '40 3 * * *', $cron$
  delete from public.event_registrations r
   where public.event_ends_at(r.event_id) < now() - interval '6 months';
  delete from public.event_staff_grants
   where expires_at < now() - interval '30 days';
$cron$);
