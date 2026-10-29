-- Çoktan seçmeli sorularda "tek cevap / çok cevap" seçeneği.
--   soru: { ..., "type": "choice", "multiple": true }  → cevap: ["Seçenek A", "Seçenek C"]
--   multiple yoksa ya da false ise eskisi gibi tek cevap (metin).

create or replace function public.registration_questions_ok(p_questions jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  q jsonb;
  ids text[] := '{}';
begin
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) > 30 then return false; end if;
  for q in select value from jsonb_array_elements(p_questions) loop
    if jsonb_typeof(q) <> 'object' then return false; end if;
    if coalesce(q->>'id', '') !~ '^[a-z0-9_-]{1,40}$' or (q->>'id') = any(ids) then return false; end if;
    ids := ids || (q->>'id');
    if coalesce(q->>'type', '') not in ('text', 'choice') then return false; end if;
    if char_length(btrim(coalesce(q->>'label', ''))) not between 1 and 200 then return false; end if;
    if jsonb_typeof(coalesce(q->'required', 'false'::jsonb)) <> 'boolean' then return false; end if;
    if jsonb_typeof(coalesce(q->'multiple', 'false'::jsonb)) <> 'boolean' then return false; end if;
    if q->>'type' <> 'choice' and coalesce((q->>'multiple')::boolean, false) then return false; end if;
    if q->>'type' = 'choice' then
      if jsonb_typeof(q->'options') <> 'array' or jsonb_array_length(q->'options') not between 2 and 20 then return false; end if;
      if exists (select 1 from jsonb_array_elements(q->'options') o
                 where jsonb_typeof(o.value) <> 'string' or char_length(btrim(o.value #>> '{}')) not between 1 and 100) then return false; end if;
    end if;
  end loop;
  return true;
end;
$$;

create or replace function public.register_for_event(
  p_event uuid, p_full_name text, p_email text, p_answers jsonb, p_consent boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.event_registration_settings;
  v_capacity integer;
  v_count integer;
  v_title text;
  v_name text := btrim(coalesce(p_full_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_answers jsonb := '{}'::jsonb;
  q jsonb;
  v_val text;
  v_picked jsonb;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no 0/O, 1/I
  i integer;
begin
  if p_consent is distinct from true then raise exception 'Devam etmek için KVKK aydınlatma metnini onayla.'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Ad soyad 2–120 karakter olmalı.'; end if;
  if char_length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Geçerli bir e-posta adresi yaz.'; end if;

  select e.capacity, e.title into v_capacity, v_title from public.events e
   where e.id = p_event and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on');
  if v_title is null then raise exception 'Etkinlik bulunamadı.'; end if;
  -- Lock the settings row: registrations for one event are counted one at a time.
  select * into v_settings from public.event_registration_settings where event_id = p_event and enabled for update;
  if not found then raise exception 'Bu etkinlik UniPakt üzerinden kayıt almıyor.'; end if;
  if not v_settings.is_open then raise exception 'Kayıtlar kapalı.'; end if;
  if now() >= public.event_ends_at(p_event) then raise exception 'Etkinlik sona erdi.'; end if;
  if v_settings.deadline is not null and now() >= v_settings.deadline then raise exception 'Kayıt süresi doldu.'; end if;
  select count(*) into v_count from public.event_registrations where event_id = p_event;
  if v_capacity is not null and v_count >= v_capacity then raise exception 'Kontenjan doldu.'; end if;
  if exists (select 1 from public.event_registrations where event_id = p_event and lower(email) = v_email) then
    raise exception 'Bu e-posta adresiyle bu etkinliğe zaten kayıt olunmuş.';
  end if;

  -- Keep only answers to this form's questions; check required ones and choices.
  for q in select value from jsonb_array_elements(v_settings.questions) loop
    -- Çok cevaplı soru: cevap bir dizi; her öğe listedeki bir seçenek olmalı (tekrar yok, seçenek sırasıyla saklanır).
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

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from public.event_registrations where event_id = p_event and code = v_code);
  end loop;

  insert into public.event_registrations (event_id, code, full_name, email, answers)
  values (p_event, v_code, v_name, v_email, v_answers);

  return jsonb_build_object('code', v_code, 'full_name', v_name, 'event_title', v_title);
end;
$$;
