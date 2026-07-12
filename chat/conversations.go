package chat

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

type ConversationSummary struct {
	ID     string    `json:"id"`
	Title  string    `json:"title"`
	LastAt time.Time `json:"last_at"`
	Pinned bool      `json:"pinned"`
}

// ListConversations returns a summary of each conversation thread the user
// has - titled by their first message in that thread - so the sidebar can
// offer a way back into previous chats after starting a new one. Pinned
// conversations sort to the top (the ones someone chose to keep close),
// then the rest by most recently active. Pin state comes from a LEFT JOIN
// so conversations with no metadata row simply read as unpinned.
func ListConversations(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	summaries := []ConversationSummary{}
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(r.Context(), `
			SELECT m.conversation_id,
			       COALESCE((SELECT message FROM chat_messages m2
			                 WHERE m2.conversation_id = m.conversation_id AND m2.sender = 'user'
			                 ORDER BY m2.created_at ASC LIMIT 1), 'New chat') AS title,
			       MAX(m.created_at) AS last_at,
			       COALESCE(cm.pinned, FALSE) AS pinned
			FROM chat_messages m
			LEFT JOIN conversation_meta cm
			       ON cm.conversation_id = m.conversation_id AND cm.user_id = m.user_id
			WHERE m.user_id = $1
			GROUP BY m.conversation_id, cm.pinned
			ORDER BY pinned DESC, last_at DESC
			LIMIT 30`, userID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s ConversationSummary
			if err := rows.Scan(&s.ID, &s.Title, &s.LastAt, &s.Pinned); err == nil {
				if len(s.Title) > 60 {
					s.Title = s.Title[:60] + "…"
				}
				summaries = append(summaries, s)
			}
		}
		return rows.Err()
	})
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(summaries)
}
