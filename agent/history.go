package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Histórico do que os celulares (e o próprio PC) fizeram: energia, comandos,
// pareamentos, textos trocados. Guarda as últimas maxHistory ações ao lado
// da config. Nunca guarda a saída de comandos nem o conteúdo dos textos.

const maxHistory = 200

// Tipos de ação; o app escolhe o ícone por eles.
const (
	histPower    = "power"
	histSchedule = "schedule"
	histCommand  = "command"
	histShell    = "shell"
	histPair     = "pair"
	histRevoke   = "revoke"
	histUpdate   = "update"
	histSend     = "send"    // PC → celular
	histReceive  = "receive" // celular → PC
)

type HistoryEntry struct {
	At     int64  `json:"at"`     // unix, milissegundos
	Device string `json:"device"` // quem fez: nome do celular, "Este PC" ou "O agendamento"
	Kind   string `json:"kind"`
	Text   string `json:"text"` // "desligou o PC", "rodou \"Abrir Steam\""
	Failed bool   `json:"failed,omitempty"`
}

type History struct {
	path string // vazio: só na memória (testes)
	now  func() time.Time

	mu      sync.Mutex
	entries []HistoryEntry // da mais antiga para a mais nova
}

func newHistory(configPath string) *History {
	h := &History{now: time.Now}
	if configPath == "" {
		return h
	}
	h.path = filepath.Join(filepath.Dir(configPath), "history.json")
	if data, err := os.ReadFile(h.path); err == nil {
		if err := json.Unmarshal(data, &h.entries); err != nil {
			log.Printf("histórico ilegível, começando outro: %v", err)
			h.entries = nil
		}
	}
	return h
}

func (h *History) Add(device, kind, text string, failed bool) {
	if h == nil {
		return
	}
	h.mu.Lock()
	h.entries = append(h.entries, HistoryEntry{At: h.now().UnixMilli(), Device: device, Kind: kind, Text: text, Failed: failed})
	if over := len(h.entries) - maxHistory; over > 0 {
		h.entries = append([]HistoryEntry(nil), h.entries[over:]...)
	}
	data, err := json.Marshal(h.entries)
	path := h.path
	h.mu.Unlock()
	if path == "" || err != nil {
		return
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		log.Printf("falha ao gravar o histórico: %v", err)
	}
}

// List devolve até limit ações, da mais nova para a mais antiga. O terminal
// só aparece para quem pode usá-lo (terminal livre ligado).
func (h *History) List(limit int, includeShell bool) []HistoryEntry {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make([]HistoryEntry, 0, min(limit, len(h.entries)))
	for i := len(h.entries) - 1; i >= 0 && len(out) < limit; i-- {
		if e := h.entries[i]; includeShell || e.Kind != histShell {
			out = append(out, e)
		}
	}
	return out
}

// GET /api/history?limit=50
func (s *Server) historyList(w http.ResponseWriter, r *http.Request) {
	limit := 50
	if n, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && n > 0 {
		limit = min(n, maxHistory)
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": s.history.List(limit, s.cfg.AllowShell)})
}

// historyLine é uma ação numa linha, para a janela do ícone:
// "hoje 23:10  Pixel 9 desligou o PC".
func historyLine(e HistoryEntry, now time.Time) string {
	at := time.UnixMilli(e.At).In(now.Location())
	y1, m1, d1 := at.Date()
	y2, m2, d2 := now.Date()
	yesterday := now.AddDate(0, 0, -1)
	var when string
	switch {
	case y1 == y2 && m1 == m2 && d1 == d2:
		when = "hoje " + at.Format("15:04")
	case at.Year() == yesterday.Year() && at.YearDay() == yesterday.YearDay():
		when = "ontem " + at.Format("15:04")
	default:
		when = at.Format("02/01 15:04")
	}
	line := fmt.Sprintf("%s  %s %s", when, e.Device, e.Text)
	if e.Failed {
		line += " (falhou)"
	}
	return strings.TrimSpace(line)
}

// pastVerb: "desligou", "reiniciou", "suspendeu".
func pastVerb(action string) string {
	switch action {
	case "reboot":
		return "reiniciou"
	case "sleep":
		return "suspendeu"
	}
	return "desligou"
}
