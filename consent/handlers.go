package consent

import (
	"encoding/json"
	"net/http"

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
	_, err := db.Pool.Exec(r.Context(),
		`INSERT INTO consents (user_id, type, granted, ip_address, user_agent)
		 VALUES ($1, $2, $3, $4, $5)`,
		userID, req.Type, req.Granted, r.RemoteAddr, r.UserAgent())
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func Status(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	rows, err := db.Pool.Query(r.Context(),
		`SELECT type, granted, created_at FROM consents
		 WHERE user_id=$1 ORDER BY created_at DESC`, userID)
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	var result []map[string]interface{}
	for rows.Next() {
		var t string
		var g bool
		var ts interface{}
		rows.Scan(&t, &g, &ts)
		result = append(result, map[string]interface{}{"type": t, "granted": g, "timestamp": ts})
	}
	json.NewEncoder(w).Encode(result)
}
