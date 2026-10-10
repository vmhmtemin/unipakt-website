-- ============================================================
-- UniPakt Panel — live database schema snapshot (public + storage policies)
-- Generated from the production database (hcgotmcbwmleeklbvawb) on 2026-10-10 19:52 Europe/Istanbul.
-- This file documents the schema; it is NOT a migration. Changes go through
-- supabase/migrations/. Vault secrets and data are not included.
-- ============================================================

-- ---------- Tables ----------

create table if not exists public.announcements (
  id uuid not null default gen_random_uuid(),
  club_id uuid,
  title text not null,
  body text not null,
  status text not null default 'pending'::text,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  constraint announcements_pkey PRIMARY KEY (id),
  constraint announcements_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint announcements_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 1500))),
  constraint announcements_note_check CHECK ((char_length(note) <= 400)),
  constraint announcements_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'published'::text, 'rejected'::text]))),
  constraint announcements_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 120)))
);
alter table public.announcements enable row level security;

create table if not exists public.clubs (
  id uuid not null default gen_random_uuid(),
  name text not null,
  university text not null,
  created_at timestamp with time zone not null default now(),
  category text,
  email text,
  instagram text,
  linkedin text,
  x text,
  tiktok text,
  web text,
  visible boolean not null default true,
  constraint clubs_pkey PRIMARY KEY (id),
  constraint clubs_category_check CHECK ((char_length(category) <= 40)),
  constraint clubs_email_check CHECK ((char_length(email) <= 200)),
  constraint clubs_instagram_check CHECK ((char_length(instagram) <= 200)),
  constraint clubs_linkedin_check CHECK ((char_length(linkedin) <= 200)),
  constraint clubs_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 120))),
  constraint clubs_tiktok_check CHECK ((char_length(tiktok) <= 200)),
  constraint clubs_university_check CHECK (((char_length(university) >= 1) AND (char_length(university) <= 120))),
  constraint clubs_web_check CHECK ((char_length(web) <= 200)),
  constraint clubs_x_check CHECK ((char_length(x) <= 200))
);
alter table public.clubs enable row level security;

create table if not exists public.event_applications (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  club_id uuid not null,
  note text not null,
  status text not null default 'pending'::text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  constraint event_applications_event_id_club_id_key UNIQUE (event_id, club_id),
  constraint event_applications_pkey PRIMARY KEY (id),
  constraint event_applications_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint event_applications_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  constraint event_applications_note_check CHECK (((char_length(note) >= 1) AND (char_length(note) <= 500))),
  constraint event_applications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'removed'::text])))
);
alter table public.event_applications enable row level security;

create table if not exists public.event_edit_requests (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  club_id uuid not null,
  changes jsonb not null default '{}'::jsonb,
  status text not null default 'pending'::text,
  note text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  constraint event_edit_requests_pkey PRIMARY KEY (id),
  constraint event_edit_requests_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint event_edit_requests_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  constraint event_edit_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);
alter table public.event_edit_requests enable row level security;

create table if not exists public.event_occurrences (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  date date not null,
  "time" time without time zone,
  created_at timestamp with time zone not null default now(),
  constraint event_occurrences_pkey PRIMARY KEY (id),
  constraint event_occurrences_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
);
alter table public.event_occurrences enable row level security;

create table if not exists public.event_visibility_requests (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  club_id uuid not null,
  desired_visible boolean not null,
  note text,
  status text not null default 'pending'::text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  constraint event_visibility_requests_pkey PRIMARY KEY (id),
  constraint event_visibility_requests_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint event_visibility_requests_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  constraint event_visibility_requests_note_check CHECK ((char_length(note) <= 400)),
  constraint event_visibility_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);
alter table public.event_visibility_requests enable row level security;

create table if not exists public.events (
  id uuid not null default gen_random_uuid(),
  club_id uuid,
  title text not null,
  description text not null,
  event_date date not null,
  event_time time without time zone,
  place text,
  seeking text,
  status text not null default 'pending'::text,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  kind text not null default 'partner'::text,
  calendar text not null default 'none'::text,
  address text,
  rules text,
  poster_url text,
  tags text[] not null default '{}'::text[],
  registration_url text,
  fee_type text not null default 'free'::text,
  fee_amount numeric(10,2),
  university text,
  visible boolean not null default true,
  constraint events_pkey PRIMARY KEY (id),
  constraint events_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint events_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint events_calendar_check CHECK ((calendar = ANY (ARRAY['none'::text, 'requested'::text, 'on'::text]))),
  constraint events_description_check CHECK (((char_length(description) >= 1) AND (char_length(description) <= 5000))),
  constraint events_fee_amount_check CHECK (((fee_amount IS NULL) OR (fee_amount >= (0)::numeric))),
  constraint events_fee_type_check CHECK ((fee_type = ANY (ARRAY['free'::text, 'paid'::text]))),
  constraint events_kind_check CHECK ((kind = ANY (ARRAY['event'::text, 'partner'::text]))),
  constraint events_note_check CHECK ((char_length(note) <= 400)),
  constraint events_place_check CHECK ((char_length(place) <= 120)),
  constraint events_poster_url_storage CHECK (((poster_url IS NULL) OR (poster_url = ''::text) OR (poster_url ~~ 'https://hcgotmcbwmleeklbvawb.supabase.co/storage/v1/object/public/event-posters/%'::text))),
  constraint events_registration_url_http CHECK (((registration_url IS NULL) OR (registration_url = ''::text) OR (registration_url ~ '^https?://[^[:space:]"''<>]+$'::text))),
  constraint events_seeking_check CHECK ((char_length(seeking) <= 200)),
  constraint events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'published'::text, 'rejected'::text]))),
  constraint events_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 120)))
);
alter table public.events enable row level security;

create table if not exists public.notifications (
  id uuid not null default gen_random_uuid(),
  recipient_club_id uuid,
  recipient_role text not null default 'club'::text,
  type text not null,
  title text not null,
  body text not null,
  event_id uuid,
  application_id uuid,
  task_id uuid,
  actionable boolean not null default false,
  resolved boolean not null default true,
  read_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  constraint notifications_pkey PRIMARY KEY (id),
  constraint notifications_application_id_fkey FOREIGN KEY (application_id) REFERENCES event_applications(id) ON DELETE CASCADE,
  constraint notifications_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  constraint notifications_recipient_club_id_fkey FOREIGN KEY (recipient_club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint notifications_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
  constraint notifications_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 1000))),
  constraint notifications_recipient_role_check CHECK ((recipient_role = ANY (ARRAY['club'::text, 'admin'::text]))),
  constraint notifications_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 160)))
);
alter table public.notifications enable row level security;

create table if not exists public.point_entries (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid,
  label text not null,
  delta integer not null,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  constraint point_entries_pkey PRIMARY KEY (id),
  constraint point_entries_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint point_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint point_entries_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL,
  constraint point_entries_delta_check CHECK ((delta <> 0)),
  constraint point_entries_label_check CHECK (((char_length(label) >= 1) AND (char_length(label) <= 120))),
  constraint point_entries_note_check CHECK (((note IS NULL) OR (char_length(note) <= 1000)))
);
alter table public.point_entries enable row level security;

create table if not exists public.profiles (
  id uuid not null,
  role text not null,
  club_id uuid,
  full_name text,
  created_at timestamp with time zone not null default now(),
  constraint profiles_pkey PRIMARY KEY (id),
  constraint profiles_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint profiles_full_name_check CHECK ((char_length(full_name) <= 120)),
  constraint profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'club'::text]))),
  constraint profiles_role_club CHECK ((((role = 'admin'::text) AND (club_id IS NULL)) OR ((role = 'club'::text) AND (club_id IS NOT NULL))))
);
alter table public.profiles enable row level security;

create table if not exists public.support_ticket_messages (
  id uuid not null default gen_random_uuid(),
  ticket_id uuid not null,
  author_id uuid not null default auth.uid(),
  author_role text not null,
  author_label text,
  body text not null,
  created_at timestamp with time zone not null default now(),
  constraint support_ticket_messages_pkey PRIMARY KEY (id),
  constraint support_ticket_messages_author_id_fkey FOREIGN KEY (author_id) REFERENCES auth.users(id) ON DELETE RESTRICT,
  constraint support_ticket_messages_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES support_tickets(id) ON DELETE CASCADE,
  constraint support_ticket_messages_author_role_check CHECK ((author_role = ANY (ARRAY['club'::text, 'admin'::text]))),
  constraint support_ticket_messages_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 2000)))
);
alter table public.support_ticket_messages enable row level security;

create table if not exists public.support_tickets (
  id uuid not null default gen_random_uuid(),
  ticket_number text not null default ('UP-'::text || upper(substr(replace((gen_random_uuid())::text, '-'::text, ''::text), 1, 8))),
  club_id uuid not null,
  created_by uuid not null default auth.uid(),
  subject text not null,
  category text not null default 'technical'::text,
  category_label text,
  status text not null default 'open'::text,
  preview text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  event_id uuid,
  attachment_path text,
  attachment_name text,
  constraint support_tickets_ticket_number_key UNIQUE (ticket_number),
  constraint support_tickets_pkey PRIMARY KEY (id),
  constraint support_tickets_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint support_tickets_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT,
  constraint support_tickets_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL,
  constraint support_tickets_category_check CHECK ((category = ANY (ARRAY['technical'::text, 'community'::text, 'event'::text]))),
  constraint support_tickets_status_check CHECK ((status = ANY (ARRAY['open'::text, 'reviewing'::text, 'waiting_user'::text, 'answered'::text, 'resolved'::text, 'closed'::text]))),
  constraint support_tickets_subject_check CHECK (((char_length(subject) >= 1) AND (char_length(subject) <= 160)))
);
alter table public.support_tickets enable row level security;

create table if not exists public.tasks (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  title text not null,
  description text,
  due_date date,
  status text not null default 'open'::text,
  proof_text text,
  proof_path text,
  proof_name text,
  done_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  review_status text not null default 'none'::text,
  review_note text,
  reviewed_at timestamp with time zone,
  constraint tasks_pkey PRIMARY KEY (id),
  constraint tasks_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  constraint tasks_description_check CHECK ((char_length(description) <= 1000)),
  constraint tasks_proof_name_check CHECK ((char_length(proof_name) <= 120)),
  constraint tasks_proof_text_check CHECK ((char_length(proof_text) <= 1500)),
  constraint tasks_status_check CHECK ((status = ANY (ARRAY['open'::text, 'done'::text]))),
  constraint tasks_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 120)))
);
alter table public.tasks enable row level security;

-- ---------- Indexes ----------

CREATE INDEX events_status_date_idx ON public.events USING btree (status, event_date);
CREATE UNIQUE INDEX event_visibility_one_pending_idx ON public.event_visibility_requests USING btree (event_id) WHERE (status = 'pending'::text);
CREATE INDEX event_edit_requests_status_idx ON public.event_edit_requests USING btree (status);
CREATE INDEX support_tickets_club_updated_idx ON public.support_tickets USING btree (club_id, updated_at DESC);
CREATE INDEX event_visibility_requests_status_idx ON public.event_visibility_requests USING btree (status, created_at DESC);
CREATE INDEX notifications_role_idx ON public.notifications USING btree (recipient_role, created_at DESC);
CREATE INDEX event_occurrences_event_idx ON public.event_occurrences USING btree (event_id, date, "time");
CREATE INDEX notifications_club_idx ON public.notifications USING btree (recipient_club_id, created_at DESC);
CREATE INDEX point_entries_event_idx ON public.point_entries USING btree (event_id);
CREATE INDEX support_ticket_messages_ticket_created_idx ON public.support_ticket_messages USING btree (ticket_id, created_at);
CREATE INDEX event_edit_requests_event_idx ON public.event_edit_requests USING btree (event_id);
CREATE INDEX notifications_action_idx ON public.notifications USING btree (actionable, resolved, created_at DESC);
CREATE INDEX event_edit_requests_club_idx ON public.event_edit_requests USING btree (club_id);
CREATE INDEX tasks_club_idx ON public.tasks USING btree (club_id, status);
CREATE INDEX announcements_status_idx ON public.announcements USING btree (status, created_at DESC);
CREATE INDEX support_tickets_event_idx ON public.support_tickets USING btree (event_id);
CREATE INDEX event_applications_club_idx ON public.event_applications USING btree (club_id);
CREATE UNIQUE INDEX event_edit_one_pending_idx ON public.event_edit_requests USING btree (event_id) WHERE (status = 'pending'::text);
CREATE INDEX events_visible_status_idx ON public.events USING btree (status, visible, event_date);
CREATE INDEX point_entries_club_idx ON public.point_entries USING btree (club_id);
CREATE INDEX event_visibility_requests_club_idx ON public.event_visibility_requests USING btree (club_id);
CREATE INDEX profiles_club_idx ON public.profiles USING btree (club_id);
CREATE INDEX event_visibility_requests_event_idx ON public.event_visibility_requests USING btree (event_id);
CREATE INDEX announcements_club_idx ON public.announcements USING btree (club_id);
CREATE UNIQUE INDEX event_edit_requests_one_pending_idx ON public.event_edit_requests USING btree (event_id) WHERE (status = 'pending'::text);
CREATE INDEX events_club_idx ON public.events USING btree (club_id);

-- ---------- Functions ----------

CREATE OR REPLACE FUNCTION public.admin_delete_support_ticket(p_ticket_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_found boolean;
begin
  if not public.is_unipakt_admin() then
    raise exception 'Not allowed';
  end if;

  select exists(select 1 from public.support_tickets where id = p_ticket_id)
    into v_found;

  if not v_found then
    raise exception 'Support ticket not found';
  end if;

  delete from public.support_tickets where id = p_ticket_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_update_support_ticket(p_ticket_id uuid, p_status text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_category_label text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_unipakt_admin() then
    raise exception 'Not allowed';
  end if;

  if not exists (select 1 from public.support_tickets where id = p_ticket_id) then
    raise exception 'Support ticket not found';
  end if;

  if p_status is not null and p_status not in ('open','reviewing','waiting_user','answered','resolved','closed') then
    raise exception 'Invalid support status';
  end if;

  if p_category is not null and p_category not in ('technical','community','event') then
    raise exception 'Invalid support category';
  end if;

  update public.support_tickets
     set status = coalesce(p_status, status),
         category = coalesce(p_category, category),
         category_label = coalesce(p_category_label, category_label),
         updated_at = now()
   where id = p_ticket_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.complete_task(p_task uuid, p_text text, p_path text DEFAULT NULL::text, p_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_club uuid := public.my_club(); v_title text;
begin
  if v_club is null then raise exception 'Bu işlem için kulüp hesabı gerekir.'; end if;
  if coalesce(btrim(p_text), '') = '' and p_path is null then raise exception 'Bir mesaj ya da dosya gerekli.'; end if;
  if p_path is not null and split_part(p_path, '/', 1) <> v_club::text then raise exception 'Dosya yolu bu kulübe ait değil.'; end if;
  update public.tasks set status='done', review_status='pending', review_note=null, proof_text=nullif(btrim(p_text),''), proof_path=p_path, proof_name=left(p_name,120), done_at=now(), reviewed_at=null where id=p_task and club_id=v_club and status='open';
  if not found then raise exception 'Görev bulunamadı ya da zaten tamamlanmış.'; end if;
  perform public.push_admin_notification('Görev kanıtı gönderildi','Bir kulüp “'||(select title from public.tasks where id=p_task)||'” görevinin kanıtını gönderdi.','task_submitted',null,null,p_task);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_support_ticket(p_subject text, p_category text, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_club uuid;
begin
  v_club := public.my_club_id();
  if v_club is null or public.is_unipakt_admin() then raise exception 'Only club accounts can create support tickets'; end if;
  insert into public.support_tickets(club_id,created_by,subject,category,category_label,status,preview)
  values(v_club,auth.uid(),p_subject,p_category,p_category,'open',left(p_body,300)) returning id into v_id;
  insert into public.support_ticket_messages(ticket_id,author_id,author_role,author_label,body)
  values(v_id,auth.uid(),'club','Kulüp',p_body);
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_support_ticket(p_subject text, p_category text, p_body text, p_category_label text DEFAULT NULL::text, p_event_id uuid DEFAULT NULL::uuid, p_attachment_path text DEFAULT NULL::text, p_attachment_name text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_club uuid;
  v_ticket_number text;
begin
  v_club := public.my_club_id();

  if v_club is null or public.is_unipakt_admin() then
    raise exception 'Only club accounts can create support tickets';
  end if;

  if p_category not in ('technical','community','event') then
    raise exception 'Invalid support category';
  end if;

  if char_length(trim(coalesce(p_subject,''))) = 0 then
    raise exception 'Subject is required';
  end if;

  if char_length(trim(coalesce(p_body,''))) = 0 then
    raise exception 'Message is required';
  end if;

  -- Event-category tickets may be event-specific OR event-free.
  if p_event_id is not null
     and not exists (
       select 1 from public.events e
       where e.id = p_event_id and e.club_id = v_club
     ) then
    raise exception 'Selected event does not belong to this club';
  end if;

  insert into public.support_tickets(
    club_id, created_by, subject, category, category_label, event_id,
    attachment_path, attachment_name, status, preview
  )
  values(
    v_club,
    auth.uid(),
    trim(p_subject),
    p_category,
    coalesce(nullif(trim(p_category_label),''),
      case p_category
        when 'event' then 'Etkinlik Desteği'
        when 'community' then 'Topluluk ve Güvenlik'
        else 'Teknik Destek'
      end
    ),
    p_event_id,
    p_attachment_path,
    p_attachment_name,
    'open',
    left(trim(p_body),300)
  )
  returning id, ticket_number into v_id, v_ticket_number;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values(v_id, auth.uid(), 'club', 'Kulüp', trim(p_body));

  -- Notify UniPakt admins immediately when the ticket is created.
  if to_regprocedure('public.push_admin_notification(text,text,text,uuid,uuid,uuid)') is not null then
    perform public.push_admin_notification(
      'Yeni destek talebi',
      'Yeni bir destek talebi oluşturuldu: ' || coalesce(v_ticket_number, 'UP-' || upper(substr(replace(v_id::text,'-',''),1,8))),
      'support_ticket_new',
      null, null, null
    );
  end if;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.decide_event_application(p_application uuid, p_status text, p_note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event uuid; v_host uuid; v_club uuid; v_title text; v_name text;
begin
  if p_status not in ('approved','rejected') then raise exception 'Geçersiz karar.'; end if;
  select a.event_id,a.club_id,e.club_id,e.title into v_event,v_club,v_host,v_title
  from public.event_applications a join public.events e on e.id=a.event_id where a.id=p_application and a.status='pending';
  if not found then raise exception 'Bekleyen ortaklık başvurusu bulunamadı.'; end if;
  if not (public.is_admin() or v_host=public.my_club()) then raise exception 'Bu başvuruyu yalnızca etkinlik sahibi yönetebilir.'; end if;
  if p_status='rejected' and coalesce(btrim(p_note),'')='' then raise exception 'Reddetmek için not zorunludur.'; end if;
  update public.event_applications set status=p_status, decided_at=now() where id=p_application;
  -- Başvurunun ilk bildirimini sonuçlandır: butonlar kaybolsun ve bildirim silinebilir hale gelsin.
  update public.notifications
     set actionable=false, resolved=true, read_at=coalesce(read_at, now())
   where application_id=p_application
     and recipient_club_id=v_host
     and type='partnership_application'
     and actionable=true
     and resolved=false;
  select name into v_name from public.clubs where id=coalesce(public.my_club(),v_host);
  if p_status='approved' then
    perform public.push_notification(v_club,'Ortaklık başvurun onaylandı','“'||v_title||'” etkinliğine ortaklığın onaylandı. Etkinliklerim bölümünden diğer ortakları ve iletişim bilgilerini görebilirsin.','partnership_decision',v_event,p_application,null,false,true);
  else
    perform public.push_notification(v_club,'Ortaklık başvurun reddedildi','“'||v_title||'” etkinliğine ortaklık başvurun reddedildi. Not: '||btrim(p_note),'partnership_decision',v_event,p_application,null,false,true);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_my_rejected_application(p_kind text, p_id uuid, p_event_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_club uuid := public.my_club_id();
  v_deleted integer;
begin
  if v_club is null or public.is_unipakt_admin() then
    raise exception 'Only club accounts can delete rejected submissions';
  end if;

  if p_kind = 'announcement' then
    delete from public.announcements
     where id = p_id
       and club_id = v_club
       and status = 'rejected';
    get diagnostics v_deleted = row_count;

  elsif p_kind = 'event' then
    delete from public.events
     where id = p_id
       and club_id = v_club
       and status = 'rejected';
    get diagnostics v_deleted = row_count;

  elsif p_kind = 'partner_application' then
    if p_event_id is null then
      raise exception 'Event ID is required for partnership application deletion';
    end if;

    delete from public.event_applications
     where id = p_id
       and event_id = p_event_id
       and club_id = v_club
       and status = 'rejected';
    get diagnostics v_deleted = row_count;

  else
    raise exception 'Invalid rejected submission type';
  end if;

  if coalesce(v_deleted, 0) = 0 then
    raise exception 'Rejected submission not found or not owned by this club';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(public.my_role() = 'admin', false)
$function$
;

CREATE OR REPLACE FUNCTION public.is_unipakt_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$function$
;

CREATE OR REPLACE FUNCTION public.leaderboard()
 RETURNS TABLE(club_id uuid, name text, university text, points bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.id,
    c.name,
    c.university,
    coalesce(sum(p.delta), 0)::bigint as points
  from public.clubs c
  left join public.point_entries p
    on p.club_id = c.id
  where public.my_role() is not null
  group by c.id, c.name, c.university
  order by points desc, c.name asc;
$function$
;

CREATE OR REPLACE FUNCTION public.my_club()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select club_id from public.profiles where id = (select auth.uid())
$function$
;

CREATE OR REPLACE FUNCTION public.my_club_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.club_id
  from public.profiles p
  where p.id = auth.uid()
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.my_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select role from public.profiles where id = (select auth.uid())
$function$
;

CREATE OR REPLACE FUNCTION public.notify_event_edit_decision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_title text;
begin
  if NEW.status<>OLD.status and NEW.status in ('approved','rejected') then
    select title into v_title from public.events where id=NEW.event_id;
    perform public.push_notification(NEW.club_id,case when NEW.status='approved' then 'Etkinlik düzenleme talebin onaylandı' else 'Etkinlik düzenleme talebin reddedildi' end,
      case when NEW.status='approved' then '“'||v_title||'” etkinliğindeki değişiklikler yayınlandı.' else '“'||v_title||'” etkinlik düzenleme talebin reddedildi. Not: '||coalesce(NEW.note,'') end,'event_edit_decision',NEW.event_id,null,null,false,true);
  end if;
  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_event_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_title text;
  v_body text;
begin
  select coalesce(NEW.title,'Etkinlik') into v_title;

  -- Club event submission approved/rejected by UniPakt.
  if NEW.club_id is not null and NEW.status <> OLD.status and NEW.status in ('published','rejected') then
    if NEW.status='published' then
      if NEW.kind='partner' then
        v_body := '“'||v_title||'” ortak arama başvurun onaylandı. Ortak Arama sayfasından etkinliğini dilersen yayına alma talebi de oluşturabilirsin.';
        perform public.push_notification(NEW.club_id,'Ortak Arama başvurun kabul edildi',v_body,'event_submission_decision',NEW.id,null,null,false,true);
      else
        v_body := '“'||v_title||'” etkinlik başvurun onaylandı.';
        perform public.push_notification(NEW.club_id,'Etkinlik başvurun onaylandı',v_body,'event_submission_decision',NEW.id,null,null,false,true);
      end if;
    elsif NEW.status='rejected' then
      v_body := '“'||v_title||'” başvurun reddedildi.'||case when coalesce(NEW.note,'')<>'' then ' Not: '||NEW.note else '' end;
      perform public.push_notification(NEW.club_id,case when NEW.kind='partner' then 'Ortak Arama başvurun reddedildi' else 'Etkinlik başvurun reddedildi' end,v_body,'event_submission_decision',NEW.id,null,null,false,true);
    end if;
  end if;

  -- Calendar publication request result.
  if NEW.club_id is not null and OLD.calendar='requested' and NEW.calendar='on' then
    perform public.push_notification(NEW.club_id,'Etkinliğin yayına alındı','“'||v_title||'” etkinliğinin takvimde yayınlanma talebi onaylandı.','calendar_decision',NEW.id,null,null,false,true);
  elsif NEW.club_id is not null and OLD.calendar='requested' and NEW.calendar='none' then
    perform public.push_notification(NEW.club_id,'Yayına alma talebin reddedildi','“'||v_title||'” etkinliğinin yayına alma talebi reddedildi.'||case when coalesce(NEW.note,'')<>'' then ' Not: '||NEW.note else '' end,'calendar_decision',NEW.id,null,null,false,true);
  elsif NEW.club_id is not null and OLD.calendar='on' and NEW.calendar='none' then
    perform public.push_notification(NEW.club_id,'Etkinliğin takvimden kaldırıldı','“'||v_title||'” etkinliğin takvimden kaldırıldı.'||case when coalesce(NEW.note,'')<>'' then ' Not: '||NEW.note else '' end,'event_unpublished',NEW.id,null,null,false,true);
  end if;

  -- Site visibility removal, including a note entered by UniPakt.
  if NEW.club_id is not null and OLD.visible is distinct from NEW.visible and NEW.visible=false then
    perform public.push_notification(NEW.club_id,'Etkinliğin yayından kaldırıldı','“'||v_title||'” etkinliğin siteden kaldırıldı.'||case when coalesce(NEW.note,'')<>'' then ' Not: '||NEW.note else '' end,'event_unpublished',NEW.id,null,null,false,true);
  end if;

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_new_support_ticket()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_club_name text;
  v_title text;
  v_body text;
begin
  select name
  into v_club_name
  from public.clubs
  where id = NEW.club_id;

  v_title := 'Yeni destek talebi — ' || coalesce(v_club_name, 'Kulüp');

  v_body :=
    'Yeni bir destek talebi oluşturuldu.' ||
    E'\n\n' ||
    'Kulüp: ' || coalesce(v_club_name, 'Bilinmiyor') ||
    E'\n' ||
    'Kategori: ' || coalesce(NEW.category_label, NEW.category, 'Bilinmiyor') ||
    E'\n' ||
    'Konu: ' || coalesce(NEW.subject, 'Bilinmiyor') ||
    E'\n\n' ||
    coalesce(NEW.preview, '');

  perform public.push_admin_notification(
    left(v_title, 160),
    left(v_body, 1000),
    'support_ticket_created'
  );

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_new_unipakt_announcement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_club record;
  v_title text;
  v_body text;
begin
  -- UniPakt duyuruları club_id NULL ve status published olarak oluşturuluyor.
  if NEW.club_id is null and NEW.status = 'published' then
    v_title := coalesce(NEW.title, 'Yeni UniPakt duyurusu');
    v_body := coalesce(NEW.body, '');

    for v_club in
      select id
      from public.clubs
      where coalesce(visible, true) = true
    loop
      perform public.push_notification(
        v_club.id,
        'Yeni UniPakt duyurusu',
        v_body,
        'unipakt_announcement_published',
        null,
        null,
        null,
        false,
        true
      );
    end loop;
  end if;

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_new_unipakt_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_club record;
  v_title text;
  v_body text;
begin
  -- UniPakt tarafından doğrudan oluşturulan/yayınlanan event:
  -- club_id NULL + status published.
  if NEW.club_id is null and NEW.status = 'published' then
    v_title := coalesce(NEW.title, 'Yeni UniPakt etkinliği');
    v_body := 'UniPakt yeni bir etkinlik yayınladı: “' || v_title || '”. Etkinlik detaylarını panelden inceleyebilirsin.';

    for v_club in
      select id
      from public.clubs
      where coalesce(visible, true) = true
    loop
      perform public.push_notification(
        v_club.id,
        'Yeni UniPakt etkinliği',
        v_body,
        'unipakt_event_published',
        NEW.id,
        null,
        null,
        false,
        true
      );
    end loop;
  end if;

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_task_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.push_notification(NEW.club_id,'Yeni görev atandı','UniPakt sana “'||NEW.title||'” görevini atadı.','task_assigned',null,null,NEW.id,false,true);
  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_visibility_decision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_title text;
begin
  if NEW.status<>OLD.status and NEW.status in ('approved','rejected') then
    select title into v_title from public.events where id=NEW.event_id;
    perform public.push_notification(NEW.club_id,case when NEW.status='approved' then 'Etkinlik görünürlük talebin onaylandı' else 'Etkinlik görünürlük talebin reddedildi' end,
      case when NEW.status='approved' then '“'||v_title||'” için görünürlük talebin uygulandı.' else '“'||v_title||'” için görünürlük talebin reddedildi. Not: '||coalesce(NEW.note,'') end,'event_visibility_decision',NEW.event_id,null,null,false,true);
  end if;
  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.public_events()
 RETURNS TABLE(id uuid, title text, description text, event_date date, event_time time without time zone, place text, address text, rules text, poster_url text, tags text[], registration_url text, fee_type text, fee_amount numeric, kind text, organizer_id uuid, organizer text, university text, occurrences jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select e.id,e.title,e.description,e.event_date,e.event_time,e.place,e.address,e.rules,e.poster_url,e.tags,e.registration_url,e.fee_type,e.fee_amount,e.kind,
    c.id as organizer_id,
    coalesce(nullif(e.university,''),c.university,'UniPakt') ||
      coalesce((select ', '||string_agg(distinct coalesce(pc.university,pc.name), ', ' order by coalesce(pc.university,pc.name)) from public.event_applications pa join public.clubs pc on pc.id=pa.club_id where pa.event_id=e.id and pa.status='approved'),'') as organizer,
    coalesce(nullif(e.university,''),c.university) as university,
    coalesce((select jsonb_agg(jsonb_build_object('date',o.date,'time',o.time) order by o.date,o.time) from public.event_occurrences o where o.event_id=e.id),jsonb_build_array(jsonb_build_object('date',e.event_date,'time',e.event_time))) as occurrences
  from public.events e left join public.clubs c on c.id=e.club_id
  where e.status='published' and coalesce(e.visible,true)<>false and (e.kind='event' or e.calendar='on')
  order by e.event_date,e.event_time,e.created_at;
$function$
;

CREATE OR REPLACE FUNCTION public.push_admin_notification(p_title text, p_body text, p_type text, p_event uuid DEFAULT NULL::uuid, p_application uuid DEFAULT NULL::uuid, p_task uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  insert into public.notifications(recipient_club_id,recipient_role,type,title,body,event_id,application_id,task_id,actionable,resolved)
  values(null,'admin',p_type,left(p_title,160),left(p_body,1000),p_event,p_application,p_task,false,true)
  returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.push_notification(p_club uuid, p_title text, p_body text, p_type text, p_event uuid DEFAULT NULL::uuid, p_application uuid DEFAULT NULL::uuid, p_task uuid DEFAULT NULL::uuid, p_actionable boolean DEFAULT false, p_resolved boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  insert into public.notifications(recipient_club_id,recipient_role,type,title,body,event_id,application_id,task_id,actionable,resolved)
  values(p_club,'club',p_type,left(p_title,160),left(p_body,1000),p_event,p_application,p_task,p_actionable,p_resolved)
  returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.remove_event_partner(p_event uuid, p_club uuid, p_note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_app uuid; v_title text;
begin
  if not public.is_admin() then raise exception 'Bu işlem yalnızca UniPakt tarafından yapılabilir.'; end if;
  select a.id,e.title into v_app,v_title from public.event_applications a join public.events e on e.id=a.event_id
   where a.event_id=p_event and a.club_id=p_club and a.status='approved';
  if not found then raise exception 'Onaylı ortak bulunamadı.'; end if;
  update public.event_applications set status='removed', decided_at=now(), note=left(coalesce(note,'')||case when p_note<>'' then ' | UniPakt: '||p_note else '' end,500) where id=v_app;
  perform public.push_notification(p_club,'Etkinlik ortaklığın kaldırıldı','“'||v_title||'” etkinliğindeki ortaklığın UniPakt tarafından kaldırıldı.'||case when p_note<>'' then ' Not: '||p_note else '' end,'partner_removed',p_event,v_app,null,false,true);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.reply_support_ticket(p_ticket_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ticket public.support_tickets%rowtype;
  v_role text;
begin
  if char_length(trim(coalesce(p_body,''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  select * into v_ticket
  from public.support_tickets
  where id = p_ticket_id;

  if not found then
    raise exception 'Support ticket not found';
  end if;

  if public.is_unipakt_admin() then
    v_role := 'admin';
  elsif v_ticket.club_id = public.my_club_id() or v_ticket.created_by = auth.uid() then
    v_role := 'club';
  else
    raise exception 'Not allowed';
  end if;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values (
    p_ticket_id,
    auth.uid(),
    v_role,
    case when v_role = 'admin' then 'UniPakt Destek' else 'Kulüp' end,
    trim(p_body)
  );

  update public.support_tickets
  set status = case when v_role = 'admin' then 'answered' else 'waiting_user' end,
      preview = left(trim(p_body),300),
      updated_at = now()
  where id = p_ticket_id;

  -- Notify the admin panel when a club replies.
  if v_role = 'club'
     and to_regprocedure('public.push_admin_notification(text,text,text,uuid,uuid,uuid)') is not null then
    perform public.push_admin_notification(
      'Destek talebine yeni yanıt',
      'Bir kulüp destek talebine yeni bir yanıt gönderdi: ' || coalesce(v_ticket.ticket_number, 'UP-' || upper(substr(replace(v_ticket.id::text,'-',''),1,8))),
      'support_ticket_reply',
      null, null, null
    );
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.request_calendar(p_event uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.events
     set calendar = 'requested'
   where id = p_event and club_id = public.my_club()
     and status = 'published' and kind = 'partner' and calendar = 'none';
  if not found then
    raise exception 'Bu etkinlik için talep gönderilemiyor.';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.review_task(p_task uuid, p_status text, p_note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_club uuid; v_title text;
begin
  if not public.is_admin() then raise exception 'Bu işlem yalnızca UniPakt tarafından yapılabilir.'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Geçersiz karar.'; end if;
  if p_status='rejected' and coalesce(btrim(p_note),'')='' then raise exception 'Reddetmek için not zorunludur.'; end if;
  select club_id,title into v_club,v_title from public.tasks where id=p_task and status='done' and review_status='pending';
  if not found then raise exception 'İnceleme bekleyen görev bulunamadı.'; end if;
  if p_status='approved' then
    update public.tasks set review_status='approved',review_note=null,reviewed_at=now() where id=p_task;
    perform public.push_notification(v_club,'Görevin onaylandı','“'||v_title||'” görevinin tamamlanması UniPakt tarafından onaylandı.','task_review',null,null,p_task,false,true);
  else
    update public.tasks set status='open',review_status='rejected',review_note=left(btrim(p_note),500),reviewed_at=now() where id=p_task;
    perform public.push_notification(v_club,'Görev kanıtın reddedildi','“'||v_title||'” görevin için kanıt reddedildi. Not: '||btrim(p_note),'task_review',null,null,p_task,false,true);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.send_notification_email_webhook()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
declare
  function_key text;
begin

  select decrypted_secret
  into function_key
  from vault.decrypted_secrets
  where name = 'notification_function_key'
  limit 1;

  if function_key is null then
    raise exception 'notification_function_key Vault secret bulunamadı';
  end if;

  perform net.http_post(
    url := 'https://hcgotmcbwmleeklbvawb.supabase.co/functions/v1/send-email-notifications',

    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', function_key
    ),

    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'notifications',
      'schema', 'public',
      'record', to_jsonb(NEW),
      'old_record', null
    )
  );

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_event(p_event jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_club uuid := public.my_club();
  v_admin boolean := public.is_admin();
  v_status text;
  v_calendar text;
  v_occ jsonb;
  v_item jsonb;
begin
  if not v_admin and v_club is null then
    raise exception 'Bu işlem için kulüp hesabı gerekir.';
  end if;

  if coalesce(nullif(trim(p_event->>'title'), ''), '') = '' then
    raise exception 'Etkinlik adı gerekli.';
  end if;

  v_status := case when v_admin then 'published' else 'pending' end;
  v_calendar := case
    when v_admin then coalesce(nullif(p_event->>'kind','partner'), 'on')
    else 'none'
  end;

  insert into public.events (
    club_id,
    title,
    description,
    event_date,
    event_time,
    place,
    seeking,
    status,
    note,
    created_by,
    decided_at,
    kind,
    calendar,
    address,
    rules,
    poster_url,
    tags,
    registration_url,
    fee_type,
    fee_amount,
    university,
    visible
  )
  values (
    case when v_admin then null else v_club end,
    p_event->>'title',
    coalesce(p_event->>'description',''),
    ((p_event->'occurrences'->0)->>'date')::date,
    nullif((p_event->'occurrences'->0)->>'time','')::time,
    nullif(p_event->>'place',''),
    nullif(p_event->>'seeking',''),
    v_status,
    null,
    auth.uid(),
    case when v_admin then now() else null end,
    coalesce(nullif(p_event->>'kind',''),'event'),
    case when v_admin then
      case when coalesce(p_event->>'kind','event') = 'event' then 'on' else 'none' end
    else 'none' end,
    nullif(p_event->>'address',''),
    nullif(p_event->>'rules',''),
    nullif(p_event->>'poster_url',''),
    coalesce(
      array(
        select jsonb_array_elements_text(coalesce(p_event->'tags','[]'::jsonb))
      ),
      '{}'
    ),
    nullif(p_event->>'registration_url',''),
    case when p_event->>'fee_type' = 'paid' then 'paid' else 'free' end,
    case when p_event->>'fee_type' = 'paid' then nullif(p_event->>'fee_amount','')::numeric else null end,
    nullif(p_event->>'university',''),
    true
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(coalesce(p_event->'occurrences','[]'::jsonb))
  loop
    insert into public.event_occurrences(event_id, date, time)
    values (
      v_id,
      (v_item->>'date')::date,
      nullif(v_item->>'time','')::time
    );
  end loop;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_event_application(p_event uuid, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_club uuid := public.my_club(); v_host uuid; v_id uuid; v_title text; v_name text;
begin
  if v_club is null then raise exception 'Kulüp hesabı gerekir.'; end if;
  if coalesce(btrim(p_note),'')='' then raise exception 'Katkı açıklaması zorunlu.'; end if;
  select club_id,title into v_host,v_title from public.events where id=p_event and status='published' and kind='partner';
  if not found then raise exception 'Ortak aranan yayınlanmış etkinlik bulunamadı.'; end if;
  if v_host is null then raise exception 'Bu etkinliğin kulüp sahibi yok.'; end if;
  if v_host=v_club then raise exception 'Kendi etkinliğine ortak olamazsın.'; end if;
  if exists(select 1 from public.event_applications where event_id=p_event and club_id=v_club and status in ('pending','approved')) then
    raise exception 'Bu etkinliğe zaten başvurdun.';
  end if;
  insert into public.event_applications(event_id,club_id,note,status) values(p_event,v_club,btrim(p_note),'pending') returning id into v_id;
  select name into v_name from public.clubs where id=v_club;
  perform public.push_notification(v_host,'Yeni ortaklık başvurusu',coalesce(v_name,'Bir kulüp')||' “'||v_title||'” etkinliğine ortak olmak istiyor.','partnership_application',p_event,v_id,null,true,false);
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.support_create_ticket_v2(p_subject text, p_category text, p_body text, p_category_label text DEFAULT NULL::text, p_event_id uuid DEFAULT NULL::uuid, p_attachment_path text DEFAULT NULL::text, p_attachment_name text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_club uuid;
begin
  v_club := public.my_club_id();
  if v_club is null or public.is_unipakt_admin() then
    raise exception 'Only club accounts can create support tickets';
  end if;

  if p_category not in ('technical','community','event') then
    raise exception 'Invalid support category';
  end if;
  if char_length(trim(coalesce(p_subject,''))) = 0 then
    raise exception 'Subject is required';
  end if;
  if char_length(trim(coalesce(p_body,''))) = 0 then
    raise exception 'Message is required';
  end if;

  if p_event_id is not null and not exists (
    select 1 from public.events e
    where e.id = p_event_id and e.club_id = v_club
  ) then
    raise exception 'Selected event does not belong to this club';
  end if;

  insert into public.support_tickets(
    club_id, created_by, subject, category, category_label, event_id,
    attachment_path, attachment_name, status, preview
  )
  values(
    v_club,
    auth.uid(),
    trim(p_subject),
    p_category,
    coalesce(nullif(trim(p_category_label), ''),
      case p_category
        when 'event' then 'Etkinlik Desteği'
        when 'community' then 'Topluluk ve Güvenlik'
        else 'Teknik Destek'
      end
    ),
    p_event_id,
    p_attachment_path,
    p_attachment_name,
    'open',
    left(trim(p_body), 300)
  )
  returning id into v_id;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values(v_id, auth.uid(), 'club', 'Kulüp', trim(p_body));

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.support_reply_ticket_v2(p_ticket_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ticket public.support_tickets%rowtype;
  v_role text;
begin
  if char_length(trim(coalesce(p_body,''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  select * into v_ticket
  from public.support_tickets
  where id = p_ticket_id
  for update;

  if not found then
    raise exception 'Support ticket not found';
  end if;

  if public.is_unipakt_admin() then
    v_role := 'admin';
  elsif v_ticket.club_id = public.my_club_id() or v_ticket.created_by = auth.uid() then
    v_role := 'club';
  else
    raise exception 'Not allowed';
  end if;

  insert into public.support_ticket_messages(ticket_id, author_id, author_role, author_label, body)
  values (
    p_ticket_id,
    auth.uid(),
    v_role,
    case when v_role = 'admin' then 'UniPakt Destek' else 'Kulüp' end,
    trim(p_body)
  );

  update public.support_tickets
     set status = case when v_role = 'admin' then 'answered' else 'waiting_user' end,
         preview = left(trim(p_body), 300),
         updated_at = now()
   where id = p_ticket_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.touch_support_ticket()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.verify_notification_key(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(p_key, '') <> ''
     and exists (
       select 1 from vault.decrypted_secrets
        where name = 'notification_function_key' and decrypted_secret = p_key
     );
$function$
;

-- ---------- Triggers ----------

CREATE TRIGGER event_edit_notification AFTER UPDATE ON public.event_edit_requests FOR EACH ROW EXECUTE FUNCTION notify_event_edit_decision();
CREATE TRIGGER event_lifecycle_notification AFTER UPDATE ON public.events FOR EACH ROW EXECUTE FUNCTION notify_event_lifecycle();
CREATE TRIGGER event_visibility_notification AFTER UPDATE ON public.event_visibility_requests FOR EACH ROW EXECUTE FUNCTION notify_visibility_decision();
CREATE TRIGGER new_support_ticket_admin_notification AFTER INSERT ON public.support_tickets FOR EACH ROW EXECUTE FUNCTION notify_new_support_ticket();
CREATE TRIGGER new_unipakt_announcement_notification AFTER INSERT ON public.announcements FOR EACH ROW EXECUTE FUNCTION notify_new_unipakt_announcement();
CREATE TRIGGER new_unipakt_event_notification AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION notify_new_unipakt_event();
CREATE TRIGGER notifications_send_email AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION send_notification_email_webhook();
CREATE TRIGGER support_ticket_touch BEFORE UPDATE ON public.support_tickets FOR EACH ROW EXECUTE FUNCTION touch_support_ticket();
CREATE TRIGGER task_assignment_notification AFTER INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION notify_task_assignment();

-- ---------- Row level security policies ----------

create policy announcements_admin_write on public.announcements as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy announcements_club_insert on public.announcements as PERMISSIVE for INSERT to authenticated
  with check (((club_id = ( SELECT my_club() AS my_club)) AND (status = 'pending'::text) AND (note IS NULL) AND (decided_at IS NULL)));
create policy announcements_select on public.announcements as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club)) OR ((status = 'published'::text) AND (( SELECT my_role() AS my_role) IS NOT NULL))));
create policy clubs_admin_write on public.clubs as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy clubs_public_select on public.clubs as PERMISSIVE for SELECT to anon
  using ((visible IS NOT FALSE));
create policy clubs_select on public.clubs as PERMISSIVE for SELECT to authenticated
  using ((( SELECT my_role() AS my_role) IS NOT NULL));
create policy event_applications_select on public.event_applications as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club)) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_applications.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)))))));
create policy event_edit_requests_admin_write on public.event_edit_requests as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy event_edit_requests_club_insert on public.event_edit_requests as PERMISSIVE for INSERT to authenticated
  with check (((club_id = ( SELECT my_club() AS my_club)) AND (status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_edit_requests.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'published'::text))))));
create policy event_edit_requests_select on public.event_edit_requests as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club))));
create policy event_occurrences_admin_write on public.event_occurrences as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy event_occurrences_club_insert on public.event_occurrences as PERMISSIVE for INSERT to authenticated
  with check ((EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_occurrences.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'pending'::text)))));
create policy event_occurrences_delete on public.event_occurrences as PERMISSIVE for DELETE to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_occurrences.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'pending'::text))))));
create policy event_occurrences_insert on public.event_occurrences as PERMISSIVE for INSERT to authenticated
  with check ((( SELECT is_admin() AS is_admin) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_occurrences.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'pending'::text))))));
create policy event_occurrences_select on public.event_occurrences as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_occurrences.event_id) AND ((e.club_id = ( SELECT my_club() AS my_club)) OR (e.status = 'published'::text)))))));
create policy event_occurrences_update on public.event_occurrences as PERMISSIVE for UPDATE to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_occurrences.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'pending'::text))))))
  with check ((( SELECT is_admin() AS is_admin) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_occurrences.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'pending'::text))))));
create policy event_visibility_requests_admin_write on public.event_visibility_requests as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy event_visibility_requests_club_insert on public.event_visibility_requests as PERMISSIVE for INSERT to authenticated
  with check (((club_id = ( SELECT my_club() AS my_club)) AND (status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_visibility_requests.event_id) AND (e.club_id = ( SELECT my_club() AS my_club)) AND (e.status = 'published'::text))))));
create policy event_visibility_requests_select on public.event_visibility_requests as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club))));
create policy events_admin_write on public.events as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy events_club_insert on public.events as PERMISSIVE for INSERT to authenticated
  with check ((( SELECT is_admin() AS is_admin) OR ((club_id = ( SELECT my_club() AS my_club)) AND (status = 'pending'::text) AND (note IS NULL) AND (decided_at IS NULL) AND (calendar = 'none'::text) AND (visible = true))));
create policy events_select on public.events as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club)) OR ((status = 'published'::text) AND (( SELECT my_role() AS my_role) IS NOT NULL))));
create policy notifications_delete on public.notifications as PERMISSIVE for DELETE to authenticated
  using (((( SELECT is_admin() AS is_admin) OR (recipient_club_id = ( SELECT my_club() AS my_club))) AND ((NOT actionable) OR resolved)));
create policy notifications_read on public.notifications as PERMISSIVE for UPDATE to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (recipient_club_id = ( SELECT my_club() AS my_club))))
  with check ((( SELECT is_admin() AS is_admin) OR (recipient_club_id = ( SELECT my_club() AS my_club))));
create policy notifications_select on public.notifications as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (recipient_club_id = ( SELECT my_club() AS my_club))));
create policy point_entries_admin_write on public.point_entries as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy point_entries_select on public.point_entries as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club))));
create policy profiles_select on public.profiles as PERMISSIVE for SELECT to authenticated
  using (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT is_admin() AS is_admin)));
create policy support_ticket_messages_admin_all on public.support_ticket_messages as PERMISSIVE for ALL to authenticated
  using (is_unipakt_admin())
  with check (is_unipakt_admin());
create policy support_ticket_messages_club_insert on public.support_ticket_messages as PERMISSIVE for INSERT to authenticated
  with check (((author_id = auth.uid()) AND (author_role = 'club'::text) AND (EXISTS ( SELECT 1
   FROM support_tickets t
  WHERE ((t.id = support_ticket_messages.ticket_id) AND ((t.club_id = my_club_id()) OR (t.created_by = auth.uid())))))));
create policy support_ticket_messages_club_select on public.support_ticket_messages as PERMISSIVE for SELECT to authenticated
  using ((EXISTS ( SELECT 1
   FROM support_tickets t
  WHERE ((t.id = support_ticket_messages.ticket_id) AND ((t.club_id = my_club_id()) OR (t.created_by = auth.uid()))))));
create policy support_tickets_admin_all on public.support_tickets as PERMISSIVE for ALL to authenticated
  using (is_unipakt_admin())
  with check (is_unipakt_admin());
create policy support_tickets_club_insert on public.support_tickets as PERMISSIVE for INSERT to authenticated
  with check (((club_id = my_club_id()) AND (created_by = auth.uid())));
create policy support_tickets_club_select on public.support_tickets as PERMISSIVE for SELECT to authenticated
  using (((club_id = my_club_id()) OR (created_by = auth.uid())));
create policy tasks_admin_write on public.tasks as PERMISSIVE for ALL to authenticated
  using (( SELECT is_admin() AS is_admin))
  with check (( SELECT is_admin() AS is_admin));
create policy tasks_select on public.tasks as PERMISSIVE for SELECT to authenticated
  using ((( SELECT is_admin() AS is_admin) OR (club_id = ( SELECT my_club() AS my_club))));
create policy event_posters_authenticated_delete on storage.objects as PERMISSIVE for DELETE to authenticated
  using (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))));
create policy event_posters_authenticated_insert on storage.objects as PERMISSIVE for INSERT to authenticated
  with check (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))));
create policy event_posters_authenticated_update on storage.objects as PERMISSIVE for UPDATE to authenticated
  using (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))))
  with check (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))));
create policy event_posters_delete on storage.objects as PERMISSIVE for DELETE to authenticated
  using (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))));
create policy event_posters_insert on storage.objects as PERMISSIVE for INSERT to authenticated
  with check (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))));
create policy event_posters_update on storage.objects as PERMISSIVE for UPDATE to authenticated
  using (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))))
  with check (((bucket_id = 'event-posters'::text) AND (( SELECT is_admin() AS is_admin) OR (split_part(name, '/'::text, 1) = (( SELECT my_club() AS my_club))::text))));
create policy support_attachments_insert on storage.objects as PERMISSIVE for INSERT to authenticated
  with check (((bucket_id = 'support-attachments'::text) AND (is_unipakt_admin() OR (split_part(name, '/'::text, 1) = (my_club_id())::text))));
create policy support_attachments_select on storage.objects as PERMISSIVE for SELECT to authenticated
  using (((bucket_id = 'support-attachments'::text) AND (is_unipakt_admin() OR (split_part(name, '/'::text, 1) = (my_club_id())::text))));
create policy task_proofs_admin_delete on storage.objects as PERMISSIVE for DELETE to authenticated
  using (((bucket_id = 'task-proofs'::text) AND ( SELECT is_admin() AS is_admin)));
create policy task_proofs_insert on storage.objects as PERMISSIVE for INSERT to authenticated
  with check (((bucket_id = 'task-proofs'::text) AND ((storage.foldername(name))[1] = (( SELECT my_club() AS my_club))::text)));
create policy task_proofs_select on storage.objects as PERMISSIVE for SELECT to authenticated
  using (((bucket_id = 'task-proofs'::text) AND (( SELECT is_admin() AS is_admin) OR ((storage.foldername(name))[1] = (( SELECT my_club() AS my_club))::text))));

-- ---------- Function privileges ----------

revoke all on function admin_delete_support_ticket(uuid) from public, anon, authenticated;
grant execute on function admin_delete_support_ticket(uuid) to authenticated;
revoke all on function admin_update_support_ticket(uuid,text,text,text) from public, anon, authenticated;
grant execute on function admin_update_support_ticket(uuid,text,text,text) to authenticated;
revoke all on function complete_task(uuid,text,text,text) from public, anon, authenticated;
grant execute on function complete_task(uuid,text,text,text) to authenticated;
revoke all on function create_support_ticket(text,text,text) from public, anon, authenticated;
grant execute on function create_support_ticket(text,text,text) to authenticated;
revoke all on function create_support_ticket(text,text,text,text,uuid,text,text) from public, anon, authenticated;
grant execute on function create_support_ticket(text,text,text,text,uuid,text,text) to authenticated;
revoke all on function decide_event_application(uuid,text,text) from public, anon, authenticated;
grant execute on function decide_event_application(uuid,text,text) to authenticated;
revoke all on function delete_my_rejected_application(text,uuid,uuid) from public, anon, authenticated;
grant execute on function delete_my_rejected_application(text,uuid,uuid) to authenticated;
revoke all on function is_admin() from public, anon, authenticated;
grant execute on function is_admin() to authenticated;
revoke all on function is_unipakt_admin() from public, anon, authenticated;
grant execute on function is_unipakt_admin() to authenticated;
revoke all on function leaderboard() from public, anon, authenticated;
grant execute on function leaderboard() to authenticated;
revoke all on function my_club() from public, anon, authenticated;
grant execute on function my_club() to authenticated;
revoke all on function my_club_id() from public, anon, authenticated;
grant execute on function my_club_id() to authenticated;
revoke all on function my_role() from public, anon, authenticated;
grant execute on function my_role() to authenticated;
revoke all on function notify_event_edit_decision() from public, anon, authenticated;
revoke all on function notify_event_lifecycle() from public, anon, authenticated;
revoke all on function notify_new_support_ticket() from public, anon, authenticated;
revoke all on function notify_new_unipakt_announcement() from public, anon, authenticated;
revoke all on function notify_new_unipakt_event() from public, anon, authenticated;
revoke all on function notify_task_assignment() from public, anon, authenticated;
revoke all on function notify_visibility_decision() from public, anon, authenticated;
revoke all on function public_events() from public, anon, authenticated;
grant execute on function public_events() to anon;
grant execute on function public_events() to authenticated;
revoke all on function push_admin_notification(text,text,text,uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function push_notification(uuid,text,text,text,uuid,uuid,uuid,boolean,boolean) from public, anon, authenticated;
revoke all on function remove_event_partner(uuid,uuid,text) from public, anon, authenticated;
grant execute on function remove_event_partner(uuid,uuid,text) to authenticated;
revoke all on function reply_support_ticket(uuid,text) from public, anon, authenticated;
grant execute on function reply_support_ticket(uuid,text) to authenticated;
revoke all on function request_calendar(uuid) from public, anon, authenticated;
grant execute on function request_calendar(uuid) to authenticated;
revoke all on function review_task(uuid,text,text) from public, anon, authenticated;
grant execute on function review_task(uuid,text,text) to authenticated;
revoke all on function send_notification_email_webhook() from public, anon, authenticated;
revoke all on function submit_event(jsonb) from public, anon, authenticated;
grant execute on function submit_event(jsonb) to authenticated;
revoke all on function submit_event_application(uuid,text) from public, anon, authenticated;
grant execute on function submit_event_application(uuid,text) to authenticated;
revoke all on function support_create_ticket_v2(text,text,text,text,uuid,text,text) from public, anon, authenticated;
grant execute on function support_create_ticket_v2(text,text,text,text,uuid,text,text) to authenticated;
revoke all on function support_reply_ticket_v2(uuid,text) from public, anon, authenticated;
grant execute on function support_reply_ticket_v2(uuid,text) to authenticated;
revoke all on function touch_support_ticket() from public, anon, authenticated;
grant execute on function touch_support_ticket() to anon;
grant execute on function touch_support_ticket() to authenticated;
revoke all on function verify_notification_key(text) from public, anon, authenticated;

-- ---------- Table privileges (reference) ----------

-- announcements: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- clubs: anon=SELECT authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- event_applications: anon=- authenticated=REFERENCES,SELECT,TRIGGER,TRUNCATE
-- event_edit_requests: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- event_occurrences: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- event_visibility_requests: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- events: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- notifications: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- point_entries: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- profiles: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- support_ticket_messages: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- support_tickets: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
-- tasks: anon=- authenticated=DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE

-- ---------- Storage buckets ----------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('event-posters', 'event-posters', t, 5242880, '{image/jpeg,image/png,image/webp}'::text[]) on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('support-attachments', 'support-attachments', f, 5242880, '{image/png,image/jpeg,image/webp,application/pdf}'::text[]) on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('task-proofs', 'task-proofs', f, 5242880, '{image/png,image/jpeg,image/webp,application/pdf}'::text[]) on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
