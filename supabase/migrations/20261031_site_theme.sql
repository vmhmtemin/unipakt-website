-- Marka rengi: sitenin, panelin, giriş kontrol sayfasının, logoların ve e-postaların rengi
-- tek satırdan gelir. Yönetici panelden (Marka rengi sayfası) değiştirir.
--   colors   : 1–4 renk (#RRGGBB), gradyan sırası
--   angle    : gradyan açısı (derece, CSS linear-gradient gibi)
--   on_dark  : koyu zeminde okunan tek renk (yazı, çizgi)   — panel hesaplar
--   on_light : açık zeminde okunan tek renk                 — panel hesaplar
--   on_accent: gradyanın üstündeki yazı rengi (#FFFFFF / #000000)
create table if not exists public.site_theme (
  id smallint primary key default 1 check (id = 1),
  colors text[] not null,
  angle smallint not null default 135 check (angle between 0 and 360),
  on_dark text not null,
  on_light text not null,
  on_accent text not null default '#FFFFFF',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint site_theme_colors check (cardinality(colors) between 1 and 4
    and array_to_string(colors, ',') ~ '^#[0-9A-F]{6}(,#[0-9A-F]{6}){0,3}$'),
  constraint site_theme_singles check (on_dark ~ '^#[0-9A-F]{6}$' and on_light ~ '^#[0-9A-F]{6}$' and on_accent in ('#FFFFFF', '#000000'))
);
insert into public.site_theme (id, colors, angle, on_dark, on_light, on_accent)
values (1, array['#8F244D', '#A94B86'], 135, '#A94B86', '#8F244D', '#FFFFFF')
on conflict (id) do nothing;

alter table public.site_theme enable row level security;
drop policy if exists site_theme_read on public.site_theme;
create policy site_theme_read on public.site_theme for select to anon, authenticated using (true);
revoke all on public.site_theme from anon, authenticated;
grant select (id, colors, angle, on_dark, on_light, on_accent, updated_at) on public.site_theme to anon, authenticated;

create or replace function public.set_site_theme(p_colors text[], p_angle integer, p_on_dark text, p_on_light text, p_on_accent text)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare v_colors text[];
begin
  if not public.is_admin() or not public.mfa_ok() then raise exception 'Marka rengini yalnızca UniPakt yöneticisi değiştirebilir.'; end if;
  select array_agg(upper(btrim(c)) order by o) into v_colors from unnest(p_colors) with ordinality as t(c, o);
  if v_colors is null or cardinality(v_colors) not between 1 and 4
     or array_to_string(v_colors, ',') !~ '^#[0-9A-F]{6}(,#[0-9A-F]{6}){0,3}$' then
    raise exception '1 ile 4 arasında renk seç (#RRGGBB).';
  end if;
  update public.site_theme
     set colors = v_colors, angle = coalesce(p_angle, 135) % 360, on_dark = upper(p_on_dark), on_light = upper(p_on_light),
         on_accent = upper(p_on_accent), updated_at = now(), updated_by = auth.uid()
   where id = 1;
  perform public.log_activity('Marka rengini değiştirdi', array_to_string(v_colors, ' → '), auth.uid());
end;
$function$;
revoke all on function public.set_site_theme(text[], integer, text, text, text) from public, anon;
grant execute on function public.set_site_theme(text[], integer, text, text, text) to authenticated;
