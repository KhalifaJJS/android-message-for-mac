package app

import (
	"strings"

	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
)

// SIMRecord is one SIM on the paired phone (dual-SIM). The Payload is the exact
// gmproto value to put on an outgoing SendMessageRequest to send from this SIM.
type SIMRecord struct {
	SIMNumber int32
	Carrier   string
	Phone     string
	Payload   *gmproto.SIMPayload
}

// SetSIMs captures the phone's SIM list from a Settings event. This is the only
// source — libgm has no on-demand "get settings" RPC, so the list arrives via
// the event stream shortly after connecting.
func (a *App) SetSIMs(settings *gmproto.Settings) {
	if settings == nil {
		return
	}
	var sims []SIMRecord
	for _, card := range settings.GetSIMCards() {
		data := card.GetSIMData()
		if data == nil {
			continue
		}
		payload := data.GetSIMPayload()
		if payload == nil {
			continue
		}
		phone := data.GetFormattedPhoneNumber()
		if phone == "" {
			phone = data.GetInternationalPhoneNumber()
		}
		sims = append(sims, SIMRecord{
			SIMNumber: payload.GetSIMNumber(),
			Carrier:   strings.TrimSpace(data.GetCarrierName()),
			Phone:     strings.TrimSpace(phone),
			Payload:   payload,
		})
	}
	a.simMu.Lock()
	a.sims = sims
	a.simMu.Unlock()
	a.Logger.Info().Int("count", len(sims)).Msg("Captured SIM list from settings")
}

// SIMList returns the captured SIMs as JSON-friendly maps for the /api/sims
// endpoint. Empty until the Settings event arrives (and on single-SIM phones it
// typically has one entry).
func (a *App) SIMList() []map[string]any {
	a.simMu.Lock()
	defer a.simMu.Unlock()
	out := make([]map[string]any, 0, len(a.sims))
	for _, s := range a.sims {
		out = append(out, map[string]any{
			"sim_number": s.SIMNumber,
			"carrier":    s.Carrier,
			"phone":      s.Phone,
		})
	}
	return out
}

// SelectSIM returns the SIMPayload for a chosen SIM number, or nil if unknown
// (caller then falls back to the conversation's default SIM).
func (a *App) SelectSIM(simNumber int) *gmproto.SIMPayload {
	if simNumber == 0 {
		return nil
	}
	a.simMu.Lock()
	defer a.simMu.Unlock()
	for _, s := range a.sims {
		if int(s.SIMNumber) == simNumber {
			return s.Payload
		}
	}
	return nil
}
