-- Sponsorluk "Sponsor Ağı", Kulüp İlişkileri "Kulüp Ağı", Denetim "Denetim Kayıtları" ve birim destek talepleri.
-- Kararlar:
--  * Sponsor Ağı, Sponsorship File ile aynı düzende (kategori sekmeleri + aynı sütunlar) + Paket ve Etkinlik.
--    Aşamalar: Araştırma → İletişim → Görüşme → Teklif → Anlaşma / Olumsuz. Sorumlu Sponsorluk biriminin üyesidir.
--    Sponsor e-postalarını yalnızca Sponsorluk birimi ve Merkez görür. Bütçe kısmı Merkez onayına gider.
--  * Kulüp Ağı: kota yok, kulüp kabulü/çıkışı yok (Merkez'de). Temas kaydı + memnuniyet (1-5) + aday listesi (elle).
--  * Denetim: hedef birim (YK dahil) / etkinlik / kulüp; Merkez kapsam dışı. Uyarı sözlü 1 → sözlü 2 → yazılı →
--    Merkez'e rapor; ağır ihlalde gerekçeyle basamak atlanır. Savunma elden alınır, Denetim kayda geçirir.
--    Sorumlu yalnızca kulüp etkinliklerine atanır; sorumlu etkinlikte kontrol notunu girer. Operasyon durdurulmaz.
--  * Birim destek talepleri Merkez'e gider.

-- ---------------------------------------------------------------- sponsor ağı
create table if not exists public.sponsors (
  id uuid primary key default gen_random_uuid(),
  category text not null check (char_length(category) between 2 and 60),
  brand text not null check (char_length(brand) between 1 and 160),
  email text,
  web text,
  contact_person text,
  owner uuid references auth.users(id) on delete set null,
  stage text not null default 'research' check (stage in ('research', 'contact', 'meeting', 'offer', 'deal', 'lost')),
  last_action date,
  notes text,
  package text check (package is null or package in ('main', 'platinum', 'gold', 'silver')),
  event_label text,
  sort int not null default 1000,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sponsors_category on public.sponsors (category, sort, brand);

create table if not exists public.sponsor_contacts (
  id uuid primary key default gen_random_uuid(),
  sponsor_id uuid not null references public.sponsors(id) on delete cascade,
  at date not null default current_date,
  kind text not null default 'mail' check (kind in ('mail', 'call', 'meeting', 'other')),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists sponsor_contacts_sponsor on public.sponsor_contacts (sponsor_id, at desc);

-- ---------------------------------------------------------------- kulüp ağı
create table if not exists public.club_relations (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  notes text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create table if not exists public.club_contacts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  at date not null default current_date,
  kind text not null default 'message' check (kind in ('message', 'call', 'meeting', 'event', 'other')),
  note text,
  satisfaction smallint check (satisfaction is null or satisfaction between 1 and 5),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists club_contacts_club on public.club_contacts (club_id, at desc);
create table if not exists public.club_candidates (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 160),
  university text,
  contact text,
  status text not null default 'candidate' check (status in ('candidate', 'talking', 'added', 'dropped')),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- denetim
create table if not exists public.audit_records (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('unit', 'event', 'club')),
  target_id uuid not null,
  target_label text not null,
  level text not null check (level in ('note', 'verbal1', 'verbal2', 'written', 'report')),
  skipped boolean not null default false,
  skip_reason text,
  violation text not null,
  evidence text,
  evidence_url text,
  occurred_on date not null default current_date,
  defense text,
  defense_at timestamptz,
  drive_url text,
  center_seen_by uuid references auth.users(id) on delete set null,
  center_seen_at timestamptz,
  center_note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists audit_records_target on public.audit_records (target_type, target_id, created_at);
create table if not exists public.audit_assignments (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  note text,
  check_note text,
  checked_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

-- ---------------------------------------------------------------- birim destek talepleri
create table if not exists public.unit_tickets (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  subject text not null check (char_length(subject) between 2 and 160),
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.unit_ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.unit_tickets(id) on delete cascade,
  author uuid references auth.users(id) on delete set null,
  from_admin boolean not null default false,
  body text not null check (char_length(body) between 1 and 5000),
  created_at timestamptz not null default now()
);

alter table public.sponsors enable row level security;
alter table public.sponsor_contacts enable row level security;
alter table public.club_relations enable row level security;
alter table public.club_contacts enable row level security;
alter table public.club_candidates enable row level security;
alter table public.audit_records enable row level security;
alter table public.audit_assignments enable row level security;
alter table public.unit_tickets enable row level security;
alter table public.unit_ticket_messages enable row level security;
revoke all on public.sponsors, public.sponsor_contacts, public.club_relations, public.club_contacts, public.club_candidates,
              public.audit_records, public.audit_assignments, public.unit_tickets, public.unit_ticket_messages from anon, authenticated;

-- ---------------------------------------------------------------- okuma
create or replace function public.uwr_sponsors()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.uw_admin() or public.uw_kind() = 'sponsor') then return null; end if;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'category', s.category, 'brand', s.brand, 'email', s.email, 'web', s.web,
        'contact_person', s.contact_person, 'owner', s.owner, 'owner_name', public.uw_name(s.owner), 'stage', s.stage,
        'last_action', greatest(s.last_action, (select max(c.at) from public.sponsor_contacts c where c.sponsor_id = s.id)),
        'contacts', (select count(*) from public.sponsor_contacts c where c.sponsor_id = s.id),
        'notes', s.notes, 'package', s.package, 'event_label', s.event_label, 'updated_at', s.updated_at,
        'budget', (select jsonb_build_object('status', r.status, 'note', r.note) from public.unit_requests r where r.kind = 'sponsor' and r.ref_id = s.id order by r.created_at desc limit 1))
        order by s.category, s.sort, s.brand) from public.sponsors s), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'sponsor_id', c.sponsor_id, 'at', c.at, 'kind', c.kind, 'note', c.note,
        'by_name', public.uw_name(c.created_by)) order by c.at desc, c.created_at desc)
        from (select * from public.sponsor_contacts order by at desc, created_at desc limit 1000) c), '[]'::jsonb));
end;
$$;

create or replace function public.uwr_clubnet()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.uw_admin() or public.uw_kind() = 'clubs') then return null; end if;
  return jsonb_build_object(
    'clubs', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'university', c.university, 'category', c.category,
        'joined_at', c.created_at, 'notes', r.notes, 'last_contact', (select max(x.at) from public.club_contacts x where x.club_id = c.id),
        'satisfaction', (select x.satisfaction from public.club_contacts x where x.club_id = c.id and x.satisfaction is not null order by x.at desc, x.created_at desc limit 1))
        order by c.name) from public.clubs c left join public.club_relations r on r.club_id = c.id), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'club_id', x.club_id, 'at', x.at, 'kind', x.kind, 'note', x.note,
        'satisfaction', x.satisfaction, 'by_name', public.uw_name(x.created_by)) order by x.at desc, x.created_at desc)
        from (select * from public.club_contacts order by at desc, created_at desc limit 1000) x), '[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'university', k.university, 'contact', k.contact,
        'status', k.status, 'note', k.note, 'updated_at', k.updated_at) order by k.updated_at desc) from public.club_candidates k), '[]'::jsonb));
end;
$$;

create or replace function public.uwr_audit()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_full boolean := public.uw_admin() or public.uw_can('audit', 'audit') or public.uw_can('audit', 'audit_assign');
begin
  if not (v_admin or public.uw_kind() = 'audit') then return null; end if;
  return jsonb_build_object(
    'records', case when v_full then coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'target_type', a.target_type, 'target_id', a.target_id,
        'target_label', a.target_label, 'level', a.level, 'skipped', a.skipped, 'skip_reason', a.skip_reason, 'violation', a.violation,
        'evidence', a.evidence, 'evidence_url', a.evidence_url, 'occurred_on', a.occurred_on, 'defense', a.defense, 'defense_at', a.defense_at,
        'drive_url', a.drive_url, 'center_seen_by_name', public.uw_name(a.center_seen_by), 'center_seen_at', a.center_seen_at, 'center_note', a.center_note,
        'created_by_name', public.uw_name(a.created_by), 'created_at', a.created_at) order by a.created_at desc) from public.audit_records a), '[]'::jsonb) else '[]'::jsonb end,
    -- Denetim tüm kulüp etkinliklerini görür (yayında olmayanlar dahil).
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'title', e.title, 'date', e.event_date, 'time', e.event_time, 'place', e.place,
        'status', e.status, 'club_id', e.club_id, 'club_name', (select c.name from public.clubs c where c.id = e.club_id),
        'assignees', coalesce((select jsonb_agg(jsonb_build_object('user_id', s.user_id, 'name', public.uw_name(s.user_id), 'note', s.note,
            'check_note', s.check_note, 'checked_at', s.checked_at)) from public.audit_assignments s where s.event_id = e.id), '[]'::jsonb))
        order by e.event_date desc)
      from public.events e where e.club_id is not null and (v_full or exists (select 1 from public.audit_assignments s where s.event_id = e.id and s.user_id = (select auth.uid())))), '[]'::jsonb));
end;
$$;

create or replace function public.uwr_support()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_unit uuid := public.uw_unit(); v_head boolean := public.uw_head();
begin
  if not v_admin and v_unit is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'unit_id', t.unit_id, 'subject', t.subject, 'status', t.status,
      'created_by', t.created_by, 'created_by_name', public.uw_name(t.created_by), 'created_at', t.created_at, 'updated_at', t.updated_at,
      'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'from_admin', m.from_admin, 'author_name', public.uw_name(m.author),
          'body', m.body, 'created_at', m.created_at) order by m.created_at) from public.unit_ticket_messages m where m.ticket_id = t.id), '[]'::jsonb))
      order by t.updated_at desc)
    from public.unit_tickets t where v_admin or t.created_by = (select auth.uid()) or (v_head and t.unit_id = v_unit)), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- işlemler: sponsor
create or replace function public.uw_sponsor_lead()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_can('sponsor', 'sponsors');
$$;

create or replace function public.uwa_sponsor_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := public.uw_uuid(p, 'id'); v_owner uuid := public.uw_uuid(p, 'owner'); v_s public.sponsors;
  v_stage text := coalesce(nullif(p ->> 'stage', ''), 'research'); v_pkg text := nullif(p ->> 'package', ''); v_email text := lower(public.uw_text(p, 'email', 200));
begin
  if not public.uw_sponsor_lead() then raise exception 'Bu işlem için Sponsorluk’ta sponsor yetkisi gerekir.'; end if;
  if v_owner is not null and not exists (select 1 from public.unit_members where user_id = v_owner and unit_id = public.uw_unit() and status = 'active') then
    raise exception 'Sorumlu Sponsorluk biriminden olmalı.';
  end if;
  if v_email is not null and v_email !~ '^[^\s@<>"'']+@[^\s@<>"'']+\.[^\s@<>"'']+$' then raise exception 'E-posta adresi geçersiz.'; end if;
  if v_stage not in ('research', 'contact', 'meeting', 'offer', 'deal', 'lost') then raise exception 'Geçersiz aşama.'; end if;
  if v_pkg is not null and v_pkg not in ('main', 'platinum', 'gold', 'silver') then raise exception 'Geçersiz paket.'; end if;
  if v_id is null then
    insert into public.sponsors (category, brand, email, web, contact_person, owner, stage, last_action, notes, package, event_label, created_by)
    values (public.uw_text(p, 'category', 60, true, 'Kategori'), public.uw_text(p, 'brand', 160, true, 'Marka'), v_email, public.uw_text(p, 'web', 300),
            public.uw_text(p, 'contact_person', 200), v_owner, v_stage, nullif(p ->> 'last_action', '')::date, public.uw_text(p, 'notes', 4000),
            v_pkg, public.uw_text(p, 'event_label', 160), (select auth.uid()))
    returning * into v_s;
    perform public.log_activity('Sponsor ekledi', v_s.brand);
  else
    update public.sponsors set category = public.uw_text(p, 'category', 60, true, 'Kategori'), brand = public.uw_text(p, 'brand', 160, true, 'Marka'),
      email = v_email, web = public.uw_text(p, 'web', 300), contact_person = public.uw_text(p, 'contact_person', 200), owner = v_owner,
      stage = v_stage, last_action = nullif(p ->> 'last_action', '')::date, notes = public.uw_text(p, 'notes', 4000), package = v_pkg,
      event_label = public.uw_text(p, 'event_label', 160), updated_at = now()
     where id = v_id returning * into v_s;
    if not found then raise exception 'Sponsor bulunamadı.'; end if;
    perform public.log_activity('Sponsoru güncelledi', v_s.brand);
  end if;
  if v_owner is not null and v_owner <> (select auth.uid()) then
    perform public.uw_notify(v_owner, null, null, false, 'sponsor', 'Sponsor sorumlusu oldun', v_s.brand, 'b-sponsorlar');
  end if;
  return jsonb_build_object('id', v_s.id);
end;
$$;

create or replace function public.uwa_sponsor_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.sponsors;
begin
  if not (public.uw_sponsor_lead() and (public.uw_head() or public.uw_has('team'))) then raise exception 'Sponsoru birim başkanı ya da ekip yöneticisi siler.'; end if;
  delete from public.sponsors where id = public.uw_uuid(p, 'id') returning * into v_s;
  if not found then raise exception 'Sponsor bulunamadı.'; end if;
  perform public.log_activity('Sponsoru sildi', v_s.brand);
  return null;
end;
$$;

-- Görüşme kaydı: sayı ve son işlem tarihi buradan otomatik çıkar.
create or replace function public.uwa_sponsor_contact(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.sponsors; v_kind text := coalesce(nullif(p ->> 'kind', ''), 'mail');
begin
  if not public.uw_sponsor_lead() then raise exception 'Bu işlem için Sponsorluk’ta sponsor yetkisi gerekir.'; end if;
  select * into v_s from public.sponsors where id = public.uw_uuid(p, 'sponsor_id');
  if not found then raise exception 'Sponsor bulunamadı.'; end if;
  if v_kind not in ('mail', 'call', 'meeting', 'other') then raise exception 'Geçersiz görüşme türü.'; end if;
  insert into public.sponsor_contacts (sponsor_id, at, kind, note, created_by)
  values (v_s.id, coalesce(nullif(p ->> 'at', '')::date, current_date), v_kind, public.uw_text(p, 'note', 2000), (select auth.uid()));
  update public.sponsors set stage = case when stage = 'research' then 'contact' else stage end, updated_at = now() where id = v_s.id;
  perform public.log_activity('Sponsor görüşmesi kaydetti', v_s.brand);
  return null;
end;
$$;

create or replace function public.uwa_sponsor_contact_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.uw_sponsor_lead() then raise exception 'Bu işlem için Sponsorluk’ta sponsor yetkisi gerekir.'; end if;
  delete from public.sponsor_contacts where id = public.uw_uuid(p, 'id');
  return null;
end;
$$;

-- Bütçe gerektiren sponsor işi Merkez onayına gider.
create or replace function public.uwa_sponsor_budget(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.sponsors; v_note text := public.uw_text(p, 'note', 1000, true, 'Bütçe açıklaması');
begin
  if not public.uw_sponsor_lead() then raise exception 'Bu işlem için Sponsorluk’ta sponsor yetkisi gerekir.'; end if;
  select * into v_s from public.sponsors where id = public.uw_uuid(p, 'id');
  if not found then raise exception 'Sponsor bulunamadı.'; end if;
  if exists (select 1 from public.unit_requests where kind = 'sponsor' and ref_id = v_s.id and status = 'center') then raise exception 'Bu sponsor için bekleyen bir bütçe talebi var.'; end if;
  perform public.uw_req_open('sponsor', v_s.id, v_s.brand, v_note, true, v_note, 'center');
  perform public.log_activity('Sponsor bütçesini Merkez onayına gönderdi', v_s.brand);
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: kulüp ağı
create or replace function public.uw_club_lead()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_can('clubs', 'clubs');
$$;

create or replace function public.uwa_club_note(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_club uuid := public.uw_uuid(p, 'club_id');
begin
  if not public.uw_club_lead() then raise exception 'Bu işlem için Kulüp İlişkileri’nde kulüp ağı yetkisi gerekir.'; end if;
  if not exists (select 1 from public.clubs where id = v_club) then raise exception 'Kulüp bulunamadı.'; end if;
  insert into public.club_relations (club_id, notes, updated_by, updated_at) values (v_club, public.uw_text(p, 'notes', 4000), (select auth.uid()), now())
  on conflict (club_id) do update set notes = excluded.notes, updated_by = excluded.updated_by, updated_at = now();
  return null;
end;
$$;

create or replace function public.uwa_club_contact(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_club uuid := public.uw_uuid(p, 'club_id'); v_kind text := coalesce(nullif(p ->> 'kind', ''), 'message'); v_sat int := nullif(p ->> 'satisfaction', '')::int;
begin
  if not public.uw_club_lead() then raise exception 'Bu işlem için Kulüp İlişkileri’nde kulüp ağı yetkisi gerekir.'; end if;
  if not exists (select 1 from public.clubs where id = v_club) then raise exception 'Kulüp bulunamadı.'; end if;
  if v_kind not in ('message', 'call', 'meeting', 'event', 'other') then raise exception 'Geçersiz temas türü.'; end if;
  if v_sat is not null and v_sat not between 1 and 5 then raise exception 'Memnuniyet 1 ile 5 arasında olmalı.'; end if;
  insert into public.club_contacts (club_id, at, kind, note, satisfaction, created_by)
  values (v_club, coalesce(nullif(p ->> 'at', '')::date, current_date), v_kind, public.uw_text(p, 'note', 2000), v_sat, (select auth.uid()));
  perform public.log_activity('Kulüple temas kaydetti', (select name from public.clubs where id = v_club));
  return null;
end;
$$;

create or replace function public.uwa_club_contact_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.uw_club_lead() then raise exception 'Bu işlem için Kulüp İlişkileri’nde kulüp ağı yetkisi gerekir.'; end if;
  delete from public.club_contacts where id = public.uw_uuid(p, 'id');
  return null;
end;
$$;

create or replace function public.uwa_club_cand_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := public.uw_uuid(p, 'id'); v_status text := coalesce(nullif(p ->> 'status', ''), 'candidate');
begin
  if not public.uw_club_lead() then raise exception 'Bu işlem için Kulüp İlişkileri’nde kulüp ağı yetkisi gerekir.'; end if;
  if v_status not in ('candidate', 'talking', 'added', 'dropped') then raise exception 'Geçersiz durum.'; end if;
  if v_id is null then
    insert into public.club_candidates (name, university, contact, status, note, created_by)
    values (public.uw_text(p, 'name', 160, true, 'Kulüp adı'), public.uw_text(p, 'university', 160), public.uw_text(p, 'contact', 300), v_status, public.uw_text(p, 'note', 2000), (select auth.uid()));
    perform public.log_activity('Aday kulüp ekledi', p ->> 'name');
  else
    update public.club_candidates set name = public.uw_text(p, 'name', 160, true, 'Kulüp adı'), university = public.uw_text(p, 'university', 160),
      contact = public.uw_text(p, 'contact', 300), status = v_status, note = public.uw_text(p, 'note', 2000), updated_at = now() where id = v_id;
    if not found then raise exception 'Aday bulunamadı.'; end if;
  end if;
  return null;
end;
$$;

create or replace function public.uwa_club_cand_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.uw_club_lead() then raise exception 'Bu işlem için Kulüp İlişkileri’nde kulüp ağı yetkisi gerekir.'; end if;
  delete from public.club_candidates where id = public.uw_uuid(p, 'id');
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: denetim
create or replace function public.uwa_audit_add(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_type text := p ->> 'target_type'; v_target uuid := public.uw_uuid(p, 'target_id'); v_label text; v_mode text := coalesce(p ->> 'mode', 'warning');
  v_level text; v_prev int; v_skip boolean := false; v_reason text := public.uw_text(p, 'skip_reason', 1000); v_id uuid;
begin
  if not public.uw_can('audit', 'audit') then raise exception 'Bu işlem için Denetim’de denetim kaydı yetkisi gerekir.'; end if;
  v_label := case v_type
    when 'unit' then (select name from public.units where id = v_target)
    when 'event' then (select e.title || coalesce(' · ' || c.name, '') from public.events e left join public.clubs c on c.id = e.club_id where e.id = v_target)
    when 'club' then (select name from public.clubs where id = v_target) end;
  if v_label is null then raise exception 'Denetlenen birim, etkinlik ya da kulüp bulunamadı.'; end if;
  select count(*) into v_prev from public.audit_records where target_type = v_type and target_id = v_target and level <> 'note';
  if v_mode = 'note' then v_level := 'note';
  elsif v_mode = 'skip' then
    v_level := p ->> 'level';
    if v_level not in ('verbal2', 'written', 'report') then raise exception 'Atlanacak basamağı seç.'; end if;
    if v_reason is null then raise exception 'Basamak atlamak için gerekçe yaz.'; end if;
    v_skip := true;
  else
    v_level := case when v_prev = 0 then 'verbal1' when v_prev = 1 then 'verbal2' when v_prev = 2 then 'written' else 'report' end;
  end if;
  insert into public.audit_records (target_type, target_id, target_label, level, skipped, skip_reason, violation, evidence, evidence_url, occurred_on, drive_url, created_by)
  values (v_type, v_target, v_label, v_level, v_skip, case when v_skip then v_reason end, public.uw_text(p, 'violation', 4000, true, 'Tespit'),
          public.uw_text(p, 'evidence', 4000), public.uw_link(p, 'evidence_url'), coalesce(nullif(p ->> 'occurred_on', '')::date, current_date),
          public.uw_link(p, 'drive_url'), (select auth.uid()))
  returning id into v_id;
  if v_level = 'report' then
    perform public.uw_notify(null, null, null, true, 'audit_report', 'Denetim raporu: ' || v_label, left(p ->> 'violation', 300), 'b-onaylar');
  end if;
  perform public.log_activity('Denetim kaydı açtı', v_label);
  return jsonb_build_object('id', v_id, 'level', v_level);
end;
$$;

create or replace function public.uwa_audit_update(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_a public.audit_records; v_def text := public.uw_text(p, 'defense', 4000);
begin
  if not public.uw_can('audit', 'audit') then raise exception 'Bu işlem için Denetim’de denetim kaydı yetkisi gerekir.'; end if;
  update public.audit_records set defense = v_def, defense_at = case when v_def is distinct from defense then case when v_def is null then null else now() end else defense_at end,
         drive_url = public.uw_link(p, 'drive_url'), evidence = public.uw_text(p, 'evidence', 4000), evidence_url = public.uw_link(p, 'evidence_url')
   where id = public.uw_uuid(p, 'id') returning * into v_a;
  if not found then raise exception 'Kayıt bulunamadı.'; end if;
  perform public.log_activity('Denetim kaydını güncelledi', v_a.target_label);
  return null;
end;
$$;

-- Merkez'e gelen raporu görüldü olarak işaretler.
create or replace function public.uwa_audit_seen(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_a public.audit_records;
begin
  if not public.uw_admin() then raise exception 'Bu işlemi Merkez Yönetim yapar.'; end if;
  update public.audit_records set center_seen_by = (select auth.uid()), center_seen_at = now(), center_note = public.uw_text(p, 'note', 2000)
   where id = public.uw_uuid(p, 'id') and level = 'report' returning * into v_a;
  if not found then raise exception 'Rapor bulunamadı.'; end if;
  perform public.uw_notify(null, public.uw_unit_of_kind('audit'), 'audit', false, 'audit_seen', 'Merkez raporu inceledi', v_a.target_label || coalesce(' · Not: ' || v_a.center_note, ''), 'b-denetim');
  perform public.log_activity('Denetim raporunu inceledi', v_a.target_label);
  return null;
end;
$$;

create or replace function public.uwa_audit_assign(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_event uuid := public.uw_uuid(p, 'event_id'); v_user uuid := public.uw_uuid(p, 'user_id'); v_title text;
begin
  if not public.uw_can('audit', 'audit_assign') then raise exception 'Bu işlem için Denetim’de sorumlu atama yetkisi gerekir.'; end if;
  select title into v_title from public.events where id = v_event and club_id is not null;
  if v_title is null then raise exception 'Sorumlu yalnızca kulüp etkinliklerine atanır.'; end if;
  if not exists (select 1 from public.unit_members where user_id = v_user and unit_id = public.uw_unit() and status = 'active') then raise exception 'Sorumlu Denetim ekibinden olmalı.'; end if;
  insert into public.audit_assignments (event_id, user_id, assigned_by, note) values (v_event, v_user, (select auth.uid()), public.uw_text(p, 'note', 1000))
  on conflict (event_id, user_id) do update set note = excluded.note;
  perform public.uw_notify(v_user, null, null, false, 'audit_assign', 'Etkinlik kontrolü sana atandı', v_title, 'b-denetim');
  perform public.log_activity('Etkinliğe denetim sorumlusu atadı', v_title);
  return null;
end;
$$;

create or replace function public.uwa_audit_unassign(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.uw_can('audit', 'audit_assign') then raise exception 'Bu işlem için Denetim’de sorumlu atama yetkisi gerekir.'; end if;
  delete from public.audit_assignments where event_id = public.uw_uuid(p, 'event_id') and user_id = public.uw_uuid(p, 'user_id');
  return null;
end;
$$;

-- Atanan kişi etkinlikteki kontrol notunu girer.
create or replace function public.uwa_audit_check(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_note text := public.uw_text(p, 'note', 4000, true, 'Kontrol notu'); v_event uuid := public.uw_uuid(p, 'event_id'); v_title text;
begin
  update public.audit_assignments set check_note = v_note, checked_at = now() where event_id = v_event and user_id = (select auth.uid());
  if not found then raise exception 'Bu etkinliğin kontrolü sana atanmamış.'; end if;
  select title into v_title from public.events where id = v_event;
  perform public.uw_notify(null, public.uw_unit_of_kind('audit'), 'audit', false, 'audit_check', 'Etkinlik kontrol notu girildi', v_title, 'b-denetim');
  perform public.log_activity('Etkinlik kontrol notu girdi', v_title);
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: birim destek talepleri
create or replace function public.uwa_support_open(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_subject text := public.uw_text(p, 'subject', 160, true, 'Konu');
begin
  if public.uw_unit() is null then raise exception 'Birim destek talebini birim üyeleri açar.'; end if;
  insert into public.unit_tickets (unit_id, created_by, subject) values (public.uw_unit(), (select auth.uid()), v_subject) returning id into v_id;
  insert into public.unit_ticket_messages (ticket_id, author, from_admin, body) values (v_id, (select auth.uid()), false, public.uw_text(p, 'body', 5000, true, 'Mesaj'));
  perform public.uw_notify(null, null, null, true, 'support', 'Birimden destek talebi', v_subject, 'b-destek');
  perform public.log_activity('Destek talebi açtı', v_subject);
  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.uwa_support_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_t public.unit_tickets; v_admin boolean := public.uw_admin();
begin
  select * into v_t from public.unit_tickets where id = public.uw_uuid(p, 'id') for update;
  if not found or not (v_admin or v_t.created_by = (select auth.uid()) or (public.uw_head() and v_t.unit_id = public.uw_unit())) then raise exception 'Talep bulunamadı.'; end if;
  if v_t.status = 'closed' and not v_admin then raise exception 'Bu talep kapatıldı.'; end if;
  insert into public.unit_ticket_messages (ticket_id, author, from_admin, body) values (v_t.id, (select auth.uid()), v_admin, public.uw_text(p, 'body', 5000, true, 'Mesaj'));
  update public.unit_tickets set status = case when v_admin then 'answered' else 'open' end, updated_at = now() where id = v_t.id;
  if v_admin then perform public.uw_notify(v_t.created_by, null, null, false, 'support', 'Destek talebin yanıtlandı', v_t.subject, 'b-destek');
  else perform public.uw_notify(null, null, null, true, 'support', 'Destek talebine yeni mesaj', v_t.subject, 'b-destek'); end if;
  return null;
end;
$$;

create or replace function public.uwa_support_close(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_t public.unit_tickets;
begin
  select * into v_t from public.unit_tickets where id = public.uw_uuid(p, 'id');
  if not found or not (public.uw_admin() or v_t.created_by = (select auth.uid())) then raise exception 'Talep bulunamadı.'; end if;
  update public.unit_tickets set status = case when coalesce((p ->> 'reopen')::boolean, false) then 'open' else 'closed' end, updated_at = now() where id = v_t.id;
  return null;
end;
$$;

-- Sponsor bütçe talebi sonucu Sponsor Ağı'na; detayı onay kartında görünür.
create or replace function public.uwr_requests()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_board boolean := public.uw_board(); v_unit uuid := public.uw_unit();
begin
  if not v_admin and v_unit is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'ref_id', r.ref_id, 'from_unit', r.from_unit, 'title', r.title,
      'summary', r.summary, 'needs_budget', r.needs_budget, 'budget_note', r.budget_note, 'status', r.status,
      'board_by_name', public.uw_name(r.board_by), 'board_at', r.board_at, 'center_by_name', public.uw_name(r.center_by), 'center_at', r.center_at,
      'note', r.note, 'created_by_name', public.uw_name(r.created_by), 'created_at', r.created_at, 'can_decide', public.uw_req_can_decide(r),
      'detail', case r.kind
        when 'post' then (select jsonb_build_object('body', s.body, 'design_url', s.design_url, 'platforms', s.platforms, 'format', s.format, 'plan_at', s.plan_at, 'brief', s.brief) from public.social_posts s where s.id = r.ref_id)
        when 'campaign' then (select jsonb_build_object('idea', c.idea, 'goal', c.goal) from public.pr_campaigns c where c.id = r.ref_id)
        when 'sponsor' then (select jsonb_build_object('category', s.category, 'stage', s.stage, 'package', s.package, 'event_label', s.event_label, 'contact_person', s.contact_person) from public.sponsors s where s.id = r.ref_id)
        else null end) order by r.created_at desc)
    from (select * from public.unit_requests r
           where v_admin or v_board or r.from_unit = v_unit
           order by r.created_at desc limit 300) r), '[]'::jsonb);
end;
$$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'uw\_%' or p.proname like 'uwr\_%' or p.proname like 'uwa\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
