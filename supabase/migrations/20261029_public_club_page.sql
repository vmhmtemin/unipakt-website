-- Sitedeki kulüp sayfası (/kulup/?id=…): kulübün adı, üniversitesi, kategorisi; iletişim
-- bilgileri yalnızca KVKK onayı varsa (public_clubs ile aynı kural); panel profilindeki
-- logo ve kısa tanıtım; kulübün düzenlediği ya da ortak olduğu yayındaki etkinlikler.
create or replace function public.public_club_page(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke all on function public.public_club_page(uuid) from public;
grant execute on function public.public_club_page(uuid) to anon, authenticated, service_role;
