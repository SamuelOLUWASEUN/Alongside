package chat

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
	openai "github.com/sashabaranov/go-openai"
	"github.com/yourorg/innerarc-core/ai"
	"github.com/yourorg/innerarc-core/config"
	"github.com/yourorg/innerarc-core/db"
	"github.com/yourorg/innerarc-core/safety"
)

const (
	writeWait = 10 * time.Second
	// Backgrounded mobile connections often die silently (OS drops the
	// socket with no close handshake) - the server only notices via this
	// ping/pong timeout, so keeping it short means a dead connection gets
	// cleaned up in ~20s instead of lingering up to a minute or more.
	pongWait       = 20 * time.Second
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
	// crisisExempt becomes permanently true for the rest of this session
	// the first time a crisis keyword fires, so the daily message cap can
	// never cut someone off mid-disclosure just because a later message in
	// the same hard conversation didn't happen to contain a trigger word.
	crisisExempt bool
	// historyMu guards history, which is now appended to from both the read
	// loop (user messages) and the per-turn AI goroutines (assistant
	// replies), so the two can't race on the same slice.
	historyMu sync.Mutex
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
			c.crisisExempt = true
			alertText := safety.GetCrisisResponse()
			c.saveMessage("system", alertText, time.Now())
			alert := Message{Type: "crisis_alert", Text: alertText, Timestamp: time.Now().Unix()}
			if resp, err := json.Marshal(alert); err == nil {
				c.send <- resp
			}
		}

		if !c.checkDailyLimit(context.Background()) {
			limitMsg := Message{Type: "limit_reached", Text: limitReachedMessage, Timestamp: time.Now().Unix()}
			if resp, err := json.Marshal(limitMsg); err == nil {
				c.send <- resp
			}
			continue
		}

		// Generate the AI reply in its own goroutine so this read loop is
		// never blocked waiting on Groq. If the AI call ran inline here (as
		// it used to), the loop couldn't read a second message the person
		// sent while the first reply was still generating - that stalled
		// message then collided with the client's stale-connection timeout,
		// which is what caused both the "loads previous chats" history
		// replay and the "connection needed a refresh" errors. A locked
		// snapshot of history is passed in so the goroutine reads a stable
		// copy rather than racing with appendHistory on the next turn.
		go c.generateAndSend(c.historyCopy())
	}
}

// generateAndSend runs one AI turn off the read loop. It appends the reply
// to shared history and pushes it to the write pump via the buffered send
// channel. Because Groq processes a given connection's requests in the
// order they're sent and this uses the same ordered send channel, replies
// still arrive in order for normal back-and-forth; the point of the
// goroutine is purely to keep the read loop free, not to parallelize a
// single person's turns.
func (c *Client) generateAndSend(history []openai.ChatCompletionMessage) {
	defer func() {
		// A panic in the AI path (nil deref, etc.) must never take down the
		// whole server - recover, log, and let the person keep chatting.
		if r := recover(); r != nil {
			log.Printf("chat: recovered from panic in AI generation: %v", r)
		}
	}()

	aiText := ai.GenerateReply(history, c.userContext)
	c.appendHistory(openai.ChatMessageRoleAssistant, aiText)
	aiTime := time.Now()
	c.saveMessage("ai", aiText, aiTime)

	response := Message{Type: "ai_response", Text: aiText, Timestamp: aiTime.Unix()}
	if respBytes, err := json.Marshal(response); err == nil {
		// Non-blocking send: if the client has already disconnected, the
		// send channel may be closed/full - don't let this goroutine wedge.
		select {
		case c.send <- respBytes:
		default:
		}
	}
}

// saveMessage persists a chat turn. Uses context.Background() rather than
// the original HTTP request's context, since this runs in a long-lived
// goroutine that outlives the request that opened the WebSocket.
func (c *Client) saveMessage(sender, text string, at time.Time) {
	err := db.RunAsUser(context.Background(), c.userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(context.Background(),
			"INSERT INTO chat_messages (user_id, conversation_id, sender, message, created_at) VALUES ($1, $2, $3, $4, $5)",
			c.userID, c.conversationID, sender, text, at)
		return err
	})
	if err != nil {
		log.Printf("chat: failed to persist message: %v", err)
	}
}

func (c *Client) appendHistory(role, content string) {
	c.historyMu.Lock()
	defer c.historyMu.Unlock()
	c.history = append(c.history, openai.ChatCompletionMessage{Role: role, Content: content})
	if len(c.history) > maxHistoryLen {
		c.history = c.history[len(c.history)-maxHistoryLen:]
	}
}

// historyCopy returns a stable snapshot of the current history under lock,
// so an AI goroutine reads a consistent slice rather than one being mutated
// by a concurrent appendHistory.
func (c *Client) historyCopy() []openai.ChatCompletionMessage {
	c.historyMu.Lock()
	defer c.historyMu.Unlock()
	out := make([]openai.ChatCompletionMessage, len(c.history))
	copy(out, c.history)
	return out
}

// updateMemory asks the AI to fold this session into an updated
// cross-conversation memory summary, encrypts it at rest, then persists it.
// Runs in its own goroutine after the connection has already closed, using
// context.Background() since the original request context is gone by then.
func (c *Client) updateMemory() {
	ctx := context.Background()
	existing := loadMemorySummary(ctx, c.userID)
	updated := ai.SummarizeForMemory(existing, c.historyCopy())
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
