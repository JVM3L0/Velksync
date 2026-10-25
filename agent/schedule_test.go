package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeScheduler nunca desliga nada: registra o que faria.
type fakePower struct {
	mu     sync.Mutex
	ran    []string
	warns  []string
	status string
}

func (f *fakePower) scheduler() *Scheduler {
	s := newScheduler(
		func(a string) { f.mu.Lock(); f.ran = append(f.ran, a); f.mu.Unlock() },
		func(t string) { f.mu.Lock(); f.warns = append(f.warns, t); f.mu.Unlock() },
		func() MediaState { f.mu.Lock(); defer f.mu.Unlock(); return MediaState{Status: f.status} },
	)
	s.minDelay, s.warning, s.stoppedFor, s.poll = 20*time.Millisecond, 40*time.Millisecond, 30*time.Millisecond, 5*time.Millisecond
	return s
}

func (f *fakePower) set(status string) { f.mu.Lock(); f.status = status; f.mu.Unlock() }

func (f *fakePower) snapshot() ([]string, []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.ran...), append([]string(nil), f.warns...)
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	for end := time.Now().Add(2 * time.Second); time.Now().Before(end); time.Sleep(5 * time.Millisecond) {
		if cond() {
			return
		}
	}
	t.Fatal("tempo esgotado")
}

func TestScheduleAfterWarnsAndRuns(t *testing.T) {
	f := &fakePower{}
	s := f.scheduler()
	p, err := s.After("shutdown", 100*time.Millisecond)
	if err != nil || p.At == 0 || s.Current() == nil {
		t.Fatalf("agendar: %v %+v", err, p)
	}
	waitFor(t, func() bool { ran, _ := f.snapshot(); return len(ran) == 1 })
	ran, warns := f.snapshot()
	if ran[0] != "shutdown" || len(warns) != 1 || !strings.Contains(warns[0], "desligar em 1 minuto") {
		t.Fatalf("ran=%v warns=%v", ran, warns)
	}
	if s.Current() != nil {
		t.Fatal("agendamento continuou depois de executar")
	}
}

func TestScheduleCancel(t *testing.T) {
	f := &fakePower{}
	s := f.scheduler()
	s.After("sleep", 80*time.Millisecond)
	if !s.Cancel() || s.Cancel() {
		t.Fatal("cancelar deveria funcionar uma vez só")
	}
	time.Sleep(150 * time.Millisecond)
	if ran, _ := f.snapshot(); len(ran) != 0 {
		t.Fatalf("executou depois de cancelado: %v", ran)
	}
}

func TestScheduleReplaceKeepsOnlyNewest(t *testing.T) {
	f := &fakePower{}
	s := f.scheduler()
	s.After("shutdown", 60*time.Millisecond)
	s.After("sleep", 120*time.Millisecond)
	waitFor(t, func() bool { ran, _ := f.snapshot(); return len(ran) == 1 })
	time.Sleep(100 * time.Millisecond)
	if ran, _ := f.snapshot(); len(ran) != 1 || ran[0] != "sleep" {
		t.Fatalf("o agendamento trocado também rodou: %v", ran)
	}
}

func TestScheduleValidation(t *testing.T) {
	f := &fakePower{}
	s := f.scheduler()
	if _, err := s.After("reboot", time.Second); err == nil {
		t.Fatal("reboot agendado não deveria ser aceito")
	}
	if _, err := s.After("shutdown", time.Millisecond); err == nil {
		t.Fatal("atraso abaixo do mínimo aceito")
	}
	if _, err := s.After("shutdown", 25*time.Hour); err == nil {
		t.Fatal("atraso acima do máximo aceito")
	}
	f.set("paused")
	if _, err := s.WhenMediaStops("shutdown"); err == nil {
		t.Fatal("aceitou esperar a mídia sem nada tocando")
	}
}

func TestScheduleWhenMediaStops(t *testing.T) {
	f := &fakePower{status: "playing"}
	s := f.scheduler()
	if _, err := s.WhenMediaStops("shutdown"); err != nil {
		t.Fatal(err)
	}
	time.Sleep(60 * time.Millisecond)
	if ran, _ := f.snapshot(); len(ran) != 0 {
		t.Fatal("desligou com a mídia tocando")
	}
	// Para, avisa, volta a tocar dentro do minuto de aviso: não desliga.
	f.set("paused")
	waitFor(t, func() bool { _, w := f.snapshot(); return len(w) == 1 })
	f.set("playing")
	time.Sleep(80 * time.Millisecond)
	if ran, _ := f.snapshot(); len(ran) != 0 {
		t.Fatal("desligou mesmo com a mídia voltando")
	}
	if c := s.Current(); c == nil || c.At != 0 {
		t.Fatalf("devia voltar a esperar a mídia: %+v", c)
	}
	// Para de vez: desliga.
	f.set("stopped")
	waitFor(t, func() bool { ran, _ := f.snapshot(); return len(ran) == 1 })
	if _, w := f.snapshot(); len(w) != 2 || !strings.Contains(w[1], "A mídia parou") {
		t.Fatalf("avisos: %v", w)
	}
}

func TestSchedulePowerOverHTTP(t *testing.T) {
	f := &fakePower{}
	srv := &Server{cfg: Config{Name: "pc", Token: testMaster}, hub: NewHub(), schedule: f.scheduler()}
	srv.schedule.minDelay = time.Minute // valores reais: nada roda durante o teste
	ts := httptest.NewServer(srv.routes())
	defer ts.Close()
	call := func(method, path string, body any) (int, map[string]any) {
		var buf bytes.Buffer
		if body != nil {
			json.NewEncoder(&buf).Encode(body)
		}
		req, _ := http.NewRequest(method, ts.URL+path, &buf)
		req.Header.Set("Authorization", "Bearer "+testMaster)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]any
		json.NewDecoder(res.Body).Decode(&out)
		return res.StatusCode, out
	}
	if code, _ := call("POST", "/api/power", map[string]any{"action": "shutdown", "delay_s": 5}); code != http.StatusBadRequest {
		t.Fatalf("5 s aceito: %d", code)
	}
	if code, _ := call("POST", "/api/power", map[string]any{"action": "shutdown", "delay_s": 60, "when": "media_stopped"}); code != http.StatusBadRequest {
		t.Fatalf("delay e when juntos aceitos: %d", code)
	}
	code, p := call("POST", "/api/power", map[string]any{"action": "shutdown", "delay_s": 1800})
	if code != http.StatusAccepted || p["action"] != "shutdown" {
		t.Fatalf("agendar: %d %v", code, p)
	}
	_, info := call("GET", "/api/info", nil)
	if sch, _ := info["schedule"].(map[string]any); sch["action"] != "shutdown" {
		t.Fatalf("info sem o agendamento: %v", info["schedule"])
	}
	if code, _ := call("DELETE", "/api/power/schedule", nil); code != http.StatusOK {
		t.Fatalf("cancelar: %d", code)
	}
	if code, _ := call("DELETE", "/api/power/schedule", nil); code != http.StatusNotFound {
		t.Fatalf("cancelar de novo: %d", code)
	}
	if ran, _ := f.snapshot(); len(ran) != 0 {
		t.Fatalf("executou energia de verdade no teste: %v", ran)
	}
}
