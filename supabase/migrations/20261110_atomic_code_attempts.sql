-- Doğrulama kodlarında deneme hakkı tek adımda (atomik) düşülür.
--
-- Önceden Edge Function'lar deneme sayısını okuyup sonra artırıyordu; aynı anda gelen
-- istekler hepsi eski sayıyı görüp sınırı aşabiliyordu (6 haneli kod kaba kuvvetle
-- denenebilirdi). Artık her deneme önce buradan bir hak alır: hak kalmadıysa NULL döner
-- ve kod hiç karşılaştırılmaz.
--
--   p_kind: 'mfa'      -> mfa_codes.attempts               (mfa fonksiyonu)
--           'register' -> event_registration_pending.attempts (event-register › verify)
--           'cancel'   -> event_registration_cancels.attempts (event-register › cancel_verify)
--           'checkin'  -> event_staff_grants.failed_attempts  (event-checkin › erişim kodu)
--   Dönen değer: bu denemeyle birlikte kullanılan hak sayısı; NULL = hak kalmadı / kayıt yok.
create or replace function public.claim_code_attempt(p_kind text, p_id uuid, p_max integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v integer;
begin
  if p_max is null or p_max < 1 then
    raise exception 'p_max geçersiz';
  end if;
  if p_kind = 'mfa' then
    update public.mfa_codes set attempts = attempts + 1
     where id = p_id and used_at is null and attempts < p_max
     returning attempts into v;
  elsif p_kind = 'register' then
    update public.event_registration_pending set attempts = attempts + 1
     where id = p_id and attempts < p_max
     returning attempts into v;
  elsif p_kind = 'cancel' then
    update public.event_registration_cancels set attempts = attempts + 1
     where id = p_id and attempts < p_max
     returning attempts into v;
  elsif p_kind = 'checkin' then
    update public.event_staff_grants set failed_attempts = failed_attempts + 1
     where id = p_id and failed_attempts < p_max
     returning failed_attempts into v;
  else
    raise exception 'bilinmeyen tür: %', p_kind;
  end if;
  return v;
end;
$$;

-- Yalnızca Edge Function'lar (service role) çağırır.
revoke all on function public.claim_code_attempt(text, uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_code_attempt(text, uuid, integer) to service_role;
