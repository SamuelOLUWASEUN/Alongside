package mood

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

type MoodLog struct {
	Score int    `json:"score"`
	Note  string `json:"note,omitempty"`
}

type SleepLog struct {
	Hours   float64 `json:"hours"`
	Quality int     `json:"quality"`
}

func LogMood(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var e MoodLog
	json.NewDecoder(r.Body).Decode(&e)
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(),
			"INSERT INTO mood_entries (time, user_id, mood_score, note) VALUES ($1, $2, $3, $4)",
			time.Now(), userID, e.Score, e.Note)
		return err
	})
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func MoodHistory(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	days := r.URL.Query().Get("days")
	if days == "" {
		days = "7"
	}
	var entries []map[string]interface{}
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(r.Context(),
			`SELECT time, mood_score, note FROM mood_entries
			 WHERE user_id=$1 AND time > now() - interval '1 day' * $2::int
			 ORDER BY time DESC`, userID, days)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var t time.Time
			var s int
			var n *string
			if err := rows.Scan(&t, &s, &n); err != nil {
				return err
			}
			entries = append(entries, map[string]interface{}{"time": t, "score": s, "note": n})
		}
		return rows.Err()
	})
	if err != nil {
		http.Error(w, "DB error", 500)
		return
	}
	json.NewEncoder(w).Encode(entries)
}

func LogSleep(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var e SleepLog
	json.NewDecoder(r.Body).Decode(&e)
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(),
			"INSERT INTO sleep_entries (time, user_id, hours, quality) VALUES ($1, $2, $3, $4)",
			time.Now(), userID, e.Hours, e.Quality)
		return err
	})
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func SleepHistory(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	days := r.URL.Query().Get("days")
	if days == "" {
		days = "7"
	}
	var entries []map[string]interface{}
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(r.Context(),
			`SELECT time, hours, quality FROM sleep_entries
			 WHERE user_id=$1 AND time > now() - interval '1 day' * $2::int
			 ORDER BY time DESC`, userID, days)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var t time.Time
			var h float64
			var q int
			if err := rows.Scan(&t, &h, &q); err != nil {
				return err
			}
			entries = append(entries, map[string]interface{}{"time": t, "hours": h, "quality": q})
		}
		return rows.Err()
	})
	if err != nil {
		http.Error(w, "DB error", 500)
		return
	}
	json.NewEncoder(w).Encode(entries)
}

