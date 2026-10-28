package main

import (
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestHistoryKeepsTheLatestAndPersists(t *testing.T) {
	cfg := filepath.Join(t.TempDir(), "config.json")
	h := newHistory(cfg)
	clock := time.Date(2026, 11, 1, 9, 0, 0, 0, time.Local)
	h.now = func() time.Time { clock = clock.Add(time.Second); return clock }
	for i := range maxHistory + 25 {
		h.Add("Pixel", histCommand, fmt.Sprintf("rodou %d", i), false)
	}
	got := h.List(1000, true)
	if len(got) != maxHistory {
		t.Fatalf("guardou %d, queria %d", len(got), maxHistory)
	}
	if got[0].Text != fmt.Sprintf("rodou %d", maxHistory+24) || got[len(got)-1].Text != "rodou 25" {
		t.Errorf("ordem ou descarte errados: %q … %q", got[0].Text, got[len(got)-1].Text)
	}
	again := newHistory(cfg)
	if l := again.List(3, true); len(l) != 3 || l[0].Text != got[0].Text {
		t.Errorf("não sobreviveu a reiniciar: %+v", l)
	}
}

func TestHistoryHidesShellWhenDisabled(t *testing.T) {
	h := newHistory("")
	h.Add("Pixel", histShell, "rodou no terminal: dir", false)
	h.Add("Pixel", histCommand, "rodou \"Steam\"", false)
	if l := h.List(10, false); len(l) != 1 || l[0].Kind != histCommand {
		t.Errorf("terminal apareceu com ele desligado: %+v", l)
	}
	if l := h.List(10, true); len(l) != 2 {
		t.Errorf("com terminal ligado: %+v", l)
	}
	if l := h.List(1, true); len(l) != 1 || l[0].Kind != histCommand {
		t.Errorf("limite: %+v", l)
	}
}

func TestHistoryLine(t *testing.T) {
	now := time.Date(2026, 11, 2, 23, 30, 0, 0, time.Local)
	at := func(d time.Time) int64 { return d.UnixMilli() }
	cases := map[string]HistoryEntry{
		"hoje 23:10  Pixel 9 desligou o PC":            {At: at(now.Add(-20 * time.Minute)), Device: "Pixel 9", Text: "desligou o PC"},
		"ontem 21:05  Galaxy rodou \"Steam\" (falhou)": {At: at(time.Date(2026, 11, 1, 21, 5, 0, 0, time.Local)), Device: "Galaxy", Text: "rodou \"Steam\"", Failed: true},
		"25/10 18:00  Este PC revogou Velho":           {At: at(time.Date(2026, 10, 25, 18, 0, 0, 0, time.Local)), Device: "Este PC", Text: "revogou Velho"},
	}
	for want, e := range cases {
		if got := historyLine(e, now); got != want {
			t.Errorf("historyLine = %q, queria %q", got, want)
		}
	}
}

func TestHistoryRecordsCancelAndAPI(t *testing.T) {
	d := &fakeDesktop{present: true, asked: make(chan string, 1)}
	s := &Server{cfg: Config{Token: testMaster, Devices: []PairedDevice{{ID: "dev1", Name: "Pixel 9"}}}, hub: NewHub(), ui: d}
	s.routes()
	req := withAuth(httptest.NewRequest("POST", "/api/power", strings.NewReader(`{"action":"shutdown"}`)), authDevice, "dev1")
	s.power(httptest.NewRecorder(), req)
	<-d.asked
	var entries []HistoryEntry
	for range 100 {
		if entries = s.history.List(10, false); len(entries) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if len(entries) != 1 || entries[0].Device != "Este PC" || !strings.Contains(entries[0].Text, "cancelou desligar (pedido de Pixel 9)") {
		t.Fatalf("histórico do cancelamento: %+v", entries)
	}

	rec := httptest.NewRecorder()
	s.historyList(rec, withAuth(httptest.NewRequest("GET", "/api/history?limit=5", nil), authDevice, "dev1"))
	if !strings.Contains(rec.Body.String(), "cancelou desligar") {
		t.Errorf("GET /api/history: %s", rec.Body)
	}
}
