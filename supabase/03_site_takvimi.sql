-- ============================================================
-- UniPakt — sitedeki herkese açık takvim (02'den SONRA çalıştırın)
-- unipakt.com'daki Takvim sayfası yayındaki etkinlikleri buradan okur.
-- Ziyaretçi yalnızca bu fonksiyonun döndürdüğü alanları görür:
-- etkinlik adı, açıklaması, tarihi, saati, yeri ve düzenleyen kulübün adı.
-- "Aranan ortak" notu, ret notları, bekleyen ya da reddedilen etkinlikler
-- ve ortaklık başvuruları dışarı açılmaz.
-- Tekrar çalıştırmak güvenlidir.
-- ============================================================

create or replace function public.public_events()
returns table (id uuid, title text, description text, event_date date, event_time time, place text, organizer text)
language sql stable security definer set search_path = '' as $$
  select e.id, e.title, e.description, e.event_date, e.event_time, e.place, coalesce(c.name, 'UniPakt')
    from public.events e
    left join public.clubs c on c.id = e.club_id
   where e.status = 'published'
   order by e.event_date, e.event_time nulls first
$$;

revoke execute on function public.public_events() from public;
grant execute on function public.public_events() to anon, authenticated;
