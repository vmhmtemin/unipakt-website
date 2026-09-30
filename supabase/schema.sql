-- ============================================================
-- UniPakt Panel — veritabanı şeması
-- Supabase > SQL Editor'e yapıştırıp bir kez çalıştırın.
-- Tekrar çalıştırmak güvenlidir; var olan veriyi silmez.
--
-- Roller
--   admin : UniPakt yetkilisi. Her şeyi görür, onaylar, görev atar, puan verir.
--   club  : Kulüp başkanı. Yayındaki içeriği ve yalnızca kendi kulübünün
--           başvurularını, görevlerini ve puan kayıtlarını görür.
-- Profili olmayan bir hesap (ör. kendi kendine kaydolan biri) hiçbir şey göremez.
-- ============================================================

-- ---------- Tablolar ----------

create table if not exists public.clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 120),
  university  text not null check (char_length(university) between 1 and 120),
  created_at  timestamptz not null default now()
);

-- auth.users içindeki her hesap için bir satır. Rolü ve kulübü burası belirler.
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        text not null check (role in ('admin', 'club')),
  club_id     uuid references public.clubs (id) on delete cascade,
  full_name   text check (char_length(full_name) <= 120),
  created_at  timestamptz not null default now(),
  constraint profiles_role_club check (
    (role = 'admin' and club_id is null) or (role = 'club' and club_id is not null)
  )
);

-- club_id boş ise duyuruyu UniPakt yayınlamıştır.
create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid references public.clubs (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 120),
  body        text not null check (char_length(body) between 1 and 1500),
  status      text not null default 'pending' check (status in ('pending', 'published', 'rejected')),
  note        text check (char_length(note) <= 400),          -- ret notu
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);

-- Ortak aranan etkinlikler. club_id boş ise etkinlik UniPakt'ındır.
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid references public.clubs (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 120),
  description text not null check (char_length(description) between 1 and 1200),
  event_date  date not null,
  event_time  time,
  place       text check (char_length(place) <= 120),
  seeking     text check (char_length(seeking) <= 200),
  status      text not null default 'pending' check (status in ('pending', 'published', 'rejected')),
  note        text check (char_length(note) <= 400),
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);

-- Bir kulübün bir etkinliğe ortak olma başvurusu. UniPakt onaylar.
create table if not exists public.event_applications (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events (id) on delete cascade,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  note        text not null check (char_length(note) between 1 and 500),
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  unique (event_id, club_id)
);

create table if not exists public.tasks (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 120),
  description text check (char_length(description) <= 1000),
  due_date    date,
  status      text not null default 'open' check (status in ('open', 'done')),
  proof_text  text check (char_length(proof_text) <= 1500),
  proof_path  text,                                           -- task-proofs deposundaki dosya yolu
  proof_name  text check (char_length(proof_name) <= 120),
  done_at     timestamptz,
  created_at  timestamptz not null default now()
);

-- Vanguard: her artı / eksi puan bir kayıttır, toplam bunlardan hesaplanır.
create table if not exists public.point_entries (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  event_id    uuid references public.events (id) on delete set null,
  label       text not null check (char_length(label) between 1 and 120),  -- etkinlik adı ya da "Etkinlik dışı"
  delta       integer not null check (delta <> 0),
  note        text check (char_length(note) <= 120),
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists profiles_club_idx            on public.profiles (club_id);
create index if not exists announcements_status_idx     on public.announcements (status, created_at desc);
create index if not exists announcements_club_idx       on public.announcements (club_id);
create index if not exists events_status_date_idx       on public.events (status, event_date);
create index if not exists events_club_idx              on public.events (club_id);
create index if not exists event_applications_club_idx  on public.event_applications (club_id);
create index if not exists tasks_club_idx               on public.tasks (club_id, status);
create index if not exists point_entries_club_idx       on public.point_entries (club_id);
create index if not exists point_entries_event_idx      on public.point_entries (event_id);

-- ---------- Yardımcı fonksiyonlar ----------
-- security definer: profiles tablosunu, o tablonun kendi kurallarına takılmadan okur.

create or replace function public.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = (select auth.uid())
$$;

create or replace function public.my_club() returns uuid
language sql stable security definer set search_path = '' as $$
  select club_id from public.profiles where id = (select auth.uid())
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_role() = 'admin', false)
$$;

-- Kulübün kendi görevini kanıtıyla kapatması. Kulüpler tasks tablosunu doğrudan
-- güncelleyemez; başlığı, son tarihi ya da başka kulübün görevini değiştiremezler.
create or replace function public.complete_task(
  p_task uuid, p_text text, p_path text default null, p_name text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_club uuid := public.my_club();
begin
  if v_club is null then
    raise exception 'Bu işlem için kulüp hesabı gerekir.';
  end if;
  if coalesce(btrim(p_text), '') = '' and p_path is null then
    raise exception 'Bir mesaj ya da dosya gerekli.';
  end if;
  if p_path is not null and split_part(p_path, '/', 1) <> v_club::text then
    raise exception 'Dosya yolu bu kulübe ait değil.';
  end if;
  update public.tasks
     set status = 'done', proof_text = nullif(btrim(p_text), ''),
         proof_path = p_path, proof_name = left(p_name, 120), done_at = now()
   where id = p_task and club_id = v_club and status = 'open';
  if not found then
    raise exception 'Görev bulunamadı ya da zaten tamamlanmış.';
  end if;
end;
$$;

-- Sıralama: kulüpler birbirinin puan kayıtlarını göremez, yalnızca toplamları görür.
create or replace function public.leaderboard()
returns table (club_id uuid, name text, university text, points bigint)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, c.university, coalesce(sum(p.delta), 0)::bigint as points
    from public.clubs c
    left join public.point_entries p on p.club_id = c.id
   where public.my_role() is not null
   group by c.id
   order by 4 desc, c.name
$$;

revoke execute on function public.my_role(), public.my_club(), public.is_admin(),
  public.complete_task(uuid, text, text, text), public.leaderboard() from public, anon;
grant execute on function public.my_role(), public.my_club(), public.is_admin(),
  public.complete_task(uuid, text, text, text), public.leaderboard() to authenticated;

-- ---------- Erişim kuralları (Row Level Security) ----------

alter table public.clubs              enable row level security;
alter table public.profiles           enable row level security;
alter table public.announcements      enable row level security;
alter table public.events             enable row level security;
alter table public.event_applications enable row level security;
alter table public.tasks              enable row level security;
alter table public.point_entries      enable row level security;

revoke all on public.clubs, public.profiles, public.announcements, public.events,
  public.event_applications, public.tasks, public.point_entries from anon;
grant select, insert, update, delete on public.clubs, public.announcements, public.events,
  public.event_applications, public.tasks, public.point_entries to authenticated;
grant select on public.profiles to authenticated;   -- profilleri yalnızca SQL Editor değiştirir

-- clubs
drop policy if exists clubs_select on public.clubs;
create policy clubs_select on public.clubs for select to authenticated
  using ((select public.my_role()) is not null);
drop policy if exists clubs_admin_write on public.clubs;
create policy clubs_admin_write on public.clubs for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

-- announcements
drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select to authenticated
  using (
    (select public.is_admin())
    or club_id = (select public.my_club())
    or (status = 'published' and (select public.my_role()) is not null)
  );
drop policy if exists announcements_club_insert on public.announcements;
create policy announcements_club_insert on public.announcements for insert to authenticated
  with check (
    club_id = (select public.my_club()) and status = 'pending' and note is null and decided_at is null
  );
drop policy if exists announcements_admin_write on public.announcements;
create policy announcements_admin_write on public.announcements for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- events
drop policy if exists events_select on public.events;
create policy events_select on public.events for select to authenticated
  using (
    (select public.is_admin())
    or club_id = (select public.my_club())
    or (status = 'published' and (select public.my_role()) is not null)
  );
drop policy if exists events_club_insert on public.events;
create policy events_club_insert on public.events for insert to authenticated
  with check (
    club_id = (select public.my_club()) and status = 'pending' and note is null and decided_at is null
  );
drop policy if exists events_admin_write on public.events;
create policy events_admin_write on public.events for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- event_applications: onaylanan ortaklar herkese görünür, bekleyenler yalnızca sahibine ve UniPakt'a
drop policy if exists event_applications_select on public.event_applications;
create policy event_applications_select on public.event_applications for select to authenticated
  using (
    (select public.is_admin())
    or club_id = (select public.my_club())
    or (status = 'approved' and (select public.my_role()) is not null)
  );
drop policy if exists event_applications_club_insert on public.event_applications;
create policy event_applications_club_insert on public.event_applications for insert to authenticated
  with check (
    club_id = (select public.my_club()) and status = 'pending' and decided_at is null
    and exists (
      select 1 from public.events e
       where e.id = event_id and e.status = 'published'
         and e.club_id is distinct from (select public.my_club())
    )
  );
drop policy if exists event_applications_admin_write on public.event_applications;
create policy event_applications_admin_write on public.event_applications for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- tasks: kulüp yalnızca kendi görevlerini okur, kapatmayı complete_task() ile yapar
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select to authenticated
  using ((select public.is_admin()) or club_id = (select public.my_club()));
drop policy if exists tasks_admin_write on public.tasks;
create policy tasks_admin_write on public.tasks for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- point_entries: kulüp yalnızca kendi kayıtlarını okur
drop policy if exists point_entries_select on public.point_entries;
create policy point_entries_select on public.point_entries for select to authenticated
  using ((select public.is_admin()) or club_id = (select public.my_club()));
drop policy if exists point_entries_admin_write on public.point_entries;
create policy point_entries_admin_write on public.point_entries for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- ---------- Görev kanıtı dosyaları ----------
-- Gizli depo. Dosya yolu: <kulüp id>/<görev id>/<dosya adı>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('task-proofs', 'task-proofs', false, 5242880,
        array['image/png', 'image/jpeg', 'image/webp', 'application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists task_proofs_insert on storage.objects;
create policy task_proofs_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'task-proofs'
    and (storage.foldername(name))[1] = (select public.my_club())::text
  );
drop policy if exists task_proofs_select on storage.objects;
create policy task_proofs_select on storage.objects for select to authenticated
  using (
    bucket_id = 'task-proofs'
    and ((select public.is_admin()) or (storage.foldername(name))[1] = (select public.my_club())::text)
  );
drop policy if exists task_proofs_admin_delete on storage.objects;
create policy task_proofs_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'task-proofs' and (select public.is_admin()));

-- ---------- İlk veri ----------

insert into public.clubs (name, university)
select 'GDG on Campus', 'İstinye Üniversitesi'
where not exists (select 1 from public.clubs where name = 'GDG on Campus');

-- ============================================================
-- HESAP AÇMA (bu şemayı çalıştırdıktan sonra)
--
-- 1) Authentication > Users > Add user ile hesabı oluşturun
--    (e-posta + şifre, "Auto Confirm User" işaretli).
--
-- 2) UniPakt yetkilisi yapmak için, e-postayı değiştirip çalıştırın:
--
--    insert into public.profiles (id, role, full_name)
--    select id, 'admin', 'UniPakt' from auth.users where email = 'ORNEK@unipakt.com';
--
-- 3) Kulüp başkanı yapmak için, e-postayı ve kulüp adını değiştirip çalıştırın:
--
--    insert into public.profiles (id, role, club_id, full_name)
--    select u.id, 'club', c.id, 'Ad Soyad'
--      from auth.users u, public.clubs c
--     where u.email = 'BASKAN@ornek.com' and c.name = 'GDG on Campus';
--
-- Yeni kulüp eklemek için:
--    insert into public.clubs (name, university) values ('Kulüp adı', 'Üniversite adı');
-- ============================================================
