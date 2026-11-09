-- Birim türleri ve birime özel yetkiler.
--  * units.kind: birimin özel sayfalarını belirler (social, pr, sponsor, clubs, audit, board = YK).
--    Her türden tek birim olur; Merkez Yönetim Birimler sayfasından atar.
--  * Yetki kataloğu: ortak (team, roles, chat) + türe özel. Başkan, birim türünün tüm yetkilerine sahiptir.
--    Hangi yetkinin hangi türe ait olduğunu unit_kind_perms() söyler; unit-team fonksiyonu da buna uyar.
--  * Sosyal Medya'da "brand" yetkisi olan kişi marka rengini değiştirebilir (set_site_theme).
alter table public.units add column if not exists kind text
  check (kind is null or kind in ('social', 'pr', 'sponsor', 'clubs', 'audit', 'board'));
create unique index if not exists units_kind_unique on public.units (kind) where kind is not null;
update public.units set kind = 'social' where name = 'Sosyal Medya' and kind is null;
update public.units set kind = 'pr' where name = 'Halkla İlişkiler' and kind is null;
update public.units set kind = 'sponsor' where name = 'Sponsorluk' and kind is null;
update public.units set kind = 'clubs' where name = 'Kulüp İlişkileri' and kind is null;
update public.units set kind = 'audit' where name = 'Denetim' and kind is null;

create or replace function public.unit_kind_perms(p_kind text)
returns text[] language sql immutable set search_path = '' as $$
  select array['team', 'roles', 'chat'] || case p_kind
    when 'social' then array['posts', 'brand']
    when 'pr' then array['campaigns']
    when 'sponsor' then array['sponsors']
    when 'clubs' then array['clubs', 'clubs_accept']
    when 'audit' then array['audit', 'audit_assign']
    when 'board' then array['approve']
    else array[]::text[] end;
$$;
grant execute on function public.unit_kind_perms(text) to authenticated, service_role;

alter table public.unit_roles drop constraint if exists unit_roles_permissions_check;
alter table public.unit_members drop constraint if exists unit_members_permissions_check;
alter table public.unit_roles add constraint unit_roles_permissions_check check (permissions <@ array['team', 'roles', 'chat', 'posts', 'brand', 'campaigns', 'sponsors', 'clubs', 'clubs_accept', 'audit', 'audit_assign', 'approve']::text[]);
alter table public.unit_members add constraint unit_members_permissions_check check (permissions <@ array['team', 'roles', 'chat', 'posts', 'brand', 'campaigns', 'sponsors', 'clubs', 'clubs_accept', 'audit', 'audit_assign', 'approve']::text[]);

create or replace function public.my_unit_perms()
returns text[] language sql stable security definer set search_path = '' as $$
  select case when m.is_head then public.unit_kind_perms(u.kind)
              else array(select distinct x from unnest(r.permissions || m.permissions) x where x = any(public.unit_kind_perms(u.kind))) end
  from public.unit_members m join public.unit_roles r on r.id = m.role_id join public.units u on u.id = m.unit_id
  where m.user_id = (select auth.uid()) and m.status = 'active';
$$;

-- Çağıranın türü verilen birimde aktif üyeliği ve yetkisi var mı?
create or replace function public.unit_can(p_kind text, p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select u.kind = p_kind from public.units u where u.id = public.my_unit()), false)
     and p_perm = any(coalesce(public.my_unit_perms(), '{}')) and public.mfa_ok();
$$;
revoke all on function public.unit_can(text, text) from public, anon;
grant execute on function public.unit_can(text, text) to authenticated, service_role;

create or replace function public.set_site_theme(p_colors text[], p_angle integer, p_on_dark text, p_on_light text, p_on_accent text)
 returns void language plpgsql security definer set search_path to '' as $function$
declare v_colors text[];
begin
  if not ((public.is_admin() and public.mfa_ok()) or public.unit_can('social', 'brand')) then
    raise exception 'Marka rengini yalnızca UniPakt yöneticisi ve Sosyal Medya biriminde yetkisi olanlar değiştirebilir.';
  end if;
  select array_agg(upper(btrim(c)) order by o) into v_colors from unnest(p_colors) with ordinality as t(c, o);
  if v_colors is null or cardinality(v_colors) not between 1 and 4
     or array_to_string(v_colors, ',') !~ '^#[0-9A-F]{6}(,#[0-9A-F]{6}){0,3}$' then
    raise exception '1 ile 4 arasında renk seç (#RRGGBB).';
  end if;
  if upper(p_on_dark) !~ '^#[0-9A-F]{6}$' or upper(p_on_light) !~ '^#[0-9A-F]{6}$' or upper(p_on_accent) !~ '^#[0-9A-F]{6}$' then
    raise exception 'Yazı renkleri #RRGGBB olmalı.';
  end if;
  update public.site_theme
     set colors = v_colors, angle = coalesce(p_angle, 135) % 360, on_dark = upper(p_on_dark), on_light = upper(p_on_light),
         on_accent = upper(p_on_accent), updated_at = now(), updated_by = auth.uid()
   where id = 1;
  perform public.log_activity('Marka rengini değiştirdi', array_to_string(v_colors, ' → '), auth.uid());
end;
$function$;

-- Rehbere birim türü ve türün yetki kataloğu eklenir.
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
    'me', jsonb_build_object('id', me, 'unit_id', mine, 'perms', coalesce(to_jsonb(public.my_unit_perms()), '[]'::jsonb),
                             'is_head', coalesce((select is_head from public.unit_members where user_id = me and status = 'active'), false),
                             'admin', admin_ok),
    'units', coalesce((select jsonb_agg(jsonb_build_object(
        'id', u.id, 'name', u.name, 'sort', u.sort, 'kind', u.kind, 'kind_perms', to_jsonb(public.unit_kind_perms(u.kind)),
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
