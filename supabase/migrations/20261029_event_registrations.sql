-- UniPakt — event registration (kayıt toplama) and entry check (giriş kontrolü).
--
--  * event_registration_settings  one row per event that collects registrations
--                                 on UniPakt: open/closed, deadline, the form's
--                                 questions and the board's visible columns.
--  * event_registrations          one row per person: fixed full name + e-mail,
--                                 answers, a 6-character entry code (A–Z, 2–9),
--                                 check-in time and the staff member who checked.
--  * event_staff                  a club's (or UniPakt's) reusable list of door
--                                 staff; they need no panel account.
--  * event_staff_grants           "this staff member may check this event":
--                                 hashed link token + hashed 6-digit access code,
--                                 valid until the end of the event's last day.
--
-- Visitors register through register_for_event() (anon). Staff use the Edge
-- Function `event-checkin`, which runs with the service role. Everything else is
-- for the event's owner (its club, or UniPakt for UniPakt's own events) and the
-- UniPakt admin, through the shared helpers (which already include 2FA).

create table if not exists public.event_registration_settings (
  event_id      uuid primary key references public.events(id) on delete cascade,
  enabled       boolean not null default true,
  is_open       boolean not null default true,
  deadline      timestamptz,
  questions     jsonb not null default '[]'::jsonb,
  board_columns jsonb not null default '[]'::jsonb,
  updated_at    timestamptz not null default now()
);

create table if not exists public.event_staff (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid references public.clubs(id) on delete cascade,   -- null = UniPakt
  full_name  text not null check (char_length(btrim(full_name)) between 2 and 120),
  email      text not null check (char_length(email) <= 254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  created_at timestamptz not null default now()
);
create unique index if not exists event_staff_owner_email on public.event_staff (coalesce(club_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(email));

create table if not exists public.event_registrations (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events(id) on delete cascade,
  code          text not null check (code ~ '^[A-Z0-9]{6}$'),
  full_name     text not null check (char_length(btrim(full_name)) between 2 and 120),
  email         text not null check (char_length(email) <= 254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  answers       jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  checked_in_at timestamptz,
  checked_in_by uuid references public.event_staff(id) on delete set null,
  unique (event_id, code)
);
create unique index if not exists event_registrations_event_email on public.event_registrations (event_id, lower(email));
create index if not exists event_registrations_event on public.event_registrations (event_id, created_at);

create table if not exists public.event_staff_grants (
  id               uuid primary key default gen_random_uuid(),
  staff_id         uuid not null references public.event_staff(id) on delete cascade,
  event_id         uuid not null references public.events(id) on delete cascade,
  link_token_hash  text not null unique,
  access_code_hash text not null,
  failed_attempts  integer not null default 0,
  expires_at       timestamptz not null,
  created_at       timestamptz not null default now(),
  last_used_at     timestamptz,
  unique (staff_id, event_id)
);

alter table public.event_registration_settings enable row level security;
alter table public.event_registrations         enable row level security;
alter table public.event_staff                 enable row level security;
alter table public.event_staff_grants          enable row level security;

-- Does the signed-in panel user own this event? (its club, or UniPakt/admin)
create or replace function public.owns_event(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin()
      or exists (select 1 from public.events e where e.id = p_event and e.club_id is not null and e.club_id = public.my_club());
$$;

-- Does this staff list row belong to the signed-in user's club (or UniPakt)?
create or replace function public.owns_staff(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_club is null then public.is_admin() else p_club = public.my_club() end;
$$;

-- ---- RLS ----
create policy event_registration_settings_select on public.event_registration_settings
  for select to authenticated using (public.owns_event(event_id));

create policy event_registrations_select on public.event_registrations
  for select to authenticated using (public.owns_event(event_id));
create policy event_registrations_delete on public.event_registrations
  for delete to authenticated using (public.owns_event(event_id));

create policy event_staff_select on public.event_staff
  for select to authenticated using (public.owns_staff(club_id));
create policy event_staff_insert on public.event_staff
  for insert to authenticated with check (public.owns_staff(club_id));
create policy event_staff_update on public.event_staff
  for update to authenticated using (public.owns_staff(club_id)) with check (public.owns_staff(club_id));
create policy event_staff_delete on public.event_staff
  for delete to authenticated using (public.owns_staff(club_id));

create policy event_staff_grants_select on public.event_staff_grants
  for select to authenticated
  using (exists (select 1 from public.event_staff s where s.id = staff_id and public.owns_staff(s.club_id)));
create policy event_staff_grants_delete on public.event_staff_grants
  for delete to authenticated
  using (exists (select 1 from public.event_staff s where s.id = staff_id and public.owns_staff(s.club_id)));

-- Start from nothing (Supabase grants everything on new tables by default), then allow only what is needed.
revoke all on public.event_registrations, public.event_registration_settings, public.event_staff, public.event_staff_grants from anon, authenticated;
grant select, delete on public.event_registrations to authenticated;
grant select on public.event_registration_settings to authenticated;
grant select, insert, update, delete on public.event_staff to authenticated;
-- The token/code hashes are never readable from the browser: only these columns are.
grant select (id, staff_id, event_id, failed_attempts, expires_at, created_at, last_used_at) on public.event_staff_grants to authenticated;
grant delete on public.event_staff_grants to authenticated;

-- ---- Question list validation ----
-- [{ id, type: 'text'|'choice', label, required, options: [..] }], at most 30.
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
    if q->>'type' = 'choice' then
      if jsonb_typeof(q->'options') <> 'array' or jsonb_array_length(q->'options') not between 2 and 20 then return false; end if;
      if exists (select 1 from jsonb_array_elements(q->'options') o
                 where jsonb_typeof(o.value) <> 'string' or char_length(btrim(o.value #>> '{}')) not between 1 and 100) then return false; end if;
    end if;
  end loop;
  return true;
end;
$$;

-- ---- Owner: create/update the registration settings of an event ----
-- Questions cannot change once someone has registered (answers would no longer match).
create or replace function public.set_event_registration(
  p_event uuid, p_enabled boolean, p_open boolean, p_deadline timestamptz,
  p_questions jsonb default null, p_columns jsonb default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_count integer;
begin
  if not public.owns_event(p_event) then raise exception 'Bu etkinliğin kayıtlarını yönetme yetkin yok.'; end if;
  if p_questions is not null and not public.registration_questions_ok(p_questions) then
    raise exception 'Form soruları geçersiz.';
  end if;
  if p_columns is not null and (jsonb_typeof(p_columns) <> 'array' or jsonb_array_length(p_columns) > 40) then
    raise exception 'Pano sütunları geçersiz.';
  end if;
  select questions into v_old from public.event_registration_settings where event_id = p_event;
  select count(*) into v_count from public.event_registrations where event_id = p_event;
  if p_questions is not null and v_count > 0 and v_old is distinct from p_questions then
    raise exception 'Kayıt gelmeye başladığı için form soruları artık değiştirilemez.';
  end if;
  insert into public.event_registration_settings as s (event_id, enabled, is_open, deadline, questions, board_columns, updated_at)
  values (p_event, coalesce(p_enabled, true), coalesce(p_open, true), p_deadline,
          coalesce(p_questions, '[]'::jsonb), coalesce(p_columns, '[]'::jsonb), now())
  on conflict (event_id) do update set
    enabled = coalesce(p_enabled, s.enabled),
    is_open = coalesce(p_open, s.is_open),
    deadline = p_deadline,
    questions = coalesce(p_questions, s.questions),
    board_columns = coalesce(p_columns, s.board_columns),
    updated_at = now();
end;
$$;

-- ---- Owner: mark a registration as checked in / not checked in from the board ----
create or replace function public.set_registration_checkin(p_registration uuid, p_checked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_event uuid;
begin
  select event_id into v_event from public.event_registrations where id = p_registration;
  if v_event is null or not public.owns_event(v_event) then raise exception 'Kayıt bulunamadı.'; end if;
  update public.event_registrations
     set checked_in_at = case when p_checked then coalesce(checked_in_at, now()) else null end,
         checked_in_by = case when p_checked then checked_in_by else null end
   where id = p_registration;
end;
$$;

-- Last moment of an event: end of its last day (Istanbul, UTC+03:00).
create or replace function public.event_ends_at(p_event uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select ((greatest(
            e.event_date,
            coalesce(e.end_date, e.event_date),
            coalesce((select max(o.date) from public.event_occurrences o where o.event_id = e.id), e.event_date)
          ) + 1)::timestamp at time zone 'Europe/Istanbul')
  from public.events e where e.id = p_event;
$$;

-- ---- Public: what the event page needs to show the form ----
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
    select count(*)::integer as n from public.event_registrations r where r.event_id = p_event
  )
  select case when not exists (select 1 from s) then jsonb_build_object('enabled', false)
  else (
    select jsonb_build_object(
      'enabled', true,
      'open', s.is_open and (s.deadline is null or now() < s.deadline)
              and (ev.capacity is null or c.n < ev.capacity) and now() < public.event_ends_at(ev.id),
      'reason', case
        when not s.is_open then 'closed'
        when now() >= public.event_ends_at(ev.id) then 'ended'
        when s.deadline is not null and now() >= s.deadline then 'deadline'
        when ev.capacity is not null and c.n >= ev.capacity then 'full'
        else null end,
      'deadline', s.deadline,
      'remaining', case when ev.capacity is null then null else greatest(ev.capacity - c.n, 0) end,
      'questions', s.questions)
    from s, ev, c)
  end;
$$;

-- ---- Public: register; returns the entry code ----
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

revoke all on function public.owns_event(uuid), public.owns_staff(uuid), public.set_event_registration(uuid, boolean, boolean, timestamptz, jsonb, jsonb),
  public.set_registration_checkin(uuid, boolean), public.event_ends_at(uuid), public.registration_questions_ok(jsonb) from public, anon;
grant execute on function public.owns_event(uuid), public.owns_staff(uuid), public.set_event_registration(uuid, boolean, boolean, timestamptz, jsonb, jsonb),
  public.set_registration_checkin(uuid, boolean), public.event_ends_at(uuid), public.registration_questions_ok(jsonb) to authenticated;
grant execute on function public.event_ends_at(uuid) to service_role;
grant execute on function public.public_event_registration(uuid), public.register_for_event(uuid, text, text, jsonb, boolean) to anon, authenticated;
