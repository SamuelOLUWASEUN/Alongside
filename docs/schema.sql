-- Enable TimescaleDB if it's available. Not every Postgres host has this
-- extension (e.g. Railway's default "Database" template is plain Postgres),
-- so this degrades gracefully to regular tables instead of failing the
-- whole schema. Locally, docker-compose runs the timescale/timescaledb
-- image, so this succeeds and mood_entries/sleep_entries below become real
-- hypertables.
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS timescaledb;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TimescaleDB extension not available - continuing with plain Postgres tables';
END $$;

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    -- Running cross-conversation memory summary, updated by the AI after
    -- each chat session so it has continuity across separate threads
    -- without needing to replay full transcripts.
    memory_summary TEXT DEFAULT ''
);

-- Refresh tokens (for blacklisting)
CREATE TABLE refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN DEFAULT FALSE
);

-- Consent records
CREATE TABLE consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,  -- 'mood_tracking', 'ai_journal', 'data_sharing'
    granted BOOLEAN NOT NULL,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Mood entries (hypertable when TimescaleDB is available)
CREATE TABLE mood_entries (
    time TIMESTAMPTZ NOT NULL,
    user_id UUID NOT NULL,
    mood_score INT CHECK (mood_score BETWEEN 1 AND 10),
    note TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable('mood_entries', 'time', if_not_exists => TRUE);
    END IF;
END $$;

-- Sleep entries (hypertable when TimescaleDB is available)
CREATE TABLE sleep_entries (
    time TIMESTAMPTZ NOT NULL,
    user_id UUID NOT NULL,
    hours DECIMAL(4,2) CHECK (hours BETWEEN 0 AND 24),
    quality INT CHECK (quality BETWEEN 1 AND 5),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable('sleep_entries', 'time', if_not_exists => TRUE);
    END IF;
END $$;

-- Crisis alert logs
CREATE TABLE crisis_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    message TEXT,
    helpline_shown BOOLEAN DEFAULT TRUE,
    email_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Vault items (server stores encrypted data only)
CREATE TABLE vault_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    label TEXT,
    encrypted_data TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Chat history (persisted so the AI coach has memory and the app can
-- replay the conversation on reconnect). conversation_id groups messages
-- into separate threads - a new one is minted whenever the client starts
-- a fresh chat rather than continuing an existing one.
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL DEFAULT gen_random_uuid(),
    sender VARCHAR(50) NOT NULL,  -- 'user', 'ai', or 'system' (crisis alerts)
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_chat_messages_user_created ON chat_messages (user_id, created_at DESC);
CREATE INDEX idx_chat_messages_conversation ON chat_messages (conversation_id, created_at);

-- Row-level security: makes cross-user isolation a database-enforced rule,
-- not only something application code has to remember on every query. Not
-- applied to `users` itself - see docs/migration_rls.sql for why, and for
-- the FORCE ROW LEVEL SECURITY gotcha this depends on.
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

-- Per-conversation metadata (currently just pin state). Conversations are
-- otherwise just messages sharing a conversation_id; this is the one place
-- custom per-conversation state lives. See docs/migration_conversation_meta.sql.
CREATE TABLE conversation_meta (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL,
    pinned          BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, conversation_id)
);
ALTER TABLE conversation_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_meta FORCE ROW LEVEL SECURITY;
CREATE POLICY conversation_meta_user_isolation ON conversation_meta
    USING (user_id::text = current_setting('app.current_user_id', true))
    WITH CHECK (user_id::text = current_setting('app.current_user_id', true));
