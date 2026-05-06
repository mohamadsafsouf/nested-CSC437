-- alter table public.protection_actions
--   drop constraint if exists protection_actions_action_check;

-- alter table public.protection_actions
--   add constraint protection_actions_action_check check (
--     action in (
--       'none',
--       'warnOnly',
--       'closeBrowserTab',
--       'terminateProcess',
--       'requestManualReview',
--       'openPrivacySettings'
--     )
--   );

-- notify pgrst, 'reload schema';
