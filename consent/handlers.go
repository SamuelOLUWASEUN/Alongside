package consent

import (
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

type ConsentRequest struct {
	Type    string `json:"type"` // mood_tracking, ai_journal
	Granted bool   `json:"granted"`
}

func Grant(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var req ConsentRequest
	json.NewDecoder(r.Body).Decode(&req)
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(),
			`INSERT INTO consents (user_id, type, granted, ip_address, user_agent)
			 VALUES ($1, $2, $3, $4, $5)`,
			userID, req.Type, req.Granted, r.RemoteAddr, r.UserAgent())
		return err
	})
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func Status(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var result []map[string]interface{}
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(r.Context(),
			`SELECT type, granted, created_at FROM consents
			 WHERE user_id=$1 ORDER BY created_at DESC`, userID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var t string
			var g bool
			var ts interface{}
			if err := rows.Scan(&t, &g, &ts); err != nil {
				return err
			}
			result = append(result, map[string]interface{}{"type": t, "granted": g, "timestamp": ts})
		}
		return rows.Err()
	})
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(result)
}

