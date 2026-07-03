package safety

import "strings"

var crisisKeywords = []string{
	"suicide", "kill myself", "end it all", "want to die",
	"not worth living", "no reason to live", "harm myself", "self-harm",
}

func ContainsCrisisKeywords(text string) bool {
	lower := strings.ToLower(text)
	for _, kw := range crisisKeywords {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	return false
}

func GetCrisisResponse() string {
	return `I'm really concerned about you right now. You're not alone - please reach out to a crisis helpline:
- US: 988 Suicide & Crisis Lifeline (call/text 988)
- International: https://findahelpline.com
If you're in immediate danger, please contact emergency services.`
}
