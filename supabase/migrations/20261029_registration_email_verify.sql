-- Etkinlik kaydında e-posta doğrulaması.
--   1) start  (event-register fonksiyonu → start_event_registration): bilgiler doğrulanır,
--      "bekleyen" kayıt açılır; fonksiyon e-postaya 6 haneli kod gönderir.
--   2) verify (kod doğruysa → confirm_event_registration): kontenjan / süre / tekrar
--      kontrolü kilit altında yeniden yapılır, kesin kayıt ve giriş kodu üretilir.
-- Doğrudan (doğrulamasız) kayıt kapatılır: register_for_event artık herkese açık değil.
-- Kötüye kullanım: aynı ağdan saatte en fazla 10, bir etkinliğe 5 dakikada en fazla 100
-- kayıt denemesi; kod 15 dakika geçerli, en fazla 5 yanlış deneme (fonksiyonda).

create table if not exists public.event_registration_pending (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 120),
  email text not null check (char_length(email) <= 254),
  answers jsonb not null default '{}'::jsonb,
  code_hash text,
  attempts integer not null default 0,
  sends integer not null default 0,
  last_sent_at timestamptz,
  expires_at timestamptz not null default now() + interval '15 minutes',
  ip_hash text,
  created_at timestamptz not null default now()
);
create index if not exists event_registration_pending_event_idx on public.event_registration_pending (event_id, created_at);
create index if not exists event_registration_pending_ip_idx on public.event_registration_pending (ip_hash, created_at);
alter table public.event_registration_pending enable row level security;
revoke all on public.event_registration_pending from anon, authenticated;

-- Formdaki sorulara verilen cevapları ayıklar: zorunlular, seçenekler, çok cevaplar.
create or replace function public.registration_clean_answers(p_questions jsonb, p_answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_answers jsonb := '{}'::jsonb;
  q jsonb;
  v_val text;
  v_picked jsonb;
begin
  p_answers := coalesce(p_answers, '{}'::jsonb);
  if jsonb_typeof(p_answers) <> 'object' then raise exception 'Cevaplar okunamadı.'; end if;
  for q in select value from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) loop
    if q->>'type' = 'choice' and coalesce((q->>'multiple')::boolean, false) then
      v_picked := p_answers -> (q->>'id');
      if v_picked is null or jsonb_typeof(v_picked) = 'null' or (jsonb_typeof(v_picked) = 'array' and jsonb_array_length(v_picked) = 0) then
        if coalesce((q->>'required')::boolean, false) then raise exception '“%” sorusu zorunlu.', q->>'label'; end if;
        continue;
      end if;
      if jsonb_typeof(v_picked) <> 'array'
         or exists (select 1 from jsonb_array_elements(v_picked) a
                     where jsonb_typeof(a.value) <> 'string'
                        or not exists (select 1 from jsonb_array_elements_text(q->'options') o where o = a.value #>> '{}')) then
        raise exception '“%” için listedeki seçeneklerden seç.', q->>'label';
      end if;
      v_answers := v_answers || jsonb_build_object(q->>'id',
        (select jsonb_agg(o.value order by o.ord) from jsonb_array_elements_text(q->'options') with ordinality o(value, ord)
          where v_picked ? o.value));
      continue;
    end if;
    v_val := btrim(coalesce(p_answers ->> (q->>'id'), ''));
    if v_val = '' then
      if coalesce((q->>'required')::boolean, false) then raise exception '“%” sorusu zorunlu.', q->>'label'; end if;
      continue;
    end if;
    if q->>'type' = 'choice' and not exists (select 1 from jsonb_array_elements_text(q->'options') o where o = v_val) then
      raise exception '“%” için listedeki seçeneklerden birini seç.', q->>'label';
    end if;
    if char_length(v_val) > 1000 then raise exception '“%” cevabı en fazla 1000 karakter olabilir.', q->>'label'; end if;
    v_answers := v_answers || jsonb_build_object(q->>'id', v_val);
  end loop;
  return v_answers;
end;
$$;

-- Adım 1: bilgileri doğrula, bekleyen kaydı aç. (Yalnız event-register fonksiyonu çağırır.)
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
  v_taken integer;
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
  -- Kontenjan: kesin kayıtlar + doğrulanmayı bekleyen (süresi geçmemiş) diğer kayıtlar.
  select (select count(*) from public.event_registrations where event_id = p_event)
       + (select count(*) from public.event_registration_pending
           where event_id = p_event and expires_at > now() and email <> v_email)
    into v_taken;
  if v_capacity is not null and v_taken >= v_capacity then raise exception 'Kontenjan doldu.'; end if;

  v_answers := public.registration_clean_answers(v_settings.questions, p_answers);

  delete from public.event_registration_pending where event_id = p_event and email = v_email;
  insert into public.event_registration_pending (event_id, full_name, email, answers, ip_hash)
  values (p_event, v_name, v_email, v_answers, p_ip_hash)
  returning id into v_id;

  return jsonb_build_object('pending_id', v_id, 'full_name', v_name, 'email', v_email, 'event_title', v_title);
end;
$$;

-- Adım 2: kod doğrulandıktan sonra kesin kayıt. (Yalnız event-register fonksiyonu çağırır.)
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
  v_count integer;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no 0/O, 1/I
  i integer;
begin
  select * into v_p from public.event_registration_pending where id = p_pending;
  if not found then raise exception 'Doğrulama süresi doldu. Formu yeniden gönder.'; end if;

  select e.capacity, e.title into v_capacity, v_title from public.events e
   where e.id = v_p.event_id and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on');
  if v_title is null then raise exception 'Etkinlik bulunamadı.'; end if;
  -- Kilit: bir etkinliğin kayıtları sırayla kesinleşir (kontenjan aşılmaz).
  select * into v_settings from public.event_registration_settings where event_id = v_p.event_id and enabled for update;
  if not found then raise exception 'Bu etkinlik UniPakt üzerinden kayıt almıyor.'; end if;
  if not v_settings.is_open then raise exception 'Kayıtlar kapalı.'; end if;
  if now() >= public.event_ends_at(v_p.event_id) then raise exception 'Etkinlik sona erdi.'; end if;
  if v_settings.deadline is not null and now() >= v_settings.deadline then raise exception 'Kayıt süresi doldu.'; end if;
  if exists (select 1 from public.event_registrations where event_id = v_p.event_id and lower(email) = v_p.email) then
    delete from public.event_registration_pending where id = p_pending;
    raise exception 'Bu e-posta adresiyle bu etkinliğe zaten kayıt olunmuş.';
  end if;
  select count(*) into v_count from public.event_registrations where event_id = v_p.event_id;
  if v_capacity is not null and v_count >= v_capacity then raise exception 'Kontenjan doldu.'; end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from public.event_registrations where event_id = v_p.event_id and code = v_code);
  end loop;

  insert into public.event_registrations (event_id, code, full_name, email, answers)
  values (v_p.event_id, v_code, v_p.full_name, v_p.email, v_p.answers);
  delete from public.event_registration_pending where id = p_pending;

  return jsonb_build_object('code', v_code, 'full_name', v_p.full_name, 'event_title', v_title, 'event_id', v_p.event_id);
end;
$$;

revoke all on function public.registration_clean_answers(jsonb, jsonb), public.start_event_registration(uuid, text, text, jsonb, boolean, text),
  public.confirm_event_registration(uuid) from public, anon, authenticated;
grant execute on function public.registration_clean_answers(jsonb, jsonb), public.start_event_registration(uuid, text, text, jsonb, boolean, text),
  public.confirm_event_registration(uuid) to service_role;

-- Doğrulamasız eski yol kapanır.
revoke execute on function public.register_for_event(uuid, text, text, jsonb, boolean) from public, anon, authenticated;

-- Saklama: doğrulanmamış bekleyen kayıtlar 1 gün sonra silinir (gece işine eklenir).
select cron.schedule('unipakt-registration-retention', '40 3 * * *', $cron$
  delete from public.event_registrations r
   where public.event_ends_at(r.event_id) < now() - interval '6 months';
  delete from public.event_staff_grants
   where expires_at < now() - interval '30 days';
  delete from public.event_registration_pending
   where created_at < now() - interval '1 day';
$cron$);
