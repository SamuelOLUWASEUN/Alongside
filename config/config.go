package config

import (
	"os"
	"strings"
)

type Config struct {
	DatabaseURL string
	RedisURL    string
	JWTSecret   string
}

func Load() *Config {
	return &Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		RedisURL:    os.Getenv("REDIS_URL"),
		JWTSecret:   os.Getenv("JWT_SECRET"),
	}
}

// AllowedOrigins lists exact production origins allowed to call the API or
// open a chat WebSocket. Add more here (or via the ALLOWED_ORIGINS env var,
// comma-separated) if you add a custom domain or rename the Netlify site
// again. Shared by both the HTTP CORS middleware and the WebSocket
// upgrader's origin check, so there's one allowlist, not two to keep in sync.
func AllowedOrigins() []string {
	origins := []string{"https://alongsides.netlify.app"}
	if extra := os.Getenv("ALLOWED_ORIGINS"); extra != "" {
		for _, o := range strings.Split(extra, ",") {
			if trimmed := strings.TrimSpace(o); trimmed != "" {
				origins = append(origins, trimmed)
			}
		}
	}
	return origins
}

// IsAllowedOrigin checks a request's Origin header against AllowedOrigins,
// plus any localhost/127.0.0.1 origin (dev servers use random ports, so
// allow any port from those two hosts rather than needing updates every run).
func IsAllowedOrigin(origin string) bool {
	if origin == "" {
		return false
	}
	if strings.HasPrefix(origin, "http://localhost:") || strings.HasPrefix(origin, "http://127.0.0.1:") {
		return true
	}
	for _, o := range AllowedOrigins() {
		if origin == o {
			return true
		}
	}
	return false
}

