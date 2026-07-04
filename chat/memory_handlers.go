package chat

import (
	"net/http"

	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)


// ClearMemory lets a user erase their AI memory summary on demand. Being
// upfront that this feature exists means it should be just as easy to turn
// off as it was to never notice - not something buried or hard to undo.
//
// Uses db.Pool directly rather than db.RunAsUser: `users` isn't RLS-
// protected (see docs/migration_rls.sql for why), and this query is already
// scoped by the exact primary key, not a broader user-owned row range.
func ClearMemory(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	_, err := db.Pool.Exec(r.Context(), `UPDATE users SET memory_summary='' WHERE id=$1`, userID)
	if err != nil {
		http.Error(w, "Failed to clear memory", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}

