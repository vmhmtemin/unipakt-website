-- ============================================================
-- UniPakt Panel — etkinlik türleri ve takvime alma
-- (schema.sql ve 02'den SONRA çalıştırın. 03'ü çalıştırmadıysanız
--  gerek yok: bu dosya 03'ün yaptığını da içerir.)
--
-- İki tür etkinlik var:
--   event   : düz etkinlik. Onaylanınca doğrudan takvime düşer.
--   partner : ortak arayan etkinlik. Onaylanınca Ortak Arama sayfasına düşer;
--             takvime ancak UniPakt "yayına alırsa" girer.
-- calendar sütunu ortak arayan etkinliğin takvim durumudur:
--   none (takvimde değil) / requested (kulüp talep etti) / on (takvimde)
-- Tekrar çalıştırmak güvenlidir.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'events' and column_name = 'kind') then
    alter table public.events
      add column kind text not null default 'partner' check (kind in ('event', 'partner')),
      add column calendar text not null default 'none' check (calendar in ('none', 'requested', 'on'));
    -- Bugüne kadar yayınlanan etkinlikler takvimde görünüyordu; öyle kalsınlar.
    update public.events set calendar = 'on' where status = 'published';
  end if;
end $$;

-- Kulüp etkinliği kendisi takvime koyamaz: eklerken takvim durumu "none" olmalı.
drop policy if exists events_club_insert on public.events;
create policy events_club_insert on public.events for insert to authenticated
  with check (
    club_id = (select public.my_club()) and status = 'pending' and calendar = 'none'
    and note is null and decided_at is null
  );

-- Kulübün kendi ortak arama etkinliği için "yayına alma talebi".
create or replace function public.request_calendar(p_event uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.events
     set calendar = 'requested'
   where id = p_event and club_id = public.my_club()
     and status = 'published' and kind = 'partner' and calendar = 'none';
  if not found then
    raise exception 'Bu etkinlik için talep gönderilemiyor.';
  end if;
end;
$$;
revoke execute on function public.request_calendar(uuid) from public, anon;
grant execute on function public.request_calendar(uuid) to authenticated;

-- Sitedeki herkese açık takvim: yalnızca takvimdeki etkinlikler.
create or replace function public.public_events()
returns table (id uuid, title text, description text, event_date date, event_time time, place text, organizer text)
language sql stable security definer set search_path = '' as $$
  select e.id, e.title, e.description, e.event_date, e.event_time, e.place, coalesce(c.name, 'UniPakt')
    from public.events e
    left join public.clubs c on c.id = e.club_id
   where e.status = 'published' and (e.kind = 'event' or e.calendar = 'on')
   order by e.event_date, e.event_time nulls first
$$;
revoke execute on function public.public_events() from public;
grant execute on function public.public_events() to anon, authenticated;
