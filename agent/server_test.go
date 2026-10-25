package main

import (
	"bufio"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"
)

// startTLS sobe newHTTPServer numa porta livre e devolve o endereço e o pin.
func startTLS(t *testing.T, h http.Handler, tweak func(*http.Server)) (string, string) {
	t.Helper()
	cert, pin, err := tlsCertificate(testMaster, "teste")
	if err != nil {
		t.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	hs := newHTTPServer(ln.Addr().String(), h, cert)
	if tweak != nil {
		tweak(hs)
	}
	go hs.ServeTLS(ln, "", "")
	t.Cleanup(func() { hs.Close() })
	return ln.Addr().String(), pin
}

func TestServerRefusesOldTLS(t *testing.T) {
	addr, pin := startTLS(t, http.NotFoundHandler(), nil)
	old := pinnedTLS(pin)
	old.MinVersion, old.MaxVersion = tls.VersionTLS12, tls.VersionTLS12
	if c, err := tls.Dial("tcp", addr, old); err == nil {
		c.Close()
		t.Fatal("o agente aceitou TLS 1.2")
	}
	c, err := tls.Dial("tcp", addr, pinnedTLS(pin))
	if err != nil {
		t.Fatalf("TLS 1.3 com o pin certo: %v", err)
	}
	if v := c.ConnectionState().Version; v != tls.VersionTLS13 {
		t.Fatalf("versão negociada: %x", v)
	}
	c.Close()
}

func TestServerLimitsHeaderSize(t *testing.T) {
	addr, pin := startTLS(t, http.NotFoundHandler(), nil)
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: pinnedTLS(pin)}}
	req, _ := http.NewRequest("GET", "https://"+addr+"/", nil)
	req.Header.Set("X-Grande", strings.Repeat("a", 64<<10))
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusRequestHeaderFieldsTooLarge {
		t.Fatalf("cabeçalho de 64 KB: %d", res.StatusCode)
	}
}

// Sem WriteTimeout de propósito: o SSE precisa durar mais que o ReadTimeout.
func TestEventsOutliveReadTimeout(t *testing.T) {
	srv := &Server{cfg: Config{Name: "pc", Token: testMaster}, hub: NewHub()}
	addr, pin := startTLS(t, srv.routes(), func(hs *http.Server) { hs.ReadTimeout = 200 * time.Millisecond })
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: pinnedTLS(pin)}}
	req, _ := http.NewRequest("GET", "https://"+addr+"/api/events", nil)
	req.Header.Set("Authorization", "Bearer "+testMaster)
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	lines := bufio.NewScanner(res.Body)
	lines.Scan() // ": conectado"

	time.Sleep(600 * time.Millisecond)
	srv.hub.Publish(Event{Type: "notify", Text: "ainda aqui"})
	got := make(chan string, 1)
	go func() {
		for lines.Scan() {
			if strings.HasPrefix(lines.Text(), "data: ") {
				got <- lines.Text()
				return
			}
		}
		got <- fmt.Sprint("conexão fechada: ", lines.Err())
	}()
	select {
	case l := <-got:
		if !strings.Contains(l, "ainda aqui") {
			t.Fatal(l)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("evento não chegou depois do ReadTimeout")
	}
}
