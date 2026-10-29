-- Kulüp ekibi: başkan (role = 'club') panelden ek hesap davet eder (role = 'member').
-- Üyenin yetkileri profiles.permissions içinde:
--   events (etkinlik oluştur/düzenle, ortak arama, başvurular), registrations (kayıtlar,
--   özet, görevliler, giriş kontrolü), announcements, tasks, support, chat.
-- Ekip yönetimi ve kulüp profili yalnızca başkanda. Yetkiler sunucuda zorlanır:
--   * has_perm(p): admin ve başkan için her zaman true; üye için permissions içinde p.
--   * Yazma işlemlerine RESTRICTIVE kurallar (mevcut izin kurallarıyla birlikte "ve").
--   * Güvenlik tanımlı (security definer) fonksiyonların başına yetki kontrolü.
-- Üye profili (rol, kulüp, yetkiler) yalnızca club-team fonksiyonuyla değişir.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin', 'club', 'member'));
alter table public.profiles drop constraint if exists profiles_role_club;
alter table public.profiles add constraint profiles_role_club check (
  (role = 'admin' and club_id is null) or (role in ('club', 'member') and club_id is not null));
alter table public.profiles
  add column if not exists member_title text check (member_title is null or char_length(member_title) <= 60),
  add column if not exists permissions text[] not null default '{}'
    check (permissions <@ array['events', 'registrations', 'announcements', 'tasks', 'support', 'chat']::text[]),
  add column if not exists invited_by uuid references auth.users(id) on delete set null;
grant select (member_title, permissions) on public.profiles to authenticated;

create or replace function public.has_perm(p text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select case when pr.role in ('admin', 'club') then true
                               when pr.role = 'member' then p = any(pr.permissions)
                               else false end
                     from public.profiles pr where pr.id = (select auth.uid())), false)
     and public.mfa_ok();
$$;
revoke all on function public.has_perm(text) from public, anon;
grant execute on function public.has_perm(text) to authenticated, service_role;

-- Kayıtlar ve görevliler: kulübün olması yetmez, "registrations" yetkisi de gerekir.
create or replace function public.owns_event(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin()
      or (public.has_perm('registrations')
          and exists (select 1 from public.events e where e.id = p_event and e.club_id is not null and e.club_id = public.my_club()));
$$;
create or replace function public.owns_staff(p_club uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_club is null then public.is_admin()
              else public.has_perm('registrations') and p_club = public.my_club() end;
$$;

-- Yazma işlemleri için kısıtlayıcı kurallar.
create policy announcements_perm_insert on public.announcements as restrictive for insert to authenticated
  with check (public.has_perm('announcements'));
create policy events_perm_insert on public.events as restrictive for insert to authenticated with check (public.has_perm('events'));
create policy events_perm_update on public.events as restrictive for update to authenticated using (public.has_perm('events')) with check (public.has_perm('events'));
create policy events_perm_delete on public.events as restrictive for delete to authenticated using (public.has_perm('events'));
create policy event_occurrences_perm_insert on public.event_occurrences as restrictive for insert to authenticated with check (public.has_perm('events'));
create policy event_occurrences_perm_update on public.event_occurrences as restrictive for update to authenticated using (public.has_perm('events')) with check (public.has_perm('events'));
create policy event_occurrences_perm_delete on public.event_occurrences as restrictive for delete to authenticated using (public.has_perm('events'));
create policy event_edit_requests_perm_insert on public.event_edit_requests as restrictive for insert to authenticated with check (public.has_perm('events'));
create policy event_visibility_requests_perm_insert on public.event_visibility_requests as restrictive for insert to authenticated with check (public.has_perm('events'));
create policy objects_perm_insert on storage.objects as restrictive for insert to authenticated with check (
  case bucket_id
    when 'event-posters' then public.has_perm('events')
    when 'task-proofs' then public.has_perm('tasks')
    when 'support-attachments' then public.has_perm('support')
    when 'profile-logos' then coalesce((select pr.role in ('admin', 'club') from public.profiles pr where pr.id = (select auth.uid())), false)
    else true end);

-- Güvenlik tanımlı fonksiyonların başına yetki kontrolü (gövde aynen kalır).
do $do$
declare
  item record;
  d text;
begin
  for item in select * from (values
      ('public.submit_event(jsonb)', 'events'),
      ('public.submit_event_application(uuid,text)', 'events'),
      ('public.decide_event_application(uuid,text,text)', 'events'),
      ('public.remove_event_partner(uuid,uuid,text)', 'events'),
      ('public.delete_my_rejected_application(text,uuid,uuid)', 'events'),
      ('public.request_calendar(uuid)', 'events'),
      ('public.complete_task(uuid,text,text,text)', 'tasks'),
      ('public.support_create_ticket_v2(text,text,text,text,uuid,text,text)', 'support'),
      ('public.support_reply_ticket_v2(uuid,text)', 'support')) as t(sig, perm)
  loop
    d := pg_get_functiondef(item.sig::regprocedure);
    continue when position('has_perm(' in d) > 0;
    d := regexp_replace(d, E'\\nbegin\\n',
      E'\nbegin\n  if not public.has_perm(''' || item.perm || E''') then raise exception ''Bu işlem için yetkin yok. Kulüp başkanından yetki iste.''; end if;\n', 'i');
    execute d;
  end loop;
end
$do$;

-- Üye kendi rolünü / yetkilerini değiştiremez (yalnız servis rolü: club-team fonksiyonu).
create or replace function public.profiles_guard_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.role is distinct from old.role or new.club_id is distinct from old.club_id
          or new.permissions is distinct from old.permissions or new.member_title is distinct from old.member_title) then
    raise exception 'Rol ve yetkiler yalnızca ekip yönetiminden değiştirilir.';
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_guard_role on public.profiles;
create trigger profiles_guard_role before update on public.profiles for each row execute function public.profiles_guard_role();
