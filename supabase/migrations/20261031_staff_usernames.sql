-- Kişisel yönetici hesapları: kullanıcı adı (ilk girişte panel sorar) ve "Merkez Yönetim" etiketi.
-- Merkez Yönetim hesapları mesajlaşmada kendi Matrix hesabıyla (staff_<id>) yazışır (matrix-session).
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists staff_title text;
alter table public.profiles drop constraint if exists profiles_username_check;
alter table public.profiles add constraint profiles_username_check check (username is null or username ~ '^[a-z0-9._]{3,24}$');
create unique index if not exists profiles_username_key on public.profiles (username) where username is not null;
alter table public.profiles drop constraint if exists profiles_staff_title_check;
alter table public.profiles add constraint profiles_staff_title_check check (staff_title is null or char_length(staff_title) between 2 and 40);
grant select (username, staff_title) on public.profiles to authenticated;
grant update (username) on public.profiles to authenticated;
update public.profiles p set staff_title = 'Merkez Yönetim'
  from auth.users u where u.id = p.id and p.role = 'admin'
   and lower(u.email) in ('mehmetemingzkysl@unipakt.com', 'akiftonbul@unipakt.com', 'ugursaginda@unipakt.com');
-- staff_title yalnızca sunucudan atanır.
create or replace function public.profiles_guard_role()
 returns trigger language plpgsql set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon')
     and (new.role is distinct from old.role or new.club_id is distinct from old.club_id
          or new.permissions is distinct from old.permissions or new.member_title is distinct from old.member_title
          or new.staff_title is distinct from old.staff_title) then
    raise exception 'Rol ve yetkiler yalnızca ekip yönetiminden değiştirilir.';
  end if;
  return new;
end;
$function$;
