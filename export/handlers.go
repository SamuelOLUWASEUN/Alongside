package export

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

type moodRow struct {
	Time  time.Time `json:"time"`
	Score int       `json:"score"`
	Note  *string   `json:"note"`
}

type sleepRow struct {
	Time    time.Time `json:"time"`
	Hours   float64   `json:"hours"`
	Quality int       `json:"quality"`
}

// FullExport returns a GDPR-style data export of everything the platform
// holds about the requesting user (mood logs, sleep logs). Extend this with
// consents, vault metadata, and chat history as those features mature.
func FullExport(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())

	var result struct {
		UserID string     `json:"user_id"`
		Moods  []moodRow  `json:"moods"`
		Sleep  []sleepRow `json:"sleep"`
	}
	result.UserID = userID

	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		moodRows, err := tx.Query(r.Context(), "SELECT time, mood_score, note FROM mood_entries WHERE user_id=$1 ORDER BY time DESC", userID)
		if err == nil {
			defer moodRows.Close()
			for moodRows.Next() {
				var m moodRow
				if moodRows.Scan(&m.Time, &m.Score, &m.Note) == nil {
					result.Moods = append(result.Moods, m)
				}
			}
		}

		sleepRows, err := tx.Query(r.Context(), "SELECT time, hours, quality FROM sleep_entries WHERE user_id=$1 ORDER BY time DESC", userID)
		if err == nil {
			defer sleepRows.Close()
			for sleepRows.Next() {
				var s sleepRow
				if sleepRows.Scan(&s.Time, &s.Hours, &s.Quality) == nil {
					result.Sleep = append(result.Sleep, s)
				}
			}
		}
		return nil
	})
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

