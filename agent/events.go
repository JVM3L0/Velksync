package main

import (
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
	subs map[chan Event]struct{}
}

func NewHub() *Hub { return &Hub{subs: map[chan Event]struct{}{}} }

func (h *Hub) Subscribe() chan Event {
	ch := make(chan Event, 16)
	h.mu.Lock()
	h.subs[ch] = struct{}{}
	h.mu.Unlock()
	return ch
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
