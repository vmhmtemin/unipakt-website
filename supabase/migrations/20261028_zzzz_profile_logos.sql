-- Public club profile logos used in the authenticated panel and club chats.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-logos', 'profile-logos', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists profile_logos_insert_own on storage.objects;
create policy profile_logos_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-logos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists profile_logos_select_own on storage.objects;
create policy profile_logos_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'profile-logos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists profile_logos_update_own on storage.objects;
create policy profile_logos_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-logos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'profile-logos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

commit;
