-- Applied to production on 2026-10-10.
-- push_* are internal helpers, called only from SECURITY DEFINER functions/triggers.
revoke execute on function public.push_notification from public, anon, authenticated;
revoke execute on function public.push_admin_notification from public, anon, authenticated;

-- SECURITY DEFINER functions: no anon access (public_events stays public);
-- trigger functions are not callable by anyone directly.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, pg_get_function_result(p.oid) = 'trigger' as is_trg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and p.proname not in ('public_events','push_notification','push_admin_notification','verify_notification_key')
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    if r.is_trg then
      execute format('revoke execute on function %s from authenticated', r.sig);
    else
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;

alter function public.touch_support_ticket() set search_path = '';
