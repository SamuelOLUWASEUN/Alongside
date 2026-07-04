package db

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// RunAsUser begins a transaction, tells Postgres which user this request is
// acting as (via a transaction-scoped session variable), runs fn against
// that transaction, then commits. Row-level security policies on
// user-scoped tables check this variable to enforce that a query can only
// ever see or modify that one user's rows - enforced by the database
// itself, not only by the application remembering to add WHERE user_id=$1
// everywhere.
//
// set_config(..., true) behaves exactly like SET LOCAL (reverts at the end
// of the transaction) but - unlike SET LOCAL - accepts a normal query
// parameter, so the user ID never has to be string-formatted into the SQL.
// Since this is scoped to one transaction, it can never leak between
// different requests sharing the same pooled connection.
func RunAsUser(ctx context.Context, userID string, fn func(tx pgx.Tx) error) error {
	tx, err := Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) // no-op once committed

	if _, err := tx.Exec(ctx, "SELECT set_config('app.current_user_id', $1, true)", userID); err != nil {
		return err
	}

	if err := fn(tx); err != nil {
		return err
	}

	return tx.Commit(ctx)
}