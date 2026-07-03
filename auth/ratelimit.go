package auth

import (
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/yourorg/innerarc-core/redis"
)

// RateLimit blocks more than `limit` requests from the same client IP to
// the same path within `window`. Used on login/register to blunt
// brute-force and spam-signup attempts without needing a full WAF.
func RateLimit(limit int, window time.Duration) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := fmt.Sprintf("ratelimit:%s:%s", r.URL.Path, clientIP(r))
			count, err := redis.Client.Incr(r.Context(), key).Result()
			if err == nil && count == 1 {
				redis.Client.Expire(r.Context(), key, window)
			}
			if err == nil && count > int64(limit) {
				w.Header().Set("Retry-After", strconv.Itoa(int(window.Seconds())))
				http.Error(w, "Too many attempts - please try again shortly", http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// clientIP prefers X-Forwarded-For since Railway (and most hosting
// platforms) sit behind a proxy - RemoteAddr alone would just be the
// proxy's own address, not the actual visitor's.
func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if idx := strings.Index(fwd, ","); idx != -1 {
			return strings.TrimSpace(fwd[:idx])
		}
		return strings.TrimSpace(fwd)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

