package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"reflect"
	"strings"
	"sync"
	"time"
)

// Canal ao vivo (/api/live): em vez de o app perguntar a cada segundo, o
// agente coleta só enquanto alguém está olhando e manda a mídia só quando
// ela muda. Separado de /api/events, que leva ordens ao celular.

const (
	liveTick       = time.Second
	liveStatsEvery = 2 // ticks
	// Desempenho fica aberto em todas as abas do PC e a mídia na dela; o
	// terceiro cobre a troca de aba antes de o canal antigo fechar.
	maxLivePerClient = 3
	// Salto de posição maior que isso (fora o andamento normal) é um seek.
	liveSeekSlackMs = 1500
)

var (
	// Depois de um comando de mídia o player muda em instantes: lê de novo
	// nestes momentos em vez de esperar o próximo tique.
	liveBurst        = []time.Duration{150 * time.Millisecond, 400 * time.Millisecond, 800 * time.Millisecond, 1500 * time.Millisecond}
	liveTopics       = map[string]bool{"stats": true, "media": true}
	errTooManyStream = errors.New("canais ao vivo demais para este celular")
)

type liveMsg struct {
	topic string
	data  []byte
}

type liveSub struct {
	client string
	topics map[string]bool
	ch     chan liveMsg
}

type Live struct {
	stats func() any
	media func() MediaState
	tick  time.Duration
	burst []time.Duration
	kick  chan struct{}

	mu      sync.Mutex
	subs    map[*liveSub]struct{}
	running bool
	last    map[string][]byte // último envio por tópico, para quem chega agora
}

func newLive(stats func() any, media func() MediaState) *Live {
	return &Live{
		stats: stats, media: media, tick: liveTick, burst: liveBurst,
		kick: make(chan struct{}, 1), subs: map[*liveSub]struct{}{},
	}
}

// Clients conta os celulares com o canal ao vivo aberto (um celular pode ter
// mais de um canal).
func (l *Live) Clients() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	seen := map[string]bool{}
	for sub := range l.subs {
		seen[sub.client] = true
	}
	return len(seen)
}

// Kick avisa que a mídia deve mudar já (próxima, anterior, play, seek): o
// laço lê o player algumas vezes seguidas até ver a mudança. Sem ninguém
// inscrito não faz nada; vários seguidos viram uma rajada só.
func (l *Live) Kick() {
	l.mu.Lock()
	running := l.running
	l.mu.Unlock()
	if !running {
		return
	}
	select {
	case l.kick <- struct{}{}:
	default:
	}
}

func (l *Live) Subscribe(client string, topics map[string]bool) (*liveSub, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	n := 0
	for s := range l.subs {
		if s.client == client {
			n++
		}
	}
	if n >= maxLivePerClient {
		return nil, errTooManyStream
	}
	sub := &liveSub{client: client, topics: topics, ch: make(chan liveMsg, 8)}
	l.subs[sub] = struct{}{}
	for t := range topics {
		if data, ok := l.last[t]; ok {
			sub.ch <- liveMsg{t, data}
		}
	}
	if !l.running {
		l.running = true
		l.last = map[string][]byte{}
		go l.loop()
	}
	return sub, nil
}

func (l *Live) Unsubscribe(sub *liveSub) {
	l.mu.Lock()
	delete(l.subs, sub)
	l.mu.Unlock()
}

// wanted diz quais tópicos alguém quer; sem ninguém, o laço para.
func (l *Live) wanted() map[string]bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	w := map[string]bool{}
	for s := range l.subs {
		for t := range s.topics {
			w[t] = true
		}
	}
	if len(l.subs) == 0 {
		l.running = false
		l.last = nil
	}
	return w
}

func (l *Live) publish(topic string, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.last == nil {
		return // parou enquanto coletava
	}
	l.last[topic] = data
	for s := range l.subs {
		if !s.topics[topic] {
			continue
		}
		select {
		case s.ch <- liveMsg{topic, data}:
		default: // celular lento perde a mensagem; o próximo envio corrige
		}
	}
}

func (l *Live) loop() {
	t := time.NewTicker(l.tick)
	defer t.Stop()
	burst := time.NewTimer(time.Hour)
	burst.Stop()
	defer burst.Stop()
	step := -1 // posição na rajada depois de um Kick; -1 = sem rajada
	var prev *MediaState
	var prevAt time.Time
	// Lê o player e publica se mudou; diz se publicou.
	readMedia := func() bool {
		cur, now := l.media(), time.Now()
		if prev != nil && !mediaChanged(*prev, cur, now.Sub(prevAt)) {
			return false
		}
		l.publish("media", cur)
		prev, prevAt = &cur, now
		return true
	}
	for n := 0; ; n++ {
		w := l.wanted()
		if len(w) == 0 {
			return
		}
		if w["stats"] && n%liveStatsEvery == 0 {
			l.publish("stats", l.stats())
		}
		if w["media"] {
			readMedia()
		} else {
			prev = nil
		}
	wait:
		for {
			select {
			case <-t.C:
				break wait
			case <-l.kick:
				if w["media"] && len(l.burst) > 0 {
					step = 0
					burst.Reset(l.burst[0])
				}
			case <-burst.C:
				if step < 0 {
					continue
				}
				changed := readMedia()
				if step++; changed || step >= len(l.burst) {
					step = -1 // a mudança chegou (ou desistiu): volta ao ritmo normal
					continue
				}
				burst.Reset(l.burst[step] - l.burst[step-1])
			}
		}
	}
}

// mediaChanged ignora o andamento normal da posição: o app a calcula
// sozinho entre um envio e outro. Muda tudo o mais, ou um salto (seek).
func mediaChanged(prev, cur MediaState, since time.Duration) bool {
	p, c := prev, cur
	p.PositionMs, c.PositionMs = 0, 0
	if !reflect.DeepEqual(p, c) {
		return true
	}
	expected := prev.PositionMs
	if prev.Status == "playing" {
		expected += since.Milliseconds()
	}
	diff := cur.PositionMs - expected
	return diff > liveSeekSlackMs || diff < -liveSeekSlackMs
}

// GET /api/live?topics=stats,media
func (s *Server) liveFeed(w http.ResponseWriter, r *http.Request) {
	topics := map[string]bool{}
	for _, t := range strings.Split(r.URL.Query().Get("topics"), ",") {
		if !liveTopics[t] {
			writeErr(w, http.StatusBadRequest, "tópicos: stats, media")
			return
		}
		topics[t] = true
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErr(w, http.StatusInternalServerError, "streaming não suportado")
		return
	}
	sub, err := s.live.Subscribe(clientOf(r), topics)
	if err != nil {
		writeErr(w, http.StatusTooManyRequests, err.Error())
		return
	}
	defer s.live.Unsubscribe(sub)
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	fmt.Fprint(w, ": conectado\n\n")
	flusher.Flush()
	ping := time.NewTicker(20 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-ping.C:
			fmt.Fprint(w, ": ping\n\n")
		case m := <-sub.ch:
			if _, err := fmt.Fprintf(w, "event: %s\ndata: %s\n\n", m.topic, m.data); err != nil {
				log.Printf("ao vivo: %v", err)
				return
			}
		}
		flusher.Flush()
	}
}
