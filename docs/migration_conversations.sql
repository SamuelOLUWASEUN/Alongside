-- Run this ONCE against an already-running database that predates
-- conversation support (i.e. you ran the original docs/schema.sql before
-- this migration existed). Fresh installs don't need this - docs/schema.sql
-- already includes conversation_id from the start.
--
-- Groups all pre-existing chat_messages under one shared "legacy"
-- conversation so nothing is lost, then sets up the column properly going
-- forward.
--
-- How to run (same way you ran docs/schema.sql originally):
--   docker compose exec -T postgres psql -U innerarc -d innerarc < docs/migration_conversations.sql

DO $$
DECLARE legacy_id UUID := gen_random_uuid();
BEGIN
  ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS conversation_id UUID;
  UPDATE chat_messages SET conversation_id = legacy_id WHERE conversation_id IS NULL;
  ALTER TABLE chat_messages ALTER COLUMN conversation_id SET NOT NULL;
  ALTER TABLE chat_messages ALTER COLUMN conversation_id SET DEFAULT gen_random_uuid();
END $$;

CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation ON chat_messages (conversation_id, created_at);
