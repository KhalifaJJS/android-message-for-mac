package web

import (
	"encoding/json"
	"strings"

	"github.com/maxghenis/openmessage/internal/db"
)

// otherParticipantPhone reads the locally stored conversation and returns the
// other party's phone number (used as the `phone` arg for DeleteConversation).
// Reading the local row (not the server) lets us delete even orphan/empty
// threads whose server lookup might fail.
func otherParticipantPhone(store *db.Store, conversationID string) string {
	conv, err := store.GetConversation(conversationID)
	if err != nil || conv == nil {
		return ""
	}
	var parts []struct {
		Number string `json:"number"`
		IsMe   bool   `json:"is_me"`
	}
	if err := json.Unmarshal([]byte(conv.Participants), &parts); err != nil {
		return ""
	}
	for _, p := range parts {
		if !p.IsMe && strings.TrimSpace(p.Number) != "" {
			return p.Number
		}
	}
	// Fallback: first number of any kind.
	for _, p := range parts {
		if strings.TrimSpace(p.Number) != "" {
			return p.Number
		}
	}
	return ""
}
