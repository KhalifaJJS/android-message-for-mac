package db

import "fmt"

// GetConversationSIM returns the per-conversation preferred outgoing SIM number,
// or 0 when the user hasn't chosen one (meaning: use the conversation default).
func (s *Store) GetConversationSIM(conversationID string) (int, error) {
	var sim int
	err := s.db.QueryRow(
		`SELECT sim_number FROM conversation_sim WHERE conversation_id = ?`,
		conversationID,
	).Scan(&sim)
	if err != nil {
		// No row → no preference.
		return 0, nil
	}
	return sim, nil
}

// GetDefaultSIM returns the app-wide default outgoing SIM number (0 = none).
func (s *Store) GetDefaultSIM() (int, error) {
	var v string
	err := s.db.QueryRow(`SELECT value FROM app_settings WHERE key = 'default_sim'`).Scan(&v)
	if err != nil {
		return 0, nil
	}
	n := 0
	_, _ = fmt.Sscanf(v, "%d", &n)
	return n, nil
}

// SetDefaultSIM stores the app-wide default outgoing SIM number.
func (s *Store) SetDefaultSIM(simNumber int) error {
	_, err := s.db.Exec(`
		INSERT INTO app_settings (key, value) VALUES ('default_sim', ?)
		ON CONFLICT(key) DO UPDATE SET value = excluded.value
	`, fmt.Sprintf("%d", simNumber))
	return err
}

// SetConversationSIM stores the preferred outgoing SIM for a conversation.
// simNumber == 0 clears the preference (back to the conversation default).
func (s *Store) SetConversationSIM(conversationID string, simNumber int) error {
	if simNumber == 0 {
		_, err := s.db.Exec(`DELETE FROM conversation_sim WHERE conversation_id = ?`, conversationID)
		return err
	}
	_, err := s.db.Exec(`
		INSERT INTO conversation_sim (conversation_id, sim_number) VALUES (?, ?)
		ON CONFLICT(conversation_id) DO UPDATE SET sim_number = excluded.sim_number
	`, conversationID, simNumber)
	return err
}
