# supabase/

| Path | What it is |
| --- | --- |
| `schema.sql` | Snapshot of the live database: tables, constraints, indexes, functions, triggers, RLS policies, privileges and storage buckets. Regenerated from production; read it to see how the database looks today. Not meant to be run. Currently predates `20261011` and later; regenerate it. |
| `migrations/` | Changes applied to production, one file per change, named `YYYYMMDD_description.sql`. |
| `functions/` | Edge Function source: `club-account` (admin-only club account management), `send-email-notifications` and `send-club-kvkk-notice`. |

When the database changes: add a file to `migrations/`, apply it, then regenerate `schema.sql`.
Secrets (Vault, Resend key, service role key) are never stored here.

## Functions the public site calls (anon)

| Function | Used by |
| --- | --- |
| `public_events()` | Events calendar on the site |
| `public_clubs()` | Club list on the site. Contact columns are `NULL` unless the club has `kvkk_consent_at`. Visitors cannot read `clubs` directly. |
| `submit_contact_message(p_name, p_email, p_message, p_honey, p_kvkk_version)` | Contact form |
| `submit_join_application(p_name, p_email, p_university, p_city, p_outside_university, p_club, p_message, p_honey, p_kvkk_version)` | Bize Katıl form |

Every other SECURITY DEFINER function is for signed-in users only. If you add a new
anon-callable SECURITY DEFINER function, also add it to the exclusion list in
`migrations/20261010_harden_function_grants.sql`, or re-running that file revokes anon from it.

The `unipakt-retention` pg_cron job (from `20261013_audit_fixes.sql`) deletes site form
records after 12 months and read, resolved notifications after 6 months.
