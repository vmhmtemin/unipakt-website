-- Applied to production on 2026-10-10.
-- Posters: the broad policies are narrowed to the club's own folder (or admin)
alter policy event_posters_authenticated_delete on storage.objects
  using (bucket_id = 'event-posters' and ((select public.is_admin()) or split_part(name,'/',1) = (select public.my_club())::text));
alter policy event_posters_authenticated_insert on storage.objects
  with check (bucket_id = 'event-posters' and ((select public.is_admin()) or split_part(name,'/',1) = (select public.my_club())::text));
alter policy event_posters_authenticated_update on storage.objects
  using (bucket_id = 'event-posters' and ((select public.is_admin()) or split_part(name,'/',1) = (select public.my_club())::text))
  with check (bucket_id = 'event-posters' and ((select public.is_admin()) or split_part(name,'/',1) = (select public.my_club())::text));

-- Occurrences: clubs may change dates only while their event is pending
alter policy event_occurrences_update on public.event_occurrences
  using ((select public.is_admin()) or exists (select 1 from public.events e where e.id = event_occurrences.event_id and e.club_id = (select public.my_club()) and e.status = 'pending'))
  with check ((select public.is_admin()) or exists (select 1 from public.events e where e.id = event_occurrences.event_id and e.club_id = (select public.my_club()) and e.status = 'pending'));
alter policy event_occurrences_delete on public.event_occurrences
  using ((select public.is_admin()) or exists (select 1 from public.events e where e.id = event_occurrences.event_id and e.club_id = (select public.my_club()) and e.status = 'pending'));

-- URL constraints
alter table public.events add constraint events_registration_url_http
  check (registration_url is null or registration_url = '' or registration_url ~ '^https?://[^[:space:]"''<>]+$');
alter table public.events add constraint events_poster_url_storage
  check (poster_url is null or poster_url = '' or poster_url like 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/event-posters/%');

-- Clubs cannot insert events straight into the calendar or hidden
alter policy events_club_insert on public.events
  with check ((select public.is_admin()) or (club_id = (select public.my_club()) and status = 'pending' and note is null and decided_at is null and calendar = 'none' and visible = true));

-- Anonymous visitors don't see hidden clubs
alter policy clubs_public_select on public.clubs using (visible is not false);

-- Support attachments: 5 MB, images/PDF only
update storage.buckets set file_size_limit = 5242880,
  allowed_mime_types = array['image/png','image/jpeg','image/webp','application/pdf']
where id = 'support-attachments';

-- Support tables are for logged-in users only
revoke all on public.support_tickets, public.support_ticket_messages from anon;
