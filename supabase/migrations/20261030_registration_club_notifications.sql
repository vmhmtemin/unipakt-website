-- Kulübe kayıt bildirimleri (panel Bildirimler + e-posta, send-email-notifications ile):
--   * registration_full   — kontenjan dolunca bir kez (sonrası bekleme listesine düşer)
--   * registration_digest — kayıt gelen günlerde akşam 20:00'de (İstanbul) günün özeti
-- E-posta alıcıları fonksiyonda: kulüp başkanı + ilgili yetkisi olan ekip üyeleri.

alter table public.event_registration_settings
  add column if not exists full_notified_at timestamptz;

create or replace function public.notify_registration_full()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ev record;
  v_taken integer;
begin
  if new.status not in ('confirmed', 'offered') then return null; end if;
  select e.id, e.title, e.capacity, e.club_id into v_ev from public.events e where e.id = new.event_id;
  if v_ev.capacity is null then return null; end if;
  if exists (select 1 from public.event_registration_settings s where s.event_id = new.event_id and s.full_notified_at is not null) then return null; end if;
  select count(*) into v_taken from public.event_registrations r where r.event_id = new.event_id and r.status in ('confirmed', 'offered');
  if v_taken < v_ev.capacity then return null; end if;
  update public.event_registration_settings set full_notified_at = now() where event_id = new.event_id and full_notified_at is null;
  if not found then return null; end if;
  if v_ev.club_id is null then
    perform public.push_admin_notification('Kontenjan doldu',
      '“' || v_ev.title || '” etkinliğinin kontenjanı (' || v_ev.capacity || ') doldu. Yeni gelenler bekleme listesine alınıyor.',
      'registration_full', v_ev.id, null, null);
  else
    perform public.push_notification(v_ev.club_id, 'Kontenjan doldu',
      '“' || v_ev.title || '” etkinliğinin kontenjanı (' || v_ev.capacity || ') doldu. Yeni gelenler bekleme listesine alınıyor; kayıt silinirse yer sıradakine teklif edilir.',
      'registration_full', v_ev.id, null, null, false, true);
  end if;
  return null;
end;
$$;
revoke all on function public.notify_registration_full() from public, anon, authenticated;
drop trigger if exists notify_registration_full on public.event_registrations;
create trigger notify_registration_full after insert or update of status on public.event_registrations
  for each row execute function public.notify_registration_full();

-- Günün kayıt özeti: son 24 saatte kayıt gelen her kulübe tek bildirim.
create or replace function public.send_registration_digest()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
  v_sent integer := 0;
begin
  for c in
    select e.club_id,
           sum(x.new_count) as total_new,
           string_agg('• ' || e.title || ': +' || x.new_count || ' yeni kayıt (' || x.confirmed
                      || coalesce(' / ' || e.capacity, '') || ' kesin'
                      || case when x.waiting > 0 then ', ' || x.waiting || ' bekleme listesinde' else '' end || ')',
                      E'\n' order by e.event_date) as lines
      from public.events e
      join lateral (
        select count(*) filter (where r.created_at > now() - interval '24 hours') as new_count,
               count(*) filter (where r.status = 'confirmed') as confirmed,
               count(*) filter (where r.status in ('waitlist', 'offered')) as waiting
          from public.event_registrations r where r.event_id = e.id
      ) x on x.new_count > 0
     where e.club_id is not null
     group by e.club_id
  loop
    perform public.push_notification(c.club_id, 'Bugün ' || c.total_new || ' yeni kayıt',
      'Bugünkü kayıt özeti:' || E'\n' || c.lines || E'\n\n' || 'Ayrıntılar panelde Etkinliklerim → Kayıtlar’da.',
      'registration_digest', null, null, null, false, true);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;
revoke all on function public.send_registration_digest() from public, anon, authenticated;

select cron.schedule('unipakt-registration-digest', '0 17 * * *', $cron$ select public.send_registration_digest(); $cron$);
