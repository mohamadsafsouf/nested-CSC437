# CamGuard Supabase Data Layer

This folder contains the local source of truth for the Supabase/Postgres schema.

## Files

- `migrations/20260426014600_initial_normalized_schema.sql` - initial normalized CamGuard schema, lookup seeds, indexes, triggers, and RLS policies.

## Environment

Local Supabase connection values live in `.env`.

- Public URL and publishable key may be used by dashboard code with RLS enabled.
- `SUPABASE_SECRET_KEY` is server-only and must never be used in Swift apps or browser bundles.
- Do not copy actual key values into documentation, logs, screenshots, or committed code.

## Applying Migrations

Use the Supabase CLI or dashboard SQL editor after reviewing the SQL:

```sh
supabase db push
```

If the project is not linked locally yet, link it first with the Supabase CLI using your project reference. Keep credentials in local environment variables or Supabase's secure auth flow.

## Schema Principles

- Keep event tables metadata-only and append-oriented.
- Store repeated values in lookup tables.
- Store TCB-AD learned means and covariance values in normalized profile tables.
- Store remote endpoint IP/location/reputation as defensive metadata only; it describes the contacted endpoint, not the user's exact location.
- Keep RLS enabled on user-owned data.
- Update `databaseSchema/inventory.md` whenever tables or important columns change.
