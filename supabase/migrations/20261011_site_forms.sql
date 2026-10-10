-- ============================================================
-- UniPakt — sitedeki İletişim ve Bize Katıl formları
-- FormSubmit yerine: form verisi yalnızca bu veritabanında (Frankfurt) tutulur.
--
--  * Ziyaretçi tabloları göremez, yazamaz. Kayıt yalnızca aşağıdaki iki
--    fonksiyonla eklenir; fonksiyonlar alanları kendisi doğrular.
--  * Okuma ve silme yalnızca UniPakt yetkilisinde (is_admin).
--  * Yeni kayıtta yöneticilere bildirim düşer (notifications → e-posta).
--    Bildirimde kişisel veri YOK: sadece "yeni mesaj var, panelden bak".
--  * IP adresi ya da tarayıcı bilgisi saklanmaz.
-- Tekrar çalıştırmak güvenlidir.
-- ============================================================

create table if not exists public.contact_messages (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 120),
  email      text not null check (char_length(email) between 3 and 200),
  message    text not null default '' check (char_length(message) <= 4000),
  created_at timestamptz not null default now()
);

create table if not exists public.join_applications (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (char_length(name) between 1 and 120),
  email              text not null check (char_length(email) between 3 and 200),
  university         text not null default '' check (char_length(university) <= 200),
  city               text not null default '' check (char_length(city) <= 80),
  outside_university text not null default '' check (char_length(outside_university) <= 200),
  club               text not null default '' check (char_length(club) <= 200),
  message            text not null default '' check (char_length(message) <= 4000),
  created_at         timestamptz not null default now()
);

create index if not exists contact_messages_created_idx  on public.contact_messages (created_at desc);
create index if not exists join_applications_created_idx on public.join_applications (created_at desc);

alter table public.contact_messages  enable row level security;
alter table public.join_applications enable row level security;

-- Ziyaretçi (anon) hiçbir şey yapamaz; giriş yapmış kullanıcıda da yalnızca
-- yetkili okuyup silebilir (politikalar aşağıda).
revoke all on public.contact_messages, public.join_applications from public, anon, authenticated;
grant select, delete on public.contact_messages, public.join_applications to authenticated;

drop policy if exists contact_messages_admin_select on public.contact_messages;
create policy contact_messages_admin_select on public.contact_messages for select to authenticated
  using ((select public.is_admin()));
drop policy if exists contact_messages_admin_delete on public.contact_messages;
create policy contact_messages_admin_delete on public.contact_messages for delete to authenticated
  using ((select public.is_admin()));

drop policy if exists join_applications_admin_select on public.join_applications;
create policy join_applications_admin_select on public.join_applications for select to authenticated
  using ((select public.is_admin()));
drop policy if exists join_applications_admin_delete on public.join_applications;
create policy join_applications_admin_delete on public.join_applications for delete to authenticated
  using ((select public.is_admin()));

-- Ortak doğrulama: boşlukları kırp, e-postayı kontrol et.
create or replace function public.site_form_clean(p text, p_max int) returns text
language sql immutable set search_path = '' as $$
  select left(btrim(coalesce(p, '')), p_max)
$$;
revoke execute on function public.site_form_clean(text, int) from public, anon, authenticated;

-- İletişim formu
create or replace function public.submit_contact_message(
  p_name text, p_email text, p_message text default '', p_honey text default ''
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_name  text := public.site_form_clean(p_name, 120);
  v_email text := lower(public.site_form_clean(p_email, 200));
  v_msg   text := public.site_form_clean(p_message, 4000);
begin
  -- Bot tuzağı doluysa sessizce "başarılı" dön, hiçbir şey kaydetme.
  if coalesce(p_honey, '') <> '' then return; end if;

  if v_name = '' then raise exception 'Adını yaz.'; end if;
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Geçerli bir e-posta gir.'; end if;

  -- Basit taşma koruması: aynı adresten saatte en fazla 3, toplamda 10 dakikada en fazla 30 mesaj.
  if (select count(*) from public.contact_messages
       where email = v_email and created_at > now() - interval '1 hour') >= 3
     or (select count(*) from public.contact_messages
          where created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'Çok fazla mesaj gönderildi. Biraz sonra tekrar dene.';
  end if;

  insert into public.contact_messages (name, email, message) values (v_name, v_email, v_msg);

  perform public.push_admin_notification(
    'Yeni iletişim mesajı',
    'Sitedeki iletişim formundan yeni bir mesaj geldi. Panelde "Site Mesajları" bölümünden okuyabilirsin.',
    'site_contact_message'
  );
end;
$$;

-- Bize Katıl formu
create or replace function public.submit_join_application(
  p_name text, p_email text,
  p_university text default '', p_city text default '', p_outside_university text default '',
  p_club text default '', p_message text default '', p_honey text default ''
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_name  text := public.site_form_clean(p_name, 120);
  v_email text := lower(public.site_form_clean(p_email, 200));
begin
  if coalesce(p_honey, '') <> '' then return; end if;

  if v_name = '' then raise exception 'Adını yaz.'; end if;
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Geçerli bir e-posta gir.'; end if;

  if (select count(*) from public.join_applications
       where email = v_email and created_at > now() - interval '1 hour') >= 3
     or (select count(*) from public.join_applications
          where created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'Çok fazla başvuru gönderildi. Biraz sonra tekrar dene.';
  end if;

  insert into public.join_applications (name, email, university, city, outside_university, club, message)
  values (
    v_name, v_email,
    public.site_form_clean(p_university, 200),
    public.site_form_clean(p_city, 80),
    public.site_form_clean(p_outside_university, 200),
    public.site_form_clean(p_club, 200),
    public.site_form_clean(p_message, 4000)
  );

  perform public.push_admin_notification(
    'Yeni Bize Katıl başvurusu',
    'Sitedeki Bize Katıl formundan yeni bir başvuru geldi. Panelde "Site Mesajları" bölümünden okuyabilirsin.',
    'site_join_application'
  );
end;
$$;

-- Bu iki fonksiyon sitenin herkese açık formlarıdır: ziyaretçi çağırabilir.
revoke execute on function public.submit_contact_message(text, text, text, text) from public;
revoke execute on function public.submit_join_application(text, text, text, text, text, text, text, text) from public;
grant execute on function public.submit_contact_message(text, text, text, text) to anon, authenticated;
grant execute on function public.submit_join_application(text, text, text, text, text, text, text, text) to anon, authenticated;
