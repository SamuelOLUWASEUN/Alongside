package chat

import (
	"encoding/json"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

// DeleteConversation permanently removes a whole conversation thread - every
// message in it, plus any metadata (pin state). This matters for a wellness
// app specifically: people work through hard things here, and being able to
// actually erase a conversation - not just hide it - is part of it feeling
// like a safe space rather than a permanent record. RLS guarantees the
// delete can only ever touch the requesting user's own rows.
func DeleteConversation(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	conversationID := mux.Vars(r)["id"]

	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(r.Context(),
			"DELETE FROM chat_messages WHERE conversation_id=$1 AND user_id=$2",
			conversationID, userID); err != nil {
			return err
		}
		_, err := tx.Exec(r.Context(),
			"DELETE FROM conversation_meta WHERE conversation_id=$1 AND user_id=$2",
			conversationID, userID)
		return err
	})
	if err != nil {
		http.Error(w, "Failed to delete conversation", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// PinConversation sets (or clears) the pinned flag on a conversation. The
// intended use is gentle: keep a trail back to the conversations that
// actually helped, so they're easy to return to on a harder day - not to
// keep heavy moments permanently surfaced. Upserts because most
// conversations have no metadata row until the first time they're pinned.
func PinConversation(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	conversationID := mux.Vars(r)["id"]

	var body struct {
		Pinned bool `json:"pinned"`
	}
	json.NewDecoder(r.Body).Decode(&body)

	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(), `
			INSERT INTO conversation_meta (user_id, conversation_id, pinned, updated_at)
			VALUES ($1, $2, $3, now())
			ON CONFLICT (user_id, conversation_id)
			DO UPDATE SET pinned = EXCLUDED.pinned, updated_at = now()`,
			userID, conversationID, body.Pinned)
		return err
	})
	if err != nil {
		http.Error(w, "Failed to update conversation", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}
