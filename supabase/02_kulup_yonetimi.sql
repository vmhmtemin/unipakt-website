-- ============================================================
-- UniPakt Panel — kulüp yönetimi (schema.sql'den SONRA çalıştırın)
-- Kulüplere kategori ve iletişim bilgisi ekler, kulüp listesini
-- unipakt.com'un okuyabilmesi için herkese açar.
-- Tekrar çalıştırmak güvenlidir.
-- ============================================================

alter table public.clubs
  add column if not exists category  text check (char_length(category)  <= 40),
  add column if not exists email     text check (char_length(email)     <= 200),
  add column if not exists instagram text check (char_length(instagram) <= 200),
  add column if not exists linkedin  text check (char_length(linkedin)  <= 200),
  add column if not exists x         text check (char_length(x)         <= 200),
  add column if not exists tiktok    text check (char_length(tiktok)    <= 200),
  add column if not exists web       text check (char_length(web)       <= 200);

-- Kulüp listesi zaten sitede herkese açık bilgi: giriş yapmayan ziyaretçi de okuyabilir.
-- Yazma hakkı yine yalnızca UniPakt yetkilisinde (clubs_admin_write).
grant select on public.clubs to anon;
drop policy if exists clubs_public_select on public.clubs;
create policy clubs_public_select on public.clubs for select to anon using (true);

-- Sitede şu an görünen bilgiler
update public.clubs
   set category = 'Yazılım', email = 'iletisim@unipakt.com', instagram = 'unipakt',
       linkedin = 'https://www.linkedin.com/company/unipakt/', x = 'UniPakt', tiktok = 'unipakt'
 where name = 'GDG on Campus' and category is null;
