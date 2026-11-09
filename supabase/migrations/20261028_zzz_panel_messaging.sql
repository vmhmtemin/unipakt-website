-- Panel-only club messaging profiles and the fields shown to other signed-in clubs.
-- The public site uses public_clubs(); it never reads these profile fields.
begin;

alter table public.profiles
  add column if not exists bio text,
  add column if not exists collaboration_interests text[] not null default '{}'::text[],
  add column if not exists avatar_url text;

alter table public.profiles
  drop constraint if exists profiles_bio_check,
  add constraint profiles_bio_check check (bio is null or char_length(bio) <= 500),
  drop constraint if exists profiles_interests_check,
  add constraint profiles_interests_check check (cardinality(collaboration_interests) <= 12),
  drop constraint if exists profiles_avatar_url_check,
  add constraint profiles_avatar_url_check check (avatar_url is null or avatar_url ~ '^https://[^[:space:]"''<>]+$');

-- Replace the existing admin/own-only policy so authenticated panel users can see club profiles.
-- No anon role receives access to profiles.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select
  on public.profiles
  for select
  to authenticated
  using ((select my_role()) is not null);

-- The older profile-name migration grants only full_name; restore the complete column grant here.
revoke update on table public.profiles from authenticated;
grant update (full_name, bio, collaboration_interests, avatar_url) on public.profiles to authenticated;

drop policy if exists profiles_club_update_own_name on public.profiles;
create policy profiles_club_update_own_name
  on public.profiles
  for update
  to authenticated
  using (
    id = (select auth.uid())
    and role = 'club'
    and club_id = (select my_club_id())
  )
  with check (
    id = (select auth.uid())
    and role = 'club'
    and club_id = (select my_club_id())
    and full_name is not null
    and char_length(btrim(full_name)) between 1 and 120
    and (bio is null or char_length(bio) <= 500)
    and cardinality(collaboration_interests) <= 12
    and (avatar_url is null or avatar_url ~ '^https://[^[:space:]"''<>]+$')
  );

commit;
