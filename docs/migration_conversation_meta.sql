-- Adds a lightweight per-conversation metadata table. Conversations aren't
-- a real entity in this schema - they're just messages sharing a
-- conversation_id - so this is the first place custom per-conversation state
-- (right now: whether it's pinned) can actually live. Kept deliberately
-- minimal; a future `title` column here is all a rename feature would need,
-- without touching chat_messages.
--
-- Run this ONCE against an already-running database (local or Railway):
--   Get-Content docs/migration_conversation_meta.sql | docker compose exec -T postgres psql -U innerarc -d innerarc

CREATE TABLE IF NOT EXISTS conversation_meta (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL,
    pinned          BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, conversation_id)
);

-- Same row-level security pattern as every other user-scoped table: the
-- database itself enforces that a user can only ever see or change their own
-- rows, not just the application code. FORCE so it applies even to the
-- table's owning role.
ALTER TABLE conversation_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_meta FORCE ROW LEVEL SECURITY;
CREATE POLICY conversation_meta_user_isolation ON conversation_meta
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));
