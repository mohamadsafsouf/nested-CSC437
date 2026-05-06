-- create table if not exists public.protection_actions (
--   id uuid primary key default gen_random_uuid(),
--   user_id uuid not null references public.users(id) on delete cascade,
--   device_id uuid references public.devices(id) on delete set null,
--   camera_event_id uuid references public.camera_events(id) on delete set null,
--   client_event_id uuid,
--   app_name text not null,
--   process_id integer,
--   action text not null,
--   result text not null,
--   confidence text not null,
--   report_path text,
--   occurred_at timestamptz not null,
--   created_at timestamptz not null default now(),
--   constraint protection_actions_action_check check (
--     action in ('none', 'warnOnly', 'terminateProcess', 'requestManualReview', 'openPrivacySettings')
--   ),
--   constraint protection_actions_confidence_check check (
--     confidence in ('confirmed', 'likely', 'uncertain')
--   )
-- );

-- create index if not exists protection_actions_user_created_idx
--   on public.protection_actions (user_id, created_at desc);

-- create index if not exists protection_actions_camera_event_idx
--   on public.protection_actions (camera_event_id);

-- alter table public.protection_actions enable row level security;

-- create policy protection_actions_select_own on public.protection_actions
--   for select using (auth.uid() = user_id);
