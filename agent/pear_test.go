package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"
)

// pearFake imita a API do Pear: /auth responde allow (200) ou deny (403) e
// /api/v1/song devolve a música e o endereço da capa (servida por ele mesmo).
type pearFake struct {
	srv    *httptest.Server
	allow  bool
	title  string
	tokens int
}

var pngHeader = []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR")

func newPearFake(t *testing.T, allow bool) *pearFake {
	f := &pearFake{allow: allow, title: "Otonoke"}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /auth/{id}", func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("id") != "Velksync" || !f.allow {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		f.tokens++
		json.NewEncoder(w).Encode(map[string]string{"accessToken": "tok-123"})
	})
	mux.HandleFunc("GET /api/v1/song", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer tok-123" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"title": f.title, "imageSrc": f.srv.URL + "/img.png"})
	})
	mux.HandleFunc("GET /img.png", func(w http.ResponseWriter, r *http.Request) { w.Write(pngHeader) })
	f.srv = httptest.NewServer(mux)
	t.Cleanup(f.srv.Close)
	return f
}

type saved struct {
	mu     sync.Mutex
	token  string
	denied bool
	calls  int
}

func (s *saved) save(token string, denied bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.token, s.denied, s.calls = token, denied, s.calls+1
}

func (s *saved) wait(t *testing.T, calls int) {
	t.Helper()
	for range 200 {
		s.mu.Lock()
		n := s.calls
		s.mu.Unlock()
		if n >= calls {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("o acesso não foi gravado")
}

func testPear(f *pearFake, token string, denied bool, s *saved) *pearClient {
	p := newPearClient(token, denied, s.save)
	p.base = f.srv.URL
	host := strings.TrimPrefix(f.srv.URL, "http://")
	p.imageOK = func(u *url.URL) bool { return u.Host == host }
	return p
}

func TestPearAuthorizeAllowedThenArt(t *testing.T) {
	f := newPearFake(t, true)
	s := &saved{}
	p := testPear(f, "", false, s)
	p.MaybeAuthorize()
	s.wait(t, 1)
	if s.token != "tok-123" || s.denied || !p.Ready() {
		t.Fatalf("token %q denied %v", s.token, s.denied)
	}
	p.MaybeAuthorize() // já tem acesso: não pergunta de novo
	data, ctype, err := p.Art("  otonoke ")
	if err != nil || ctype != "image/png" || len(data) == 0 {
		t.Fatalf("Art: %v %s", err, ctype)
	}
	if f.tokens != 1 {
		t.Errorf("perguntou %d vezes", f.tokens)
	}
}

func TestPearDeniedIsRemembered(t *testing.T) {
	f := newPearFake(t, false)
	s := &saved{}
	p := testPear(f, "", false, s)
	p.MaybeAuthorize()
	s.wait(t, 1)
	if !s.denied || s.token != "" || p.Ready() {
		t.Fatalf("recusa não gravada: %+v", s)
	}
	// Quem negou não é perguntado de novo, nem depois de reiniciar o agente.
	p2 := testPear(f, "", true, s)
	p2.now = func() time.Time { return time.Now().Add(time.Hour) }
	p2.MaybeAuthorize()
	time.Sleep(50 * time.Millisecond)
	if s.calls != 1 {
		t.Error("perguntou de novo depois de negado")
	}
}

func TestPearArtChecks(t *testing.T) {
	f := newPearFake(t, true)
	s := &saved{}
	p := testPear(f, "tok-123", false, s)

	f.title = "Outra música"
	if _, _, err := p.Art("Otonoke"); err == nil || !strings.Contains(err.Error(), "outra música") {
		t.Errorf("música diferente: %v", err)
	}
	// Endereço fora da lista de servidores de imagem: recusado.
	f.title = "Otonoke"
	p.imageOK = pearImageURLOK
	if _, _, err := p.Art("Otonoke"); err == nil || !strings.Contains(err.Error(), "fora dos servidores") {
		t.Errorf("host fora da lista: %v", err)
	}
	// Token que o Pear não aceita mais: esquece e grava a limpeza.
	p2 := testPear(f, "velho", false, s)
	if _, _, err := p2.Art("Otonoke"); err == nil || p2.Ready() || s.token != "" || s.calls != 1 {
		t.Errorf("token revogado: err %v ready %v saved %+v", err, p2.Ready(), s)
	}
}

func TestPearImageURLOK(t *testing.T) {
	for raw, want := range map[string]bool{
		"https://lh3.googleusercontent.com/abc=w544-h544": true,
		"https://i.ytimg.com/vi/x/maxresdefault.jpg":      true,
		"http://lh3.googleusercontent.com/abc":            false,
		"https://lh3.googleusercontent.com.evil.com/abc":  false,
		"https://user@lh3.googleusercontent.com/abc":      false,
		"https://127.0.0.1/abc":                           false,
		"file:///C:/Windows/win.ini":                      false,
	} {
		u, _ := url.Parse(raw)
		if got := pearImageURLOK(u); got != want {
			t.Errorf("%s = %v", raw, got)
		}
	}
}

func TestBiggerImage(t *testing.T) {
	for raw, want := range map[string]string{
		"https://yt3.googleusercontent.com/abc=w544-h544-l90-rj": "https://yt3.googleusercontent.com/abc=w1200-h1200-l90-rj",
		"https://lh3.googleusercontent.com/x=w120-h120":          "https://lh3.googleusercontent.com/x=w1200-h1200",
		"https://i.ytimg.com/vi/x/hqdefault.jpg":                 "https://i.ytimg.com/vi/x/hqdefault.jpg",
	} {
		u, _ := url.Parse(raw)
		biggerImage(u)
		if u.String() != want {
			t.Errorf("%s → %s", raw, u)
		}
	}
}

func TestIsPear(t *testing.T) {
	if !isPear("com.github.th-ch.youtube-music") || isPear("Helium._crx_cinhimbnkkghhklpknlkffjgod") {
		t.Error("isPear")
	}
}

// Logo depois da troca o Pear pode ainda estar na música anterior: o
// Prefetch falha, espera pearArtRetry e tenta de novo.
func TestPearPrefetchRetries(t *testing.T) {
	f := newPearFake(t, true)
	p := testPear(f, "tok-123", false, &saved{})
	now := time.Now()
	p.now = func() time.Time { return now }
	settle := func() {
		t.Helper()
		for range 200 {
			p.mu.Lock()
			busy := p.fetching
			p.mu.Unlock()
			if !busy {
				return
			}
			time.Sleep(5 * time.Millisecond)
		}
		t.Fatal("a busca não terminou")
	}

	f.title = "Anterior"
	p.Prefetch("Otonoke")
	settle()
	if _, _, ok := p.HD("Otonoke"); ok {
		t.Fatal("guardou a capa de outra música")
	}
	f.title = "Otonoke"
	p.Prefetch("Otonoke") // cedo demais: nem tenta
	settle()
	if _, _, ok := p.HD("Otonoke"); ok {
		t.Fatal("tentou de novo antes da hora")
	}
	now = now.Add(pearArtRetry)
	p.Prefetch("Otonoke")
	settle()
	if data, ctype, ok := p.HD("otonoke"); !ok || ctype != "image/png" || len(data) == 0 {
		t.Fatalf("capa não chegou: %v %s", ok, ctype)
	}
}
