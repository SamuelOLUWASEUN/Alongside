# Alongside — Empathic Core (Phase 1 MVP)

A mobile-first AI wellness companion: onboarding & consent, AI coach chat
(CBT/ACT-flavored), mood & sleep check-ins, a crisis safety switch, and an
end-to-end encrypted personal vault.

- **Backend**: Go (Gorilla Mux + WebSocket), PostgreSQL/TimescaleDB, Redis,
  JWT auth.
- **Frontend**: Flutter scaffold (chat, mood logging, settings, onboarding).

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Compose)
- [Go 1.22+](https://go.dev/dl/) (only needed if you want to build outside Docker)
- [Flutter SDK 3.0+](https://docs.flutter.dev/get-started/install) (for the mobile app)
- VS Code, ideally with the Flutter and Docker extensions

On Windows, run everything from WSL2 (Ubuntu) — the tooling here is Unix-first.

## 1. (Optional) Enable real AI responses

Copy `.env.example` to `.env` and add an OpenAI API key if you want live
model responses instead of the built-in rule-based fallback:

```bash
cp .env.example .env
# then edit .env and set OPENAI_API_KEY
```

`docker compose` reads `.env` automatically. Skip this step entirely if you
just want to run locally without a key — the AI coach falls back to a
deterministic rule-based responder.

## 2. Start the backend

```bash
cd innerarc-core
docker compose up --build
```

This starts PostgreSQL (with TimescaleDB), Redis, MailHog (fake SMTP inbox
for crisis-alert emails, UI at http://localhost:8025), and the Go API on
`:8080`.

## 3. Apply the database schema

In a second terminal:

```bash
docker compose exec -T postgres psql -U innerarc -d innerarc < docs/schema.sql
```

If you're updating an existing database rather than starting fresh (i.e. you
already ran `schema.sql` before), also run any files in `docs/migrations_*`
or `docs/migration_*.sql` that have appeared since - e.g.:

```bash
docker compose exec -T postgres psql -U innerarc -d innerarc < docs/migration_conversations.sql
```

Verify the backend is up: `curl http://localhost:8080/healthz` → `ok`.

## 4. Try the API

```bash
# Register
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"secret123"}'

# Login (grab access_token from the response)
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"secret123"}'

# Authenticated call
curl http://localhost:8080/api/mood/history?days=7 \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

WebSocket chat (needs `websocat` or similar):

```bash
websocat "ws://localhost:8080/ws/chat?token=YOUR_ACCESS_TOKEN"
> {"type":"user_message","text":"I feel anxious today"}
```

Reconnecting with the same token replays your last 50 messages as a single
`history` batch before any new messages come through.

## 5. Run the Flutter app

```bash
cd innerarc-core/frontend
flutter pub get
flutter run
```

- Android emulator → backend already points at `10.0.2.2:8080` in
  `lib/services/api_service.dart`.
- iOS simulator → change `10.0.2.2` to `localhost`.
- Physical device → change it to your PC's LAN IP.

## What's implemented vs. stubbed

| Feature | Status |
|---|---|
| Auth (register/login/refresh, JWT) | Working |
| Consent logging | Working |
| Mood & sleep log + history API | Working |
| AI chat over WebSocket | Working, and now calls a real LLM (OpenAI-compatible, via `ai/agent.go`) when `OPENAI_API_KEY` is set — falls back to a rule-based responder otherwise. Chat history is persisted in Postgres (`chat_messages`) and replayed on reconnect. Flutter side has full chat bubbles with timestamps, a "thinking" indicator while waiting on a reply, smart auto-scroll, and a crisis overlay. |
| Crisis keyword detection + helpline + email alert | Working (email needs real SMTP creds in production; MailHog catches it locally). Flutter shows a modal crisis overlay on trigger. |
| Vault (encrypted storage) | Working end-to-end: Flutter encrypts with AES-256-GCM (key derived via PBKDF2 from a passphrase, using `Random.secure()` for salts/IVs) before sending; server only ever stores ciphertext. See `docs/e2e-encryption.md`. Passphrase is re-entered per session for now — pair with biometric unlock for a smoother flow. |
| Data export | Working (mood + sleep; extend for consents/vault/chat history) |
| Flutter onboarding/chat/mood/vault/settings screens | Functional. Biometric app-lock is still stubbed (`// TODO` marker in settings) |

## Known things to fix before shipping

- `auth.JwtSecret` is a hardcoded placeholder — move it to an env var /
  secrets manager (Vault, AWS KMS, etc.) before any real deployment.
- No TLS termination here — put this behind a load balancer/ingress with
  TLS in production.
- `go-openai` talks to OpenAI's API specifically. If you want Claude instead,
  point it at an OpenAI-compatible proxy or swap in Anthropic's own SDK —
  this repo doesn't call Anthropic's API directly.
- The crisis keyword filter in `safety/filter.go` is a deterministic,
  independent safety net that runs regardless of which AI provider (or the
  fallback) is generating replies — keep it active even if you swap models.
- CORS / WebSocket `CheckOrigin` currently allows all origins — tighten
  before going live.
- Per-connection AI context is capped at the last 20 turns
  (`maxHistoryLen` in `chat/client.go`) to bound token usage/latency; raise
  or lower it as needed.

## Project layout

```
innerarc-core/
├── main.go, go.mod              # Go backend entrypoint
├── auth/ consent/ mood/ chat/   # feature packages
├── crisis/ vault/ export/ ai/ safety/
├── db/ redis/ config/           # infra glue
├── docs/                        # schema.sql, encryption + AI prompt docs
├── .env.example                 # copy to .env to set OPENAI_API_KEY
├── Dockerfile, docker-compose.yml
└── frontend/                    # Flutter app
    └── lib/{screens,services,models}
```
