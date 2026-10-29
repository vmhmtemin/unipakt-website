-- UniPakt Panel — optional two-step verification (2FA) by e-mail code.
--
-- How it works
--  * A user turns 2FA on from the Hesap page (row in mfa_settings).
--  * From then on every new login session must be verified once: a 6-digit
--    code is e-mailed (Edge Function `mfa`), or a browser the user verified
--    before presents its 30-day "trusted browser" token.
--  * A verified session is recorded by its JWT `session_id` in
--    mfa_verified_sessions. Refreshing the token keeps the same session id.
--
-- Enforcement is in the database, not the browser: the helper functions every
-- RLS policy relies on (my_role, my_club, my_club_id, is_unipakt_admin — and
-- is_admin through my_role) return "no access" for a session that still needs
-- verification. Policies and functions that use auth.uid() directly get an
-- explicit mfa_ok() check below. Accounts without 2FA are not affected.
--
-- The four tables are only touched by the Edge Function (service role):
-- RLS is on and there are no policies for anon/authenticated.

create table if not exists public.mfa_settings (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  enabled_at timestamptz not null default now()
);

create table if not exists public.mfa_codes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  session_id  uuid not null,
  purpose     text not null check (purpose in ('enable', 'login', 'disable')),
  code_hash   text not null,
  attempts    integer not null default 0,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  used_at     timestamptz
);
create index if not exists mfa_codes_lookup on public.mfa_codes (user_id, session_id, purpose, created_at desc);

create table if not exists public.mfa_trusted_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  token_hash   text not null unique,
  label        text,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  last_used_at timestamptz
);
create index if not exists mfa_trusted_devices_user on public.mfa_trusted_devices (user_id);

create table if not exists public.mfa_verified_sessions (
  session_id  uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  verified_at timestamptz not null default now()
);
create index if not exists mfa_verified_sessions_user on public.mfa_verified_sessions (user_id);

alter table public.mfa_settings          enable row level security;
alter table public.mfa_codes             enable row level security;
alter table public.mfa_trusted_devices   enable row level security;
alter table public.mfa_verified_sessions enable row level security;
revoke all on public.mfa_settings, public.mfa_codes, public.mfa_trusted_devices, public.mfa_verified_sessions from anon, authenticated;

-- Is this request's session allowed through? True when there is no user,
-- when the user has no 2FA, or when this session was verified.
create or replace function public.mfa_ok()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is null
      or not exists (select 1 from public.mfa_settings s where s.user_id = (select auth.uid()))
      or exists (
        select 1 from public.mfa_verified_sessions v
        where v.user_id = (select auth.uid())
          and v.session_id = nullif((select auth.jwt()) ->> 'session_id', '')::uuid
      );
$$;

-- Same check for Edge Functions that run with the service role.
create or replace function public.mfa_session_ok(p_user uuid, p_session uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (select 1 from public.mfa_settings s where s.user_id = p_user)
      or exists (select 1 from public.mfa_verified_sessions v where v.user_id = p_user and v.session_id = p_session);
$$;
revoke all on function public.mfa_session_ok(uuid, uuid) from public, anon, authenticated;
grant execute on function public.mfa_session_ok(uuid, uuid) to service_role;

-- ---- The shared helpers: no role / club for an unverified session ----
create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = (select auth.uid()) and public.mfa_ok()
$$;

create or replace function public.my_club()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select club_id from public.profiles where id = (select auth.uid()) and public.mfa_ok()
$$;

create or replace function public.my_club_id()
returns uuid
language sql
stable
security definer
set search_path = 'public'
as $$
  select p.club_id
  from public.profiles p
  where p.id = auth.uid() and public.mfa_ok()
  limit 1;
$$;

create or replace function public.is_unipakt_admin()
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ) and public.mfa_ok();
$$;

-- ---- Policies that use auth.uid() directly ----
drop policy if exists support_tickets_club_select on public.support_tickets;
create policy support_tickets_club_select on public.support_tickets
  for select to authenticated
  using ((club_id = public.my_club_id()) or (created_by = auth.uid() and public.mfa_ok()));

drop policy if exists support_ticket_messages_club_select on public.support_ticket_messages;
create policy support_ticket_messages_club_select on public.support_ticket_messages
  for select to authenticated
  using (exists (
    select 1 from public.support_tickets t
    where t.id = support_ticket_messages.ticket_id
      and ((t.club_id = public.my_club_id()) or (t.created_by = auth.uid() and public.mfa_ok()))
  ));

drop policy if exists profile_logos_insert_own on storage.objects;
create policy profile_logos_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'profile-logos' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.mfa_ok()));

drop policy if exists profile_logos_select_own on storage.objects;
create policy profile_logos_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'profile-logos' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.mfa_ok()));

drop policy if exists profile_logos_update_own on storage.objects;
create policy profile_logos_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'profile-logos' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.mfa_ok()))
  with check (bucket_id = 'profile-logos' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.mfa_ok()));

-- ---- support_reply_ticket_v2: the "ticket creator" path also needs 2FA ----
create or replace function public.support_reply_ticket_v2(p_ticket_id uuid, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_club    uuid;
  v_creator uuid;
  v_status  text;
  v_role    text;
begin
  if char_length(btrim(coalesce(p_body,''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  select t.club_id, t.created_by, t.status into v_club, v_creator, v_status
    from public.support_tickets t
   where t.id = p_ticket_id
   for update;

  if not found then
    raise exception 'Support ticket not found';
  end if;

  if public.is_unipakt_admin() then
    v_role := 'admin';
  elsif v_club = public.my_club_id() or (v_creator = auth.uid() and public.mfa_ok()) then
    v_role := 'club';
  else
    raise exception 'Not allowed';
  end if;

  if v_role = 'club' and v_status = 'closed' then
    raise exception 'Bu destek talebi kapatıldı; yeni bir talep oluştur.';
  end if;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values (
    p_ticket_id,
    auth.uid(),
    v_role,
    case when v_role = 'admin' then 'UniPakt Destek' else 'Kulüp' end,
    btrim(p_body)
  );

  update public.support_tickets
     set status = case when v_role = 'admin' then 'answered' else 'open' end,
         preview = left(btrim(p_body), 300),
         updated_at = now()
   where id = p_ticket_id;
end;
$function$;
