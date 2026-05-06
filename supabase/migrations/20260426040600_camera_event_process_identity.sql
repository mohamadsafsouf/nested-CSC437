-- alter table public.camera_events
--   add column if not exists observed_app_name text,
--   add column if not exists observed_process_id integer,
--   add column if not exists observed_bundle_identifier text;

-- create index if not exists camera_events_observed_process_idx
--   on public.camera_events (observed_process_id)
--   where observed_process_id is not null;

-- notify pgrst, 'reload schema';
