package web

import (
	"encoding/json"
	"strings"

	"github.com/maxghenis/openmessage/internal/db"
)

// firstOtherNumber returns the first non-self participant phone number from a
// conversation's participants JSON.
func firstOtherNumber(participantsJSON string) string {
	var parts []struct {
		Number string `json:"number"`
		IsMe   bool   `json:"is_me"`
	}
	if json.Unmarshal([]byte(participantsJSON), &parts) != nil {
		return ""
	}
	for _, p := range parts {
		if !p.IsMe && strings.TrimSpace(p.Number) != "" {
			return p.Number
		}
	}
	return ""
}

// enrichContactProfiles replaces number-only conversation names with the synced
// Google contact name and attaches the contact photo (avatar_url) when known.
func enrichContactProfiles(store *db.Store, convos []*db.Conversation) {
	for _, c := range convos {
		if c == nil || c.IsGroup {
			continue
		}
		num := firstOtherNumber(c.Participants)
		if num == "" {
			num = c.Name // the stored name is often just the raw number
		}
		prof, ok := store.LookupContactByNumber(num)
		if !ok {
			continue
		}
		if prof.Name != "" {
			c.Name = prof.Name
			if c.UnifiedName == "" {
				c.UnifiedName = prof.Name
			}
		}
		if prof.Photo != "" {
			c.AvatarURL = prof.Photo
		}
	}
}
