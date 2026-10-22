-- 2026-10-22 — Etkinlik kategorisi (Mehmet'in kararı: ayrı sütun, kulüp kategorileriyle aynı liste)

alter table public.events add column if not exists category text;
alter table public.events drop constraint if exists events_category_check;
alter table public.events add constraint events_category_check check (
  category is null or category in ('Yazılım & Teknoloji','Tasarım & Medya','Girişim & Kariyer','Sosyal Sorumluluk','Sanat & Kültür','Spor & Outdoor','Yaşam & Hobi'));

create or replace function public.submit_event(p_event jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id uuid;
  v_club uuid := public.my_club();
  v_admin boolean := public.is_admin();
  v_status text;
  v_item jsonb;
begin
  if not v_admin and v_club is null then
    raise exception 'Bu işlem için kulüp hesabı gerekir.';
  end if;

  if coalesce(nullif(trim(p_event->>'title'), ''), '') = '' then
    raise exception 'Etkinlik adı gerekli.';
  end if;

  if p_event->>'fee_type' = 'paid'
     and coalesce(nullif(p_event->>'fee_amount','')::numeric, 0) <= 0 then
    raise exception 'Ücretli etkinlikte ücret tutarı 0''dan büyük olmalı.';
  end if;

  v_status := case when v_admin then 'published' else 'pending' end;

  insert into public.events (
    club_id, title, description, event_date, event_time, place, seeking,
    status, note, created_by, decided_at, kind, calendar,
    address, rules, poster_url, tags, registration_url, fee_type, fee_amount,
    university, visible,
    end_date, end_time, banner_url, city, biletimgo_url,
    instagram_url, facebook_url, x_url, youtube_url, capacity, category
  )
  values (
    case when v_admin then null else v_club end,
    p_event->>'title',
    coalesce(p_event->>'description',''),
    ((p_event->'occurrences'->0)->>'date')::date,
    nullif((p_event->'occurrences'->0)->>'time','')::time,
    nullif(p_event->>'place',''),
    nullif(p_event->>'seeking',''),
    v_status,
    null,
    auth.uid(),
    case when v_admin then now() else null end,
    coalesce(nullif(p_event->>'kind',''),'event'),
    case when v_admin then
      case when coalesce(p_event->>'kind','event') = 'event' then 'on' else 'none' end
    else 'none' end,
    nullif(p_event->>'address',''),
    nullif(p_event->>'rules',''),
    nullif(p_event->>'poster_url',''),
    coalesce(array(select jsonb_array_elements_text(coalesce(p_event->'tags','[]'::jsonb))), '{}'),
    nullif(p_event->>'registration_url',''),
    case when p_event->>'fee_type' = 'paid' then 'paid' else 'free' end,
    case when p_event->>'fee_type' = 'paid' then nullif(p_event->>'fee_amount','')::numeric else null end,
    nullif(p_event->>'university',''),
    coalesce((p_event->>'visible')::boolean, true),
    nullif(p_event->>'end_date','')::date,
    nullif(p_event->>'end_time','')::time,
    nullif(p_event->>'banner_url',''),
    nullif(trim(p_event->>'city'),''),
    nullif(p_event->>'biletimgo_url',''),
    nullif(p_event->>'instagram_url',''),
    nullif(p_event->>'facebook_url',''),
    nullif(p_event->>'x_url',''),
    nullif(p_event->>'youtube_url',''),
    nullif(p_event->>'capacity','')::integer,
    nullif(p_event->>'category','')
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(coalesce(p_event->'occurrences','[]'::jsonb))
  loop
    insert into public.event_occurrences(event_id, date, time)
    values (v_id, (v_item->>'date')::date, nullif(v_item->>'time','')::time);
  end loop;

  return v_id;
end;
$function$;

revoke all on function public.submit_event(jsonb) from public, anon;
grant execute on function public.submit_event(jsonb) to authenticated;

-- Dönüş tipi değiştiği için drop + create.
drop function if exists public.public_events();
create function public.public_events()
 returns table(
   id uuid, title text, description text, event_date date, event_time time without time zone,
   place text, address text, rules text, poster_url text, tags text[], registration_url text,
   fee_type text, fee_amount numeric, kind text, organizer_id uuid, organizer text,
   university text, occurrences jsonb,
   end_date date, end_time time without time zone, banner_url text, city text,
   biletimgo_url text, instagram_url text, facebook_url text, x_url text, youtube_url text,
   capacity integer, category text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select e.id,e.title,e.description,e.event_date,e.event_time,e.place,e.address,e.rules,e.poster_url,e.tags,e.registration_url,e.fee_type,e.fee_amount,e.kind,
    c.id as organizer_id,
    coalesce(nullif(e.university,''),c.university,'UniPakt') ||
      coalesce((select ', '||string_agg(distinct coalesce(pc.university,pc.name), ', ' order by coalesce(pc.university,pc.name)) from public.event_applications pa join public.clubs pc on pc.id=pa.club_id where pa.event_id=e.id and pa.status='approved'),'') as organizer,
    coalesce(nullif(e.university,''),c.university) as university,
    coalesce((select jsonb_agg(jsonb_build_object('date',o.date,'time',o.time) order by o.date,o.time) from public.event_occurrences o where o.event_id=e.id),jsonb_build_array(jsonb_build_object('date',e.event_date,'time',e.event_time))) as occurrences,
    e.end_date,e.end_time,e.banner_url,e.city,e.biletimgo_url,e.instagram_url,e.facebook_url,e.x_url,e.youtube_url,e.capacity,e.category
  from public.events e left join public.clubs c on c.id=e.club_id
  where e.status='published' and coalesce(e.visible,true)<>false and (e.kind='event' or e.calendar='on')
  order by e.event_date,e.event_time,e.created_at;
$function$;
revoke all on function public.public_events() from public;
grant execute on function public.public_events() to anon, authenticated, service_role;

drop function if exists public.public_event(uuid);
create function public.public_event(p_id uuid)
 returns table(
   id uuid, title text, description text, event_date date, event_time time without time zone,
   place text, address text, rules text, poster_url text, tags text[], registration_url text,
   fee_type text, fee_amount numeric, kind text, organizer_id uuid, organizer_name text,
   organizer text, university text, occurrences jsonb,
   end_date date, end_time time without time zone, banner_url text, city text,
   biletimgo_url text, instagram_url text, facebook_url text, x_url text, youtube_url text,
   capacity integer, partners jsonb, category text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select e.id,e.title,e.description,e.event_date,e.event_time,e.place,e.address,e.rules,e.poster_url,e.tags,e.registration_url,e.fee_type,e.fee_amount,e.kind,
    c.id as organizer_id,
    coalesce(c.name,'UniPakt') as organizer_name,
    coalesce(nullif(e.university,''),c.university,'UniPakt') ||
      coalesce((select ', '||string_agg(distinct coalesce(pc.university,pc.name), ', ' order by coalesce(pc.university,pc.name)) from public.event_applications pa join public.clubs pc on pc.id=pa.club_id where pa.event_id=e.id and pa.status='approved'),'') as organizer,
    coalesce(nullif(e.university,''),c.university) as university,
    coalesce((select jsonb_agg(jsonb_build_object('date',o.date,'time',o.time) order by o.date,o.time) from public.event_occurrences o where o.event_id=e.id),jsonb_build_array(jsonb_build_object('date',e.event_date,'time',e.event_time))) as occurrences,
    e.end_date,e.end_time,e.banner_url,e.city,e.biletimgo_url,e.instagram_url,e.facebook_url,e.x_url,e.youtube_url,e.capacity,
    coalesce((select jsonb_agg(jsonb_build_object('id',pc.id,'name',pc.name,'university',pc.university) order by pc.name)
                from public.event_applications pa join public.clubs pc on pc.id=pa.club_id
               where pa.event_id=e.id and pa.status='approved'),'[]'::jsonb) as partners,
    e.category
  from public.events e left join public.clubs c on c.id=e.club_id
  where e.id = p_id and e.status='published' and (e.kind='event' or e.calendar='on')
  limit 1;
$function$;
revoke all on function public.public_event(uuid) from public;
grant execute on function public.public_event(uuid) to anon, authenticated, service_role;
