package app

import "strings"

// isFallbackWorthyStatus decides whether a failed outgoing message should be
// resent. We retry on ANY failure (incl. OUTGOING_FAILED_GENERIC) so the phone
// can route it as SMS/MMS, EXCEPT failures where a retry can't help or is
// unsafe: no-retry/no-fallback, too-large, or emergency numbers.
func isFallbackWorthyStatus(status string) bool {
	s := strings.ToUpper(strings.TrimSpace(status))
	if !strings.Contains(s, "FAILED") {
		return false
	}
	for _, bad := range []string{"NO_RETRY_NO_FALLBACK", "TOO_LARGE", "EMERGENCY"} {
		if strings.Contains(s, bad) {
			return false
		}
	}
	return true
}

// HandleSendFailure is called when one of our outgoing messages comes back with
// a failure status. When the failure is an RCS-specific one, we resend the text
// once: with forceRCS unset, the phone routes the retry as SMS/MMS. Tracked per
// message ID so a persistently failing message can't loop.
func (a *App) HandleSendFailure(conversationID, messageID, status, body string) {
	if !isFallbackWorthyStatus(status) {
		return
	}
	body = strings.TrimSpace(body)
	if body == "" || conversationID == "" {
		return
	}

	// Dedup on (conversation, body) — NOT message ID — because the resend creates
	// a new message with a new ID; if that also fails, keying on ID would loop.
	dedupKey := conversationID + "|" + body
	a.resentMu.Lock()
	if a.resent == nil {
		a.resent = make(map[string]struct{})
	}
	if _, done := a.resent[dedupKey]; done {
		a.resentMu.Unlock()
		return
	}
	a.resent[dedupKey] = struct{}{}
	a.resentMu.Unlock()

	a.Logger.Warn().
		Str("conv_id", conversationID).
		Str("status", status).
		Msg("RCS send failed — resending once as SMS/MMS (forceRCS unset)")

	// SendTextToConversation builds the payload with forceRCS unset, so the
	// phone falls back to SMS/MMS.
	if _, _, err := a.SendTextToConversation(conversationID, body); err != nil {
		a.Logger.Error().Err(err).Str("conv_id", conversationID).Msg("SMS/MMS fallback resend failed")
		return
	}
	if a.OnMessagesChange != nil {
		a.OnMessagesChange(conversationID)
	}
}
