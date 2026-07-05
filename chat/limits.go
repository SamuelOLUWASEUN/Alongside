package chat

import (
	"context"
	"fmt"
	"time"

	"github.com/yourorg/innerarc-core/redis"
)

// dailyMessageLimit is a safety net against a runaway API bill (e.g. a
// viral spike sending far more traffic than expected overnight), not a way
// to ration normal use - it's set generously high on purpose. A real,
// engaged conversation should essentially never feel this.
const dailyMessageLimit = 50

// checkDailyLimit reports whether this user is still within today's
// message allowance. Crisis-flagged messages are checked and exempted
// before this is ever called (see readPump) - once a conversation trips
// the crisis detector once, c.crisisExempt stays true for the rest of that
// session, since a blunt one-message-at-a-time keyword scan can't tell that
// a later message is still part of the same serious disclosure just
// because it happens to use different words.
func (c *Client) checkDailyLimit(ctx context.Context) bool {
	if c.crisisExempt {
		return true
	}

	key := fmt.Sprintf("msgcap:%s:%s", c.userID, time.Now().UTC().Format("2006-01-02"))
	count, err := redis.Client.Incr(ctx, key).Result()
	if err != nil {
		// Fail open: a Redis hiccup should never be the reason someone
		// can't talk to their coach.
		return true
	}
	if count == 1 {
		// 25h rather than exactly 24h as a small safety margin so the key
		// reliably outlives "today" even with minor clock drift, rather
		// than resetting a few minutes early.
		redis.Client.Expire(ctx, key, 25*time.Hour)
	}
	return count <= dailyMessageLimit
}

const limitReachedMessage = "We've reached today's chat limit while we're keeping the beta sustainable for now " +
	"- I'll be right here again in a few hours. In the meantime, your Vault's always open if you want to write " +
	"something down, or check in on your Mood."

	