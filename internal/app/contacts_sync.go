package app

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"sync/atomic"

	"github.com/maxghenis/openmessage/internal/db"
)

var contactSyncRunning atomic.Bool

// SyncGoogleContacts pulls the paired phone's contacts (which mirror the signed-in
// Google account) and stores their names + photos so conversations can show a
// real name/avatar instead of a raw phone number.
func (a *App) SyncGoogleContacts() error {
	if !contactSyncRunning.CompareAndSwap(false, true) {
		return nil // already running
	}
	defer contactSyncRunning.Store(false)

	cli := a.GetClient()
	if cli == nil {
		return fmt.Errorf(ErrNotConnected)
	}

	resp, err := cli.GM.ListContacts()
	if err != nil {
		return fmt.Errorf("list contacts: %w", err)
	}
	contacts := resp.GetContacts()

	var ids []string
	for _, c := range contacts {
		id := c.GetContactID()
		if id == "" {
			continue
		}
		number := c.GetNumber().GetNumber()
		if number == "" {
			number = c.GetNumber().GetNumber2()
		}
		if err := a.Store.UpsertContactProfile(&db.ContactProfile{
			ContactID: id,
			Name:      c.GetName(),
			Number:    number,
		}); err != nil {
			a.Logger.Debug().Err(err).Str("contact_id", id).Msg("Failed to store contact")
			continue
		}
		ids = append(ids, id)
	}
	a.Logger.Info().Int("count", len(ids)).Msg("Synced Google contact names")

	// Photos are fetched separately (not in the contact list).
	a.syncContactPhotos(ids)

	if a.OnConversationsChange != nil {
		a.OnConversationsChange() // refresh names/avatars in the UI
	}
	return nil
}

func (a *App) syncContactPhotos(ids []string) {
	cli := a.GetClient()
	if cli == nil {
		return
	}
	const batch = 100
	photos := 0
	for i := 0; i < len(ids); i += batch {
		end := i + batch
		if end > len(ids) {
			end = len(ids)
		}
		resp, err := cli.GM.GetContactThumbnail(ids[i:end]...)
		if err != nil {
			a.Logger.Debug().Err(err).Msg("Contact thumbnail batch failed")
			continue
		}
		for _, t := range resp.GetThumbnail() {
			img := t.GetData().GetImageBuffer()
			if len(img) == 0 {
				continue
			}
			mime := http.DetectContentType(img)
			dataURL := "data:" + mime + ";base64," + base64.StdEncoding.EncodeToString(img)
			if err := a.Store.SetContactPhoto(t.GetIdentifier(), dataURL); err == nil {
				photos++
			}
		}
	}
	a.Logger.Info().Int("photos", photos).Msg("Synced Google contact photos")
}
