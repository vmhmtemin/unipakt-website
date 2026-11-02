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
