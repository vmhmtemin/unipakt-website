-- ============================================================
-- UniPakt — denetim (audit) düzeltmeleri, 13 Ekim 2026
--
-- Bu dosya tek seferde şunları yapar (bölüm numaraları aşağıdaki başlıklarla aynı):
--   1. clubs.kvkk_consent_at: kulübün iletişim bilgilerinin sitede
--      gösterilmesine KVKK onayı verdiği an. E-posta değişince sıfırlanır.
--   2. public_clubs(): sitenin kulüp listesi artık bu fonksiyondan okunur.
--      İletişim bilgileri yalnızca onayı olan kulüpte döner. Ziyaretçi (anon)
--      clubs tablosunu artık doğrudan okuyamaz.
--   3. Site formları: KVKK onayı zorunlu (sürüm + zaman damgası saklanır),
--      daha sıkı e-posta kontrolü, genel sınır 10 dakikada 60, yöneticiye
--      30 dakikada en fazla bir bildirim.
--   4. Destek talepleri: kullanıcı silinince talep/mesaj kalır (yazar NULL),
--      kulüpler tablolara doğrudan yazamaz (yalnızca v2 fonksiyonları),
--      ek dosya yolu kulübün klasöründe olmalı, eski fonksiyonlar kaldırıldı,
--      durum (status) anlamları düzeltildi.
--   5. event-posters: kulüp afiş yükleyebilir ama var olan dosyayı
--      değiştiremez/silemez (yalnızca yetkili).
--   6. notifications: giriş yapmış kullanıcı yalnızca read_at sütununu günceller.
--   7. announcements/events: kulüp kaydında created_by başkası olamaz.
--   8. send_notification_email_webhook: Vault anahtarı yoksa bildirim kaydı
--      yine oluşur (uyarı yazılır, hata verilmez).
--   9. Gereksiz tablo yetkileri (truncate, trigger, references) kaldırıldı.
--  10. events / event_edit_requests için uzunluk sınırları.
--  11. Yinelenen indeks ve politika temizliği.
--  12. (EN SONDA, isteğe bağlı) pg_cron ile KVKK saklama süresi temizliği.
--
-- SIRA ÖNEMLİ: Bu dosya site formlarının ve kulüp listesinin çağırdığı
-- fonksiyonları değiştirir. Dosyayı çalıştırdıktan hemen sonra yeni
-- index.html / panel.html yayına alınmalıdır (eski site formları ve eski
-- kulüp listesi bu dosyadan sonra çalışmaz).
--
-- Supabase SQL Editor dosyayı tek işlem (transaction) olarak çalıştırır:
-- bir hata olursa hiçbir değişiklik uygulanmaz. Tek istisna 12. bölüm
-- (pg_cron): orada hata olursa yalnızca uyarı yazılır, geri kalan her şey
-- uygulanmış olur.
--
-- Tekrar çalıştırmak güvenlidir.
-- ============================================================


-- ------------------------------------------------------------
-- 1. clubs.kvkk_consent_at
-- ------------------------------------------------------------
-- Yetkili bu alanı panelden normal PATCH ile doldurur (clubs_admin_write
-- politikası yetkiliye tüm sütunlarda yazma izni verir).
-- Kulübün e-postası değişince hem bilgilendirme damgası (kvkk_notice_sent_at)
-- hem de onay (kvkk_consent_at) NULL olur: onay yeni adresten alınmalı.
-- NOT: E-postayı değiştiren aynı kayıtta onay da gönderilirse tetikleyici onayı
-- yine siler; onay, e-posta değişikliği kaydedildikten SONRA ayrıca işaretlenir.

alter table public.clubs add column if not exists kvkk_consent_at timestamptz;

create or replace function public.clubs_kvkk_notice_reset() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.email is distinct from old.email then
    new.kvkk_notice_sent_at := null;
    new.kvkk_consent_at     := null;
  end if;
  return new;
end;
$$;
revoke execute on function public.clubs_kvkk_notice_reset() from public, anon, authenticated;

-- Tetikleyici 20261012'de kuruldu (before update of email); aynı tanımla
-- yeniden kuruluyor.
drop trigger if exists clubs_kvkk_notice_reset on public.clubs;
create trigger clubs_kvkk_notice_reset
  before update of email on public.clubs
  for each row execute function public.clubs_kvkk_notice_reset();


-- ------------------------------------------------------------
-- 2. public_clubs() ve clubs tablosunda anon erişiminin kapatılması
-- ------------------------------------------------------------
-- Sitedeki kulüp listesi. Gizli kulüpler (visible = false) dönmez (eski
-- clubs_public_select politikasıyla aynı kural). İletişim sütunları
-- (email, instagram, linkedin, x, tiktok, web) yalnızca kvkk_consent_at
-- dolu ise döner, değilse NULL.

create or replace function public.public_clubs()
returns table(
  id uuid, name text, university text, category text, created_at timestamptz,
  email text, instagram text, linkedin text, x text, tiktok text, web text
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, c.university, c.category, c.created_at,
         case when c.kvkk_consent_at is not null then c.email     end,
         case when c.kvkk_consent_at is not null then c.instagram end,
         case when c.kvkk_consent_at is not null then c.linkedin  end,
         case when c.kvkk_consent_at is not null then c.x         end,
         case when c.kvkk_consent_at is not null then c.tiktok    end,
         case when c.kvkk_consent_at is not null then c.web       end
    from public.clubs c
   where c.visible is not false
   order by c.created_at;
$$;
revoke all on function public.public_clubs() from public;
grant execute on function public.public_clubs() to anon, authenticated;

-- Ziyaretçi tabloyu artık doğrudan okuyamaz. Giriş yapmış kullanıcıların
-- erişimi değişmez: clubs_select (profili olan herkes tüm kulüpleri okur,
-- ortak seçimi vb. için) ve clubs_admin_write (yetkili yazar) aynen kalır.
drop policy if exists clubs_public_select on public.clubs;
revoke all on public.clubs from anon;


-- ------------------------------------------------------------
-- 3. Site formları (İletişim, Bize Katıl)
-- ------------------------------------------------------------

alter table public.contact_messages
  add column if not exists kvkk_version text check (char_length(kvkk_version) <= 40),
  add column if not exists kvkk_ack_at  timestamptz;
alter table public.join_applications
  add column if not exists kvkk_version text check (char_length(kvkk_version) <= 40),
  add column if not exists kvkk_ack_at  timestamptz;

-- Eski imzaları kaldır: aynı adla iki fonksiyon kalırsa PostgREST hangisini
-- çağıracağını seçemez.
drop function if exists public.submit_contact_message(text, text, text, text);
drop function if exists public.submit_join_application(text, text, text, text, text, text, text, text);

-- İletişim formu
create or replace function public.submit_contact_message(
  p_name text, p_email text, p_message text default '', p_honey text default '',
  p_kvkk_version text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_name  text := public.site_form_clean(p_name, 120);
  v_email text := lower(public.site_form_clean(p_email, 200));
  v_msg   text := public.site_form_clean(p_message, 4000);
  v_kvkk  text := public.site_form_clean(p_kvkk_version, 40);
begin
  -- Bot tuzağı doluysa sessizce "başarılı" dön, hiçbir şey kaydetme.
  if coalesce(p_honey, '') <> '' then return; end if;

  if v_kvkk = '' then raise exception 'KVKK Aydınlatma Metni''ni okuduğunu işaretle.'; end if;
  if v_name = '' then raise exception 'Adını yaz.'; end if;
  if v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Geçerli bir e-posta gir.';
  end if;

  -- Taşma koruması: aynı adresten saatte en fazla 3, toplamda 10 dakikada en fazla 60 mesaj.
  if (select count(1) from public.contact_messages
       where email = v_email and created_at > now() - interval '1 hour') >= 3
     or (select count(1) from public.contact_messages
          where created_at > now() - interval '10 minutes') >= 60 then
    raise exception 'Çok fazla mesaj gönderildi. Biraz sonra tekrar dene.';
  end if;

  insert into public.contact_messages (name, email, message, kvkk_version, kvkk_ack_at)
  values (v_name, v_email, v_msg, v_kvkk, now());

  -- Son 30 dakikada aynı türde bildirim düştüyse yenisini gönderme (e-posta yağmuru olmasın).
  if not exists (select 1 from public.notifications
                  where recipient_role = 'admin' and type = 'site_contact_message'
                    and created_at > now() - interval '30 minutes') then
    perform public.push_admin_notification(
      'Yeni iletişim mesajı',
      'Sitedeki iletişim formundan yeni bir mesaj geldi. Panelde "Site Mesajları" bölümünden okuyabilirsin.',
      'site_contact_message'
    );
  end if;
end;
$$;

-- Bize Katıl formu
create or replace function public.submit_join_application(
  p_name text, p_email text,
  p_university text default '', p_city text default '', p_outside_university text default '',
  p_club text default '', p_message text default '', p_honey text default '',
  p_kvkk_version text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_name  text := public.site_form_clean(p_name, 120);
  v_email text := lower(public.site_form_clean(p_email, 200));
  v_kvkk  text := public.site_form_clean(p_kvkk_version, 40);
begin
  if coalesce(p_honey, '') <> '' then return; end if;

  if v_kvkk = '' then raise exception 'KVKK Aydınlatma Metni''ni okuduğunu işaretle.'; end if;
  if v_name = '' then raise exception 'Adını yaz.'; end if;
  if v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Geçerli bir e-posta gir.';
  end if;

  if (select count(1) from public.join_applications
       where email = v_email and created_at > now() - interval '1 hour') >= 3
     or (select count(1) from public.join_applications
          where created_at > now() - interval '10 minutes') >= 60 then
    raise exception 'Çok fazla başvuru gönderildi. Biraz sonra tekrar dene.';
  end if;

  insert into public.join_applications
    (name, email, university, city, outside_university, club, message, kvkk_version, kvkk_ack_at)
  values (
    v_name, v_email,
    public.site_form_clean(p_university, 200),
    public.site_form_clean(p_city, 80),
    public.site_form_clean(p_outside_university, 200),
    public.site_form_clean(p_club, 200),
    public.site_form_clean(p_message, 4000),
    v_kvkk, now()
  );

  if not exists (select 1 from public.notifications
                  where recipient_role = 'admin' and type = 'site_join_application'
                    and created_at > now() - interval '30 minutes') then
    perform public.push_admin_notification(
      'Yeni Bize Katıl başvurusu',
      'Sitedeki Bize Katıl formundan yeni bir başvuru geldi. Panelde "Site Mesajları" bölümünden okuyabilirsin.',
      'site_join_application'
    );
  end if;
end;
$$;

revoke all on function public.submit_contact_message(text, text, text, text, text) from public;
revoke all on function public.submit_join_application(text, text, text, text, text, text, text, text, text) from public;
grant execute on function public.submit_contact_message(text, text, text, text, text) to anon, authenticated;
grant execute on function public.submit_join_application(text, text, text, text, text, text, text, text, text) to anon, authenticated;


-- ------------------------------------------------------------
-- 4. Destek talepleri
-- ------------------------------------------------------------

-- 4a. Kulüp hesabı (auth kullanıcısı) silinince talep ve mesajlar kalsın,
--     yazar alanı NULL olsun. (Eskiden ON DELETE RESTRICT, hesap silinemiyordu.)
alter table public.support_tickets alter column created_by drop not null;
alter table public.support_tickets drop constraint if exists support_tickets_created_by_fkey;
alter table public.support_tickets
  add constraint support_tickets_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.support_ticket_messages alter column author_id drop not null;
alter table public.support_ticket_messages drop constraint if exists support_ticket_messages_author_id_fkey;
alter table public.support_ticket_messages
  add constraint support_ticket_messages_author_id_fkey
  foreign key (author_id) references auth.users(id) on delete set null;

-- 4b. Kulüpler tablolara doğrudan yazamaz; panel yalnızca
--     support_create_ticket_v2 / support_reply_ticket_v2 kullanır.
--     Yetkili: support_tickets_admin_all ve support_ticket_messages_admin_all
--     aynen kalır (panel talebin durumunu/kategorisini PATCH ile değiştirir,
--     talebi DELETE ile siler; yanıtı support_reply_ticket_v2 ile yazar).
drop policy if exists support_tickets_club_insert on public.support_tickets;
drop policy if exists support_ticket_messages_club_insert on public.support_ticket_messages;

-- 4c. Eski fonksiyonlar (panel bunları yalnızca v2 bulunamazsa yedek olarak
--     çağırıyordu; admin_update/admin_delete hiç çağrılmıyor). Eski create_support_ticket ayrıca
--     yöneticiye ikinci bir bildirim gönderiyordu; yeni talep bildirimi artık
--     yalnızca notify_new_support_ticket tetikleyicisinden gelir.
drop function if exists public.create_support_ticket(text, text, text);
drop function if exists public.create_support_ticket(text, text, text, text, uuid, text, text);
drop function if exists public.reply_support_ticket(uuid, text);
drop function if exists public.admin_update_support_ticket(uuid, text, text, text);
drop function if exists public.admin_delete_support_ticket(uuid);

-- 4d. Talep oluşturma: ek dosya yolu kulübün kendi klasöründe olmalı
--     (support-attachments/<club_id>/...).
create or replace function public.support_create_ticket_v2(
  p_subject text, p_category text, p_body text,
  p_category_label text default null, p_event_id uuid default null,
  p_attachment_path text default null, p_attachment_name text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id   uuid;
  v_club uuid;
  v_path text := nullif(btrim(coalesce(p_attachment_path, '')), '');
begin
  v_club := public.my_club_id();
  if v_club is null or public.is_unipakt_admin() then
    raise exception 'Only club accounts can create support tickets';
  end if;

  if p_category not in ('technical','community','event') then
    raise exception 'Invalid support category';
  end if;
  if char_length(btrim(coalesce(p_subject,''))) = 0 then
    raise exception 'Subject is required';
  end if;
  if char_length(btrim(coalesce(p_body,''))) = 0 then
    raise exception 'Message is required';
  end if;

  if v_path is not null and split_part(v_path, '/', 1) <> v_club::text then
    raise exception 'Dosya yolu bu kulübe ait değil.';
  end if;

  if p_event_id is not null and not exists (
    select 1 from public.events e
    where e.id = p_event_id and e.club_id = v_club
  ) then
    raise exception 'Selected event does not belong to this club';
  end if;

  insert into public.support_tickets(
    club_id, created_by, subject, category, category_label, event_id,
    attachment_path, attachment_name, status, preview
  )
  values(
    v_club,
    auth.uid(),
    btrim(p_subject),
    p_category,
    coalesce(nullif(btrim(p_category_label), ''),
      case p_category
        when 'event' then 'Etkinlik Desteği'
        when 'community' then 'Topluluk ve Güvenlik'
        else 'Teknik Destek'
      end
    ),
    p_event_id,
    v_path,
    case when v_path is null then null else p_attachment_name end,
    'open',
    left(btrim(p_body), 300)
  )
  returning id into v_id;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values(v_id, auth.uid(), 'club', 'Kulüp', btrim(p_body));

  -- Yöneticiye bildirim: notify_new_support_ticket tetikleyicisi (burada ayrıca gönderilmez).
  return v_id;
end;
$$;

-- 4e. Yanıt yazma ve DURUM ANLAMLARI (panel buna göre yazılır):
--   - Kulüp yanıt yazınca status = 'open' (UniPakt'tan yanıt bekleniyor).
--   - Kulüp, status = 'closed' olmayan her talebe yanıt yazabilir
--     ('resolved' bir talebe yazınca talep yeniden 'open' olur).
--   - Yetkili yanıt yazınca status = 'answered' (eskisi gibi); yetkili her
--     durumdaki talebe yazabilir.
--   - 'reviewing', 'waiting_user', 'resolved', 'closed' yalnızca yetkilinin
--     panelden elle seçtiği durumlardır.
create or replace function public.support_reply_ticket_v2(p_ticket_id uuid, p_body text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_club    uuid;
  v_creator uuid;
  v_status  text;
  v_role    text;
begin
  if char_length(btrim(coalesce(p_body,''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  select t.club_id, t.created_by, t.status into v_club, v_creator, v_status
    from public.support_tickets t
   where t.id = p_ticket_id
   for update;

  if not found then
    raise exception 'Support ticket not found';
  end if;

  if public.is_unipakt_admin() then
    v_role := 'admin';
  elsif v_club = public.my_club_id() or v_creator = auth.uid() then
    v_role := 'club';
  else
    raise exception 'Not allowed';
  end if;

  if v_role = 'club' and v_status = 'closed' then
    raise exception 'Bu destek talebi kapatıldı; yeni bir talep oluştur.';
  end if;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values (
    p_ticket_id,
    auth.uid(),
    v_role,
    case when v_role = 'admin' then 'UniPakt Destek' else 'Kulüp' end,
    btrim(p_body)
  );

  update public.support_tickets
     set status = case when v_role = 'admin' then 'answered' else 'open' end,
         preview = left(btrim(p_body), 300),
         updated_at = now()
   where id = p_ticket_id;
end;
$$;

revoke all on function public.support_create_ticket_v2(text, text, text, text, uuid, text, text) from public, anon;
revoke all on function public.support_reply_ticket_v2(uuid, text) from public, anon;
grant execute on function public.support_create_ticket_v2(text, text, text, text, uuid, text, text) to authenticated;
grant execute on function public.support_reply_ticket_v2(uuid, text) to authenticated;


-- ------------------------------------------------------------
-- 5. event-posters deposu (storage)
-- ------------------------------------------------------------
-- Eskiden iki kopya politika takımı vardı (event_posters_insert/update/delete
-- ve event_posters_authenticated_insert/update/delete) ve kulüp kendi klasöründeki her dosyayı,
-- onaylanmış etkinliğin afişi dahil, değiştirip silebiliyordu.
-- Yeni kural:
--   - INSERT: kulüp yalnızca kendi klasörüne (<club_id>/...), yetkili her yere.
--   - UPDATE / DELETE: yalnızca yetkili.
--   - Okuma: bucket herkese açık (public), /object/public/ adresleri politika
--     gerektirmez; değişmedi.
-- Panel her yüklemede benzersiz dosya adı kullanmalı ve x-upsert göndermemeli
-- (upsert = UPDATE, kulüpte artık izin yok). Aynı adla ikinci yükleme reddedilir.
drop policy if exists event_posters_authenticated_delete on storage.objects;
drop policy if exists event_posters_authenticated_insert on storage.objects;
drop policy if exists event_posters_authenticated_update on storage.objects;
drop policy if exists event_posters_delete on storage.objects;
drop policy if exists event_posters_insert on storage.objects;
drop policy if exists event_posters_update on storage.objects;

create policy event_posters_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'event-posters'
              and ((select public.is_admin())
                   or split_part(name, '/', 1) = (select public.my_club())::text));
create policy event_posters_update on storage.objects for update to authenticated
  using (bucket_id = 'event-posters' and (select public.is_admin()))
  with check (bucket_id = 'event-posters' and (select public.is_admin()));
create policy event_posters_delete on storage.objects for delete to authenticated
  using (bucket_id = 'event-posters' and (select public.is_admin()));

-- support-attachments: silme politikası hiç yoktu, bu yüzden talep silinince
-- ek dosyası depoda kalıyordu. Panel talebi silerken eki de siler (yalnızca yetkili).
-- (task-proofs için task_proofs_admin_delete zaten var.)
drop policy if exists support_attachments_admin_delete on storage.objects;
create policy support_attachments_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'support-attachments' and (select public.is_unipakt_admin()));


-- ------------------------------------------------------------
-- 6. notifications: yalnızca read_at güncellenebilir
-- ------------------------------------------------------------
-- Panel yalnızca "okundu" işaretler (PATCH read_at). Diğer sütunları
-- (actionable, resolved, ...) SECURITY DEFINER fonksiyonlar değiştirir.
-- notifications_read politikası (yalnızca kendi bildirimi / yetkili) aynen kalır.
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;


-- ------------------------------------------------------------
-- 7. created_by sahteciliği
-- ------------------------------------------------------------
-- Her iki tabloda created_by varsayılanı auth.uid(); panel bu alanı göndermez,
-- bu yüzden mevcut akış bozulmaz. Kulüp başka bir kullanıcıyı yazamaz.
drop policy if exists announcements_club_insert on public.announcements;
create policy announcements_club_insert on public.announcements for insert to authenticated
  with check (club_id = (select public.my_club())
              and status = 'pending' and note is null and decided_at is null
              and created_by = (select auth.uid()));

drop policy if exists events_club_insert on public.events;
create policy events_club_insert on public.events for insert to authenticated
  with check ((select public.is_admin())
              or (club_id = (select public.my_club())
                  and status = 'pending' and note is null and decided_at is null
                  and calendar = 'none' and visible = true
                  and created_by = (select auth.uid())));


-- ------------------------------------------------------------
-- 8. send_notification_email_webhook: anahtar yoksa hata verme
-- ------------------------------------------------------------
-- Eskiden Vault anahtarı yoksa exception atıyordu ve bildirimi oluşturan
-- işlem (ör. ortaklık başvurusu) tamamen geri alınıyordu. Artık bildirim
-- kaydı oluşur, yalnızca e-posta gitmez ve uyarı yazılır.
create or replace function public.send_notification_email_webhook() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_key text;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'notification_function_key'
   limit 1;

  if v_key is null then
    raise warning 'notification_function_key Vault secret bulunamadı; bildirim e-postası gönderilmedi.';
    return new;
  end if;

  perform net.http_post(
    url     := 'https://hcgotmcbwmleeklbvawb.supabase.co/functions/v1/send-email-notifications',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_key),
    body    := jsonb_build_object(
      'type', 'INSERT',
      'table', 'notifications',
      'schema', 'public',
      'record', to_jsonb(new),
      'old_record', null
    )
  );
  return new;
end;
$$;
revoke execute on function public.send_notification_email_webhook() from public, anon, authenticated;


-- ------------------------------------------------------------
-- 9. Gereksiz tablo ve fonksiyon yetkileri
-- ------------------------------------------------------------
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
-- Tetikleyici fonksiyonu; kimsenin doğrudan çağırmasına gerek yok.
revoke execute on function public.touch_support_ticket() from public, anon, authenticated;


-- ------------------------------------------------------------
-- 10. Uzunluk sınırları (events, event_edit_requests)
-- ------------------------------------------------------------
-- Kısıt önce NOT VALID eklenir (yeni/değişen kayıtlarda hemen geçerli), sonra
-- mevcut satırlar doğrulanır. Eski bir kayıt sınırı aşıyorsa dosya durmaz:
-- uyarı yazılır, kısıt yeni kayıtlar için yine çalışır; o kayıt düzeltilince
-- "alter table ... validate constraint ..." çalıştırılabilir.

-- Etiket kontrolü: en fazla 20 etiket, her biri en fazla 40 karakter.
-- (CHECK içinde alt sorgu olamadığı için küçük bir yardımcı fonksiyon.)
create or replace function public.event_tags_ok(p_tags text[]) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(cardinality(p_tags), 0) <= 20
     and not exists (select 1 from unnest(p_tags) t where char_length(t) > 40)
$$;

do $$
declare
  r record;
begin
  for r in
    select v.tbl, v.con, v.def from (values
      ('events',              'events_address_check',          'check (char_length(address) <= 300)'),
      ('events',              'events_rules_check',            'check (char_length(rules) <= 4000)'),
      ('events',              'events_university_check',       'check (char_length(university) <= 200)'),
      ('events',              'events_tags_check',             'check (public.event_tags_ok(tags))'),
      ('event_edit_requests', 'event_edit_requests_note_check','check (char_length(note) <= 2000)')
    ) as v(tbl, con, def)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = format('public.%I', r.tbl)::regclass and conname = r.con) then
      execute format('alter table public.%I add constraint %I %s not valid', r.tbl, r.con, r.def);
    end if;
    begin
      execute format('alter table public.%I validate constraint %I', r.tbl, r.con);
    exception when check_violation then
      raise warning '% kısıtını aşan eski kayıt var; kısıt yeni kayıtlar için geçerli, eski kayıt düzeltilince VALIDATE edin.', r.con;
    end;
  end loop;
end $$;


-- ------------------------------------------------------------
-- 11. Yinelenen indeks ve politika
-- ------------------------------------------------------------
-- event_edit_one_pending_idx ile event_edit_requests_one_pending_idx aynı
-- (event_id üzerinde, status = 'pending' için tekil). Tanımlar gerçekten
-- aynıysa eski adlı olanı kaldır.
do $$
declare
  a text;
  b text;
begin
  select regexp_replace(pg_get_indexdef(to_regclass('public.event_edit_one_pending_idx')), 'INDEX \S+ ON', 'INDEX x ON') into a;
  select regexp_replace(pg_get_indexdef(to_regclass('public.event_edit_requests_one_pending_idx')), 'INDEX \S+ ON', 'INDEX x ON') into b;
  if a is not null and b is not null and a = b then
    drop index public.event_edit_one_pending_idx;
  elsif a is not null and b is not null then
    raise warning 'event_edit_one_pending_idx ve event_edit_requests_one_pending_idx farklı; ikisi de bırakıldı.';
  end if;
end $$;

-- event_occurrences_club_insert, event_occurrences_insert politikasının
-- birebir alt kümesi (aynı EXISTS koşulu; diğerinde ayrıca "or is_admin()").
-- Kaldırınca kimsenin izni değişmez.
drop policy if exists event_occurrences_club_insert on public.event_occurrences;


-- ------------------------------------------------------------
-- 12. KVKK saklama süresi (pg_cron) — İSTEĞE BAĞLI, EN SONDA
-- ------------------------------------------------------------
-- Her gün 03:30 (UTC) çalışan 'unipakt-retention' işi:
--   - 12 aydan eski site iletişim mesajları ve Bize Katıl başvuruları silinir,
--   - okunmuş (read_at dolu), sonuçlanmış ve 6 aydan eski bildirimler silinir.
-- Bu bölüm kendi hata yakalayıcısı içindedir: pg_cron açılamazsa yalnızca
-- uyarı (WARNING) yazılır, dosyanın geri kalanı uygulanmış olur. Uyarı
-- görürseniz Dashboard > Database > Extensions'tan pg_cron'u açıp bu dosyayı
-- tekrar çalıştırın.
do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;

  if exists (select 1 from cron.job where jobname = 'unipakt-retention') then
    perform cron.unschedule('unipakt-retention');
  end if;

  perform cron.schedule(
    'unipakt-retention',
    '30 3 * * *',
    $job$
      delete from public.contact_messages  where created_at < now() - interval '12 months';
      delete from public.join_applications where created_at < now() - interval '12 months';
      delete from public.notifications
       where read_at is not null
         and (not actionable or resolved)
         and created_at < now() - interval '6 months';
    $job$
  );
exception when others then
  raise warning 'pg_cron bölümü uygulanamadı (%). Dashboard > Database > Extensions üzerinden pg_cron''u açıp dosyayı tekrar çalıştırın.', sqlerrm;
end $$;


-- ============================================================
-- Kontrol (isteğe bağlı; çalıştırdıktan sonra tek tek bakılabilir)
-- ============================================================
-- -- 1) Yeni sütunlar (5 satır beklenir)
-- select table_name, column_name from information_schema.columns
--  where table_schema = 'public'
--    and ((table_name = 'clubs' and column_name = 'kvkk_consent_at')
--      or (table_name in ('contact_messages','join_applications') and column_name in ('kvkk_version','kvkk_ack_at')));
--
-- -- 2) Fonksiyon imzaları (submit_ fonksiyonları 5 ve 9 parametreli olmalı; eski destek fonksiyonları listede olmamalı)
-- select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('public_clubs','submit_contact_message','submit_join_application',
--                      'create_support_ticket','reply_support_ticket','admin_update_support_ticket','admin_delete_support_ticket');
--
-- -- 3) Ziyaretçi yetkileri: false, true, true, true beklenir
-- select has_table_privilege('anon', 'public.clubs', 'select')                                                   as anon_clubs,
--        has_function_privilege('anon', 'public.public_clubs()', 'execute')                                     as anon_public_clubs,
--        has_function_privilege('anon', 'public.submit_contact_message(text,text,text,text,text)', 'execute')   as anon_contact,
--        has_function_privilege('anon', 'public.submit_join_application(text,text,text,text,text,text,text,text,text)', 'execute') as anon_join;
--
-- -- 4) Sitedeki kulüp sayısı ve iletişim bilgisi görünen kulüp sayısı
-- select count(1) as kulup, count(email) as iletisimli from public.public_clubs();
--
-- -- 5) notifications: read_at true, title false beklenir
-- select has_column_privilege('authenticated', 'public.notifications', 'read_at', 'update') as read_at_upd,
--        has_column_privilege('authenticated', 'public.notifications', 'title',   'update') as title_upd;
--
-- -- 6) Destek yabancı anahtarları: confdeltype = 'n' (set null) beklenir
-- select conname, confdeltype from pg_constraint
--  where conname in ('support_tickets_created_by_fkey','support_ticket_messages_author_id_fkey');
--
-- -- 7) Politikalar (club_insert destek politikaları ve event_posters_authenticated_ politikaları olmamalı)
-- select schemaname, tablename, policyname, cmd from pg_policies
--  where tablename in ('clubs','support_tickets','support_ticket_messages','event_occurrences','announcements','events')
--     or policyname like 'event_posters%'
--  order by tablename, policyname;
--
-- -- 8) Uzunluk kısıtları (convalidated = false ise eski kayıt sınırı aşıyor)
-- select conname, convalidated from pg_constraint
--  where conname in ('events_address_check','events_rules_check','events_university_check',
--                    'events_tags_check','event_edit_requests_note_check');
--
-- -- 9) Tekil indeks (yalnızca event_edit_requests_one_pending_idx kalmalı)
-- select indexname from pg_indexes where schemaname = 'public' and indexname like 'event_edit%pending%';
--
-- -- 10) Saklama işi (pg_cron açıksa 1 satır)
-- select jobname, schedule, active from cron.job where jobname = 'unipakt-retention';
