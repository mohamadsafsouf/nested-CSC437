# CamGuard Shared Contracts

These files define the Phase 1 contract that every CamGuard app should map to before writing platform-specific code.

## Files

- `camera-security-event.schema.json` - metadata-only event payload for macOS, iPhone, API/scoring, Supabase mapping, and dashboard display.
- `threat-levels.json` - shared threat classification thresholds and alert rules.

## Rules

- Use `schema_version` to handle future contract changes explicitly.
- Use snake_case fields because the data layer is Supabase/Postgres-oriented.
- Do not send camera images, video, audio, screenshots, or file paths to private media.
- Remote endpoint IP, hostname, ASN, organization, coarse location, and reputation fields are for defensive correlation only.
- Treat client-provided scoring as provisional. Backend scoring is authoritative.
- On iOS, only report CamGuard's own permission status and in-app camera usage. iOS cannot monitor camera usage by other apps.
- Simulated suspicious activity must set `risk_context.is_simulated` to `true` and include a clear `simulation_label`.
- Never use CamGuard for counter-attacks. Defensive actions are limited to alerts, evidence logging, trust changes, and user-approved blocking/guidance.

## Mapping Guidance

- Swift models should use clear native names, then encode to this contract at the sync boundary.
- Supabase tables should stay normalized; do not copy the full JSON object into one event table unless a future audit-log column is intentionally added.
- Dashboard UI should read threat status from stored scores and style it with shared theme tokens.
