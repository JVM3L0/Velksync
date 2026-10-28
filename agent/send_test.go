package main

import (
	"encoding/json"
	"errors"
	"net/http/httptest"
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

func TestInbox(t *testing.T) {
	var opened, copied []string
	openLink = func(u string) error { opened = append(opened, u); return nil }
	copyText = func(s string) error { copied = append(copied, s); return nil }
	t.Cleanup(func() { openLink, copyText = openURL, writeClipboard })

	s := &Server{cfg: Config{Token: testMaster, Devices: []PairedDevice{{ID: "dev1", Name: "Pixel 9"}}}, hub: NewHub()}
	s.routes()
	post := func(body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		s.inbox(rec, withAuth(httptest.NewRequest("POST", "/api/inbox", strings.NewReader(body)), authDevice, "dev1"))
		return rec
	}

	if rec := post(`{"text":" https://youtu.be/x "}`); rec.Code != 200 || !strings.Contains(rec.Body.String(), "opened") {
		t.Fatalf("link: %d %s", rec.Code, rec.Body)
	}
	if len(opened) != 1 || opened[0] != "https://youtu.be/x" {
		t.Errorf("abriu %v", opened)
	}
	// Qualquer coisa que não seja http(s) vira texto copiado, nunca é aberta.
	for _, txt := range []string{"Rua das Flores, 12", "file:///C:/Windows/win.ini", "javascript:alert(1)", "cmd /c calc"} {
		if rec := post(`{"text":` + jsonString(txt) + `}`); rec.Code != 200 || !strings.Contains(rec.Body.String(), "copied") {
			t.Errorf("%q: %d %s", txt, rec.Code, rec.Body)
		}
	}
	if len(opened) != 1 || len(copied) != 4 {
		t.Errorf("abertos %v, copiados %v", opened, copied)
	}
	if rec := post(`{"text":"  "}`); rec.Code != 400 {
		t.Errorf("vazio: %d", rec.Code)
	}
	if rec := post(`{"text":"` + strings.Repeat("a", maxSendText+1) + `"}`); rec.Code != 413 {
		t.Errorf("grande demais: %d", rec.Code)
	}
	copyText = func(string) error { return errors.New("sem área de transferência") }
	if rec := post(`{"text":"oi"}`); rec.Code != 501 {
		t.Errorf("sem área de transferência: %d", rec.Code)
	}
	if h := s.history.List(10, false); len(h) != 5 || h[0].Kind != histReceive {
		t.Errorf("histórico: %+v", h)
	}
}

func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}
