package chat

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
	openai "github.com/sashabaranov/go-openai"
	"github.com/yourorg/innerarc-core/ai"
	"github.com/yourorg/innerarc-core/config"
	"github.com/yourorg/innerarc-core/db"
	"github.com/yourorg/innerarc-core/safety"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 2048
	// maxHistoryLen bounds how much conversation context gets sent to the
	// AI provider per request, to keep token usage and latency in check.
	maxHistoryLen = 20
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return config.IsAllowedOrigin(r.Header.Get("Origin"))
	},
}

type Message struct {
	Type           string `json:"type"` // user_message, ai_response, crisis_alert, history, session
	Text           string `json:"text,omitempty"`
	Timestamp      int64  `json:"timestamp,omitempty"`
	ConversationID string `json:"conversation_id,omitempty"`
}

// HistoryBatch is sent once, right after connecting, so the client can
// repopulate the chat view from persisted history.
type HistoryBatch struct {
	Type     string    `json:"type"` // always "history"
	Messages []Message `json:"messages"`
}

type Client struct {
	hub    *Hub
	conn   *websocket.Conn
	send   chan []byte
	userID string
	// conversationID scopes persistence and history loading to a single
	// thread. A fresh one is minted per connection unless the client asks
	// to continue an existing one via ?conversation=<id>.
	conversationID string
	// history is the bounded in-memory conversation window passed to the AI
	// provider on each turn. Seeded from persisted chat_messages on connect.
	history []openai.ChatCompletionMessage
	// userContext is built once per connection (mood/sleep trend + the
	// cross-conversation memory summary) rather than re-queried on every
	// message, since it only needs to be roughly fresh for a session.
	userContext string
	// newMessagesThisSession counts genuine new exchanges (not messages
	// replayed from history on connect), so memory only gets updated when
	// something actually new was discussed.
	newMessagesThisSession int
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
		// Update the cross-conversation memory summary in the background so
		// closing the connection isn't held up waiting on an extra LLM call.
		if c.newMessagesThisSession > 0 {
			go c.updateMemory()
		}
	}()
	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, msgBytes, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("chat read error: %v", err)
			}
			break
		}
		var incoming Message
		if err := json.Unmarshal(msgBytes, &incoming); err != nil {
			continue
		}

		c.saveMessage("user", incoming.Text, time.Now())
		c.appendHistory(openai.ChatMessageRoleUser, incoming.Text)
		c.newMessagesThisSession++

		if safety.ContainsCrisisKeywords(incoming.Text) {
			alertText := safety.GetCrisisResponse()
			c.saveMessage("system", alertText, time.Now())
			alert := Message{Type: "crisis_alert", Text: alertText, Timestamp: time.Now().Unix()}
			if resp, err := json.Marshal(alert); err == nil {
				c.send <- resp
			}
		}

		aiText := ai.GenerateReply(c.history, c.userContext)
		c.appendHistory(openai.ChatMessageRoleAssistant, aiText)
		aiTime := time.Now()
		c.saveMessage("ai", aiText, aiTime)

		response := Message{Type: "ai_response", Text: aiText, Timestamp: aiTime.Unix()}
		if respBytes, err := json.Marshal(response); err == nil {
			c.send <- respBytes
		}
	}
}

// saveMessage persists a chat turn. Uses context.Background() rather than
// the original HTTP request's context, since this runs in a long-lived
// goroutine that outlives the request that opened the WebSocket.
func (c *Client) saveMessage(sender, text string, at time.Time) {
	_, err := db.Pool.Exec(context.Background(),
		"INSERT INTO chat_messages (user_id, conversation_id, sender, message, created_at) VALUES ($1, $2, $3, $4, $5)",
		c.userID, c.conversationID, sender, text, at)
	if err != nil {
		log.Printf("chat: failed to persist message: %v", err)
	}
}

func (c *Client) appendHistory(role, content string) {
	c.history = append(c.history, openai.ChatCompletionMessage{Role: role, Content: content})
	if len(c.history) > maxHistoryLen {
		c.history = c.history[len(c.history)-maxHistoryLen:]
	}
}

// updateMemory asks the AI to fold this session into an updated
// cross-conversation memory summary, then persists it. Runs in its own
// goroutine after the connection has already closed, using
// context.Background() since the original request context is gone by then.
func (c *Client) updateMemory() {
	ctx := context.Background()
	existing := loadMemorySummary(ctx, c.userID)
	updated := ai.SummarizeForMemory(existing, c.history)
	if updated == "" || updated == existing {
		return
	}
	encrypted, err := encryptMemory(updated)
	if err != nil {
		log.Printf("chat: failed to encrypt memory summary, not saving: %v", err)
		return
	}
	_, err = db.Pool.Exec(ctx, `UPDATE users SET memory_summary=$1 WHERE id=$2`, encrypted, c.userID)
	if err != nil {
		log.Printf("chat: failed to update memory summary: %v", err)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

