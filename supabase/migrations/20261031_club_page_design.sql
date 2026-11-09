-- Kulüp sayfası özelleştirmesi (panel › Profil menüsü › Kulüp sayfası): üst alan görseli (banner)
-- ve tasarım (vurgu rengi, arka plan, başlık stili). Yalnızca kulüp başkanı kendi satırını değiştirir
-- (profiles_club_update_own_name politikası); değerler burada sınırlanır. Banner, profile-logos
-- kovasında <kullanıcı>/banner yolunda durur (1 MB, JPG/PNG/WebP).
alter table public.profiles add column if not exists page_banner text;
alter table public.profiles add column if not exists page_design jsonb;
alter table public.profiles drop constraint if exists profiles_page_banner_check;
alter table public.profiles add constraint profiles_page_banner_check check (
  page_banner is null or page_banner ~ '^https://hcgotmcbwmleeklbvawb\.supabase\.co/storage/v1/object/public/profile-logos/[0-9a-f-]{36}/banner(\?v=[0-9]+)?$');
alter table public.profiles drop constraint if exists profiles_page_design_check;
alter table public.profiles add constraint profiles_page_design_check check (
  page_design is null or (jsonb_typeof(page_design) = 'object' and octet_length(page_design::text) <= 600
    and coalesce(page_design->>'accent', '') ~ '^(#[0-9A-Fa-f]{6})?$'
    and coalesce(page_design->>'bgColor', '') ~ '^(#[0-9A-Fa-f]{6})?$'
    and coalesce(page_design->>'bg', 'default') in ('default', 'clear', 'blur', 'color', 'gradient')
    and coalesce(page_design->>'title', 'default') in ('default', 'left', 'compact', 'outline', 'caps', 'hand')));
grant select (page_banner, page_design), update (page_banner, page_design) on public.profiles to authenticated;

-- public_club_page: 'banner' ve 'design' alanları eklendi (geri kalanı aynı).
create or replace function public.public_club_page(p_id uuid)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select coalesce((
    select jsonb_build_object(
      'id', c.id, 'name', c.name, 'university', c.university, 'category', c.category,
      'contact', case when c.kvkk_consent_at is not null then jsonb_build_object(
          'email', c.email, 'instagram', c.instagram, 'linkedin', c.linkedin, 'x', c.x, 'tiktok', c.tiktok, 'web', c.web)
        else null end,
      'logo', (select p.avatar_url from public.profiles p
                where p.club_id = c.id and p.role = 'club'
                  and p.avatar_url like 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/profile-logos/%'
                limit 1),
      'bio', (select nullif(btrim(p.bio), '') from public.profiles p where p.club_id = c.id and p.role = 'club' limit 1),
      'banner', (select p.page_banner from public.profiles p where p.club_id = c.id and p.role = 'club' limit 1),
      'design', (select p.page_design from public.profiles p where p.club_id = c.id and p.role = 'club' limit 1),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', e.id, 'title', e.title, 'date', e.event_date, 'time', e.event_time, 'end_date', e.end_date,
                 'place', e.place, 'city', e.city, 'poster', e.poster_url, 'category', e.category,
                 'role', case when e.club_id = c.id then 'host' else 'partner' end)
               order by e.event_date desc, e.event_time desc nulls last)
          from public.events e
         where e.status = 'published' and coalesce(e.visible, true) and (e.kind = 'event' or e.calendar = 'on')
           and (e.club_id = c.id or exists (select 1 from public.event_applications a
                                             where a.event_id = e.id and a.club_id = c.id and a.status = 'approved'))), '[]'::jsonb))
      from public.clubs c
     where c.id = p_id and c.visible is not false), '{}'::jsonb);
$function$;
