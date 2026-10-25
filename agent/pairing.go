package main

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"net/http"
	"sync"
	"time"
)

const pairTTL = 5 * time.Minute

// A pairing code is what the QR carries instead of the token: it can be
// exchanged for the token once, within pairTTL, so a QR seen later is useless.
type pairing struct {
	expires time.Time
	claimed bool
	by      string
}

type Pairings struct {
	mu    sync.Mutex
	codes map[string]*pairing
}

func newPairings() *Pairings { return &Pairings{codes: map[string]*pairing{}} }

func (p *Pairings) start() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	code := hex.EncodeToString(b)
	p.mu.Lock()
	defer p.mu.Unlock()
	for c, v := range p.codes {
		if time.Now().After(v.expires.Add(time.Minute)) {
			delete(p.codes, c)
		}
	}
	p.codes[code] = &pairing{expires: time.Now().Add(pairTTL)}
	return code
}

func (p *Pairings) claim(code, by string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	v, ok := p.codes[code]
	if !ok || v.claimed || time.Now().After(v.expires) {
		return false
	}
	v.claimed, v.by = true, by
	return true
}

func (p *Pairings) status(code string) (claimed, expired bool, by string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	v, ok := p.codes[code]
	if !ok {
		return false, true, ""
	}
	return v.claimed, !v.claimed && time.Now().After(v.expires), v.by
}

// POST /api/pair/start (com token): usado pelo comando pair, via localhost.
func (s *Server) pairStart(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"code": s.pairs.start(), "expires_in": int(pairTTL.Seconds())})
}

// GET /api/pair/status?code= (com token): o comando pair espera aqui.
func (s *Server) pairStatus(w http.ResponseWriter, r *http.Request) {
	claimed, expired, by := s.pairs.status(r.URL.Query().Get("code"))
	writeJSON(w, http.StatusOK, map[string]any{"claimed": claimed, "expired": expired, "by": by})
}

// POST /api/pair/claim (sem token): o app troca o código do QR pelo token.
func (s *Server) pairClaim(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code   string `json:"code"`
		Device string `json:"device"`
	}
	if err := decode(r, &req); err != nil || !s.pairs.claim(req.Code, req.Device+" ("+r.RemoteAddr+")") {
		log.Printf("pareamento recusado de %s", r.RemoteAddr)
		writeErr(w, http.StatusForbidden, "código de pareamento inválido, usado ou expirado; gere outro com velksync-agent pair")
		return
	}
	log.Printf("pareado: %s %s", req.Device, r.RemoteAddr)
	writeJSON(w, http.StatusOK, map[string]any{"token": s.cfg.Token, "name": s.cfg.Name})
}
