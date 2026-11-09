-- Birim çalışma alanı: birim hesaplarının ve Merkez Yönetim'in ortak araçları.
--  * Tek okuma kapısı: unit_workspace() → { me, <bölüm>: ... }. Her bölüm uwr_<bölüm>() fonksiyonundan gelir;
--    yeni aşamalar yalnızca yeni uwr_ fonksiyonu ekler, kapı değişmez. Yetkisi olmayana bölüm null döner.
--  * Tek yazma kapısı: uw(p_action, p_data) → uwa_<işlem>(p_data). Her işlem kendi yetkisini denetler.
--  * Tablolara doğrudan erişim yok (RLS açık, politika yok); her şey bu iki kapıdan geçer.
--  * Bildirimler panel içidir (unit_notifications); kulüp bildirimlerinin e-posta tetikleyicisine dokunulmaz.
--  * Kulüp kabulü Merkez'de kaldığı için clubs_accept yetkisi katalogdan çıkar.

-- ---------------------------------------------------------------- clubs_accept kalkar
update public.unit_roles set permissions = array_remove(permissions, 'clubs_accept') where 'clubs_accept' = any(permissions);
update public.unit_members set permissions = array_remove(permissions, 'clubs_accept') where 'clubs_accept' = any(permissions);
alter table public.unit_roles drop constraint if exists unit_roles_permissions_check;
alter table public.unit_members drop constraint if exists unit_members_permissions_check;
alter table public.unit_roles add constraint unit_roles_permissions_check check (permissions <@ array['team', 'roles', 'chat', 'posts', 'brand', 'campaigns', 'sponsors', 'clubs', 'audit', 'audit_assign', 'approve']::text[]);
alter table public.unit_members add constraint unit_members_permissions_check check (permissions <@ array['team', 'roles', 'chat', 'posts', 'brand', 'campaigns', 'sponsors', 'clubs', 'audit', 'audit_assign', 'approve']::text[]);

create or replace function public.unit_kind_perms(p_kind text)
returns text[] language sql immutable set search_path = '' as $$
  select array['team', 'roles', 'chat'] || case p_kind
    when 'social' then array['posts', 'brand']
    when 'pr' then array['campaigns']
    when 'sponsor' then array['sponsors']
    when 'clubs' then array['clubs']
    when 'audit' then array['audit', 'audit_assign']
    when 'board' then array['approve']
    else array[]::text[] end;
$$;

-- ---------------------------------------------------------------- yardımcılar
create or replace function public.uw_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.is_admin(), false) and public.mfa_ok();
$$;

create or replace function public.uw_unit()
returns uuid language sql stable security definer set search_path = '' as $$
  select case when public.mfa_ok() then public.my_unit() end;
$$;

create or replace function public.uw_kind()
returns text language sql stable security definer set search_path = '' as $$
  select u.kind from public.units u where u.id = public.uw_unit();
$$;

create or replace function public.uw_head()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select m.is_head from public.unit_members m
                    where m.user_id = (select auth.uid()) and m.status = 'active' and m.unit_id = public.uw_unit()), false);
$$;

-- Çağıran kendi biriminde bu yetkiye sahip mi? (Başkan türünün tüm yetkilerine sahiptir.)
create or replace function public.uw_has(p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_unit() is not null and p_perm = any(coalesce(public.my_unit_perms(), '{}'));
$$;

-- Türü verilen birimde bu yetki var mı?
create or replace function public.uw_can(p_kind text, p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_kind() is not distinct from p_kind and public.uw_has(p_perm);
$$;

create or replace function public.uw_unit_of_kind(p_kind text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.units where kind = p_kind;
$$;

create or replace function public.uw_name(p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(btrim(p.full_name), ''), nullif(p.username, ''), 'İsimsiz') from public.profiles p where p.id = p_user;
$$;

create or replace function public.uw_text(p jsonb, p_key text, p_max int, p_required boolean default false, p_label text default 'Alan')
returns text language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(regexp_replace(coalesce(p ->> p_key, ''), '[\x01-\x08\x0B\x0C\x0E-\x1F]', '', 'g')), '');
begin
  if v is null and p_required then raise exception '% boş olamaz.', p_label; end if;
  if v is not null and char_length(v) > p_max then raise exception '% en fazla % karakter olabilir.', p_label, p_max; end if;
  return v;
end;
$$;

create or replace function public.uw_link(p jsonb, p_key text)
returns text language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(coalesce(p ->> p_key, '')), '');
begin
  if v is null then return null; end if;
  if char_length(v) > 500 or v !~* '^https?://[^\s"''<>]+$' then raise exception 'Bağlantı http:// ya da https:// ile başlayan bir web adresi olmalı.'; end if;
  return v;
end;
$$;

create or replace function public.uw_uuid(p jsonb, p_key text)
returns uuid language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(p ->> p_key, '') = '' then return null; end if;
  return (p ->> p_key)::uuid;
exception when invalid_text_representation then raise exception 'Geçersiz kayıt.';
end;
$$;

-- ---------------------------------------------------------------- işlem kaydı: birim bilgisi
alter table public.activity_log add column if not exists unit_id uuid references public.units(id) on delete set null;
create index if not exists activity_log_unit on public.activity_log (unit_id, created_at desc) where unit_id is not null;

create or replace function public.log_activity(p_action text, p_target text, p_actor uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := coalesce(p_actor, (select auth.uid()));
  v_p public.profiles;
  v_unit uuid;
  v_title text;
begin
  if v_actor is null then return; end if;
  select * into v_p from public.profiles where id = v_actor;
  if not found then return; end if;
  if v_p.role = 'unit' then
    select m.unit_id, u.name || ' · ' || case when m.is_head then 'Birim Başkanı' else r.name end
      into v_unit, v_title
      from public.unit_members m join public.units u on u.id = m.unit_id join public.unit_roles r on r.id = m.role_id
     where m.user_id = v_actor;
  end if;
  insert into public.activity_log (club_id, unit_id, actor_id, actor_name, actor_title, action, target)
  values (v_p.club_id, v_unit, v_actor,
          coalesce(nullif(btrim(v_p.full_name), ''), case v_p.role when 'admin' then 'UniPakt' when 'unit' then 'Birim üyesi' else 'Kulüp hesabı' end),
          case v_p.role when 'admin' then 'UniPakt yetkilisi' when 'club' then 'Kulüp başkanı'
                        when 'unit' then coalesce(v_title, 'Birim üyesi') else coalesce(v_p.member_title, 'Ekip üyesi') end,
          left(p_action, 120), left(coalesce(p_target, ''), 200));
end;
$$;

-- ---------------------------------------------------------------- bildirimler (panel içi)
create table if not exists public.unit_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user uuid references auth.users(id) on delete cascade,
  recipient_unit uuid references public.units(id) on delete cascade,
  recipient_perm text,
  recipient_admin boolean not null default false,
  type text not null,
  title text not null,
  body text not null default '',
  view text,
  created_at timestamptz not null default now(),
  check (recipient_admin or recipient_user is not null or recipient_unit is not null)
);
create index if not exists unit_notifications_user on public.unit_notifications (recipient_user, created_at desc);
create index if not exists unit_notifications_unit on public.unit_notifications (recipient_unit, created_at desc);
create index if not exists unit_notifications_admin on public.unit_notifications (created_at desc) where recipient_admin;

create table if not exists public.unit_notification_states (
  notification_id uuid not null references public.unit_notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz,
  hidden_at timestamptz,
  primary key (notification_id, user_id)
);

-- Alıcı: kişi, birim (isteğe bağlı yetki süzgeci; başkan her zaman görür) ya da Merkez.
create or replace function public.uw_notify(p_user uuid, p_unit uuid, p_perm text, p_admin boolean, p_type text, p_title text, p_body text, p_view text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_user is null and p_unit is null and not coalesce(p_admin, false) then return; end if;
  insert into public.unit_notifications (recipient_user, recipient_unit, recipient_perm, recipient_admin, type, title, body, view)
  values (p_user, p_unit, p_perm, coalesce(p_admin, false), p_type, left(p_title, 160), left(coalesce(p_body, ''), 1000), p_view);
end;
$$;

create or replace function public.uw_notification_visible(n public.unit_notifications)
returns boolean language sql stable security definer set search_path = '' as $$
  select (n.recipient_admin and public.uw_admin())
      or n.recipient_user = (select auth.uid())
      or (n.recipient_unit is not null and n.recipient_unit = public.uw_unit()
          and (n.recipient_perm is null or public.uw_head() or public.uw_has(n.recipient_perm)));
$$;

-- ---------------------------------------------------------------- görevler
create table if not exists public.unit_tasks (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  assignee uuid references auth.users(id) on delete set null,
  title text not null check (char_length(title) between 2 and 160),
  description text,
  due_date date,
  by_admin boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  status text not null default 'open' check (status in ('open', 'done')),
  review_status text not null default 'none' check (review_status in ('none', 'pending', 'approved', 'rejected')),
  review_note text,
  proof_text text,
  proof_link text,
  done_by uuid references auth.users(id) on delete set null,
  done_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists unit_tasks_unit on public.unit_tasks (unit_id);

-- ---------------------------------------------------------------- iç duyurular
create table if not exists public.unit_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 160),
  body text not null check (char_length(body) between 1 and 5000),
  audience uuid[] not null default '{}',   -- boş: tüm birimler
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.unit_announcement_reads (
  announcement_id uuid not null references public.unit_announcements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

-- ---------------------------------------------------------------- belgeler
create table if not exists public.unit_docs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id) on delete cascade,   -- null: tüm UniPakt
  title text not null check (char_length(title) between 2 and 160),
  url text not null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.unit_notifications enable row level security;
alter table public.unit_notification_states enable row level security;
alter table public.unit_tasks enable row level security;
alter table public.unit_announcements enable row level security;
alter table public.unit_announcement_reads enable row level security;
alter table public.unit_docs enable row level security;
revoke all on public.unit_notifications, public.unit_notification_states, public.unit_tasks, public.unit_announcements,
              public.unit_announcement_reads, public.unit_docs from anon, authenticated;

-- ---------------------------------------------------------------- okuma bölümleri
create or replace function public.uwr_notifications()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'type', n.type, 'title', n.title, 'body', n.body, 'view', n.view,
           'created_at', n.created_at, 'read_at', s.read_at) order by n.created_at desc), '[]'::jsonb)
  from (select * from public.unit_notifications n where public.uw_notification_visible(n) order by n.created_at desc limit 200) n
  left join public.unit_notification_states s on s.notification_id = n.id and s.user_id = (select auth.uid())
  where s.hidden_at is null;
$$;

create or replace function public.uwr_tasks()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_unit uuid := public.uw_unit(); v_lead boolean := public.uw_head() or public.uw_has('team');
begin
  if not v_admin and v_unit is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'unit_id', t.unit_id, 'assignee', t.assignee, 'assignee_name', public.uw_name(t.assignee),
      'title', t.title, 'description', t.description, 'due_date', t.due_date, 'by_admin', t.by_admin, 'created_by', t.created_by,
      'created_by_name', public.uw_name(t.created_by), 'status', t.status, 'review_status', t.review_status, 'review_note', t.review_note,
      'proof_text', t.proof_text, 'proof_link', t.proof_link, 'done_by_name', public.uw_name(t.done_by), 'done_at', t.done_at,
      'reviewed_at', t.reviewed_at, 'created_at', t.created_at) order by t.created_at desc)
    from public.unit_tasks t
    where v_admin or (t.unit_id = v_unit and (v_lead or t.assignee = (select auth.uid()) or t.assignee is null))), '[]'::jsonb);
end;
$$;

create or replace function public.uwr_announcements()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_unit uuid := public.uw_unit();
begin
  if not v_admin and v_unit is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'audience', a.audience,
      'created_by_name', public.uw_name(a.created_by), 'created_at', a.created_at,
      'read_at', (select r.read_at from public.unit_announcement_reads r where r.announcement_id = a.id and r.user_id = (select auth.uid())),
      'reads', case when v_admin then (select count(*) from public.unit_announcement_reads r where r.announcement_id = a.id) end)
      order by a.created_at desc)
    from public.unit_announcements a
    where v_admin or cardinality(a.audience) = 0 or v_unit = any(a.audience)), '[]'::jsonb);
end;
$$;

create or replace function public.uwr_docs()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.uw_admin() and public.uw_unit() is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'unit_id', d.unit_id, 'title', d.title, 'url', d.url, 'note', d.note,
      'created_by', d.created_by, 'created_by_name', public.uw_name(d.created_by), 'created_at', d.created_at) order by d.created_at desc)
    from public.unit_docs d), '[]'::jsonb);
end;
$$;

-- Birim başkanı kendi biriminin işlem kaydını görür (Merkez tüm kaydı İşlem Kaydı sayfasında görür).
create or replace function public.uwr_activity()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.uw_head() then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'actor_name', a.actor_name, 'actor_title', a.actor_title,
      'action', a.action, 'target', a.target, 'created_at', a.created_at) order by a.created_at desc)
    from (select * from public.activity_log where unit_id = public.uw_unit() order by created_at desc limit 300) a), '[]'::jsonb);
end;
$$;

-- Okuma kapısı. Bölümler uwr_ ile başlayan fonksiyonlardan toplanır.
create or replace function public.unit_workspace()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_admin boolean := public.uw_admin();
  v_unit uuid := public.uw_unit();
  v_out jsonb;
  f record;
  v jsonb;
begin
  if not v_admin and v_unit is null then raise exception 'Bu bölümü yalnızca Merkez Yönetim ve birim üyeleri görebilir.'; end if;
  v_out := jsonb_build_object('me', jsonb_build_object('id', (select auth.uid()), 'admin', v_admin, 'unit_id', v_unit, 'kind', public.uw_kind(),
    'is_head', public.uw_head(), 'perms', coalesce(to_jsonb(public.my_unit_perms()), '[]'::jsonb),
    'units', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'kind', u.kind,
        'members', (select coalesce(jsonb_agg(jsonb_build_object('id', m.user_id, 'name', public.uw_name(m.user_id), 'is_head', m.is_head,
             'perms', case when m.is_head then to_jsonb(public.unit_kind_perms(u.kind))
                           else to_jsonb(array(select distinct x from unnest(r.permissions || m.permissions) x where x = any(public.unit_kind_perms(u.kind)))) end)
             order by m.is_head desc, public.uw_name(m.user_id)), '[]'::jsonb)
           from public.unit_members m join public.unit_roles r on r.id = m.role_id where m.unit_id = u.id and m.status = 'active'))
        order by u.sort, u.name), '[]'::jsonb) from public.units u)));
  for f in select p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'uwr\_%' and p.pronargs = 0 order by 1 loop
    execute format('select public.%I()', f.proname) into v;
    v_out := v_out || jsonb_build_object(substr(f.proname, 5), v);
  end loop;
  return v_out;
end;
$$;

-- Yazma kapısı: uw('task_create', {...}) → uwa_task_create({...}).
create or replace function public.uw(p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Oturum kapalı.'; end if;
  if not public.mfa_ok() then raise exception 'Bu tarayıcı için iki adımlı doğrulama gerekli.'; end if;
  if coalesce(p_action, '') !~ '^[a-z][a-z_]{1,40}$'
     or not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'uwa_' || p_action and p.pronargs = 1) then
    raise exception 'Bilinmeyen işlem.';
  end if;
  execute format('select public.%I($1)', 'uwa_' || p_action) into v using coalesce(p_data, '{}'::jsonb);
  return coalesce(v, '{"ok": true}'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- işlemler: bildirimler
create or replace function public.uwa_notif_read(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_n public.unit_notifications;
begin
  for v_n in select * from public.unit_notifications n
              where public.uw_notification_visible(n) and (coalesce(p ->> 'id', '') = '' or n.id = public.uw_uuid(p, 'id')) loop
    insert into public.unit_notification_states (notification_id, user_id, read_at) values (v_n.id, (select auth.uid()), now())
    on conflict (notification_id, user_id) do update set read_at = coalesce(public.unit_notification_states.read_at, now());
  end loop;
  return null;
end;
$$;

create or replace function public.uwa_notif_hide(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_n public.unit_notifications;
begin
  select * into v_n from public.unit_notifications where id = public.uw_uuid(p, 'id');
  if not found or not public.uw_notification_visible(v_n) then raise exception 'Bildirim bulunamadı.'; end if;
  insert into public.unit_notification_states (notification_id, user_id, read_at, hidden_at) values (v_n.id, (select auth.uid()), now(), now())
  on conflict (notification_id, user_id) do update set hidden_at = now(), read_at = coalesce(public.unit_notification_states.read_at, now());
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: görevler
-- Merkez herhangi bir birime ya da kişiye; başkan (ve ekip yönetimi yetkisi olan) kendi ekibine görev atar.
create or replace function public.uwa_task_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_admin boolean := public.uw_admin();
  v_unit uuid := public.uw_uuid(p, 'unit_id');
  v_to uuid := public.uw_uuid(p, 'assignee');
  v_title text := public.uw_text(p, 'title', 160, true, 'Görev başlığı');
  v_id uuid;
begin
  if not v_admin then
    if not (public.uw_head() or public.uw_has('team')) then raise exception 'Görev atamak için ekip yönetimi yetkisi gerekir.'; end if;
    v_unit := public.uw_unit();
    if v_to is null then raise exception 'Görevi ekibinden birine ata.'; end if;
  end if;
  if not exists (select 1 from public.units where id = v_unit) then raise exception 'Birim seç.'; end if;
  if v_to is not null and not exists (select 1 from public.unit_members where user_id = v_to and unit_id = v_unit and status = 'active') then
    raise exception 'Bu kişi bu birimin aktif üyesi değil.';
  end if;
  insert into public.unit_tasks (unit_id, assignee, title, description, due_date, by_admin, created_by)
  values (v_unit, v_to, v_title, public.uw_text(p, 'description', 2000), nullif(p ->> 'due_date', '')::date, v_admin, (select auth.uid()))
  returning id into v_id;
  if v_to is not null then
    perform public.uw_notify(v_to, null, null, false, 'task_assigned', 'Sana görev atandı', '“' || v_title || '”', 'b-gorevler');
  else
    perform public.uw_notify(null, v_unit, 'team', false, 'task_assigned', 'Birimine görev atandı', '“' || v_title || '”', 'b-gorevler');
  end if;
  perform public.log_activity('Görev atadı', v_title);
  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.uwa_task_complete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_t public.unit_tasks; v_text text := public.uw_text(p, 'text', 2000); v_link text := public.uw_link(p, 'link');
begin
  select * into v_t from public.unit_tasks where id = public.uw_uuid(p, 'id') for update;
  if not found or v_t.unit_id is distinct from public.uw_unit()
     or not (v_t.assignee = (select auth.uid()) or (v_t.assignee is null and (public.uw_head() or public.uw_has('team')))) then
    raise exception 'Görev bulunamadı.';
  end if;
  if v_t.status <> 'open' then raise exception 'Bu görev zaten tamamlanmış.'; end if;
  if v_text is null and v_link is null then raise exception 'Kısa bir not ya da bağlantı bırak.'; end if;
  update public.unit_tasks set status = 'done', review_status = 'pending', review_note = null, proof_text = v_text, proof_link = v_link,
         done_by = (select auth.uid()), done_at = now(), reviewed_at = null where id = v_t.id;
  if v_t.by_admin then
    perform public.uw_notify(null, null, null, true, 'task_submitted', 'Birim görevi tamamlandı', '“' || v_t.title || '” · ' || public.uw_name((select auth.uid())), 'gorevler');
  else
    perform public.uw_notify(v_t.created_by, null, null, false, 'task_submitted', 'Görev tamamlandı, incelemeni bekliyor', '“' || v_t.title || '” · ' || public.uw_name((select auth.uid())), 'b-gorevler');
  end if;
  perform public.log_activity('Görevi tamamladı', v_t.title);
  return null;
end;
$$;

create or replace function public.uwa_task_review(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_t public.unit_tasks; v_status text := p ->> 'status'; v_note text := public.uw_text(p, 'note', 500);
begin
  select * into v_t from public.unit_tasks where id = public.uw_uuid(p, 'id') for update;
  if not found then raise exception 'Görev bulunamadı.'; end if;
  if not (case when v_t.by_admin then public.uw_admin()
               else v_t.unit_id = public.uw_unit() and (public.uw_head() or public.uw_has('team')) end) then
    raise exception 'Bu görevi yalnızca atayan taraf inceleyebilir.';
  end if;
  if v_t.status <> 'done' or v_t.review_status <> 'pending' then raise exception 'İnceleme bekleyen görev bulunamadı.'; end if;
  if v_status not in ('approved', 'rejected') then raise exception 'Geçersiz karar.'; end if;
  if v_status = 'rejected' and v_note is null then raise exception 'Geri göndermek için not yaz.'; end if;
  if v_status = 'approved' then
    update public.unit_tasks set review_status = 'approved', review_note = v_note, reviewed_at = now() where id = v_t.id;
  else
    update public.unit_tasks set status = 'open', review_status = 'rejected', review_note = v_note, reviewed_at = now() where id = v_t.id;
  end if;
  perform public.uw_notify(coalesce(v_t.done_by, v_t.assignee), case when coalesce(v_t.done_by, v_t.assignee) is null then v_t.unit_id end, 'team', false, 'task_review',
    case v_status when 'approved' then 'Görevin onaylandı' else 'Görevin geri gönderildi' end,
    '“' || v_t.title || '”' || coalesce(' · Not: ' || v_note, ''), 'b-gorevler');
  perform public.log_activity(case v_status when 'approved' then 'Görevi onayladı' else 'Görevi geri gönderdi' end, v_t.title);
  return null;
end;
$$;

create or replace function public.uwa_task_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_t public.unit_tasks;
begin
  select * into v_t from public.unit_tasks where id = public.uw_uuid(p, 'id');
  if not found or not (public.uw_admin() or (not v_t.by_admin and v_t.unit_id = public.uw_unit() and (public.uw_head() or public.uw_has('team')))) then
    raise exception 'Görev bulunamadı ya da silme yetkin yok.';
  end if;
  delete from public.unit_tasks where id = v_t.id;
  perform public.log_activity('Görevi sildi', v_t.title);
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: iç duyurular (Merkez)
create or replace function public.uwa_ann_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_title text := public.uw_text(p, 'title', 160, true, 'Başlık');
  v_body text := public.uw_text(p, 'body', 5000, true, 'Duyuru metni');
  v_aud uuid[];
  v_id uuid;
  v_u uuid;
begin
  if not public.uw_admin() then raise exception 'Birim duyurusunu yalnızca Merkez Yönetim yapar.'; end if;
  select coalesce(array_agg(distinct u.id), '{}') into v_aud
    from jsonb_array_elements_text(coalesce(p -> 'audience', '[]'::jsonb)) x join public.units u on u.id::text = x;
  insert into public.unit_announcements (title, body, audience, created_by) values (v_title, v_body, v_aud, (select auth.uid())) returning id into v_id;
  for v_u in select id from public.units where cardinality(v_aud) = 0 or id = any(v_aud) loop
    perform public.uw_notify(null, v_u, null, false, 'announcement', 'Yeni duyuru', v_title, 'b-duyurular');
  end loop;
  perform public.log_activity('Birimlere duyuru yaptı', v_title);
  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.uwa_ann_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.uw_admin() then raise exception 'Yetkin yok.'; end if;
  delete from public.unit_announcements where id = public.uw_uuid(p, 'id');
  return null;
end;
$$;

create or replace function public.uwa_ann_read(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_a public.unit_announcements; v_unit uuid := public.uw_unit();
begin
  select * into v_a from public.unit_announcements where id = public.uw_uuid(p, 'id');
  if not found or v_unit is null or not (cardinality(v_a.audience) = 0 or v_unit = any(v_a.audience)) then raise exception 'Duyuru bulunamadı.'; end if;
  insert into public.unit_announcement_reads (announcement_id, user_id) values (v_a.id, (select auth.uid())) on conflict do nothing;
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: belgeler
-- Merkez her yere, birim başkanı kendi birimine belge ekler; herkes görür.
create or replace function public.uwa_doc_add(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_unit uuid := public.uw_uuid(p, 'unit_id'); v_title text := public.uw_text(p, 'title', 160, true, 'Belge adı'); v_url text := public.uw_link(p, 'url');
begin
  if v_url is null then raise exception 'Belgenin bağlantısını yaz.'; end if;
  if not public.uw_admin() then
    if not public.uw_head() then raise exception 'Belgeyi Merkez Yönetim ya da birim başkanı ekler.'; end if;
    v_unit := public.uw_unit();
  elsif v_unit is not null and not exists (select 1 from public.units where id = v_unit) then raise exception 'Birim bulunamadı.';
  end if;
  insert into public.unit_docs (unit_id, title, url, note, created_by) values (v_unit, v_title, v_url, public.uw_text(p, 'note', 500), (select auth.uid()));
  perform public.log_activity('Belge ekledi', v_title);
  return null;
end;
$$;

create or replace function public.uwa_doc_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_d public.unit_docs;
begin
  select * into v_d from public.unit_docs where id = public.uw_uuid(p, 'id');
  if not found or not (public.uw_admin() or (public.uw_head() and v_d.unit_id = public.uw_unit())) then raise exception 'Belge bulunamadı ya da silme yetkin yok.'; end if;
  delete from public.unit_docs where id = v_d.id;
  perform public.log_activity('Belgeyi sildi', v_d.title);
  return null;
end;
$$;

-- ---------------------------------------------------------------- yetkiler
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'uw\_%' or p.proname like 'uwr\_%' or p.proname like 'uwa\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
revoke all on function public.unit_workspace() from public, anon;
grant execute on function public.unit_workspace() to authenticated, service_role;
revoke all on function public.uw(text, jsonb) from public, anon;
grant execute on function public.uw(text, jsonb) to authenticated, service_role;
