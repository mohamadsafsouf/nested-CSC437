-- alter table public.camera_events
--   add column if not exists observed_website_url text,
--   add column if not exists observed_website_host text,
--   add column if not exists source_key text;

-- create index if not exists camera_events_source_context_idx
--   on public.camera_events (user_id, source_key, occurred_at desc)
--   where source_key is not null;

-- create index if not exists camera_events_website_host_idx
--   on public.camera_events (user_id, observed_website_host, occurred_at desc)
--   where observed_website_host is not null;

-- notify pgrst, 'reload schema';
