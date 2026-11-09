-- Etkinlik konuşmacıları: panelde ad + (isteğe bağlı) LinkedIn bağlantısı,
-- etkinlik sayfasında "Konuşmacılar" listesi; ada tıklayınca LinkedIn açılır.
--   events.speakers = [{ "name": "Ayşe Yılmaz", "linkedin": "https://www.linkedin.com/in/..." }, ...]

create or replace function public.event_speakers_ok(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p) = 'array'
     and jsonb_array_length(p) <= 30
     and not exists (
       select 1 from jsonb_array_elements(p) s
        where jsonb_typeof(s) <> 'object'
           or jsonb_typeof(s->'name') is distinct from 'string'
           or char_length(btrim(s->>'name')) not between 1 and 120
           or (s ? 'linkedin' and jsonb_typeof(s->'linkedin') not in ('string', 'null'))
           or (coalesce(s->>'linkedin', '') <> ''
               and (char_length(s->>'linkedin') > 300
                    or s->>'linkedin' !~* '^https://([a-z]{2,3}\.)?(www\.)?linkedin\.com/[^\s"''<>]+$'))
           or exists (select 1 from jsonb_object_keys(s) k where k not in ('name', 'linkedin'))
     );
$$;

alter table public.events add column if not exists speakers jsonb not null default '[]'::jsonb;
alter table public.events add constraint events_speakers_check check (public.event_speakers_ok(speakers));
grant select (speakers), insert (speakers), update (speakers) on public.events to authenticated;

-- submit_event: konuşmacıları da kaydeder (imza aynı).
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

  if not public.event_speakers_ok(coalesce(p_event->'speakers', '[]'::jsonb)) then
    raise exception 'Konuşmacı listesi geçersiz. Her konuşmacının adı olmalı; LinkedIn bağlantısı https://www.linkedin.com/... biçiminde olmalı.';
  end if;

  v_status := case when v_admin then 'published' else 'pending' end;

  insert into public.events (
    club_id, title, description, event_date, event_time, place, seeking,
    status, note, created_by, decided_at, kind, calendar,
    address, rules, poster_url, tags, registration_url, fee_type, fee_amount,
    university, visible,
    end_date, end_time, banner_url, city, biletimgo_url,
    instagram_url, facebook_url, x_url, youtube_url, capacity, category, speakers
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
    nullif(p_event->>'category',''),
    coalesce(p_event->'speakers', '[]'::jsonb)
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

-- Sitedeki etkinlik sayfası için (public_event ile aynı görünürlük kuralı).
create or replace function public.public_event_speakers(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select e.speakers from public.events e
                    where e.id = p_id and e.status = 'published' and (e.kind = 'event' or e.calendar = 'on')), '[]'::jsonb);
$$;
revoke all on function public.public_event_speakers(uuid), public.event_speakers_ok(jsonb) from public;
grant execute on function public.public_event_speakers(uuid) to anon, authenticated, service_role;
grant execute on function public.event_speakers_ok(jsonb) to authenticated, service_role;
