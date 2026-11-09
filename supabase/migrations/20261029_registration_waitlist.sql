-- Bekleme listesi, kayıt iptali ve e-postayla bilet.
--   event_registrations.status: confirmed (kesin) | waitlist (bekliyor) | offered (yer teklif edildi)
--   Kontenjan = confirmed + offered. Kontenjan doluyken (ya da sırada bekleyen varken)
--   doğrulanan kayıt bekleme listesine girer. Yer açılınca (iptal, kulübün silmesi,
--   süresi dolan teklif) registration_sweep sıradakine süreli teklif açar; e-postayı
--   event-register fonksiyonu gönderir. Teklif 24 saat (etkinliğe daha az kaldıysa
--   etkinlik bitişine kadar) geçerlidir; onaylanmazsa silinir ve sıra ilerler.
--   Bilet/teklif bağlantıları ve iptal kodları yalnızca özet (hash) olarak saklanır.

alter table public.event_registrations
  add column if not exists status text not null default 'confirmed',
  add column if not exists offered_at timestamptz,
  add column if not exists offer_expires_at timestamptz,
  add column if not exists offer_token_hash text,
  add column if not exists ticket_token_hash text;
alter table public.event_registrations add constraint event_registrations_status_check check (status in ('confirmed', 'waitlist', 'offered'));
create unique index if not exists event_registrations_offer_token_idx on public.event_registrations (offer_token_hash) where offer_token_hash is not null;
create unique index if not exists event_registrations_ticket_token_idx on public.event_registrations (ticket_token_hash) where ticket_token_hash is not null;
create index if not exists event_registrations_queue_idx on public.event_registrations (event_id, status, created_at);

-- Panel yalnızca bu sütunları okur (bağlantı özetleri görünmez).
revoke select on public.event_registrations from authenticated;
grant select (id, event_id, code, full_name, email, answers, created_at, checked_in_at, checked_in_by, status, offered_at, offer_expires_at)
  on public.event_registrations to authenticated;

alter table public.event_registration_pending add column if not exists waitlist boolean not null default false;

create table if not exists public.event_registration_cancels (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.event_registrations(id) on delete cascade,
  code_hash text,
  attempts integer not null default 0,
  sends integer not null default 0,
  last_sent_at timestamptz,
  expires_at timestamptz not null default now() + interval '15 minutes',
  created_at timestamptz not null default now()
);
alter table public.event_registration_cancels enable row level security;
revoke all on public.event_registration_cancels from anon, authenticated;

-- Dolu koltuk: kesin + teklif bekleyen.
create or replace function public.registration_taken(p_event uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.event_registrations where event_id = p_event and status in ('confirmed', 'offered');
$$;

-- ---- Adım 1 (değişti): kontenjan doluysa bekleme listesine aday olarak açılır ----
create or replace function public.start_event_registration(
  p_event uuid, p_full_name text, p_email text, p_answers jsonb, p_consent boolean, p_ip_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.event_registration_settings;
  v_capacity integer;
  v_title text;
  v_name text := btrim(coalesce(p_full_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_answers jsonb;
  v_waitlist boolean;
  v_id uuid;
begin
  if p_consent is distinct from true then raise exception 'Devam etmek için KVKK aydınlatma metnini onayla.'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Ad soyad 2–120 karakter olmalı.'; end if;
  if char_length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Geçerli bir e-posta adresi yaz.'; end if;

  select e.capacity, e.title into v_capacity, v_title from public.events e
   where e.id = p_event and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on');
  if v_title is null then raise exception 'Etkinlik bulunamadı.'; end if;
  select * into v_settings from public.event_registration_settings where event_id = p_event and enabled;
  if not found then raise exception 'Bu etkinlik UniPakt üzerinden kayıt almıyor.'; end if;
  if not v_settings.is_open then raise exception 'Kayıtlar kapalı.'; end if;
  if now() >= public.event_ends_at(p_event) then raise exception 'Etkinlik sona erdi.'; end if;
  if v_settings.deadline is not null and now() >= v_settings.deadline then raise exception 'Kayıt süresi doldu.'; end if;

  if p_ip_hash is not null and (select count(*) from public.event_registration_pending
       where ip_hash = p_ip_hash and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Bu bağlantıdan çok fazla kayıt denemesi yapıldı. Biraz sonra tekrar dene.';
  end if;
  if (select count(*) from public.event_registration_pending
       where event_id = p_event and created_at > now() - interval '5 minutes') >= 100 then
    raise exception 'Şu an çok fazla kayıt isteği var. Birkaç dakika sonra tekrar dene.';
  end if;
  if exists (select 1 from public.event_registrations where event_id = p_event and lower(email) = v_email) then
    raise exception 'Bu e-posta adresiyle bu etkinliğe zaten kayıt olunmuş.';
  end if;
  -- Kontenjan: kesin + teklif + doğrulanmayı bekleyen (koltuk tutan) diğer adaylar.
  v_waitlist := exists (select 1 from public.event_registrations where event_id = p_event and status = 'waitlist')
    or (v_capacity is not null and public.registration_taken(p_event)
          + (select count(*) from public.event_registration_pending
              where event_id = p_event and not waitlist and expires_at > now() and email <> v_email) >= v_capacity);

  v_answers := public.registration_clean_answers(v_settings.questions, p_answers);

  delete from public.event_registration_pending where event_id = p_event and email = v_email;
  insert into public.event_registration_pending (event_id, full_name, email, answers, ip_hash, waitlist)
  values (p_event, v_name, v_email, v_answers, p_ip_hash, v_waitlist)
  returning id into v_id;

  return jsonb_build_object('pending_id', v_id, 'full_name', v_name, 'email', v_email, 'event_title', v_title, 'waitlist', v_waitlist);
end;
$$;

-- ---- Adım 2 (değişti): yer varsa kesin, yoksa bekleme listesi ----
create or replace function public.confirm_event_registration(p_pending uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.event_registration_pending;
  v_settings public.event_registration_settings;
  v_capacity integer;
  v_title text;
  v_status text;
  v_id uuid;
  v_pos integer;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no 0/O, 1/I
  i integer;
begin
  select * into v_p from public.event_registration_pending where id = p_pending;
  if not found then raise exception 'Doğrulama süresi doldu. Formu yeniden gönder.'; end if;

  select e.capacity, e.title into v_capacity, v_title from public.events e
   where e.id = v_p.event_id and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on');
  if v_title is null then raise exception 'Etkinlik bulunamadı.'; end if;
  select * into v_settings from public.event_registration_settings where event_id = v_p.event_id and enabled for update;
  if not found then raise exception 'Bu etkinlik UniPakt üzerinden kayıt almıyor.'; end if;
  if not v_settings.is_open then raise exception 'Kayıtlar kapalı.'; end if;
  if now() >= public.event_ends_at(v_p.event_id) then raise exception 'Etkinlik sona erdi.'; end if;
  if v_settings.deadline is not null and now() >= v_settings.deadline then raise exception 'Kayıt süresi doldu.'; end if;
  if exists (select 1 from public.event_registrations where event_id = v_p.event_id and lower(email) = v_p.email) then
    raise exception 'Bu e-posta adresiyle bu etkinliğe zaten kayıt olunmuş.';
  end if;

  v_status := case when exists (select 1 from public.event_registrations where event_id = v_p.event_id and status = 'waitlist')
                     or (v_capacity is not null and public.registration_taken(v_p.event_id) >= v_capacity)
                   then 'waitlist' else 'confirmed' end;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from public.event_registrations where event_id = v_p.event_id and code = v_code);
  end loop;

  insert into public.event_registrations (event_id, code, full_name, email, answers, status)
  values (v_p.event_id, v_code, v_p.full_name, v_p.email, v_p.answers, v_status)
  returning id into v_id;
  delete from public.event_registration_pending where id = p_pending;

  if v_status = 'waitlist' then
    select count(*) into v_pos from public.event_registrations where event_id = v_p.event_id and status = 'waitlist';
    return jsonb_build_object('status', 'waitlist', 'registration_id', v_id, 'position', v_pos, 'full_name', v_p.full_name, 'event_title', v_title, 'event_id', v_p.event_id);
  end if;
  return jsonb_build_object('status', 'confirmed', 'registration_id', v_id, 'code', v_code, 'full_name', v_p.full_name, 'event_title', v_title, 'event_id', v_p.event_id);
end;
$$;

-- ---- Sıra: süresi dolan teklifleri sil, boşalan yerler için sıradakilere teklif aç ----
-- Dönüş: yeni teklif açılan kayıtlar (e-postayı fonksiyon gönderir).
create or replace function public.registration_sweep(p_event uuid default null)
returns table (registration_id uuid, event_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ev record;
  v_free integer;
  v_ends timestamptz;
begin
  for ev in
    select s.event_id, e.capacity, s.is_open
      from public.event_registration_settings s join public.events e on e.id = s.event_id
     where s.enabled and (p_event is null or s.event_id = p_event)
       and exists (select 1 from public.event_registrations r where r.event_id = s.event_id and r.status in ('waitlist', 'offered'))
  loop
    perform 1 from public.event_registration_settings where event_registration_settings.event_id = ev.event_id for update;
    delete from public.event_registrations r
     where r.event_id = ev.event_id and r.status = 'offered' and r.offer_expires_at < now();
    v_ends := public.event_ends_at(ev.event_id);
    if not ev.is_open or v_ends is null or now() >= v_ends then continue; end if;
    v_free := case when ev.capacity is null then 1000000 else ev.capacity - public.registration_taken(ev.event_id) end;
    if v_free <= 0 then continue; end if;
    return query
      update public.event_registrations r
         set status = 'offered', offered_at = now(),
             offer_expires_at = least(now() + interval '24 hours', v_ends), offer_token_hash = null
       where r.id in (select w.id from public.event_registrations w
                       where w.event_id = ev.event_id and w.status = 'waitlist'
                       order by w.created_at limit v_free)
      returning r.id, r.event_id;
  end loop;
end;
$$;

-- Teklifi kabul et: yer hâlâ ayrılmış durumda (offered), kesin kayda döner.
create or replace function public.accept_registration_offer(p_registration uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare r public.event_registrations; v_title text;
begin
  update public.event_registrations
     set status = 'confirmed', offer_token_hash = null, offer_expires_at = null
   where id = p_registration and status = 'offered' and offer_expires_at > now()
  returning * into r;
  if not found then raise exception 'Bu teklifin süresi dolmuş ya da kullanılmış.'; end if;
  select title into v_title from public.events where id = r.event_id;
  return jsonb_build_object('status', 'confirmed', 'registration_id', r.id, 'code', r.code, 'full_name', r.full_name, 'event_title', v_title, 'event_id', r.event_id);
end;
$$;

-- Kayıt durumu (site): kontenjan doluysa kayıt yine açık ama bekleme listesine.
create or replace function public.public_event_registration(p_event uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with ev as (
    select e.id, e.capacity from public.events e
    where e.id = p_event and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on')
  ), s as (
    select s.* from public.event_registration_settings s join ev on ev.id = s.event_id where s.enabled
  ), c as (
    select public.registration_taken(p_event) as n,
           (select count(*)::integer from public.event_registrations r where r.event_id = p_event and r.status = 'waitlist') as w
  )
  select case when not exists (select 1 from s) then jsonb_build_object('enabled', false)
  else (
    select jsonb_build_object(
      'enabled', true,
      'open', s.is_open and (s.deadline is null or now() < s.deadline) and now() < public.event_ends_at(ev.id),
      'full', (ev.capacity is not null and c.n >= ev.capacity) or c.w > 0,
      'waiting', c.w,
      'reason', case
        when not s.is_open then 'closed'
        when now() >= public.event_ends_at(ev.id) then 'ended'
        when s.deadline is not null and now() >= s.deadline then 'deadline'
        when (ev.capacity is not null and c.n >= ev.capacity) or c.w > 0 then 'full'
        else null end,
      'deadline', s.deadline,
      'remaining', case when ev.capacity is null then null else greatest(ev.capacity - c.n, 0) end,
      'questions', s.questions)
    from s, ev, c)
  end;
$$;

-- Elle giriş yalnızca kesin kayıtlarda.
create or replace function public.set_registration_checkin(p_registration uuid, p_checked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_event uuid; v_status text;
begin
  select event_id, status into v_event, v_status from public.event_registrations where id = p_registration;
  if v_event is null or not public.owns_event(v_event) then raise exception 'Kayıt bulunamadı.'; end if;
  if v_status <> 'confirmed' then raise exception 'Bu kişi bekleme listesinde; giriş yalnızca kesin kayıtlarda işaretlenir.'; end if;
  update public.event_registrations
     set checked_in_at = case when p_checked then coalesce(checked_in_at, now()) else null end,
         checked_in_by = case when p_checked then checked_in_by else null end
   where id = p_registration;
end;
$$;

revoke all on function public.registration_taken(uuid), public.registration_sweep(uuid), public.accept_registration_offer(uuid) from public, anon, authenticated;
grant execute on function public.registration_taken(uuid), public.registration_sweep(uuid), public.accept_registration_offer(uuid) to service_role;
grant execute on function public.registration_taken(uuid) to authenticated;

-- Süresi dolan teklifler ve boşalan yerler için 10 dakikada bir sıra işlenir (e-postalar fonksiyondan).
select cron.schedule('unipakt-registration-queue', '*/10 * * * *', $cron$
  select net.http_post(
    url := 'https://hcgotmcbwmleeklbvawb.supabase.co/functions/v1/event-register',
    headers := '{"Content-Type": "application/json", "apikey": "sb_publishable_RcHJDYGkpd-01DPYG9o3HQ_8prlhUQn"}'::jsonb,
    body := '{"action": "sweep"}'::jsonb);
$cron$);

-- İptal talepleri 1 gün sonra silinir.
select cron.schedule('unipakt-registration-retention', '40 3 * * *', $cron$
  delete from public.event_registrations r
   where public.event_ends_at(r.event_id) < now() - interval '6 months';
  delete from public.event_staff_grants
   where expires_at < now() - interval '30 days';
  delete from public.event_registration_pending
   where created_at < now() - interval '1 day';
  delete from public.event_registration_cancels
   where created_at < now() - interval '1 day';
$cron$);
