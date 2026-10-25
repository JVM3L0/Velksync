package main

import (
	"errors"
	"log"
	"net/http"
	"sync"
	"time"
)

// MediaState é o que está tocando no PC (MPRIS no Linux, SMTC no Windows).
type MediaState struct {
	Available  bool     `json:"available"`
	Player     string   `json:"player,omitempty"`
	Status     string   `json:"status"` // playing, paused, stopped
	Title      string   `json:"title,omitempty"`
	Artist     string   `json:"artist,omitempty"`
	Album      string   `json:"album,omitempty"`
	PositionMs int64    `json:"position_ms"`
	DurationMs int64    `json:"duration_ms"`
	CanSeek    bool     `json:"can_seek"`
	CanControl bool     `json:"can_control"`
	ArtID      string   `json:"art_id,omitempty"` // muda quando a capa muda
	Volume     *float64 `json:"volume"`           // 0..1 do dispositivo de saída padrão
	Muted      *bool    `json:"muted"`
	// Há quanto tempo está pausado, quando o sistema informa (Windows: hora
	// da pausa no SMTC). Uso interno: não vai para o app.
	PausedMs int64 `json:"paused_ms,omitempty"`
}

// mediaBackend é implementado por sistema (media_linux.go, media_windows.go).
type mediaBackend interface {
	State() (MediaState, error)
	Art() (data []byte, contentType string, err error)
	Command(action string) error // play_pause, next, previous
	SeekTo(positionMs int64) error
	SetVolume(volume *float64, muted *bool) error
}

var errNoMedia = errors.New("nada tocando no PC")

const maxArtBytes = 5 << 20

var mediaActions = map[string]bool{"play_pause": true, "next": true, "previous": true}

// Criado no primeiro uso: no Windows isso inicia o processo auxiliar.
var media = sync.OnceValue(newMediaBackend)

// GET /api/media
func (s *Server) mediaState(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, currentMedia())
}

func currentMedia() MediaState {
	st, err := media().State()
	if err != nil && !errors.Is(err, errNoMedia) {
		log.Printf("mídia: %v", err)
	}
	if st.Status == "" {
		st.Status = "stopped"
	}
	return mediaIdle.apply(st, time.Now())
}

// mediaIdle esconde o que ficou pausado tempo demais. Navegadores congelam
// abas paradas: o play do app é aceito, o SMTC diz "tocando" e nada toca.
// Mídia parada há muito tempo vira "nada tocando" e só volta ao tocar de novo.
var mediaIdle = &idleFilter{after: defaultMediaIdle}

const defaultMediaIdle = 10 * time.Minute

type idleFilter struct {
	mu    sync.Mutex
	after time.Duration // 0 desliga
	key   string        // faixa pausada observada
	since time.Time     // quando o agente a viu pausada pela primeira vez
}

func (f *idleFilter) setAfter(d time.Duration) {
	f.mu.Lock()
	f.after = d
	f.mu.Unlock()
}

func (f *idleFilter) apply(st MediaState, now time.Time) MediaState {
	paused := st.PausedMs
	st.PausedMs = 0
	f.mu.Lock()
	defer f.mu.Unlock()
	if !st.Available || st.Status == "playing" {
		f.key = "" // tocou: a próxima pausa conta do zero
		return st
	}
	if f.after <= 0 {
		return st
	}
	// Sem a hora da pausa vinda do sistema (Linux), conta desde que o agente
	// viu a faixa pausada; trocar de faixa recomeça a contagem.
	key := st.Player + "|" + st.Title + "|" + st.Artist
	if key != f.key {
		f.key, f.since = key, now
	}
	idle := now.Sub(f.since)
	if paused > 0 {
		idle = time.Duration(paused) * time.Millisecond
	}
	if idle < f.after {
		return st
	}
	return MediaState{Status: "stopped", Volume: st.Volume, Muted: st.Muted}
}

// GET /api/media/art
func (s *Server) mediaArt(w http.ResponseWriter, r *http.Request) {
	data, ctype, err := media().Art()
	if err != nil || len(data) == 0 {
		writeErr(w, http.StatusNotFound, "sem capa")
		return
	}
	w.Header().Set("Content-Type", ctype)
	w.Header().Set("Cache-Control", "no-store")
	w.Write(data)
}

// POST /api/media/{action}
func (s *Server) mediaCommand(w http.ResponseWriter, r *http.Request) {
	action := r.PathValue("action")
	if !mediaActions[action] {
		writeErr(w, http.StatusBadRequest, "ação inválida (play_pause, next, previous)")
		return
	}
	if err := media().Command(action); err != nil {
		writeErr(w, http.StatusConflict, err.Error())
		return
	}
	s.live.Kick() // quem está na aba de mídia vê a mudança já
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// POST /api/media/seek {"position_ms": n}
func (s *Server) mediaSeek(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PositionMs *int64 `json:"position_ms"`
	}
	if err := decode(r, &req); err != nil || req.PositionMs == nil || *req.PositionMs < 0 {
		writeErr(w, http.StatusBadRequest, "position_ms inválido")
		return
	}
	if err := media().SeekTo(*req.PositionMs); err != nil {
		writeErr(w, http.StatusConflict, err.Error())
		return
	}
	s.live.Kick() // quem está na aba de mídia vê a mudança já
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// POST /api/media/volume {"volume": 0..1, "muted": bool} (qualquer um dos dois)
func (s *Server) mediaVolume(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Volume *float64 `json:"volume"`
		Muted  *bool    `json:"muted"`
	}
	if err := decode(r, &req); err != nil || (req.Volume == nil && req.Muted == nil) ||
		(req.Volume != nil && (*req.Volume < 0 || *req.Volume > 1)) {
		writeErr(w, http.StatusBadRequest, "informe volume (0 a 1) e/ou muted")
		return
	}
	if err := media().SetVolume(req.Volume, req.Muted); err != nil {
		writeErr(w, http.StatusConflict, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
