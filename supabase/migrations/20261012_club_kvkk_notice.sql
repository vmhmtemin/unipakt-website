-- ============================================================
-- UniPakt — yeni kulübe otomatik KVKK onay talebi e-postası
--
-- Bir kulüp sitede görünür hale geldiğinde (visible = true) ve e-postası varsa,
-- send-club-kvkk-notice Edge Function'ı o kulübe KVKK onay talebini gönderir.
--  * Her kulübe bir kez gider (kvkk_notice_sent_at).
--  * Kulübün e-postası değişirse damga sıfırlanır ve yeni adrese tekrar gider
--    (onay doğru adresten alınmalı).
--  * Gizli kulüpler (visible = false, ör. test kaydı) tetiklemez.
--  * Tetikleyici e-postayı beklemez (pg_net arka planda çağırır); kulüp ekleme
--    işlemi e-posta servisine bağlı olarak asla başarısız olmaz.
--
-- ÖNCE Edge Function'ı (verify_jwt = false) yayına alın, SONRA bu dosyayı çalıştırın.
-- Tekrar çalıştırmak güvenlidir.
-- DİKKAT: clubs_kvkk_notice_reset() 20261013_audit_fixes.sql'de genişletildi
-- (kvkk_consent_at de sıfırlanır). Bu dosya yeniden çalıştırılırsa ardından
-- 20261013'ü de tekrar çalıştırın.
-- ============================================================

alter table public.clubs add column if not exists kvkk_notice_sent_at timestamptz;

-- 12 Ekim 2026'da elle gönderilen kulüpler: tekrar gönderilmesin.
update public.clubs
   set kvkk_notice_sent_at = '2026-10-11 22:53:36+00'
 where kvkk_notice_sent_at is null
   and lower(email) in (
     'gdgoncampusisu@gmail.com',
     'kariyergelisimkulubu@stu.ihu.edu.tr',
     'info@kalitevegirisimcilik.com',
     'genckalitekulubu@altinbas.edu.tr',
     'ytusoskulubu@gmail.com',
     'bogazicidans@gmail.com'
   );

-- E-posta değişince damgayı sıfırla (yeni adres yeniden bilgilendirilir).
create or replace function public.clubs_kvkk_notice_reset() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.email is distinct from old.email then
    new.kvkk_notice_sent_at := null;
  end if;
  return new;
end;
$$;

-- Görünür, e-postalı ve henüz bilgilendirilmemiş kulüp için Edge Function'ı çağır.
create or replace function public.clubs_kvkk_notice_webhook() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_key text;
begin
  if not coalesce(new.visible, false)
     or coalesce(btrim(new.email), '') = ''
     or new.kvkk_notice_sent_at is not null then
    return new;
  end if;

  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'notification_function_key'
   limit 1;
  if v_key is null then
    raise warning 'notification_function_key Vault secret bulunamadı; KVKK e-postası gönderilmedi.';
    return new;
  end if;

  perform net.http_post(
    url     := 'https://hcgotmcbwmleeklbvawb.supabase.co/functions/v1/send-club-kvkk-notice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_key),
    body    := jsonb_build_object('club_id', new.id)
  );
  return new;
end;
$$;

revoke execute on function public.clubs_kvkk_notice_reset()   from public, anon, authenticated;
revoke execute on function public.clubs_kvkk_notice_webhook() from public, anon, authenticated;

drop trigger if exists clubs_kvkk_notice_reset on public.clubs;
create trigger clubs_kvkk_notice_reset
  before update of email on public.clubs
  for each row execute function public.clubs_kvkk_notice_reset();

drop trigger if exists clubs_kvkk_notice_send on public.clubs;
create trigger clubs_kvkk_notice_send
  after insert or update of email, visible on public.clubs
  for each row execute function public.clubs_kvkk_notice_webhook();
