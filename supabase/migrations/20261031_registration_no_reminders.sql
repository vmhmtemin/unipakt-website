-- Kayıt olan kişi "hatırlatma e-postası istemiyorum" diyebilir (formda kutucuk ya da
-- hatırlatma e-postasındaki bağlantı). İşaretliyse due_registration_reminders onu atlar.
alter table public.event_registration_pending add column if not exists no_reminders boolean not null default false;
alter table public.event_registrations add column if not exists no_reminders boolean not null default false;

drop function if exists public.start_event_registration(uuid, text, text, jsonb, boolean, text);
create function public.start_event_registration(p_event uuid, p_full_name text, p_email text, p_answers jsonb, p_consent boolean, p_ip_hash text, p_no_reminders boolean default false)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
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
  v_waitlist := exists (select 1 from public.event_registrations where event_id = p_event and status = 'waitlist')
    or (v_capacity is not null and public.registration_taken(p_event)
          + (select count(*) from public.event_registration_pending
              where event_id = p_event and not waitlist and expires_at > now() and email <> v_email) >= v_capacity);

  v_answers := public.registration_clean_answers(v_settings.questions, p_answers);

  delete from public.event_registration_pending where event_id = p_event and email = v_email;
  insert into public.event_registration_pending (event_id, full_name, email, answers, ip_hash, waitlist, no_reminders)
  values (p_event, v_name, v_email, v_answers, p_ip_hash, v_waitlist, coalesce(p_no_reminders, false))
  returning id into v_id;

  return jsonb_build_object('pending_id', v_id, 'full_name', v_name, 'email', v_email, 'event_title', v_title, 'waitlist', v_waitlist);
end;
$function$;
revoke all on function public.start_event_registration(uuid, text, text, jsonb, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.start_event_registration(uuid, text, text, jsonb, boolean, text, boolean) to service_role;

create or replace function public.confirm_event_registration(p_pending uuid)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
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

  insert into public.event_registrations (event_id, code, full_name, email, answers, status, no_reminders)
  values (v_p.event_id, v_code, v_p.full_name, v_p.email, v_p.answers, v_status, v_p.no_reminders)
  returning id into v_id;
  delete from public.event_registration_pending where id = p_pending;

  if v_status = 'waitlist' then
    select count(*) into v_pos from public.event_registrations where event_id = v_p.event_id and status = 'waitlist';
    return jsonb_build_object('status', 'waitlist', 'registration_id', v_id, 'position', v_pos, 'full_name', v_p.full_name, 'event_title', v_title, 'event_id', v_p.event_id);
  end if;
  return jsonb_build_object('status', 'confirmed', 'registration_id', v_id, 'code', v_code, 'full_name', v_p.full_name, 'event_title', v_title, 'event_id', v_p.event_id);
end;
$function$;

create or replace function public.due_registration_reminders(p_limit integer default 200)
 returns table(id uuid, event_id uuid, kind text, code text, full_name text, email text)
 language sql security definer set search_path to ''
as $function$
  with ev as (
    select e.id, public.event_starts_at(e.id) as starts, e.event_time is not null as timed, s.reminders
      from public.events e
      join public.event_registration_settings s on s.event_id = e.id and s.enabled
     where e.status = 'published' and cardinality(s.reminders) > 0
       and e.event_date between current_date - 1 and current_date + 2
  ), due as (
    select r.id, k.kind
      from ev
      cross join lateral unnest(ev.reminders) k(kind)
      join public.event_registrations r on r.event_id = ev.id and r.status = 'confirmed' and not r.no_reminders
                                      and not (k.kind = any(r.reminded))
     where (k.kind = '1d' and now() >= ev.starts - interval '24 hours' and now() < ev.starts - interval '2 hours'
              and r.created_at < ev.starts - interval '24 hours')
        or (k.kind = '2h' and ev.timed and now() >= ev.starts - interval '2 hours' and now() < ev.starts
              and r.created_at < ev.starts - interval '2 hours')
     limit greatest(1, least(coalesce(p_limit, 200), 500))
  )
  update public.event_registrations r
     set reminded = r.reminded || array[due.kind]
    from due
   where r.id = due.id
  returning r.id, r.event_id, due.kind, r.code, r.full_name, r.email;
$function$;
