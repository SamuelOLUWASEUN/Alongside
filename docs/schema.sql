-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
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

-- Mood entries (hypertable for TimescaleDB)
CREATE TABLE mood_entries (
    time TIMESTAMPTZ NOT NULL,
    user_id UUID NOT NULL,
    mood_score INT CHECK (mood_score BETWEEN 1 AND 10),
    note TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
SELECT create_hypertable('mood_entries', 'time');

-- Sleep entries (hypertable)
CREATE TABLE sleep_entries (
    time TIMESTAMPTZ NOT NULL,
    user_id UUID NOT NULL,
    hours DECIMAL(4,2) CHECK (hours BETWEEN 0 AND 24),
    quality INT CHECK (quality BETWEEN 1 AND 5),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
SELECT create_hypertable('sleep_entries', 'time');

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
