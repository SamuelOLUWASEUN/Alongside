package auth

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/yourorg/innerarc-core/db"
	"github.com/yourorg/innerarc-core/redis"
	"golang.org/x/crypto/bcrypt"
)

// JwtSecret signs and verifies access/refresh tokens. Reads from JWT_SECRET
// so it's not baked into the binary - falls back to an insecure default for
// convenience in local dev, but that fallback should never be used anywhere
// real people's data touches.
var JwtSecret = loadJwtSecret()

func loadJwtSecret() []byte {
	if secret := os.Getenv("JWT_SECRET"); secret != "" {
		return []byte(secret)
	}
	log.Println("auth: JWT_SECRET not set - using an insecure development default. Set JWT_SECRET before deploying anywhere real.")
	return []byte("change-me-in-production-use-vault")
}

type Credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func Register(w http.ResponseWriter, r *http.Request) {
	var creds Credentials
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(creds.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, "Server error", http.StatusInternalServerError)
		return
	}
	_, err = db.Pool.Exec(r.Context(), "INSERT INTO users (email, password_hash) VALUES ($1, $2)", creds.Email, string(hash))
	if err != nil {
		http.Error(w, "Email already registered", http.StatusConflict)
		return
	}
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"message": "User created"})
}

func Login(w http.ResponseWriter, r *http.Request) {
	var creds Credentials
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}
	var id, hash string
	err := db.Pool.QueryRow(r.Context(), "SELECT id, password_hash FROM users WHERE email=$1", creds.Email).Scan(&id, &hash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(creds.Password)) != nil {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}
	accessToken, _ := generateToken(id, "access", 15*time.Minute)
	refreshToken, _ := generateToken(id, "refresh", 7*24*time.Hour)
	json.NewEncoder(w).Encode(map[string]string{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
	})
}

func RefreshToken(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}
	token, err := jwt.Parse(body.RefreshToken, func(t *jwt.Token) (interface{}, error) { return JwtSecret, nil })
	if err != nil || !token.Valid {
		http.Error(w, "Invalid refresh token", http.StatusUnauthorized)
		return
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || claims["type"] != "refresh" {
		http.Error(w, "Invalid token type", http.StatusUnauthorized)
		return
	}
	userID := claims["sub"].(string)
	// Invalidate old refresh token in Redis (blacklist)
	redis.Client.Set(r.Context(), "blacklist:"+body.RefreshToken, "revoked", 7*24*time.Hour)
	newAccess, _ := generateToken(userID, "access", 15*time.Minute)
	newRefresh, _ := generateToken(userID, "refresh", 7*24*time.Hour)
	json.NewEncoder(w).Encode(map[string]string{
		"access_token":  newAccess,
		"refresh_token": newRefresh,
	})
}

func generateToken(userID, tokenType string, duration time.Duration) (string, error) {
	claims := jwt.MapClaims{
		"sub":  userID,
		"type": tokenType,
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(duration).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(JwtSecret)
}

// Logout blacklists the access token used to call it (so it can't be reused
// even though it hasn't naturally expired yet), and - if the client sends
// one - the refresh token too, so a full sign-out actually revokes both
// rather than leaving the access token quietly valid until its 15-minute
// natural expiry.
func Logout(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
	if tokenStr != "" {
		redis.Client.Set(r.Context(), "blacklist:"+tokenStr, "revoked", 15*time.Minute)
	}

	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	// Body is optional - decode errors here just mean no refresh token was
	// sent, which is fine; the access token above is still revoked either way.
	if err := json.NewDecoder(r.Body).Decode(&body); err == nil && body.RefreshToken != "" {
		redis.Client.Set(r.Context(), "blacklist:"+body.RefreshToken, "revoked", 7*24*time.Hour)
	}

	w.WriteHeader(http.StatusOK)
}

