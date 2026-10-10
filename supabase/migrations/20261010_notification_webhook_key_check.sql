-- Applied to production on 2026-10-10.
-- send-email-notifications only accepts requests carrying the Vault secret
-- `notification_function_key`; the function checks it with this helper.
create or replace function public.verify_notification_key(p_key text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_key,'') <> '' and exists (
    select 1 from vault.decrypted_secrets
    where name = 'notification_function_key' and decrypted_secret = p_key);
$$;
revoke execute on function public.verify_notification_key(text) from public, anon, authenticated;
grant execute on function public.verify_notification_key(text) to service_role;
