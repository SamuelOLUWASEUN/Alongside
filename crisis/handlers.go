package crisis

import (
	"encoding/json"
	"net/http"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/yourorg/innerarc-core/auth"
	"github.com/yourorg/innerarc-core/db"
	"gopkg.in/gomail.v2"
)

var helplines = map[string]string{
	"US": "988 Suicide & Crisis Lifeline: call/text 988",
	"GB": "Samaritans: 116 123",
}

func GetHelplines(w http.ResponseWriter, r *http.Request) {
	region := r.URL.Query().Get("region")
	if line, ok := helplines[region]; ok {
		json.NewEncoder(w).Encode(map[string]string{"helpline": line})
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"helpline": "https://findahelpline.com"})
}

func TriggerAlert(w http.ResponseWriter, r *http.Request) {
	userID := auth.GetUserID(r.Context())
	var body struct {
		Message string `json:"message"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	db.RunAsUser(r.Context(), userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(r.Context(),
			"INSERT INTO crisis_alerts (user_id, message, helpline_shown) VALUES ($1, $2, $3)",
			userID, body.Message, true)
		return err
	})
	// Email notification if SMTP is configured
	if smtpHost := os.Getenv("SMTP_HOST"); smtpHost != "" {
		m := gomail.NewMessage()
		m.SetHeader("From", "alerts@innerarc.com")
		m.SetHeader("To", os.Getenv("ALERT_EMAIL"))
		m.SetHeader("Subject", "Alongside Crisis Alert")
		m.SetBody("text/plain", "User "+userID+" triggered alert: "+body.Message)
		d := gomail.NewDialer(smtpHost, 587, os.Getenv("SMTP_USER"), os.Getenv("SMTP_PASS"))
		d.DialAndSend(m)
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "alert_sent"})
}

