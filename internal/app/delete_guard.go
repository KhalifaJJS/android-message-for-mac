package app

import "time"

// deletedGuardWindow is how long a user-deleted conversation stays suppressed,
// so a re-sync that arrives before the server-side delete propagates can't
// resurrect it. After the window, genuinely-active threads can return.
const deletedGuardWindow = 2 * time.Minute

// MarkConversationDeleted records that the user just deleted a conversation.
func (a *App) MarkConversationDeleted(conversationID string) {
	if conversationID == "" {
		return
	}
	a.deletedMu.Lock()
	if a.deletedConvs == nil {
		a.deletedConvs = make(map[string]time.Time)
	}
	a.deletedConvs[conversationID] = time.Now()
	a.deletedMu.Unlock()
}

// WasRecentlyDeleted reports whether a conversation was deleted by the user
// within the guard window (so re-sync should skip recreating it).
func (a *App) WasRecentlyDeleted(conversationID string) bool {
	if conversationID == "" {
		return false
	}
	a.deletedMu.Lock()
	defer a.deletedMu.Unlock()
	t, ok := a.deletedConvs[conversationID]
	if !ok {
		return false
	}
	if time.Since(t) > deletedGuardWindow {
		delete(a.deletedConvs, conversationID)
		return false
	}
	return true
}
