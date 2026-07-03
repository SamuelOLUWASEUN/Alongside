# Vault End-to-End Encryption

The server never sees plaintext vault content. All encryption/decryption
happens on the client.

## Scheme
- **Key derivation**: PBKDF2 from the user's passphrase + a random salt
  (stored locally, never sent to the server).
- **Cipher**: AES-256-GCM.
- **Stored blob** (in the `encrypted_data` column / API field) is JSON:

```json
{
  "ciphertext": "<base64>",
  "iv": "<base64>",
  "tag": "<base64>",
  "salt": "<base64>"
}
```

## Flutter implementation notes
Use the `cryptography` or `pointycastle` package to:
1. Derive a key from the passphrase with PBKDF2 (salt persisted in
   `flutter_secure_storage`).
2. Encrypt/decrypt vault item text with AES-256-GCM before calling
   `POST /api/vault` / after `GET /api/vault`.
3. Optionally gate access to the derived key behind `local_auth`
   biometric unlock, so the passphrase itself doesn't need to be
   re-entered every session.

The backend (`vault/handlers.go`) only stores and returns this opaque
blob — it does no decryption and has no way to.
