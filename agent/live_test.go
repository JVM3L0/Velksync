package main

import (
	"bufio"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestMediaChanged(t *testing.T) {
	vol := 0.5
	base := MediaState{Available: true, Status: "playing", Title: "a", PositionMs: 10_000, Volume: &vol}
	same := base
	same.PositionMs = 12_000
	if mediaChanged(base, same, 2*time.Second) {
		t.Fatal("andamento normal contado como mudança")
	}
	seek := base
	seek.PositionMs = 60_000
	if !mediaChanged(base, seek, 2*time.Second) {
		t.Fatal("seek não detectado")
	}
	paused := base
	paused.Status = "paused"
	if !mediaChanged(base, paused, time.Second) {
		t.Fatal("pausa não detectada")
	}
	louder := base
	v2 := 0.8
	louder.Volume = &v2
	louder.PositionMs = 11_000
	if !mediaChanged(base, louder, time.Second) {
		t.Fatal("volume não detectado")
	}
	stopped := MediaState{Status: "paused", PositionMs: 5000}
	if mediaChanged(stopped, stopped, time.Minute) {
		t.Fatal("pausado, a posição parada não é mudança")
	}
}

// fakeLive tem stats que contam chamadas e mídia controlada pelo teste.
func fakeLive() (*Live, *atomic.Int32, func(MediaState)) {
	var calls atomic.Int32
	var mu sync.Mutex
	cur := MediaState{Status: "paused", Title: "a"}
	l := newLive(func() any { return map[string]int32{"n": calls.Add(1)} }, func() MediaState {
		mu.Lock()
		defer mu.Unlock()
		return cur
	})
	l.tick = 10 * time.Millisecond
	return l, &calls, func(m MediaState) { mu.Lock(); cur = m; mu.Unlock() }
}

func recv(t *testing.T, s *liveSub, within time.Duration) (liveMsg, bool) {
	t.Helper()
	select {
	case m := <-s.ch:
		return m, true
	case <-time.After(within):
		return liveMsg{}, false
	}
}

func TestLiveSendsMediaOnlyOnChange(t *testing.T) {
	l, _, setMedia := fakeLive()
	sub, err := l.Subscribe("cel", map[string]bool{"media": true})
	if err != nil {
		t.Fatal(err)
	}
	defer l.Unsubscribe(sub)
	if m, ok := recv(t, sub, time.Second); !ok || m.topic != "media" {
		t.Fatal("estado inicial não chegou")
	}
	if _, ok := recv(t, sub, 100*time.Millisecond); ok {
		t.Fatal("mandou de novo sem mudança")
	}
	setMedia(MediaState{Status: "playing", Title: "b"})
	m, ok := recv(t, sub, time.Second)
	if !ok || !strings.Contains(string(m.data), `"title":"b"`) {
		t.Fatalf("mudança não chegou: %s", m.data)
	}
}

func TestLiveStopsWithoutSubscribers(t *testing.T) {
	l, calls, _ := fakeLive()
	sub, _ := l.Subscribe("cel", map[string]bool{"stats": true})
	recv(t, sub, time.Second)
	l.Unsubscribe(sub)
	time.Sleep(50 * time.Millisecond)
	before := calls.Load()
	time.Sleep(100 * time.Millisecond)
	if calls.Load() != before {
		t.Fatal("continuou coletando sem ninguém olhando")
	}
	// Volta a coletar com um assinante novo.
	sub2, _ := l.Subscribe("cel", map[string]bool{"stats": true})
	defer l.Unsubscribe(sub2)
	if _, ok := recv(t, sub2, time.Second); !ok {
		t.Fatal("não voltou a coletar")
	}
}

func TestLiveLimitPerClient(t *testing.T) {
	l, _, _ := fakeLive()
	topics := map[string]bool{"stats": true}
	for i := 0; i < maxLivePerClient; i++ {
		s, err := l.Subscribe("cel", topics)
		if err != nil {
			t.Fatal(err)
		}
		defer l.Unsubscribe(s)
	}
	if _, err := l.Subscribe("cel", topics); err != errTooManyStream {
		t.Fatalf("passou do limite: %v", err)
	}
	other, err := l.Subscribe("outro", topics)
	if err != nil {
		t.Fatal("o limite de um celular afetou outro")
	}
	l.Unsubscribe(other)
}

func TestLiveFeedOverHTTP(t *testing.T) {
	l, _, _ := fakeLive()
	srv := &Server{cfg: Config{Name: "pc", Token: testMaster}, hub: NewHub(), live: l}
	ts := httptest.NewServer(srv.routes())
	defer ts.Close()
	get := func(q string) *http.Response {
		req, _ := http.NewRequest("GET", ts.URL+"/api/live?topics="+q, nil)
		req.Header.Set("Authorization", "Bearer "+testMaster)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return res
	}
	for _, bad := range []string{"", "stats,senhas", "media,"} {
		res := get(bad)
		res.Body.Close()
		if res.StatusCode != http.StatusBadRequest {
			t.Fatalf("tópicos %q: %d", bad, res.StatusCode)
		}
	}
	res := get("media")
	defer res.Body.Close()
	lines := bufio.NewScanner(res.Body)
	deadline := time.After(2 * time.Second)
	got := make(chan bool, 1)
	go func() {
		for lines.Scan() {
			if lines.Text() == "event: media" && lines.Scan() && strings.HasPrefix(lines.Text(), "data: {") {
				got <- true
				return
			}
		}
		got <- false
	}()
	select {
	case ok := <-got:
		if !ok {
			t.Fatal("canal fechou sem evento de mídia")
		}
	case <-deadline:
		t.Fatal("evento de mídia não chegou")
	}
}

// slowLive só tiquetaqueia de hora em hora: qualquer leitura extra vem do Kick.
func slowLive() (*Live, *atomic.Int32, func(MediaState)) {
	var reads, inflight, maxInflight atomic.Int32
	var mu sync.Mutex
	cur := MediaState{Status: "playing", Title: "a"}
	l := newLive(func() any { return nil }, func() MediaState {
		if n := inflight.Add(1); n > maxInflight.Load() {
			maxInflight.Store(n)
		}
		defer inflight.Add(-1)
		reads.Add(1)
		time.Sleep(2 * time.Millisecond)
		mu.Lock()
		defer mu.Unlock()
		return cur
	})
	l.tick = time.Hour
	l.burst = []time.Duration{5 * time.Millisecond, 15 * time.Millisecond, 30 * time.Millisecond, 50 * time.Millisecond}
	return l, &reads, func(m MediaState) {
		if maxInflight.Load() > 1 {
			panic("leituras do player em paralelo")
		}
		mu.Lock()
		cur = m
		mu.Unlock()
	}
}

func TestKickSendsNewTrackBeforeNextTick(t *testing.T) {
	l, _, setMedia := slowLive()
	sub, _ := l.Subscribe("cel", map[string]bool{"media": true})
	defer l.Unsubscribe(sub)
	recv(t, sub, time.Second) // estado inicial
	setMedia(MediaState{Status: "playing", Title: "b"})
	l.Kick()
	m, ok := recv(t, sub, 500*time.Millisecond)
	if !ok || !strings.Contains(string(m.data), `"title":"b"`) {
		t.Fatalf("a faixa nova só viria no próximo tique (1 h): %s", m.data)
	}
}

func TestKickStopsAfterChangeAndIsBounded(t *testing.T) {
	l, reads, setMedia := slowLive()
	sub, _ := l.Subscribe("cel", map[string]bool{"media": true})
	defer l.Unsubscribe(sub)
	recv(t, sub, time.Second)
	base := reads.Load()
	for range 5 { // toques seguidos viram uma rajada só
		l.Kick()
	}
	time.Sleep(150 * time.Millisecond)
	if got := reads.Load() - base; got < 1 || got > int32(len(l.burst)) {
		t.Fatalf("rajada sem mudança leu %d vezes (esperado 1..%d)", got, len(l.burst))
	}
	setMedia(MediaState{Status: "playing", Title: "c"}) // confere que nada rodou em paralelo
}

func TestKickWithoutSubscribersDoesNothing(t *testing.T) {
	l, reads, _ := slowLive()
	l.Kick()
	time.Sleep(80 * time.Millisecond)
	if reads.Load() != 0 {
		t.Fatal("leu o player sem ninguém olhando")
	}
}
