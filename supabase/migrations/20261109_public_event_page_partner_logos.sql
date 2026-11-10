-- Etkinlik sayfası: onaylı ortak kulüplerin logoları da döner (partner_logos).
-- Canlı veritabanında 9 Kasım 2026'da uygulandı; repoda eksikti, 10 Kasım 2026'da canlıdaki
-- kayıttan geri alındı.
CREATE OR REPLACE FUNCTION public.public_event_page(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((
    select jsonb_build_object(
      'speakers', e.speakers,
      'design', e.design,
      'organizer_logo', (select p.avatar_url from public.profiles p
                          where e.club_id is not null and p.club_id = e.club_id and p.role = 'club'
                            and p.avatar_url like 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/profile-logos/%'
                          limit 1),
      -- Onaylı ortak kulüplerin logoları: { "<kulüp id>": "<logo url>" } (organizatör logosuyla aynı kural).
      'partner_logos', coalesce((select jsonb_object_agg(a.club_id::text, lg.url)
                          from public.event_applications a
                          cross join lateral (select p.avatar_url as url from public.profiles p
                                               where p.club_id = a.club_id and p.role = 'club'
                                                 and p.avatar_url like 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/profile-logos/%'
                                               limit 1) lg
                         where a.event_id = e.id and a.status = 'approved'), '{}'::jsonb))
      from public.events e
     where e.id = p_id and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on')), '{}'::jsonb);
$function$;
