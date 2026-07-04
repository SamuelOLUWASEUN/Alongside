package chat

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
	"os"
)

// This protects the memory summary at rest - e.g. a leaked database
// backup, an exposed connection string, or anyone with raw read access to
// the database but not the running server. It is NOT the same guarantee
// as the Vault's end-to-end encryption: the running application still
// holds this key and decrypts on demand, because the AI has to be able to
// read the summary to actually use it. A feature that needs the server to
// process something can never be made unreadable to the server - that's
// a hard limit, not an implementation gap. See docs/e2e-encryption.md.
func memoryEncryptionKey() ([]byte, error) {
	keyB64 := os.Getenv("MEMORY_ENCRYPTION_KEY")
	if keyB64 == "" {
		return nil, errors.New("MEMORY_ENCRYPTION_KEY not set")
	}
	key, err := base64.StdEncoding.DecodeString(keyB64)
	if err != nil || len(key) != 32 {
		return nil, errors.New("MEMORY_ENCRYPTION_KEY must be a base64-encoded 32-byte key")
	}
	return key, nil
}

func encryptMemory(plaintext string) (string, error) {
	if plaintext == "" {
		return "", nil
	}
	key, err := memoryEncryptionKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ciphertext := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

func decryptMemory(encoded string) (string, error) {
	if encoded == "" {
		return "", nil
	}
	key, err := memoryEncryptionKey()
	if err != nil {
		return "", err
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	if len(data) < gcm.NonceSize() {
		return "", errors.New("ciphertext too short")
	}
	nonce, ciphertext := data[:gcm.NonceSize()], data[gcm.NonceSize():]
	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", err
	}
	return string(plaintext), nil
}