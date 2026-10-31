-- Kişisel yönetici hesapları (UniPakt ekibi) kendi adını ve profil fotoğrafını değiştirebilir (panel › Profil).
drop policy if exists profiles_admin_update_own on public.profiles;
create policy profiles_admin_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid()) and role = 'admin' and (select public.mfa_ok()))
  with check (id = (select auth.uid()) and role = 'admin' and full_name is not null
    and char_length(btrim(full_name)) between 1 and 120
    and (avatar_url is null or avatar_url ~ '^https://hcgotmcbwmleeklbvawb\.supabase\.co/storage/v1/object/public/profile-logos/[0-9a-f-]{36}/logo(\?v=[0-9]+)?$'));

-- The Story ekip kartları: @unipakt.com adresli yönetici hesaplarının profil fotoğrafı
-- (site kartı, kartın e-posta bağlantısıyla eşleştirir).
create or replace function public.public_team_photos()
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('email', lower(u.email), 'photo', p.avatar_url)), '[]'::jsonb)
    from public.profiles p join auth.users u on u.id = p.id
   where p.role = 'admin' and lower(u.email) like '%@unipakt.com' and lower(u.email) <> 'iletisim@unipakt.com'
     and p.avatar_url like 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/profile-logos/%';
$function$;
revoke all on function public.public_team_photos() from public;
grant execute on function public.public_team_photos() to anon, authenticated;
