-- Run this ONCE against an already-running database (local or Railway) that
-- predates the AI memory feature. Fresh installs don't need this -
-- docs/schema.sql already includes memory_summary from the start.
ALTER TABLE users ADD COLUMN IF NOT EXISTS memory_summary TEXT DEFAULT '';