-- Etkinlik hatırlatma e-postaları. Kulüp kayıt ayarlarında seçer:
--   '1d' — etkinlikten 1 gün önce, '2h' — 2 saat önce (etkinlik saati varsa).
-- event-register fonksiyonunun 10 dakikalık "sweep" işi due_registration_reminders()
-- ile zamanı gelenleri alır (alırken işaretler, aynı hatırlatma iki kez gitmez).
-- Etkinlik saatinden sonra kayıt olan kişiye o pencerenin hatırlatması gitmez.

alter table public.event_registration_settings
  add column if not exists reminders text[] not null default '{1d}'
    check (reminders <@ array['1d', '2h']::text[]);
alter table public.event_registrations
  add column if not exists reminded text[] not null default '{}';
grant select (reminders) on public.event_registration_settings to authenticated;

create or replace function public.event_starts_at(p_event uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select (e.event_date + coalesce(e.event_time, time '09:00')) at time zone 'Europe/Istanbul'
    from public.events e where e.id = p_event;
$$;
revoke all on function public.event_starts_at(uuid) from public, anon;
grant execute on function public.event_starts_at(uuid) to authenticated, service_role;

create or replace function public.set_registration_reminders(p_event uuid, p_reminders text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clean text[] := array(select k from unnest(array['1d', '2h']) k where k = any(coalesce(p_reminders, '{}')));
  v_old text[];
  v_title text;
begin
  if not public.owns_event(p_event) then raise exception 'Bu etkinliğin kayıtlarını yönetme yetkin yok.'; end if;
  select reminders into v_old from public.event_registration_settings where event_id = p_event;
  if not found then raise exception 'Önce kayıt toplamayı aç.'; end if;
  if v_old is not distinct from v_clean then return; end if;
  update public.event_registration_settings set reminders = v_clean, updated_at = now() where event_id = p_event;
  select title into v_title from public.events where id = p_event;
  perform public.log_activity(case when cardinality(v_clean) = 0 then 'Hatırlatma e-postalarını kapattı' else 'Hatırlatma e-postalarını değiştirdi' end, v_title);
end;
$$;
revoke all on function public.set_registration_reminders(uuid, text[]) from public, anon;
grant execute on function public.set_registration_reminders(uuid, text[]) to authenticated;

-- Zamanı gelen hatırlatmalar (yalnız event-register fonksiyonu çağırır).
--   1d penceresi: başlangıçtan 24 saat önce → 2 saat öncesine kadar
--   2h penceresi: başlangıçtan 2 saat önce → başlangıca kadar (saat girilmişse)
create or replace function public.due_registration_reminders(p_limit integer default 200)
returns table (id uuid, event_id uuid, kind text, code text, full_name text, email text)
language sql
volatile
security definer
set search_path = ''
as $$
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
      join public.event_registrations r on r.event_id = ev.id and r.status = 'confirmed' and not (k.kind = any(r.reminded))
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
$$;
revoke all on function public.due_registration_reminders(integer) from public, anon, authenticated;
grant execute on function public.due_registration_reminders(integer) to service_role;
