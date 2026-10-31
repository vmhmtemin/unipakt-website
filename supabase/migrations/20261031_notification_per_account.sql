-- Bildirimler hesaba özel:
--  * Yöneticiler yalnızca yöneticilere giden bildirimleri görür (kulüplere gidenleri görmez).
--  * Kulüp hesapları (başkan + ekip) yalnızca kendi kulübünün bildirimlerini görür.
--  * "Okundu" ve "Sil" her hesap için ayrı tutulur (notification_states); biri okuyunca ya da
--    silince diğer yöneticilerin / ekip üyelerinin listesi değişmez.
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select to authenticated using (
  ((select public.is_admin()) and recipient_role = 'admin' and recipient_club_id is null)
  or (recipient_club_id is not null and recipient_club_id = (select public.my_club())));

drop policy if exists notifications_read on public.notifications;
drop policy if exists notifications_delete on public.notifications;

create table if not exists public.notification_states (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  read_at timestamptz,
  hidden_at timestamptz,
  primary key (notification_id, user_id)
);
alter table public.notification_states enable row level security;
drop policy if exists notification_states_own on public.notification_states;
create policy notification_states_own on public.notification_states for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid())
    and exists (select 1 from public.notifications n where n.id = notification_id));   -- yalnızca görebildiği bildirim
grant select, insert, update, delete on public.notification_states to authenticated;

-- Eski ortak "okundu" bilgisi: o ana kadar okunmuş sayılanlar herkes için okunmuş başlar.
-- (notifications.read_at artık yazılmaz; panel yalnızca okur.)
