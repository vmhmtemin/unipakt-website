-- UniPakt birimleri (Halkla İlişkiler, Sosyal Medya, …).
--  * Merkez Yönetim (role = 'admin') birim açar, başkan atar/değiştirir, rol ekler.
--  * Birim hesabı (role = 'unit') yalnızca bir birimde olur (unit_members.user_id birincil anahtar).
--  * Her birimde tek başkan (unit_members.is_head için kısmi tekil indeks).
--  * Hazır roller: Birim Başkanı, Başkan Yardımcısı, Üye. Başkan ve yetkili kişiler
--    istediği adla yeni rol açar; kişiye rolünün üstüne ek yetki de verilebilir.
--  * Birimden çıkarılan kişi silinmez, pasife alınır (status = 'passive', hesap girişi kapatılır).
--  * Yazma işlemleri yalnızca unit-team fonksiyonundan (servis rolü). Okuma unit_directory() ile.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin', 'club', 'member', 'unit'));
alter table public.profiles drop constraint if exists profiles_role_club;
alter table public.profiles add constraint profiles_role_club check (
  (role in ('admin', 'unit') and club_id is null) or (role in ('club', 'member') and club_id is not null));

-- Yetki kataloğu (birim içi): team = ekip (kişi ekle, rol ata, pasife al), roles = rol aç/düzenle, chat = mesajlaşma.
create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 2 and 60),
  sort int not null default 100,
  created_at timestamptz not null default now()
);

create table if not exists public.unit_roles (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 40),
  permissions text[] not null default '{}' check (permissions <@ array['team', 'roles', 'chat']::text[]),
  is_head boolean not null default false,
  preset boolean not null default false,
  sort int not null default 100,
  created_at timestamptz not null default now(),
  unique (unit_id, name)
);
create unique index if not exists unit_roles_one_head on public.unit_roles (unit_id) where is_head;

create table if not exists public.unit_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete restrict,
  role_id uuid not null references public.unit_roles(id) on delete restrict,
  is_head boolean not null default false,
  permissions text[] not null default '{}' check (permissions <@ array['team', 'roles', 'chat']::text[]),
  status text not null default 'active' check (status in ('active', 'passive')),
  added_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  passive_at timestamptz
);
create unique index if not exists unit_members_one_head on public.unit_members (unit_id) where is_head and status = 'active';
create index if not exists unit_members_unit on public.unit_members (unit_id);

alter table public.units enable row level security;
alter table public.unit_roles enable row level security;
alter table public.unit_members enable row level security;
revoke all on public.units, public.unit_roles, public.unit_members from anon, authenticated;

-- Yeni birime hazır roller.
create or replace function public.units_seed_roles()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.unit_roles (unit_id, name, permissions, is_head, preset, sort) values
    (new.id, 'Birim Başkanı', array['team', 'roles', 'chat'], true, true, 1),
    (new.id, 'Başkan Yardımcısı', array['team', 'chat'], false, true, 2),
    (new.id, 'Üye', array['chat'], false, true, 3);
  return new;
end;
$$;
drop trigger if exists units_seed_roles on public.units;
create trigger units_seed_roles after insert on public.units for each row execute function public.units_seed_roles();

insert into public.units (name, sort) values
  ('Halkla İlişkiler', 1), ('Sosyal Medya', 2), ('Sponsorluk', 3), ('Kulüp İlişkileri', 4),
  ('Denetim', 5), ('Yazılım ve Dijital Sistemler', 6), ('Proje Geliştirme ve Planlama', 7)
on conflict (name) do nothing;

-- Çağıranın aktif birimi.
create or replace function public.my_unit()
returns uuid language sql stable security definer set search_path = '' as $$
  select m.unit_id from public.unit_members m
  join public.profiles p on p.id = m.user_id and p.role = 'unit'
  where m.user_id = (select auth.uid()) and m.status = 'active';
$$;
revoke all on function public.my_unit() from public, anon;
grant execute on function public.my_unit() to authenticated, service_role;

-- Çağıranın birimdeki etkin yetkileri (başkan: hepsi; diğerleri: rol ∪ kişisel).
create or replace function public.my_unit_perms()
returns text[] language sql stable security definer set search_path = '' as $$
  select case when m.is_head then array['team', 'roles', 'chat']
              else array(select distinct x from unnest(r.permissions || m.permissions) x) end
  from public.unit_members m join public.unit_roles r on r.id = m.role_id
  where m.user_id = (select auth.uid()) and m.status = 'active';
$$;
revoke all on function public.my_unit_perms() from public, anon;
grant execute on function public.my_unit_perms() to authenticated, service_role;

-- Birimler rehberi: Merkez Yönetim ve birim hesapları görür (diğer birimler salt okunur).
-- E-posta adresleri burada yok; onları yalnızca yetkili kişi unit-team fonksiyonundan alır.
create or replace function public.unit_directory()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  admin_ok boolean := public.is_admin() and public.mfa_ok();
  mine uuid := public.my_unit();
begin
  if not (admin_ok or (mine is not null and public.mfa_ok())) then
    raise exception 'Birimleri yalnızca Merkez Yönetim ve birim üyeleri görebilir.';
  end if;
  return jsonb_build_object(
    'me', jsonb_build_object('unit_id', mine, 'perms', coalesce(to_jsonb(public.my_unit_perms()), '[]'::jsonb),
                             'is_head', coalesce((select is_head from public.unit_members where user_id = me and status = 'active'), false),
                             'admin', admin_ok),
    'units', coalesce((select jsonb_agg(jsonb_build_object(
        'id', u.id, 'name', u.name, 'sort', u.sort,
        'roles', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'permissions', r.permissions,
                                   'is_head', r.is_head, 'preset', r.preset) order by r.sort, r.name)
                           from public.unit_roles r where r.unit_id = u.id), '[]'::jsonb),
        'members', coalesce((select jsonb_agg(jsonb_build_object(
              'id', m.user_id, 'full_name', p.full_name, 'username', p.username, 'avatar_url', p.avatar_url,
              'role_id', m.role_id, 'is_head', m.is_head, 'permissions', m.permissions,
              'status', m.status, 'joined_at', m.created_at) order by m.is_head desc, m.status, p.full_name)
            from public.unit_members m join public.profiles p on p.id = m.user_id
            where m.unit_id = u.id and (m.status = 'active' or admin_ok or u.id = mine)), '[]'::jsonb)
      ) order by u.sort, u.name) from public.units u), '[]'::jsonb));
end;
$$;
revoke all on function public.unit_directory() from public, anon;
grant execute on function public.unit_directory() to authenticated, service_role;

-- Birim hesabı kendi adını ve fotoğrafını değiştirebilir (rol/yetki alanlarını guard tetikleyicisi korur).
drop policy if exists profiles_unit_update_own on public.profiles;
create policy profiles_unit_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid()) and role = 'unit' and (select public.mfa_ok()))
  with check (id = (select auth.uid()) and role = 'unit');
