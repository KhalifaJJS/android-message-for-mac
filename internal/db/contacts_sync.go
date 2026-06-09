package db

import "strings"

// normalizePhoneKey reduces a phone number to its last 8 digits, which match
// across formats (e.g. "010-2657-1749", "+821026571749", "01026571749" all →
// "26571749"). Good enough to match Korean/most mobile numbers between the
// conversation participant list and the synced contacts.
func normalizePhoneKey(number string) string {
	var b strings.Builder
	for _, r := range number {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	d := b.String()
	if len(d) > 8 {
		return d[len(d)-8:]
	}
	return d
}

// ContactProfile is a synced Google contact (name + optional photo data URL).
type ContactProfile struct {
	ContactID string
	Name      string
	Number    string
	Photo     string // "data:image/...;base64,..."
}

// UpsertContactProfile inserts/updates a contact, preserving an existing photo
// when the incoming one is empty (names sync separately from photos).
func (s *Store) UpsertContactProfile(p *ContactProfile) error {
	key := normalizePhoneKey(p.Number)
	_, err := s.db.Exec(`
		INSERT INTO contacts (contact_id, name, number, number_key, photo)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(contact_id) DO UPDATE SET
			name=excluded.name,
			number=excluded.number,
			number_key=excluded.number_key,
			photo=CASE WHEN excluded.photo != '' THEN excluded.photo ELSE contacts.photo END
	`, p.ContactID, p.Name, p.Number, key, p.Photo)
	return err
}

// SetContactPhoto updates only the photo for a contact id.
func (s *Store) SetContactPhoto(contactID, photo string) error {
	_, err := s.db.Exec(`UPDATE contacts SET photo=? WHERE contact_id=?`, photo, contactID)
	return err
}

// LookupContactByNumber finds a named contact whose number matches (by last-8
// digits). Returns false when there's no named match.
func (s *Store) LookupContactByNumber(number string) (*ContactProfile, bool) {
	key := normalizePhoneKey(number)
	if key == "" {
		return nil, false
	}
	p := &ContactProfile{}
	err := s.db.QueryRow(
		`SELECT contact_id, name, number, photo FROM contacts WHERE number_key = ? AND TRIM(name) != '' ORDER BY length(photo) DESC LIMIT 1`,
		key,
	).Scan(&p.ContactID, &p.Name, &p.Number, &p.Photo)
	if err != nil {
		return nil, false
	}
	return p, true
}
