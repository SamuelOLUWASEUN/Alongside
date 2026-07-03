package chat

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
	openai "github.com/sashabaranov/go-openai"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

// historyLoadLimit caps how many past messages get replayed to the client
// and used to seed the AI's conversation context on reconnect.
const historyLoadLimit = 50

func ServeWs(w http.ResponseWriter, r *http.Request) {
	tokenStr := r.URL.Query().Get("token")
	if tokenStr == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return auth.JwtSecret, nil
	})
	if err != nil || !token.Valid {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}
	claims := token.Claims.(jwt.MapClaims)
	userID := claims["sub"].(string)

	// Continue an existing thread if the client asks for one, otherwise
	// start a fresh one - this is what makes "New chat" actually mean
	// something rather than just clearing the screen locally.
	conversationID := r.URL.Query().Get("conversation")
	if conversationID == "" {
		conversationID = newConversationID()
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	client := &Client{
		hub:            ChatHub,
		conn:           conn,
		send:           make(chan []byte, 256),
		userID:         userID,
		conversationID: conversationID,
	}
	client.hub.register <- client

	session := Message{Type: "session", ConversationID: conversationID}
	if data, err := json.Marshal(session); err == nil {
		client.send <- data
	}
	client.loadHistory()

	go client.writePump()
	go client.readPump()
}

type chatRow struct {
	sender    string
	message   string
	createdAt time.Time
}

// loadHistory pulls the most recent persisted messages for this
// conversation, replays them to the client as a single "history" batch (so
// the UI can repopulate on reconnect), and seeds the in-memory AI context.
// A brand-new conversation legitimately has no rows yet, which is fine.
func (c *Client) loadHistory() {
	rows, err := db.Pool.Query(context.Background(),
		`SELECT sender, message, created_at FROM chat_messages
		 WHERE user_id=$1 AND conversation_id=$2 ORDER BY created_at DESC LIMIT $3`,
		c.userID, c.conversationID, historyLoadLimit)
	if err != nil {
		log.Printf("chat: failed to load history: %v", err)
		return
	}
	defer rows.Close()

	var descRows []chatRow
	for rows.Next() {
		var rrow chatRow
		if scanErr := rows.Scan(&rrow.sender, &rrow.message, &rrow.createdAt); scanErr == nil {
			descRows = append(descRows, rrow)
		}
	}
	if len(descRows) == 0 {
		return
	}

	// Rows came back newest-first; replay oldest-first for both the UI
	// batch and the AI context.
	messages := make([]Message, 0, len(descRows))
	for i := len(descRows) - 1; i >= 0; i-- {
		rrow := descRows[i]
		switch rrow.sender {
		case "user":
			messages = append(messages, Message{Type: "user_message", Text: rrow.message, Timestamp: rrow.createdAt.Unix()})
			c.appendHistory(openai.ChatMessageRoleUser, rrow.message)
		case "ai":
			messages = append(messages, Message{Type: "ai_response", Text: rrow.message, Timestamp: rrow.createdAt.Unix()})
			c.appendHistory(openai.ChatMessageRoleAssistant, rrow.message)
		case "system":
			messages = append(messages, Message{Type: "crisis_alert", Text: rrow.message, Timestamp: rrow.createdAt.Unix()})
			// Crisis alerts aren't fed back into the AI's context - they're
			// deterministic safety-net messages, not conversation turns.
		}
	}

	batch := HistoryBatch{Type: "history", Messages: messages}
	if data, err := json.Marshal(batch); err == nil {
		c.send <- data
	}
}
