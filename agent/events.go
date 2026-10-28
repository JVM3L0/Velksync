package main

import (
	"slices"
	"sync"
	"time"
)

// Event is something the PC asks the phone to do (notify, open_url,
// clipboard, vibrate). It is fanned out to every app connected to /api/events.
type Event struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
	URL  string `json:"url,omitempty"`
	Time int64  `json:"time"`
}

var validEventTypes = map[string]bool{"notify": true, "open_url": true, "clipboard": true, "vibrate": true}

type Hub struct {
	mu   sync.Mutex
	subs map[chan Event]string // canal → quem está nele (id do celular)
}

func NewHub() *Hub { return &Hub{subs: map[chan Event]string{}} }

// Subscribe abre um canal para o app de [client] (id do celular).
func (h *Hub) Subscribe(client string) chan Event {
	ch := make(chan Event, 16)
	h.mu.Lock()
	h.subs[ch] = client
	h.mu.Unlock()
	return ch
}

// Clients são os celulares com o app aberto agora, sem repetir.
func (h *Hub) Clients() []string {
	h.mu.Lock()
	defer h.mu.Unlock()
	var out []string
	for _, c := range h.subs {
		if c != "" && !slices.Contains(out, c) {
			out = append(out, c)
		}
	}
	slices.Sort(out)
	return out
}

// PublishTo entrega só aos canais de um celular.
func (h *Hub) PublishTo(client string, e Event) int {
	e.Time = time.Now().Unix()
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for ch, c := range h.subs {
		if c != client {
			continue
		}
		select {
		case ch <- e:
			n++
		default:
		}
	}
	return n
}

func (h *Hub) Unsubscribe(ch chan Event) {
	h.mu.Lock()
	delete(h.subs, ch)
	h.mu.Unlock()
}

// Publish returns how many clients received the event; slow clients drop it.
func (h *Hub) Publish(e Event) int {
	e.Time = time.Now().Unix()
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for ch := range h.subs {
		select {
		case ch <- e:
			n++
		default:
		}
	}
	return n
}
