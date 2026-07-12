package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"
	"github.com/yourorg/innerarc-core/ai"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/chat"
	"github.com/yourorg/innerarc-core/config"
	"github.com/yourorg/innerarc-core/consent"
	"github.com/yourorg/innerarc-core/crisis"
	"github.com/yourorg/innerarc-core/db"
	"github.com/yourorg/innerarc-core/export"
	"github.com/yourorg/innerarc-core/mood"
	"github.com/yourorg/innerarc-core/redis"
	"github.com/yourorg/innerarc-core/vault"
)

// corsMiddleware only allows requests from known frontend origins, rather
// than "*" (any website). Being on an allowlist doesn't let a request read
// another user's data - every protected route still separately requires a
// valid bearer token for that specific user - this just stops arbitrary
// third-party sites from being able to call the API at all.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if config.IsAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	cfg := config.Load()
	db.Connect(cfg.DatabaseURL)
	redis.Connect(cfg.RedisURL)
	ai.Init()
	defer db.Close()
	defer redis.Close()

	r := mux.NewRouter()

	// Health check (for Docker/K8s probes and manual checks)
	r.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	}).Methods("GET")

	// Public routes
	r.Handle("/api/auth/register", auth.RateLimit(5, 15*time.Minute)(http.HandlerFunc(auth.Register))).Methods("POST")
	r.Handle("/api/auth/login", auth.RateLimit(10, 15*time.Minute)(http.HandlerFunc(auth.Login))).Methods("POST")
	r.HandleFunc("/api/auth/refresh", auth.RefreshToken).Methods("POST")
	r.HandleFunc("/api/crisis/helplines", crisis.GetHelplines).Methods("GET")

	// Protected routes
	protected := r.PathPrefix("/api").Subrouter()
	protected.Use(auth.JWTMiddleware)

	protected.HandleFunc("/auth/logout", auth.Logout).Methods("POST")

	protected.HandleFunc("/consent/grant", consent.Grant).Methods("POST")
	protected.HandleFunc("/consent/status", consent.Status).Methods("GET")
	protected.HandleFunc("/mood/log", mood.LogMood).Methods("POST")
	protected.HandleFunc("/mood/history", mood.MoodHistory).Methods("GET")
	protected.HandleFunc("/mood/streak", mood.GetStreak).Methods("GET")
	protected.HandleFunc("/sleep/log", mood.LogSleep).Methods("POST")
	protected.HandleFunc("/sleep/history", mood.SleepHistory).Methods("GET")
	protected.HandleFunc("/crisis/alert", crisis.TriggerAlert).Methods("POST")
	protected.HandleFunc("/vault", vault.GetItems).Methods("GET")
	protected.HandleFunc("/vault", vault.CreateItem).Methods("POST")
	protected.HandleFunc("/vault/{id}", vault.UpdateItem).Methods("PUT")
	protected.HandleFunc("/vault/{id}", vault.DeleteItem).Methods("DELETE")
	protected.HandleFunc("/export", export.FullExport).Methods("GET")
	protected.HandleFunc("/chat/conversations", chat.ListConversations).Methods("GET")
	protected.HandleFunc("/chat/conversations/{id}", chat.DeleteConversation).Methods("DELETE")
	protected.HandleFunc("/chat/conversations/{id}/pin", chat.PinConversation).Methods("POST")
	protected.HandleFunc("/memory/clear", chat.ClearMemory).Methods("POST")

	// WebSocket chat (token in query)
	r.HandleFunc("/ws/chat", chat.ServeWs)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Alongside Core listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, corsMiddleware(r)))
}
