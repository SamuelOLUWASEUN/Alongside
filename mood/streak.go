package mood

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

// GetStreak returns how many consecutive days (ending today or yesterday)
// the user has logged at least one mood check-in. A gap of a full missed
// day breaks the streak; today not being logged yet doesn't - the streak
// stays "alive" until the day actually passes without a check-in.
func GetStreak(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())

	rows, err := db.Pool.Query(r.Context(),
		`SELECT DISTINCT DATE(time) AS d FROM mood_entries
		 WHERE user_id=$1 ORDER BY d DESC LIMIT 400`, userID)
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var dates []time.Time
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err == nil {
			dates = append(dates, d)
		}
	}

	now := time.Now().UTC()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	yesterday := today.AddDate(0, 0, -1)

	streak := 0
	checkedInToday := false

	if len(dates) > 0 {
		mostRecent := dates[0]
		if mostRecent.Equal(today) {
			checkedInToday = true
		}

		var cursor time.Time
		switch {
		case mostRecent.Equal(today):
			cursor = today
		case mostRecent.Equal(yesterday):
			cursor = yesterday
		default:
			// Most recent check-in is older than yesterday - streak is broken.
			cursor = time.Time{}
		}

		if !cursor.IsZero() {
			for _, d := range dates {
				if d.Equal(cursor) {
					streak++
					cursor = cursor.AddDate(0, 0, -1)
				} else if d.Before(cursor) {
					break
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"streak":           streak,
		"checked_in_today": checkedInToday,
	})
}
