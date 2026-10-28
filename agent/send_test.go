package main

import (
	"strings"
	"testing"
)

func TestClipEvent(t *testing.T) {
	for _, tc := range []struct {
		in, kind string
	}{
		{"https://youtu.be/dQw4w9WgXcQ", "open_url"},
		{"  http://192.168.3.5:8080/x?y=1  ", "open_url"},
		{"olha isso https://x.com", "clipboard"},
		{"javascript:alert(1)", "clipboard"},
		{"file:///C:/Windows/win.ini", "clipboard"},
		{"Rua das Flores, 12", "clipboard"},
		{"linha 1\nhttps://x.com", "clipboard"},
	} {
		e, err := clipEvent(tc.in)
		if err != nil || e.Type != tc.kind {
			t.Errorf("clipEvent(%q) = %+v %v, queria %s", tc.in, e, err, tc.kind)
		}
	}
	if _, err := clipEvent("   \n "); err != errNothingCopied {
		t.Errorf("vazio: %v", err)
	}
	if _, err := clipEvent(strings.Repeat("a", maxSendText+1)); err == nil {
		t.Error("aceitou texto acima do limite")
	}
}

func TestClipPreview(t *testing.T) {
	if got := clipPreview(""); got != "Nada copiado" {
		t.Error(got)
	}
	if got := clipPreview("https://example.com/a"); got != "Link: https://example.com/a" {
		t.Error(got)
	}
	if got := clipPreview(strings.Repeat("x", 100)); !strings.HasPrefix(got, "Texto: \u201c") || len([]rune(got)) > 50 {
		t.Error(got)
	}
}

func TestHubPublishTo(t *testing.T) {
	h := NewHub()
	a1, a2, b := h.Subscribe("pixel"), h.Subscribe("pixel"), h.Subscribe("galaxy")
	if got := h.Clients(); strings.Join(got, ",") != "galaxy,pixel" {
		t.Errorf("Clients = %v", got)
	}
	if n := h.PublishTo("pixel", Event{Type: "clipboard", Text: "oi"}); n != 2 {
		t.Errorf("entregou a %d canais", n)
	}
	if len(a1) != 1 || len(a2) != 1 || len(b) != 0 {
		t.Error("foi para o celular errado")
	}
	h.Unsubscribe(b)
	if got := h.Clients(); len(got) != 1 {
		t.Errorf("depois de sair: %v", got)
	}
	if n := h.PublishTo("galaxy", Event{Type: "notify"}); n != 0 {
		t.Error("entregou a quem saiu")
	}
}
