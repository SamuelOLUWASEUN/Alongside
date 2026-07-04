package vault

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
)

// EncryptedData holds the client-encrypted blob. The server never sees
// plaintext - encryption/decryption happens entirely on the client using a
// key derived from the user's passphrase (PBKDF2 -> AES-256-GCM).
// Expected JSON shape stored in this field:
// {"ciphertext":"...","iv":"...","tag":"...","salt":"..."}
type VaultItem struct {
	ID            string `json:"id,omitempty"`
	Label         string `json:"label"`
	EncryptedData string `json:"encrypted_data"`
	CreatedAt     string `json:"created_at,omitempty"`
}

func GetItems(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var items []VaultItem
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(r.Context(),
			"SELECT id, label, encrypted_data, created_at FROM vault_items WHERE user_id=$1 ORDER BY created_at DESC", userID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var item VaultItem
			var t time.Time
			if err := rows.Scan(&item.ID, &item.Label, &item.EncryptedData, &t); err != nil {
				return err
			}
			item.CreatedAt = t.Format(time.RFC3339)
			items = append(items, item)
		}
		return rows.Err()
	})
	if err != nil {
		http.Error(w, "DB error", 500)
		return
	}
	json.NewEncoder(w).Encode(items)
}

func CreateItem(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var item VaultItem
	json.NewDecoder(r.Body).Decode(&item)
	var createdAt time.Time
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		return tx.QueryRow(r.Context(),
			`INSERT INTO vault_items (user_id, label, encrypted_data)
			 VALUES ($1, $2, $3) RETURNING id, created_at`,
			userID, item.Label, item.EncryptedData).Scan(&item.ID, &createdAt)
	})
	if err != nil {
		http.Error(w, "DB error", 500)
		return
	}
	item.CreatedAt = createdAt.Format(time.RFC3339)
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(item)
}

func UpdateItem(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	itemID := mux.Vars(r)["id"]
	var item VaultItem
	json.NewDecoder(r.Body).Decode(&item)
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(),
			`UPDATE vault_items SET label=$1, encrypted_data=$2, updated_at=$3
			 WHERE id=$4 AND user_id=$5`,
			item.Label, item.EncryptedData, time.Now(), itemID, userID)
		return err
	})
	if err != nil {
		http.Error(w, "DB error", 500)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func DeleteItem(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	itemID := mux.Vars(r)["id"]
	err := db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(), "DELETE FROM vault_items WHERE id=$1 AND user_id=$2", itemID, userID)
		return err
	})
	if err != nil {
		http.Error(w, "DB error", 500)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

