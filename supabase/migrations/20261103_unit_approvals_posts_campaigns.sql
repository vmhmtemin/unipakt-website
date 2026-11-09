-- Birim onay akışı, Sosyal Medya Yayın Akışı, Halkla İlişkiler Kampanyaları, rapor talepleri ve marka kiti notu.
-- Kurallar (Mehmet'in kararları):
--  * Yayın: YK'dan approve yetkili HERHANGİ bir üye ya da Merkez onaylar; biri onaylayınca iş herkesin listesinden düşer.
--  * Kampanya: PR'ın her kartı kampanyadır, YK onayına gider; bütçe varsa YK'dan SONRA Merkez onayına gider (sıralı).
--  * Merkez YK'nın yerine kampanya onayı vermez; YK birimi yoksa kampanya YK onayında bekler.
--  * YK onayı olmadan yayın "Yayınlandı" olamaz (sunucu da engeller).

-- ---------------------------------------------------------------- onay talepleri
create table if not exists public.unit_requests (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('post', 'campaign', 'sponsor')),
  ref_id uuid not null,
  from_unit uuid references public.units(id) on delete set null,
  title text not null,
  summary text,
  needs_budget boolean not null default false,
  budget_note text,
  status text not null check (status in ('board', 'center', 'approved', 'rejected', 'cancelled')),
  board_by uuid references auth.users(id) on delete set null,
  board_at timestamptz,
  center_by uuid references auth.users(id) on delete set null,
  center_at timestamptz,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists unit_requests_status on public.unit_requests (status, created_at desc);
create index if not exists unit_requests_ref on public.unit_requests (ref_id);

-- ---------------------------------------------------------------- yayın akışı
create table if not exists public.social_posts (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'request' check (status in ('request', 'preparing', 'approval', 'planned', 'published', 'declined')),
  source text not null check (source in ('announcement', 'unit', 'admin')),
  announcement_id uuid unique references public.announcements(id) on delete set null,
  from_unit uuid references public.units(id) on delete set null,
  requested_by uuid references auth.users(id) on delete set null,
  title text not null check (char_length(title) between 2 and 160),
  brief text,
  body text,
  design_url text,
  platforms text[] not null default '{}' check (platforms <@ array['instagram', 'linkedin', 'x', 'tiktok', 'youtube', 'web']::text[]),
  format text check (format is null or format in ('post', 'carousel', 'story', 'reel', 'video', 'text')),
  plan_at timestamptz,
  assignee uuid references auth.users(id) on delete set null,
  note text,
  request_id uuid references public.unit_requests(id) on delete set null,
  published_at timestamptz,
  published_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- kampanyalar
create table if not exists public.pr_campaigns (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 160),
  idea text,
  goal text,
  has_budget boolean not null default false,
  budget_note text,
  status text not null default 'draft' check (status in ('draft', 'approval', 'approved', 'rejected', 'done')),
  request_id uuid references public.unit_requests(id) on delete set null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- rapor talepleri (Merkez → birim)
create table if not exists public.unit_reports (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 160),
  details text,
  due_date date,
  status text not null default 'open' check (status in ('open', 'answered')),
  answer text,
  answer_url text,
  asked_by uuid references auth.users(id) on delete set null,
  answered_by uuid references auth.users(id) on delete set null,
  answered_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- birim notları (marka kiti: marka dili)
create table if not exists public.unit_notes (
  unit_id uuid primary key references public.units(id) on delete cascade,
  body text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.unit_requests enable row level security;
alter table public.social_posts enable row level security;
alter table public.pr_campaigns enable row level security;
alter table public.unit_reports enable row level security;
alter table public.unit_notes enable row level security;
revoke all on public.unit_requests, public.social_posts, public.pr_campaigns, public.unit_reports, public.unit_notes from anon, authenticated;

-- YK onaycısı mı?
create or replace function public.uw_board()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_can('board', 'approve');
$$;

-- Talebin şu anki aşamasında karar verebilir mi?
create or replace function public.uw_req_can_decide(r public.unit_requests)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when r.status = 'board' and r.kind = 'post' then public.uw_board() or public.uw_admin()
    when r.status = 'board' then public.uw_board()
    when r.status = 'center' then public.uw_admin()
    else false end;
$$;

-- Yeni talep: onaycılara bildirim.
create or replace function public.uw_req_open(p_kind text, p_ref uuid, p_title text, p_summary text, p_budget boolean, p_budget_note text, p_status text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_board uuid := public.uw_unit_of_kind('board'); v_label text;
begin
  v_label := case p_kind when 'post' then 'Yayın onayı' when 'campaign' then 'Kampanya onayı' else 'Bütçe onayı' end;
  insert into public.unit_requests (kind, ref_id, from_unit, title, summary, needs_budget, budget_note, status, created_by)
  values (p_kind, p_ref, public.uw_unit(), p_title, p_summary, coalesce(p_budget, false), p_budget_note, p_status, (select auth.uid()))
  returning id into v_id;
  if p_status = 'board' then
    perform public.uw_notify(null, v_board, 'approve', false, 'request', v_label || ' bekliyor', p_title, 'b-onaylar');
    if p_kind = 'post' then perform public.uw_notify(null, null, null, true, 'request', v_label || ' bekliyor', p_title, 'b-onaylar'); end if;
  else
    perform public.uw_notify(null, null, null, true, 'request', v_label || ' bekliyor', p_title, 'b-onaylar');
  end if;
  return v_id;
end;
$$;

-- Talep sonuçlanınca kaynağına işlenir.
create or replace function public.uw_req_apply(r public.unit_requests)
returns void language plpgsql security definer set search_path = '' as $$
declare v_view text := case r.kind when 'post' then 'b-yayin' when 'campaign' then 'b-kampanyalar' else 'b-sponsorlar' end;
begin
  if r.kind = 'post' then
    if r.status = 'approved' then update public.social_posts set status = 'planned', note = r.note, updated_at = now() where id = r.ref_id and status = 'approval';
    elsif r.status = 'rejected' then update public.social_posts set status = 'preparing', note = r.note, updated_at = now() where id = r.ref_id and status = 'approval';
    end if;
  elsif r.kind = 'campaign' then
    if r.status in ('approved', 'rejected') then update public.pr_campaigns set status = r.status, note = r.note, updated_at = now() where id = r.ref_id and status = 'approval'; end if;
  end if;
  if r.status in ('approved', 'rejected') then
    perform public.uw_notify(r.created_by, null, null, false, 'request_result',
      case r.status when 'approved' then 'Onaylandı: ' else 'Reddedildi: ' end || r.title, coalesce('Not: ' || r.note, ''), v_view);
  end if;
end;
$$;

-- ---------------------------------------------------------------- okuma
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
        else null end) order by r.created_at desc)
    from (select * from public.unit_requests r
           where v_admin or v_board or r.from_unit = v_unit
           order by r.created_at desc limit 300) r), '[]'::jsonb);
end;
$$;

create or replace function public.uwr_posts()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_all boolean := public.uw_admin() or public.uw_kind() = 'social' or public.uw_board(); v_unit uuid := public.uw_unit();
begin
  if not v_all and v_unit is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'status', s.status, 'source', s.source, 'announcement_id', s.announcement_id,
      'from_unit', s.from_unit, 'requested_by_name', public.uw_name(s.requested_by), 'title', s.title, 'brief', s.brief, 'body', s.body,
      'design_url', s.design_url, 'platforms', s.platforms, 'format', s.format, 'plan_at', s.plan_at, 'assignee', s.assignee,
      'assignee_name', public.uw_name(s.assignee), 'note', s.note, 'request_id', s.request_id, 'published_at', s.published_at,
      'published_url', s.published_url, 'created_at', s.created_at, 'updated_at', s.updated_at) order by s.created_at desc)
    from public.social_posts s where v_all or s.from_unit = v_unit), '[]'::jsonb);
end;
$$;

-- Sosyal Medya'nın gelen kutusu için Merkez'in onayladığı kulüp duyuruları (son 90 gün, akışa alınmamış).
create or replace function public.uwr_post_inbox()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.uw_admin() or public.uw_kind() = 'social') then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'club_id', a.club_id,
      'club_name', (select c.name from public.clubs c where c.id = a.club_id), 'created_at', coalesce(a.decided_at, a.created_at)) order by coalesce(a.decided_at, a.created_at) desc)
    from public.announcements a
    where a.status = 'published' and a.club_id is not null and coalesce(a.decided_at, a.created_at) > now() - interval '90 days'
      and not exists (select 1 from public.social_posts s where s.announcement_id = a.id)), '[]'::jsonb);
end;
$$;

create or replace function public.uwr_campaigns()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.uw_admin() or public.uw_kind() = 'pr' or public.uw_board()) then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.title, 'idea', c.idea, 'goal', c.goal, 'has_budget', c.has_budget,
      'budget_note', c.budget_note, 'status', c.status, 'request_id', c.request_id, 'note', c.note, 'created_by_name', public.uw_name(c.created_by),
      'created_at', c.created_at, 'updated_at', c.updated_at) order by c.updated_at desc)
    from public.pr_campaigns c), '[]'::jsonb);
end;
$$;

create or replace function public.uwr_reports()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_unit uuid := public.uw_unit();
begin
  if not v_admin and v_unit is null then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'unit_id', r.unit_id, 'title', r.title, 'details', r.details, 'due_date', r.due_date,
      'status', r.status, 'answer', r.answer, 'answer_url', r.answer_url, 'asked_by_name', public.uw_name(r.asked_by),
      'answered_by_name', public.uw_name(r.answered_by), 'answered_at', r.answered_at, 'created_at', r.created_at) order by r.created_at desc)
    from public.unit_reports r where v_admin or r.unit_id = v_unit), '[]'::jsonb);
end;
$$;

create or replace function public.uwr_notes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.uw_admin() and public.uw_unit() is null then return null; end if;
  return coalesce((select jsonb_object_agg(n.unit_id, jsonb_build_object('body', n.body, 'updated_by_name', public.uw_name(n.updated_by), 'updated_at', n.updated_at))
    from public.unit_notes n), '{}'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- işlemler: onay
create or replace function public.uwa_req_decide(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.unit_requests; v_ok boolean := (p ->> 'decision') = 'approved'; v_note text := public.uw_text(p, 'note', 1000);
begin
  select * into r from public.unit_requests where id = public.uw_uuid(p, 'id') for update;
  if not found then raise exception 'Talep bulunamadı.'; end if;
  if r.status not in ('board', 'center') then raise exception 'Bu talep zaten sonuçlanmış.'; end if;
  if not public.uw_req_can_decide(r) then
    raise exception '%', case when r.status = 'center' then 'Bu aşamada yalnızca Merkez Yönetim karar verir.' else 'Bu aşamada YK karar verir.' end;
  end if;
  if (p ->> 'decision') not in ('approved', 'rejected') then raise exception 'Geçersiz karar.'; end if;
  if not v_ok and v_note is null then raise exception 'Reddetmek için not yaz.'; end if;
  if r.status = 'board' then
    update public.unit_requests set board_by = (select auth.uid()), board_at = now(), note = v_note,
      status = case when not v_ok then 'rejected' when needs_budget then 'center' else 'approved' end
     where id = r.id returning * into r;
    if r.status = 'center' then
      perform public.uw_notify(null, null, null, true, 'request', 'Bütçe onayı bekliyor', r.title || ' · YK onayladı', 'b-onaylar');
      perform public.uw_notify(r.created_by, null, null, false, 'request_result', 'YK onayladı, Merkez onayında: ' || r.title, coalesce('Not: ' || v_note, ''), 'b-kampanyalar');
    end if;
  else
    update public.unit_requests set center_by = (select auth.uid()), center_at = now(), note = coalesce(v_note, note),
      status = case when v_ok then 'approved' else 'rejected' end
     where id = r.id returning * into r;
  end if;
  perform public.uw_req_apply(r);
  perform public.log_activity(case when v_ok then 'Talebi onayladı' else 'Talebi reddetti' end, r.title);
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: yayın akışı
create or replace function public.uw_post_lead()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_can('social', 'posts');
$$;

-- Paylaşım talebi: YK (approve), PR (campaigns), Sponsorluk (sponsors), Sosyal Medya (posts) ve Merkez gönderebilir.
create or replace function public.uwa_post_request(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_admin boolean := public.uw_admin(); v_id uuid; v_title text := public.uw_text(p, 'title', 160, true, 'Başlık'); v_social boolean := public.uw_post_lead();
begin
  if not (v_admin or v_social or public.uw_board() or public.uw_can('pr', 'campaigns') or public.uw_can('sponsor', 'sponsors')) then
    raise exception 'Paylaşım talebini YK, Halkla İlişkiler, Sponsorluk ve Merkez Yönetim gönderebilir.';
  end if;
  insert into public.social_posts (status, source, from_unit, requested_by, title, brief, plan_at)
  values (case when v_social then 'preparing' else 'request' end, case when v_admin then 'admin' else 'unit' end,
          case when v_admin then null else public.uw_unit() end, (select auth.uid()), v_title,
          public.uw_text(p, 'brief', 4000), nullif(p ->> 'plan_at', '')::timestamptz)
  returning id into v_id;
  if not v_social then
    perform public.uw_notify(null, public.uw_unit_of_kind('social'), 'posts', false, 'post_request', 'Yeni paylaşım talebi', v_title, 'b-yayin');
  end if;
  perform public.log_activity(case when v_social then 'Yayın kartı açtı' else 'Paylaşım talebi gönderdi' end, v_title);
  return jsonb_build_object('id', v_id);
end;
$$;

-- Kulüp duyurusunu akışa al ya da gerek yok de.
create or replace function public.uwa_post_announcement(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_a public.announcements; v_take boolean := coalesce((p ->> 'take')::boolean, true);
begin
  if not public.uw_post_lead() then raise exception 'Bu işlem için Sosyal Medya’da paylaşım yetkisi gerekir.'; end if;
  select * into v_a from public.announcements where id = public.uw_uuid(p, 'id') and status = 'published' and club_id is not null;
  if not found then raise exception 'Duyuru bulunamadı.'; end if;
  insert into public.social_posts (status, source, announcement_id, title, brief)
  values (case when v_take then 'preparing' else 'declined' end, 'announcement', v_a.id, left(v_a.title, 160), v_a.body)
  on conflict (announcement_id) do nothing;
  perform public.log_activity(case when v_take then 'Kulüp duyurusunu akışa aldı' else 'Kulüp duyurusunu paylaşmamaya karar verdi' end, v_a.title);
  return null;
end;
$$;

create or replace function public.uwa_post_accept(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.social_posts;
begin
  if not public.uw_post_lead() then raise exception 'Bu işlem için Sosyal Medya’da paylaşım yetkisi gerekir.'; end if;
  update public.social_posts set status = 'preparing', updated_at = now() where id = public.uw_uuid(p, 'id') and status = 'request' returning * into v_s;
  if not found then raise exception 'Talep bulunamadı.'; end if;
  perform public.uw_notify(v_s.requested_by, null, null, false, 'post_status', 'Paylaşım talebin hazırlanıyor', v_s.title, 'b-yayin');
  perform public.log_activity('Paylaşım talebini kabul etti', v_s.title);
  return null;
end;
$$;

create or replace function public.uwa_post_decline(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.social_posts; v_note text := public.uw_text(p, 'note', 1000, true, 'Not');
begin
  if not public.uw_post_lead() then raise exception 'Bu işlem için Sosyal Medya’da paylaşım yetkisi gerekir.'; end if;
  update public.social_posts set status = 'declined', note = v_note, updated_at = now()
   where id = public.uw_uuid(p, 'id') and status in ('request', 'preparing') returning * into v_s;
  if not found then raise exception 'Kart bulunamadı ya da artık geri çevrilemez.'; end if;
  perform public.uw_notify(v_s.requested_by, null, null, false, 'post_status', 'Paylaşım talebin geri çevrildi', v_s.title || ' · Not: ' || v_note, 'b-yayin');
  perform public.log_activity('Paylaşım talebini geri çevirdi', v_s.title);
  return null;
end;
$$;

create or replace function public.uwa_post_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.social_posts; v_to uuid := public.uw_uuid(p, 'assignee'); v_platforms text[];
begin
  if not public.uw_post_lead() then raise exception 'Bu işlem için Sosyal Medya’da paylaşım yetkisi gerekir.'; end if;
  select * into v_s from public.social_posts where id = public.uw_uuid(p, 'id') for update;
  if not found then raise exception 'Kart bulunamadı.'; end if;
  if v_s.status not in ('request', 'preparing', 'planned') then raise exception 'Onaydaki ya da yayınlanmış kart düzenlenemez.'; end if;
  if v_to is not null and not exists (select 1 from public.unit_members where user_id = v_to and unit_id = public.uw_unit() and status = 'active') then
    raise exception 'Sorumlu Sosyal Medya ekibinden olmalı.';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_platforms from jsonb_array_elements_text(case when jsonb_typeof(p -> 'platforms') = 'array' then p -> 'platforms' else '[]'::jsonb end) x;
  if v_s.status = 'planned' then
    -- Onaylanan içerik değişmez; yalnızca yayın tarihi ve sorumlu güncellenir.
    update public.social_posts set plan_at = nullif(p ->> 'plan_at', '')::timestamptz, assignee = v_to, updated_at = now() where id = v_s.id;
  else
    update public.social_posts set title = public.uw_text(p, 'title', 160, true, 'Başlık'), body = public.uw_text(p, 'body', 5000),
      design_url = public.uw_link(p, 'design_url'), platforms = v_platforms,
      format = nullif(p ->> 'format', ''), plan_at = nullif(p ->> 'plan_at', '')::timestamptz, assignee = v_to,
      status = case when status = 'request' then 'preparing' else status end, updated_at = now()
     where id = v_s.id;
  end if;
  return null;
end;
$$;

create or replace function public.uwa_post_submit(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.social_posts; v_req uuid;
begin
  if not public.uw_post_lead() then raise exception 'Bu işlem için Sosyal Medya’da paylaşım yetkisi gerekir.'; end if;
  select * into v_s from public.social_posts where id = public.uw_uuid(p, 'id') for update;
  if not found or v_s.status <> 'preparing' then raise exception 'Yalnızca hazırlanan kart onaya gönderilir.'; end if;
  if coalesce(v_s.body, '') = '' or cardinality(v_s.platforms) = 0 then raise exception 'Onaya göndermeden önce metni ve platformu yaz.'; end if;
  v_req := public.uw_req_open('post', v_s.id, v_s.title, left(v_s.body, 300), false, null, 'board');
  update public.social_posts set status = 'approval', request_id = v_req, note = null, updated_at = now() where id = v_s.id;
  perform public.log_activity('Yayını onaya gönderdi', v_s.title);
  return null;
end;
$$;

create or replace function public.uwa_post_publish(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.social_posts;
begin
  if not public.uw_post_lead() then raise exception 'Bu işlem için Sosyal Medya’da paylaşım yetkisi gerekir.'; end if;
  select * into v_s from public.social_posts where id = public.uw_uuid(p, 'id') for update;
  if not found or v_s.status <> 'planned'
     or not exists (select 1 from public.unit_requests r where r.id = v_s.request_id and r.status = 'approved') then
    raise exception 'Onaylanmamış içerik yayınlandı olarak işaretlenemez.';
  end if;
  update public.social_posts set status = 'published', published_at = now(), published_url = public.uw_link(p, 'url'), updated_at = now() where id = v_s.id;
  perform public.uw_notify(v_s.requested_by, null, null, false, 'post_status', 'Paylaşım yayınlandı', v_s.title, 'b-yayin');
  perform public.log_activity('Yayınlandı olarak işaretledi', v_s.title);
  return null;
end;
$$;

create or replace function public.uwa_post_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.social_posts;
begin
  if not (public.uw_post_lead() and (public.uw_head() or public.uw_has('team'))) then raise exception 'Kartı birim başkanı ya da ekip yöneticisi siler.'; end if;
  delete from public.social_posts where id = public.uw_uuid(p, 'id') and status in ('request', 'preparing', 'declined') returning * into v_s;
  if not found then raise exception 'Kart bulunamadı ya da silinemez.'; end if;
  perform public.log_activity('Yayın kartını sildi', v_s.title);
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: kampanyalar
create or replace function public.uwa_camp_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := public.uw_uuid(p, 'id'); v_c public.pr_campaigns; v_budget boolean := coalesce((p ->> 'has_budget')::boolean, false);
begin
  if not public.uw_can('pr', 'campaigns') then raise exception 'Bu işlem için Halkla İlişkiler’de kampanya yetkisi gerekir.'; end if;
  if v_id is null then
    insert into public.pr_campaigns (title, idea, goal, has_budget, budget_note, created_by)
    values (public.uw_text(p, 'title', 160, true, 'Kampanya adı'), public.uw_text(p, 'idea', 4000), public.uw_text(p, 'goal', 2000), v_budget,
            case when v_budget then public.uw_text(p, 'budget_note', 1000) end, (select auth.uid()))
    returning id into v_id;
    perform public.log_activity('Kampanya açtı', p ->> 'title');
  else
    update public.pr_campaigns set title = public.uw_text(p, 'title', 160, true, 'Kampanya adı'), idea = public.uw_text(p, 'idea', 4000),
      goal = public.uw_text(p, 'goal', 2000), has_budget = v_budget, budget_note = case when v_budget then public.uw_text(p, 'budget_note', 1000) end,
      status = 'draft', updated_at = now()
     where id = v_id and status in ('draft', 'rejected') returning * into v_c;
    if not found then raise exception 'Onaydaki ya da onaylanmış kampanya düzenlenemez.'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.uwa_camp_submit(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_c public.pr_campaigns; v_req uuid;
begin
  if not public.uw_can('pr', 'campaigns') then raise exception 'Bu işlem için Halkla İlişkiler’de kampanya yetkisi gerekir.'; end if;
  select * into v_c from public.pr_campaigns where id = public.uw_uuid(p, 'id') for update;
  if not found or v_c.status <> 'draft' then raise exception 'Yalnızca taslak kampanya onaya gönderilir.'; end if;
  if v_c.has_budget and coalesce(v_c.budget_note, '') = '' then raise exception 'Bütçeli kampanyada bütçe açıklamasını yaz.'; end if;
  v_req := public.uw_req_open('campaign', v_c.id, v_c.title, left(coalesce(v_c.goal, v_c.idea, ''), 300), v_c.has_budget, v_c.budget_note, 'board');
  update public.pr_campaigns set status = 'approval', request_id = v_req, note = null, updated_at = now() where id = v_c.id;
  perform public.log_activity('Kampanyayı onaya gönderdi', v_c.title);
  return null;
end;
$$;

create or replace function public.uwa_camp_done(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_c public.pr_campaigns;
begin
  if not public.uw_can('pr', 'campaigns') then raise exception 'Bu işlem için Halkla İlişkiler’de kampanya yetkisi gerekir.'; end if;
  update public.pr_campaigns set status = 'done', updated_at = now() where id = public.uw_uuid(p, 'id') and status = 'approved' returning * into v_c;
  if not found then raise exception 'Yalnızca onaylanan kampanya tamamlanır.'; end if;
  perform public.log_activity('Kampanyayı tamamladı', v_c.title);
  return null;
end;
$$;

create or replace function public.uwa_camp_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_c public.pr_campaigns;
begin
  if not public.uw_can('pr', 'campaigns') then raise exception 'Bu işlem için Halkla İlişkiler’de kampanya yetkisi gerekir.'; end if;
  delete from public.pr_campaigns where id = public.uw_uuid(p, 'id') and status in ('draft', 'rejected') returning * into v_c;
  if not found then raise exception 'Yalnızca taslak ya da reddedilmiş kampanya silinir.'; end if;
  perform public.log_activity('Kampanyayı sildi', v_c.title);
  return null;
end;
$$;

-- ---------------------------------------------------------------- işlemler: rapor talepleri
create or replace function public.uwa_report_ask(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_unit uuid := public.uw_uuid(p, 'unit_id'); v_title text := public.uw_text(p, 'title', 160, true, 'Rapor konusu');
begin
  if not public.uw_admin() then raise exception 'Raporu Merkez Yönetim ister.'; end if;
  if not exists (select 1 from public.units where id = v_unit) then raise exception 'Birim seç.'; end if;
  insert into public.unit_reports (unit_id, title, details, due_date, asked_by)
  values (v_unit, v_title, public.uw_text(p, 'details', 2000), nullif(p ->> 'due_date', '')::date, (select auth.uid()));
  perform public.uw_notify(null, v_unit, 'team', false, 'report', 'Merkez Yönetim rapor istedi', v_title, 'b-kampanyalar');
  perform public.log_activity('Rapor istedi', v_title);
  return null;
end;
$$;

create or replace function public.uwa_report_answer(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_r public.unit_reports; v_answer text := public.uw_text(p, 'answer', 5000); v_url text := public.uw_link(p, 'url');
begin
  select * into v_r from public.unit_reports where id = public.uw_uuid(p, 'id') for update;
  if not found or v_r.unit_id is distinct from public.uw_unit() then raise exception 'Rapor talebi bulunamadı.'; end if;
  if not (public.uw_head() or public.uw_has('team') or public.uw_can('pr', 'campaigns')) then raise exception 'Raporu birim başkanı ya da yetkili kişi gönderir.'; end if;
  if v_answer is null and v_url is null then raise exception 'Raporu yaz ya da bağlantısını ekle.'; end if;
  update public.unit_reports set status = 'answered', answer = v_answer, answer_url = v_url, answered_by = (select auth.uid()), answered_at = now() where id = v_r.id;
  perform public.uw_notify(null, null, null, true, 'report', 'Rapor geldi', v_r.title, 'b-kampanyalar');
  perform public.log_activity('Rapor gönderdi', v_r.title);
  return null;
end;
$$;

-- Birim notu (marka kiti: marka dili). PR'da kampanya yetkisi olan ya da birim başkanı yazar.
create or replace function public.uwa_note_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_unit uuid := public.uw_unit();
begin
  if not (public.uw_can('pr', 'campaigns') or public.uw_head()) then raise exception 'Bu notu birim başkanı ya da yetkili kişi düzenler.'; end if;
  insert into public.unit_notes (unit_id, body, updated_by, updated_at) values (v_unit, public.uw_text(p, 'body', 10000), (select auth.uid()), now())
  on conflict (unit_id) do update set body = excluded.body, updated_by = excluded.updated_by, updated_at = now();
  perform public.log_activity('Marka kiti notunu güncelledi', '');
  return null;
end;
$$;

-- Merkez'in tamamlanan birim görevi bildirimi Birim Görevleri sayfasını açar.
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
    perform public.uw_notify(null, null, null, true, 'task_submitted', 'Birim görevi tamamlandı', '“' || v_t.title || '” · ' || public.uw_name((select auth.uid())), 'b-gorevler');
  else
    perform public.uw_notify(v_t.created_by, null, null, false, 'task_submitted', 'Görev tamamlandı, incelemeni bekliyor', '“' || v_t.title || '” · ' || public.uw_name((select auth.uid())), 'b-gorevler');
  end if;
  perform public.log_activity('Görevi tamamladı', v_t.title);
  return null;
end;
$$;
update public.unit_notifications set view = 'b-gorevler' where view = 'gorevler';

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'uw\_%' or p.proname like 'uwr\_%' or p.proname like 'uwa\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
