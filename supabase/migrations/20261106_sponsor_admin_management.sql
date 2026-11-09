-- Allow MFA-verified UniPakt administrators to manage the Sponsor Network.
-- Unit members still need Sponsorship access; sponsor deletion remains limited
-- to administrators or Sponsorship unit heads/team managers.

create or replace function public.uw_sponsor_lead()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.uw_admin()
    or (public.uw_kind() = 'sponsor' and public.uw_has('sponsors'));
$$;

create or replace function public.uwa_sponsor_delete(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_s public.sponsors;
begin
  if not (
    public.uw_admin()
    or (
      public.uw_sponsor_lead()
      and (public.uw_head() or public.uw_has('team'))
    )
  ) then
    raise exception 'Sponsoru UniPakt yöneticisi ya da Sponsorluk birim yöneticisi siler.';
  end if;

  delete from public.sponsors
  where id = public.uw_uuid(p, 'id')
  returning * into v_s;

  if not found then raise exception 'Sponsor bulunamadı.'; end if;
  perform public.log_activity('Sponsoru sildi', v_s.brand);
  return null;
end;
$$;


-- Let administrators assign a sponsor to an active member of Sponsorship.
create or replace function public.uwa_sponsor_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := public.uw_uuid(p, 'id'); v_owner uuid := public.uw_uuid(p, 'owner'); v_s public.sponsors;
  v_stage text := coalesce(nullif(p ->> 'stage', ''), 'research'); v_pkg text := nullif(p ->> 'package', ''); v_email text := lower(public.uw_text(p, 'email', 200));
begin
  if not public.uw_sponsor_lead() then raise exception 'Bu işlem için Sponsorluk’ta sponsor yetkisi gerekir.'; end if;
  if v_owner is not null and not exists (select 1 from public.unit_members where user_id = v_owner and unit_id = case when public.uw_admin() then public.uw_unit_of_kind('sponsor') else public.uw_unit() end and status = 'active') then
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
