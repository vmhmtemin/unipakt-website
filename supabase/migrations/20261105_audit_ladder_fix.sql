-- Denetim uyarı basamağı: sıradaki basamak, hedefin ulaştığı en yüksek basamaktan bir sonrakidir.
-- (Ağır ihlalde atlanan basamaklar geri gelmez; tespit notları basamak sayılmaz.)
create or replace function public.uw_audit_next(p_type text, p_target uuid)
returns text language sql stable security definer set search_path = '' as $$
  select (array['verbal1', 'verbal2', 'written', 'report'])[least(coalesce(max(array_position(array['verbal1', 'verbal2', 'written', 'report'], level)), 0) + 1, 4)]
  from public.audit_records where target_type = p_type and target_id = p_target and level <> 'note';
$$;
revoke all on function public.uw_audit_next(text, uuid) from public, anon, authenticated;
grant execute on function public.uw_audit_next(text, uuid) to service_role;

create or replace function public.uwa_audit_add(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_type text := p ->> 'target_type'; v_target uuid := public.uw_uuid(p, 'target_id'); v_label text; v_mode text := coalesce(p ->> 'mode', 'warning');
  v_level text; v_skip boolean := false; v_reason text := public.uw_text(p, 'skip_reason', 1000); v_id uuid;
begin
  if not public.uw_can('audit', 'audit') then raise exception 'Bu işlem için Denetim’de denetim kaydı yetkisi gerekir.'; end if;
  v_label := case v_type
    when 'unit' then (select name from public.units where id = v_target)
    when 'event' then (select e.title || coalesce(' · ' || c.name, '') from public.events e left join public.clubs c on c.id = e.club_id where e.id = v_target)
    when 'club' then (select name from public.clubs where id = v_target) end;
  if v_label is null then raise exception 'Denetlenen birim, etkinlik ya da kulüp bulunamadı.'; end if;
  if v_mode = 'note' then v_level := 'note';
  elsif v_mode = 'skip' then
    v_level := p ->> 'level';
    if v_level not in ('verbal2', 'written', 'report') then raise exception 'Atlanacak basamağı seç.'; end if;
    if v_reason is null then raise exception 'Basamak atlamak için gerekçe yaz.'; end if;
    v_skip := true;
  else
    v_level := public.uw_audit_next(v_type, v_target);
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
revoke all on function public.uwa_audit_add(jsonb) from public, anon, authenticated;
grant execute on function public.uwa_audit_add(jsonb) to service_role;
