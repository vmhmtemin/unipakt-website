-- İşlem kaydı: panelde kim, ne zaman, ne yaptı.
-- Satırlar tetikleyicilerle (panel kullanıcısının oturumu varken) ve servis
-- fonksiyonlarından (club-team, event-checkin) yazılır; kimse elle ekleyemez.
-- Kulüp başkanı kendi kulübünün ekibinin işlemlerini, UniPakt yetkilisi hepsini görür.
-- Saklama: 6 ay.

create table if not exists public.activity_log (
  id bigint generated always as identity primary key,
  club_id uuid references public.clubs(id) on delete cascade,
  actor_id uuid,
  actor_name text not null default '',
  actor_title text not null default '',
  action text not null,
  target text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists activity_log_club_idx on public.activity_log (club_id, created_at desc);
create index if not exists activity_log_created_idx on public.activity_log (created_at desc);
alter table public.activity_log enable row level security;
revoke all on public.activity_log from anon, authenticated;
grant select on public.activity_log to authenticated;
create policy activity_log_select on public.activity_log for select to authenticated using (
  (select public.is_admin())
  or (club_id = (select public.my_club())
      and coalesce((select pr.role = 'club' from public.profiles pr where pr.id = (select auth.uid())), false)));

-- Ortak yazıcı: işlemi yapan panel kullanıcısı (ya da servis fonksiyonunun verdiği kişi).
create or replace function public.log_activity(p_action text, p_target text, p_actor uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := coalesce(p_actor, (select auth.uid()));
  v_p public.profiles;
begin
  if v_actor is null then return; end if;
  select * into v_p from public.profiles where id = v_actor;
  if not found then return; end if;
  insert into public.activity_log (club_id, actor_id, actor_name, actor_title, action, target)
  values (v_p.club_id, v_actor,
          coalesce(nullif(btrim(v_p.full_name), ''), case v_p.role when 'admin' then 'UniPakt' else 'Kulüp hesabı' end),
          case v_p.role when 'admin' then 'UniPakt yetkilisi' when 'club' then 'Kulüp başkanı' else coalesce(v_p.member_title, 'Ekip üyesi') end,
          left(p_action, 120), left(coalesce(p_target, ''), 200));
end;
$$;
revoke all on function public.log_activity(text, text, uuid) from public, anon, authenticated;
grant execute on function public.log_activity(text, text, uuid) to service_role;

create or replace function public.activity_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_event text;
  v_action text;
  v_target text;
begin
  if (select auth.uid()) is null then return null; end if;   -- sistem işleri (cron, servis) yazılmaz
  if tg_op = 'DELETE' then r := old; else r := new; end if;

  if tg_table_name in ('event_edit_requests', 'event_applications', 'event_visibility_requests', 'event_registrations', 'event_registration_settings', 'event_staff_grants') then
    select e.title into v_event from public.events e where e.id = r.event_id;
    if v_event is null then return null; end if;   -- etkinlik silinirken zincirleme silinenler ayrıca yazılmaz
  end if;

  case tg_table_name
    when 'events' then
      v_target := r.title;
      v_action := case tg_op when 'INSERT' then 'Etkinlik oluşturdu' when 'DELETE' then 'Etkinliği sildi'
        else case when new.status is distinct from old.status and new.status = 'published' then 'Etkinliği onayladı'
                  when new.status is distinct from old.status and new.status = 'rejected' then 'Etkinliği reddetti'
                  when new.calendar is distinct from old.calendar and new.calendar = 'requested' then 'Takvim talebi gönderdi'
                  else 'Etkinliği düzenledi' end end;
    when 'event_edit_requests' then
      v_target := v_event;
      v_action := case tg_op when 'INSERT' then 'Düzenleme talebi gönderdi' else null end;
    when 'event_visibility_requests' then
      v_target := v_event;
      v_action := case tg_op when 'INSERT' then 'Görünürlük talebi gönderdi' else null end;
    when 'event_applications' then
      v_target := v_event;
      v_action := case tg_op when 'INSERT' then 'Ortak etkinliğe başvurdu' when 'DELETE' then 'Başvuruyu sildi'
        else case when new.status is distinct from old.status then
          case new.status when 'approved' then 'Ortaklık başvurusunu kabul etti' when 'rejected' then 'Ortaklık başvurusunu reddetti'
                          when 'removed' then 'Ortağı etkinlikten çıkardı' else 'Başvuruyu güncelledi' end end end;
    when 'announcements' then
      v_target := r.title;
      v_action := case tg_op when 'INSERT' then 'Duyuru gönderdi' when 'DELETE' then 'Duyuruyu kaldırdı' else null end;
    when 'event_registrations' then
      v_target := r.full_name || ' · ' || v_event;
      v_action := case tg_op when 'DELETE' then 'Kaydı sildi' when 'INSERT' then null
        else case when new.checked_in_at is distinct from old.checked_in_at then
                    case when new.checked_in_at is null then 'Girişi geri aldı' else 'Girişi işaretledi' end
                  when new.full_name is distinct from old.full_name or new.email is distinct from old.email or new.answers is distinct from old.answers then 'Kaydı düzenledi'
             end end;
    when 'event_registration_settings' then
      v_target := v_event;
      v_action := case when tg_op = 'INSERT' then 'Kayıt toplamayı açtı'
                       when tg_op = 'UPDATE' and new.enabled is distinct from old.enabled then case when new.enabled then 'Kayıt toplamayı açtı' else 'Kayıt toplamayı kapattı' end
                       when tg_op = 'UPDATE' and new.is_open is distinct from old.is_open then case when new.is_open then 'Kayıtları yeniden açtı' else 'Kayıtları kapattı' end
                       when tg_op = 'UPDATE' and (new.questions is distinct from old.questions or new.deadline is distinct from old.deadline) then 'Kayıt formunu güncelledi'
                  end;
    when 'event_staff' then
      v_target := r.full_name;
      v_action := case tg_op when 'INSERT' then 'Görevli ekledi' when 'DELETE' then 'Görevliyi sildi' else null end;
    when 'event_staff_grants' then
      v_target := coalesce((select s.full_name from public.event_staff s where s.id = r.staff_id), 'Görevli') || ' · ' || v_event;
      v_action := case tg_op when 'DELETE' then 'Görevli yetkisini geri aldı' else null end;
    when 'tasks' then
      v_target := r.title;
      v_action := case when tg_op = 'UPDATE' and new.status is distinct from old.status and new.status = 'done' then 'Görevi tamamladı'
                       when tg_op = 'UPDATE' and new.review_status is distinct from old.review_status and new.review_status = 'approved' then 'Görevi onayladı'
                       when tg_op = 'UPDATE' and new.review_status is distinct from old.review_status and new.review_status = 'rejected' then 'Görev kanıtını reddetti'
                  end;
    when 'support_tickets' then
      v_target := r.subject;
      v_action := case tg_op when 'INSERT' then 'Destek talebi açtı' else null end;
    else v_action := null;
  end case;

  if v_action is not null then perform public.log_activity(v_action, v_target); end if;
  return null;
end;
$$;
revoke all on function public.activity_trigger() from public, anon, authenticated;

do $do$
declare t text;
begin
  foreach t in array array['events', 'event_edit_requests', 'event_visibility_requests', 'event_applications', 'announcements',
                           'event_registrations', 'event_registration_settings', 'event_staff', 'event_staff_grants', 'tasks', 'support_tickets']
  loop
    execute format('drop trigger if exists activity_log on public.%I', t);
    execute format('create trigger activity_log after insert or update or delete on public.%I for each row execute function public.activity_trigger()', t);
  end loop;
end
$do$;

-- Saklama: 6 ay.
select cron.schedule('unipakt-activity-retention', '50 3 * * *', $cron$
  delete from public.activity_log where created_at < now() - interval '6 months';
$cron$);
