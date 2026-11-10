-- Kişiye özel ortaklık teklifi: etkinlik sahibi bir kulüp hesabına teklif gönderir,
-- karşı taraf bildirimden kabul ya da reddeder.
--
-- Canlı veritabanında 4 Kasım 2026'da uygulanmış iki migration'ın kaydı (partnership_offers +
-- partnership_offer_response_status). Repoda eksikti; 10 Kasım 2026'da canlıdaki kayıttan
-- geri alındı. respond_partnership_offer'ın yalnızca son (düzeltilmiş) hali yazıldı.

create or replace function public.send_partnership_offer(
  p_event uuid,
  p_recipient uuid,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner uuid;
  v_event_title text;
  v_target_club uuid;
  v_target_role text;
  v_target_name text;
  v_notification uuid;
begin
  if auth.uid() is null then raise exception 'Oturum açmalısın.'; end if;
  if not public.has_perm('events') then raise exception 'Bu işlem için yetkin yok. Kulüp başkanından yetki iste.'; end if;
  if coalesce(btrim(p_note), '') = '' or char_length(p_note) > 500 then
    raise exception 'Teklif mesajı 1–500 karakter olmalı.';
  end if;

  select e.club_id, e.title into v_owner, v_event_title
    from public.events e
   where e.id = p_event and e.status in ('published', 'pending');
  if not found then raise exception 'Etkinlik bulunamadı veya artık teklif almıyor.'; end if;
  if not (public.is_admin() or v_owner = public.my_club()) then
    raise exception 'Yalnızca etkinlik sahibi ortaklık teklifi gönderebilir.';
  end if;

  select p.club_id, p.role, p.full_name
    into v_target_club, v_target_role, v_target_name
    from public.profiles p
   where p.id = p_recipient and p.role in ('club', 'member') and p.club_id is not null;
  if not found then raise exception 'Teklif gönderilecek aktif kulüp hesabı bulunamadı.'; end if;
  if p_recipient = auth.uid() or v_target_club = coalesce(v_owner, public.my_club()) then
    raise exception 'Kendi kulübüne ortaklık teklifi gönderemezsin.';
  end if;
  if exists (
    select 1 from public.event_applications a
     where a.event_id = p_event and a.club_id = v_target_club and a.status = 'approved'
  ) then raise exception 'Bu kulüp etkinliğe zaten ortak.'; end if;
  if exists (
    select 1 from public.notifications n
     where n.event_id = p_event and n.recipient_user_id = p_recipient
       and n.type = 'partnership_offer' and n.actionable and not n.resolved
  ) then raise exception 'Bu kişiye zaten bekleyen bir teklif gönderdin.'; end if;

  insert into public.notifications (
    recipient_club_id, recipient_user_id, recipient_role, type, title, body,
    event_id, actionable, resolved
  ) values (
    null, p_recipient, 'club', 'partnership_offer',
    'Ortaklık teklifi: ' || left(v_event_title, 130),
    left('“' || v_event_title || '” etkinliği için sana ortaklık teklifi gönderildi.' || E'\n\n' || btrim(p_note), 1000),
    p_event, true, false
  ) returning id into v_notification;

  return v_notification;
end;
$function$;

revoke all on function public.send_partnership_offer(uuid, uuid, text) from public, anon;
grant execute on function public.send_partnership_offer(uuid, uuid, text) to authenticated;

create or replace function public.respond_partnership_offer(
  p_notification uuid,
  p_accept boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event uuid;
  v_body text;
  v_owner uuid;
  v_event_title text;
  v_target_club uuid;
  v_target_name text;
  v_application uuid;
  v_application_status text;
begin
  if auth.uid() is null then raise exception 'Oturum açmalısın.'; end if;
  if p_accept is null then raise exception 'Teklif yanıtını seç.'; end if;

  select n.event_id, n.body
    into v_event, v_body
    from public.notifications n
   where n.id = p_notification
     and n.recipient_user_id = auth.uid()
     and n.type = 'partnership_offer'
     and n.actionable = true
     and n.resolved = false
   for update;
  if not found then raise exception 'Bu teklif artık yanıtlanamıyor.'; end if;

  select p.club_id, coalesce(p.full_name, c.name)
    into v_target_club, v_target_name
    from public.profiles p
    left join public.clubs c on c.id = p.club_id
   where p.id = auth.uid() and p.role in ('club', 'member') and p.club_id is not null;
  if not found then raise exception 'Bu teklif yalnızca bir kulüp hesabıyla yanıtlanabilir.'; end if;

  select e.club_id, e.title
    into v_owner, v_event_title
    from public.events e
   where e.id = v_event and e.status in ('published', 'pending');
  if not found then raise exception 'Etkinlik artık yanıtlanamıyor.'; end if;
  if v_owner is not null and v_target_club = v_owner then
    raise exception 'Kendi kulübünün etkinliğine ortak olamazsın.';
  end if;

  if p_accept then
    select a.id, a.status
      into v_application, v_application_status
      from public.event_applications a
     where a.event_id = v_event and a.club_id = v_target_club
     for update;
    if found then
      if v_application_status <> 'approved' then
        update public.event_applications
           set status = 'approved', note = 'Kişiye özel ortaklık teklifi kabul edildi.', decided_at = now()
         where id = v_application;
      end if;
    else
      insert into public.event_applications(event_id, club_id, note, status, decided_at)
      values (v_event, v_target_club, 'Kişiye özel ortaklık teklifi kabul edildi.', 'approved', now())
      returning id into v_application;
    end if;

    update public.notifications
       set title = 'Ortaklık teklifini kabul ettin',
           body = '“' || v_event_title || '” etkinliğinde ortak oldun.',
           application_id = v_application,
           actionable = false, resolved = true, read_at = coalesce(read_at, now())
     where id = p_notification;

    if v_owner is null then
      perform public.push_admin_notification(
        'Ortaklık teklifin kabul edildi',
        coalesce(v_target_name, 'Bir kulüp') || ' “' || v_event_title || '” etkinliğin için gönderdiğin teklifi kabul etti.',
        'partnership_offer_response', v_event, null, null
      );
    else
      perform public.push_notification(
        v_owner,
        'Ortaklık teklifin kabul edildi',
        coalesce(v_target_name, 'Bir kulüp') || ' “' || v_event_title || '” etkinliğin için gönderdiğin teklifi kabul etti.',
        'partnership_offer_response', v_event, null, null, false, true
      );
    end if;
  else
    update public.notifications
       set title = 'Ortaklık teklifini reddettin',
           body = '“' || v_event_title || '” etkinliği için gönderilen teklifi reddettin.',
           actionable = false, resolved = true, read_at = coalesce(read_at, now())
     where id = p_notification;

    if v_owner is null then
      perform public.push_admin_notification(
        'Ortaklık teklifin reddedildi',
        coalesce(v_target_name, 'Bir kulüp') || ' “' || v_event_title || '” etkinliğin için gönderdiğin teklifi reddetti.',
        'partnership_offer_response', v_event, null, null
      );
    else
      perform public.push_notification(
        v_owner,
        'Ortaklık teklifin reddedildi',
        coalesce(v_target_name, 'Bir kulüp') || ' “' || v_event_title || '” etkinliğin için gönderdiğin teklifi reddetti.',
        'partnership_offer_response', v_event, null, null, false, true
      );
    end if;
  end if;

  return coalesce(v_application, p_notification);
end;
$function$;

revoke all on function public.respond_partnership_offer(uuid, boolean) from public, anon;
grant execute on function public.respond_partnership_offer(uuid, boolean) to authenticated;
