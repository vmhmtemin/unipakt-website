-- Birim hesapları da profil fotoğrafı yükleyebilir (profile-logos/<kendi id>/…).
drop policy if exists objects_perm_insert on storage.objects;
create policy objects_perm_insert on storage.objects as restrictive for insert to authenticated with check (
  case bucket_id
    when 'event-posters' then public.has_perm('events')
    when 'task-proofs' then public.has_perm('tasks')
    when 'support-attachments' then public.has_perm('support')
    when 'profile-logos' then coalesce((select pr.role in ('admin', 'club', 'unit') from public.profiles pr where pr.id = (select auth.uid())), false)
    else true end);
