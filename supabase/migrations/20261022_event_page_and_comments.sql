-- 2026-10-22 — Etkinlik sistemi yenileme, 1. aşama (veritabanı)
--   * events: yeni isteğe bağlı alanlar + kontroller
--   * submit_event: yeni alanları ve "gizle" seçeneğini taşır
--   * public_events: yeni alanları döndürür (gizli etkinlikleri hâlâ vermez)
--   * public_event(p_id): tek etkinlik; yayındaysa gizli olsa da döner (linkle açılır)
--   * event_comments + submit_event_comment / public_event_comments
--   * unipakt-retention: 12 aydan eski yorumların e-postası silinir
-- Tekrar çalıştırılabilir (idempotent) yazıldı.

begin;

-- ─────────────────────────────────────────────────────────────
-- 1) events — yeni sütunlar
-- ─────────────────────────────────────────────────────────────
alter table public.events
  add column if not exists end_date      date,
  add column if not exists end_time      time without time zone,
  add column if not exists banner_url    text,
  add column if not exists city          text,
  add column if not exists biletimgo_url text,
  add column if not exists instagram_url text,
  add column if not exists facebook_url  text,
  add column if not exists x_url         text,
  add column if not exists youtube_url   text,
  add column if not exists capacity      integer;

alter table public.events drop constraint if exists events_banner_url_storage;
alter table public.events add constraint events_banner_url_storage check (
  banner_url is null or banner_url = ''
  or banner_url like 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/event-posters/%');

alter table public.events drop constraint if exists events_city_check;
alter table public.events add constraint events_city_check check (char_length(city) <= 60);

alter table public.events drop constraint if exists events_biletimgo_url_check;
alter table public.events add constraint events_biletimgo_url_check check (
  biletimgo_url is null or biletimgo_url = ''
  or biletimgo_url ~ '^https://(www\.)?biletimgo\.com/[^[:space:]"''<>]*$');

alter table public.events drop constraint if exists events_social_urls_http;
alter table public.events add constraint events_social_urls_http check (
      (instagram_url is null or instagram_url = '' or instagram_url ~ '^https?://[^[:space:]"''<>]+$')
  and (facebook_url  is null or facebook_url  = '' or facebook_url  ~ '^https?://[^[:space:]"''<>]+$')
  and (x_url         is null or x_url         = '' or x_url         ~ '^https?://[^[:space:]"''<>]+$')
  and (youtube_url   is null or youtube_url   = '' or youtube_url   ~ '^https?://[^[:space:]"''<>]+$'));

alter table public.events drop constraint if exists events_capacity_check;
alter table public.events add constraint events_capacity_check check (capacity is null or capacity > 0);

-- Bitiş, başlangıçtan önce olamaz. end_date boşsa bitiş aynı gün sayılır.
alter table public.events drop constraint if exists events_end_after_start;
alter table public.events add constraint events_end_after_start check (
      (end_date is null or end_date >= event_date)
  and (end_time is null or event_time is null
       or coalesce(end_date, event_date) > event_date
       or end_time >= event_time));

-- ─────────────────────────────────────────────────────────────
-- 2) submit_event — yeni alanlar + "Etkinliği gizle"
-- ─────────────────────────────────────────────────────────────
create or replace function public.submit_event(p_event jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id uuid;
  v_club uuid := public.my_club();
  v_admin boolean := public.is_admin();
  v_status text;
  v_item jsonb;
begin
  if not v_admin and v_club is null then
    raise exception 'Bu işlem için kulüp hesabı gerekir.';
  end if;

  if coalesce(nullif(trim(p_event->>'title'), ''), '') = '' then
    raise exception 'Etkinlik adı gerekli.';
  end if;

  if p_event->>'fee_type' = 'paid'
     and coalesce(nullif(p_event->>'fee_amount','')::numeric, 0) <= 0 then
    raise exception 'Ücretli etkinlikte ücret tutarı 0''dan büyük olmalı.';
  end if;

  v_status := case when v_admin then 'published' else 'pending' end;

  insert into public.events (
    club_id, title, description, event_date, event_time, place, seeking,
    status, note, created_by, decided_at, kind, calendar,
    address, rules, poster_url, tags, registration_url, fee_type, fee_amount,
    university, visible,
    end_date, end_time, banner_url, city, biletimgo_url,
    instagram_url, facebook_url, x_url, youtube_url, capacity
  )
  values (
    case when v_admin then null else v_club end,
    p_event->>'title',
    coalesce(p_event->>'description',''),
    ((p_event->'occurrences'->0)->>'date')::date,
    nullif((p_event->'occurrences'->0)->>'time','')::time,
    nullif(p_event->>'place',''),
    nullif(p_event->>'seeking',''),
    v_status,
    null,
    auth.uid(),
    case when v_admin then now() else null end,
    coalesce(nullif(p_event->>'kind',''),'event'),
    case when v_admin then
      case when coalesce(p_event->>'kind','event') = 'event' then 'on' else 'none' end
    else 'none' end,
    nullif(p_event->>'address',''),
    nullif(p_event->>'rules',''),
    nullif(p_event->>'poster_url',''),
    coalesce(array(select jsonb_array_elements_text(coalesce(p_event->'tags','[]'::jsonb))), '{}'),
    nullif(p_event->>'registration_url',''),
    case when p_event->>'fee_type' = 'paid' then 'paid' else 'free' end,
    case when p_event->>'fee_type' = 'paid' then nullif(p_event->>'fee_amount','')::numeric else null end,
    nullif(p_event->>'university',''),
    coalesce((p_event->>'visible')::boolean, true),
    nullif(p_event->>'end_date','')::date,
    nullif(p_event->>'end_time','')::time,
    nullif(p_event->>'banner_url',''),
    nullif(trim(p_event->>'city'),''),
    nullif(p_event->>'biletimgo_url',''),
    nullif(p_event->>'instagram_url',''),
    nullif(p_event->>'facebook_url',''),
    nullif(p_event->>'x_url',''),
    nullif(p_event->>'youtube_url',''),
    nullif(p_event->>'capacity','')::integer
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(coalesce(p_event->'occurrences','[]'::jsonb))
  loop
    insert into public.event_occurrences(event_id, date, time)
    values (v_id, (v_item->>'date')::date, nullif(v_item->>'time','')::time);
  end loop;

  return v_id;
end;
$function$;

revoke all on function public.submit_event(jsonb) from public, anon;
grant execute on function public.submit_event(jsonb) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 3) public_events — yeni alanlar (dönüş tipi değiştiği için drop + create)
--    Gizli (visible = false) etkinlikler burada hâlâ yok.
-- ─────────────────────────────────────────────────────────────
drop function if exists public.public_events();
create function public.public_events()
 returns table(
   id uuid, title text, description text, event_date date, event_time time without time zone,
   place text, address text, rules text, poster_url text, tags text[], registration_url text,
   fee_type text, fee_amount numeric, kind text, organizer_id uuid, organizer text,
   university text, occurrences jsonb,
   end_date date, end_time time without time zone, banner_url text, city text,
   biletimgo_url text, instagram_url text, facebook_url text, x_url text, youtube_url text,
   capacity integer)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select e.id,e.title,e.description,e.event_date,e.event_time,e.place,e.address,e.rules,e.poster_url,e.tags,e.registration_url,e.fee_type,e.fee_amount,e.kind,
    c.id as organizer_id,
    coalesce(nullif(e.university,''),c.university,'UniPakt') ||
      coalesce((select ', '||string_agg(distinct coalesce(pc.university,pc.name), ', ' order by coalesce(pc.university,pc.name)) from public.event_applications pa join public.clubs pc on pc.id=pa.club_id where pa.event_id=e.id and pa.status='approved'),'') as organizer,
    coalesce(nullif(e.university,''),c.university) as university,
    coalesce((select jsonb_agg(jsonb_build_object('date',o.date,'time',o.time) order by o.date,o.time) from public.event_occurrences o where o.event_id=e.id),jsonb_build_array(jsonb_build_object('date',e.event_date,'time',e.event_time))) as occurrences,
    e.end_date,e.end_time,e.banner_url,e.city,e.biletimgo_url,e.instagram_url,e.facebook_url,e.x_url,e.youtube_url,e.capacity
  from public.events e left join public.clubs c on c.id=e.club_id
  where e.status='published' and coalesce(e.visible,true)<>false and (e.kind='event' or e.calendar='on')
  order by e.event_date,e.event_time,e.created_at;
$function$;

revoke all on function public.public_events() from public;
grant execute on function public.public_events() to anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 4) public_event(p_id) — etkinlik sayfası için tek kayıt
--    Yayındaysa döner; visible = false olsa da (linkle açılan gizli etkinlik).
--    pending / rejected asla dönmez. Takvime çıkmayan ortak arama ilanları da dönmez.
-- ─────────────────────────────────────────────────────────────
drop function if exists public.public_event(uuid);
create function public.public_event(p_id uuid)
 returns table(
   id uuid, title text, description text, event_date date, event_time time without time zone,
   place text, address text, rules text, poster_url text, tags text[], registration_url text,
   fee_type text, fee_amount numeric, kind text, organizer_id uuid, organizer_name text,
   organizer text, university text, occurrences jsonb,
   end_date date, end_time time without time zone, banner_url text, city text,
   biletimgo_url text, instagram_url text, facebook_url text, x_url text, youtube_url text,
   capacity integer, partners jsonb)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select e.id,e.title,e.description,e.event_date,e.event_time,e.place,e.address,e.rules,e.poster_url,e.tags,e.registration_url,e.fee_type,e.fee_amount,e.kind,
    c.id as organizer_id,
    coalesce(c.name,'UniPakt') as organizer_name,
    coalesce(nullif(e.university,''),c.university,'UniPakt') ||
      coalesce((select ', '||string_agg(distinct coalesce(pc.university,pc.name), ', ' order by coalesce(pc.university,pc.name)) from public.event_applications pa join public.clubs pc on pc.id=pa.club_id where pa.event_id=e.id and pa.status='approved'),'') as organizer,
    coalesce(nullif(e.university,''),c.university) as university,
    coalesce((select jsonb_agg(jsonb_build_object('date',o.date,'time',o.time) order by o.date,o.time) from public.event_occurrences o where o.event_id=e.id),jsonb_build_array(jsonb_build_object('date',e.event_date,'time',e.event_time))) as occurrences,
    e.end_date,e.end_time,e.banner_url,e.city,e.biletimgo_url,e.instagram_url,e.facebook_url,e.x_url,e.youtube_url,e.capacity,
    coalesce((select jsonb_agg(jsonb_build_object('id',pc.id,'name',pc.name,'university',pc.university) order by pc.name)
                from public.event_applications pa join public.clubs pc on pc.id=pa.club_id
               where pa.event_id=e.id and pa.status='approved'),'[]'::jsonb) as partners
  from public.events e left join public.clubs c on c.id=e.club_id
  where e.id = p_id and e.status='published' and (e.kind='event' or e.calendar='on')
  limit 1;
$function$;

revoke all on function public.public_event(uuid) from public;
grant execute on function public.public_event(uuid) to anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 5) event_comments
-- ─────────────────────────────────────────────────────────────
create table if not exists public.event_comments (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  name text not null,
  email text,                         -- 12 ay sonra silinir (null olur)
  body text not null,
  status text not null default 'pending',
  kvkk_version text not null,
  kvkk_ack_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  constraint event_comments_pkey primary key (id),
  constraint event_comments_event_id_fkey foreign key (event_id) references public.events(id) on delete cascade,
  constraint event_comments_name_check check (char_length(name) between 1 and 120),
  constraint event_comments_email_check check (email is null or char_length(email) between 3 and 200),
  constraint event_comments_body_check check (char_length(body) between 1 and 2000),
  constraint event_comments_kvkk_version_check check (char_length(kvkk_version) between 1 and 40),
  constraint event_comments_status_check check (status in ('pending','approved','rejected'))
);
alter table public.event_comments enable row level security;

create index if not exists event_comments_event_status_idx on public.event_comments (event_id, status, created_at);
create index if not exists event_comments_status_idx on public.event_comments (status);
create index if not exists event_comments_email_idx on public.event_comments (email, created_at);

-- Anon/kulüp doğrudan erişemez; yalnızca yönetici okur, onaylar, siler.
revoke all on table public.event_comments from anon, authenticated;
grant select, update, delete on table public.event_comments to authenticated;
grant select, insert, update, delete on table public.event_comments to service_role;

drop policy if exists event_comments_admin_select on public.event_comments;
create policy event_comments_admin_select on public.event_comments for select to authenticated
  using ((select public.is_admin()));
drop policy if exists event_comments_admin_update on public.event_comments;
create policy event_comments_admin_update on public.event_comments for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists event_comments_admin_delete on public.event_comments;
create policy event_comments_admin_delete on public.event_comments for delete to authenticated
  using ((select public.is_admin()));

-- Yorum gönderme: yalnızca bu RPC ile.
create or replace function public.submit_event_comment(
  p_event uuid, p_name text, p_email text, p_body text,
  p_honey text default '', p_kvkk_version text default null)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_name  text := public.site_form_clean(p_name, 120);
  v_email text := lower(public.site_form_clean(p_email, 200));
  v_body  text := public.site_form_clean(p_body, 2000);
  v_kvkk  text := public.site_form_clean(p_kvkk_version, 40);
begin
  -- Bot tuzağı doluysa sessizce "başarılı" dön.
  if coalesce(p_honey, '') <> '' then return; end if;

  if v_kvkk = '' then raise exception 'KVKK Aydınlatma Metni''ni okuduğunu işaretle.'; end if;
  if v_name = '' then raise exception 'Adını yaz.'; end if;
  if v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Geçerli bir e-posta gir.';
  end if;
  if v_body = '' then raise exception 'Yorumunu yaz.'; end if;

  -- Yalnızca yayındaki (takvime çıkan ya da linkle açılan) etkinliklere.
  if not exists (select 1 from public.events e
                  where e.id = p_event and e.status = 'published'
                    and (e.kind = 'event' or e.calendar = 'on')) then
    raise exception 'Etkinlik bulunamadı.';
  end if;

  -- Hız sınırı: aynı e-postadan 10 dakikada en fazla 3, genel olarak 10 dakikada en fazla 60 yorum.
  if (select count(1) from public.event_comments
       where email = v_email and created_at > now() - interval '10 minutes') >= 3
     or (select count(1) from public.event_comments
          where created_at > now() - interval '10 minutes') >= 60 then
    raise exception 'Çok fazla yorum gönderildi. Biraz sonra tekrar dene.';
  end if;

  insert into public.event_comments (event_id, name, email, body, kvkk_version, kvkk_ack_at)
  values (p_event, v_name, v_email, v_body, v_kvkk, now());

  -- Son 30 dakikada aynı bildirim düştüyse yenisini gönderme.
  if not exists (select 1 from public.notifications
                  where recipient_role = 'admin' and type = 'site_event_comment'
                    and created_at > now() - interval '30 minutes') then
    perform public.push_admin_notification(
      'Yeni etkinlik yorumu',
      'Sitede bir etkinliğe yeni yorum yazıldı. Panelde "Onaylamalar" bölümünden onaylayabilirsin.',
      'site_event_comment',
      p_event
    );
  end if;
end;
$function$;

revoke all on function public.submit_event_comment(uuid, text, text, text, text, text) from public;
grant execute on function public.submit_event_comment(uuid, text, text, text, text, text) to anon, authenticated;

-- Sitede gösterim: yalnızca onaylı yorumlar, yalnızca ad + metin + tarih.
create or replace function public.public_event_comments(p_event uuid)
 returns table(id uuid, name text, body text, created_at timestamptz)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select c.id, c.name, c.body, c.created_at
    from public.event_comments c
    join public.events e on e.id = c.event_id
   where c.event_id = p_event and c.status = 'approved'
     and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on')
   order by c.created_at;
$function$;

revoke all on function public.public_event_comments(uuid) from public;
grant execute on function public.public_event_comments(uuid) to anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 6) Saklama — 12 aydan eski yorumların e-postası silinir
-- ─────────────────────────────────────────────────────────────
select cron.unschedule('unipakt-retention')
 where exists (select 1 from cron.job where jobname = 'unipakt-retention');
select cron.schedule('unipakt-retention', '30 3 * * *', $cron$
      delete from public.contact_messages  where created_at < now() - interval '12 months';
      delete from public.join_applications where created_at < now() - interval '12 months';
      delete from public.notifications
       where read_at is not null
         and (not actionable or resolved)
         and created_at < now() - interval '6 months';
      update public.event_comments set email = null
       where email is not null and created_at < now() - interval '12 months';
    $cron$);

commit;
