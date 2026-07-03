package export

import (
	"encoding/json"
	"net/http"
	"time"

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

	var export struct {
		UserID string     `json:"user_id"`
		Moods  []moodRow  `json:"moods"`
		Sleep  []sleepRow `json:"sleep"`
	}
	export.UserID = userID

	moodRows, err := db.Pool.Query(r.Context(), "SELECT time, mood_score, note FROM mood_entries WHERE user_id=$1 ORDER BY time DESC", userID)
	if err == nil {
		defer moodRows.Close()
		for moodRows.Next() {
			var m moodRow
			if moodRows.Scan(&m.Time, &m.Score, &m.Note) == nil {
				export.Moods = append(export.Moods, m)
			}
		}
	}

	sleepRows, err := db.Pool.Query(r.Context(), "SELECT time, hours, quality FROM sleep_entries WHERE user_id=$1 ORDER BY time DESC", userID)
	if err == nil {
		defer sleepRows.Close()
		for sleepRows.Next() {
			var s sleepRow
			if sleepRows.Scan(&s.Time, &s.Hours, &s.Quality) == nil {
				export.Sleep = append(export.Sleep, s)
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(export)
}
