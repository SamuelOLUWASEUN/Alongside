-- Row-level security: makes cross-user isolation a database-enforced rule,
-- not only something the application code has to remember correctly on
-- every query. Applied to genuinely user-scoped content tables.
--
-- NOT applied to `users` itself: login and registration need to look up a
-- row by email before any authenticated user context exists at all, which
-- is fundamentally incompatible with a "you can only see your own row"
-- rule. The one sensitive column on that table (memory_summary) is already
-- separately protected via application-level AES-256-GCM encryption.
--
-- IMPORTANT GOTCHA this migration accounts for: Postgres row-level security
-- policies are silently BYPASSED for a table's owner by default. Since the
-- app's own connection role is very likely the owner (it's what ran
-- schema.sql originally), ENABLE ROW LEVEL SECURITY alone would do
-- *nothing* - every policy below is also explicitly FORCEd, which closes
-- that gap and makes the policy apply even to the owning role.
--
-- Run this ONCE against an already-running database (local or Railway):
--   Get-Content docs/migration_rls.sql | docker compose exec -T postgres psql -U innerarc -d innerarc

ALTER TABLE mood_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE mood_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY mood_entries_user_isolation ON mood_entries
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));

ALTER TABLE sleep_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY sleep_entries_user_isolation ON sleep_entries
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));

ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages FORCE ROW LEVEL SECURITY;
CREATE POLICY chat_messages_user_isolation ON chat_messages
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));

ALTER TABLE vault_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_items FORCE ROW LEVEL SECURITY;
CREATE POLICY vault_items_user_isolation ON vault_items
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));

ALTER TABLE consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE consents FORCE ROW LEVEL SECURITY;
CREATE POLICY consents_user_isolation ON consents
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));

ALTER TABLE crisis_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE crisis_alerts FORCE ROW LEVEL SECURITY;
CREATE POLICY crisis_alerts_user_isolation ON crisis_alerts
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));

    