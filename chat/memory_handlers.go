package chat

import (
	"net/http"

	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

// ClearMemory lets a user erase their AI memory summary on demand. Being
// upfront that this feature exists means it should be just as easy to turn
// off as it was to never notice - not something buried or hard to undo.
func ClearMemory(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	_, err := db.Pool.Exec(r.Context(), `UPDATE users SET memory_summary='' WHERE id=$1`, userID)
	if err != nil {
		http.Error(w, "Failed to clear memory", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}

