package chat

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/db"
)

// buildUserContext gathers a short, human-readable snapshot of what's
// relevant to bring into this session: the user's recent mood/sleep trend,
// plus a running memory summary carried over from past conversations. This
// is fed to the AI as background context only - never shown to the user,
// and the AI is explicitly instructed not to recite it verbatim.
//
// The mood/sleep lookups run inside one shared RLS-scoped transaction
// (mood_entries and sleep_entries both have row-level security enabled).
// The memory summary lookup runs separately against `users`, which isn't
// RLS-protected - see docs/migration_rls.sql for why.
func buildUserContext(ctx context.Context, userID string) string {
	var parts []string

	var moodPart, sleepPart string
	err := db.RunAsUser(ctx, userID, func(tx pgx.Tx) error {
		moodPart = recentMoodSummary(ctx, tx, userID)
		sleepPart = recentSleepSummary(ctx, tx, userID)
		return nil
	})
	if err != nil {
		log.Printf("chat: failed to load mood/sleep context: %v", err)
	}
	if moodPart != "" {
		parts = append(parts, moodPart)
	}
	if sleepPart != "" {
		parts = append(parts, sleepPart)
	}

	if memory := loadMemorySummary(ctx, userID); memory != "" {
		parts = append(parts, "What you remember about this person from past conversations: "+memory)
	}

	joined := ""
	for i, p := range parts {
		if i > 0 {
			joined += " "
		}
		joined += p
	}
	return joined
}

func recentMoodSummary(ctx context.Context, tx pgx.Tx, userID string) string {
	rows, err := tx.Query(ctx,
		`SELECT mood_score FROM mood_entries WHERE user_id=$1 AND time > now() - interval '7 days' ORDER BY time DESC`,
		userID)
	if err != nil {
		return ""
	}
	defer rows.Close()

	var scores []int
	for rows.Next() {
		var s int
		if rows.Scan(&s) == nil {
			scores = append(scores, s)
		}
	}
	if len(scores) == 0 {
		return ""
	}
	sum := 0
	for _, s := range scores {
		sum += s
	}
	avg := float64(sum) / float64(len(scores))
	return fmt.Sprintf(
		"This person's mood check-ins over the last 7 days have averaged %.1f/10, with their most recent check-in at %d/10.",
		avg, scores[0],
	)
}

func recentSleepSummary(ctx context.Context, tx pgx.Tx, userID string) string {
	var hours float64
	err := tx.QueryRow(ctx,
		`SELECT hours FROM sleep_entries WHERE user_id=$1 ORDER BY time DESC LIMIT 1`, userID,
	).Scan(&hours)
	if err != nil {
		return ""
	}
	return fmt.Sprintf("Their most recent sleep log was %.1f hours.", hours)
}

// loadMemorySummary reads the encrypted memory column directly from
// `users` via db.Pool (not RunAsUser) - that table isn't RLS-protected, see
// docs/migration_rls.sql for why - and this lookup is already scoped by the
// exact primary key, not a broader user-owned range of rows.
func loadMemorySummary(ctx context.Context, userID string) string {
	var encrypted *string
	err := db.Pool.QueryRow(ctx, `SELECT memory_summary FROM users WHERE id=$1`, userID).Scan(&encrypted)
	if err != nil || encrypted == nil || *encrypted == "" {
		return ""
	}
	plaintext, err := decryptMemory(*encrypted)
	if err != nil {
		log.Printf("chat: failed to decrypt memory summary, treating as none: %v", err)
		return ""
	}
	return plaintext
}

