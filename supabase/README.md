# supabase/

| Path | What it is |
| --- | --- |
| `schema.sql` | Snapshot of the live database: tables, constraints, indexes, functions, triggers, RLS policies, privileges and storage buckets. Regenerated from production; read it to see how the database looks today. Not meant to be run. |
| `migrations/` | Changes applied to production, one file per change, named `YYYYMMDD_description.sql`. |
| `functions/` | Edge Function source: `club-account` (admin-only club account management) and `send-email-notifications`. |

When the database changes: add a file to `migrations/`, apply it, then regenerate `schema.sql`.
Secrets (Vault, Resend key, service role key) are never stored here.
