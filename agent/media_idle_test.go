package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestIdleFilterHidesLongPause(t *testing.T) {
	f := &idleFilter{after: 10 * time.Minute}
	t0 := time.Date(2026, 10, 25, 19, 0, 0, 0, time.UTC)
	vol := 0.5
	paused := MediaState{Available: true, Status: "paused", Player: "Helium", Title: "vídeo", Volume: &vol}

	if got := f.apply(paused, t0); !got.Available {
		t.Fatal("pausa recente sumiu")
	}
	if got := f.apply(paused, t0.Add(9*time.Minute)); !got.Available {
		t.Fatal("9 min pausado já sumiu")
	}
	got := f.apply(paused, t0.Add(11*time.Minute))
	if got.Available || got.Status != "stopped" {
		t.Fatalf("11 min pausado continua no player: %+v", got)
	}
	if got.Volume == nil || *got.Volume != vol {
		t.Fatal("escondido, o volume do PC continua no app")
	}

	// Voltou a tocar: aparece, e a próxima pausa conta do zero.
	playing := paused
	playing.Status = "playing"
	if got := f.apply(playing, t0.Add(12*time.Minute)); !got.Available {
		t.Fatal("tocando de novo não voltou")
	}
	if got := f.apply(paused, t0.Add(13*time.Minute)); !got.Available {
		t.Fatal("pausa nova herdou o tempo da antiga")
	}
}

func TestIdleFilterUsesSystemPauseTime(t *testing.T) {
	f := &idleFilter{after: 10 * time.Minute}
	now := time.Now()
	st := MediaState{Available: true, Status: "paused", Title: "a", PausedMs: (15 * time.Minute).Milliseconds()}
	// O Windows diz que pausou há 15 min: some já na primeira leitura.
	if got := f.apply(st, now); got.Available {
		t.Fatal("hora da pausa do sistema ignorada")
	}
	st.PausedMs = (2 * time.Minute).Milliseconds()
	got := f.apply(st, now)
	if !got.Available {
		t.Fatal("pausa de 2 min sumiu")
	}
	data, _ := json.Marshal(got)
	if strings.Contains(string(data), "paused_ms") {
		t.Fatal("paused_ms vazou para o app")
	}
}

func TestIdleFilterTrackChangeAndDisable(t *testing.T) {
	f := &idleFilter{after: 10 * time.Minute}
	t0 := time.Now()
	a := MediaState{Available: true, Status: "paused", Title: "a"}
	b := MediaState{Available: true, Status: "paused", Title: "b"}
	f.apply(a, t0)
	if got := f.apply(b, t0.Add(11*time.Minute)); !got.Available {
		t.Fatal("faixa nova herdou o tempo da anterior")
	}
	f.setAfter(0)
	if got := f.apply(b, t0.Add(time.Hour)); !got.Available {
		t.Fatal("media_idle_minutes 0 deveria nunca esconder")
	}
}

func TestConfigMediaIdle(t *testing.T) {
	zero, five := 0, 5
	for _, c := range []struct {
		v    *int
		want time.Duration
	}{{nil, 10 * time.Minute}, {&zero, 0}, {&five, 5 * time.Minute}} {
		if got := (Config{MediaIdleMinutes: c.v}).mediaIdle(); got != c.want {
			t.Errorf("%v: %v, queria %v", c.v, got, c.want)
		}
	}
}
