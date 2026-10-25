package main

import (
	"encoding/hex"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

const testNonce = "00112233445566778899aabbccddeeff"

// Vetor fixo do protocolo: o mesmo valor é conferido nos testes do app, então
// mudar a derivação ou a prova de um lado só quebra os dois.
const (
	vectorSecret = "120d7cc7d299ac345c70dfb3195c33ab097e96c84334a88b894f08e6a0cafaa9"
	vectorProof  = "3c090eea3b8640c738fe38f842e98be8b0304923be5e015147caaac3049fd3b2"
)

func TestPresenceVector(t *testing.T) {
	s := presenceSecret(testMaster)
	if hex.EncodeToString(s) != vectorSecret || presenceProof(s, testNonce, "windows") != vectorProof {
		t.Fatal("o protocolo de presença mudou: atualize o vetor aqui e em app/test/presence_test.dart")
	}
}

func TestPresenceProof(t *testing.T) {
	secret := presenceSecret(testMaster)
	if hex.EncodeToString(secret) == testMaster || len(secret) != 32 {
		t.Fatal("o segredo de presença tem que ser derivado, nunca o mestre")
	}
	raw, ok := answerPresence(secret, presenceProbe+testNonce)
	if !ok {
		t.Fatal("desafio válido recusado")
	}
	var r map[string]string
	json.Unmarshal(raw, &r)
	if r["nonce"] != testNonce || r["os"] != runtime.GOOS || r["proof"] != presenceProof(secret, testNonce, runtime.GOOS) {
		t.Fatalf("resposta: %v", r)
	}
	if r["proof"] == presenceProof(presenceSecret(strings.Repeat("f", 64)), testNonce, runtime.GOOS) {
		t.Fatal("outro segredo gerou a mesma prova")
	}
	if r["proof"] == presenceProof(secret, testNonce, "outro-so") {
		t.Fatal("a prova não está ligada ao sistema")
	}
	for _, bad := range []string{
		presenceProbe + testNonce[:30],       // curto
		presenceProbe + "zz" + testNonce[2:], // não é hex
		presenceProbe + testNonce + "00",     // longo
		"OUTRA " + testNonce,
	} {
		if _, ok := answerPresence(secret, bad); ok {
			t.Fatalf("desafio inválido aceito: %q", bad)
		}
	}
}

func TestUDPLimiter(t *testing.T) {
	var l udpLimiter
	a, b := net.ParseIP("192.168.3.5"), net.ParseIP("192.168.3.6")
	for i := 0; i < udpRepliesPerSecond; i++ {
		if !l.allow(a) {
			t.Fatalf("resposta %d bloqueada cedo demais", i)
		}
	}
	if l.allow(a) {
		t.Fatal("passou do limite por segundo")
	}
	if !l.allow(b) {
		t.Fatal("o limite de um IP afetou outro")
	}
	l.window = l.window.Add(-time.Second)
	if !l.allow(a) {
		t.Fatal("o limite não reiniciou depois de 1 s")
	}
}

func TestDiscoveryOverUDP(t *testing.T) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	secret := presenceSecret(testMaster)
	go serveUDP(conn, discoveryHandler("pc", 41100, secret))

	ask := func(msg string) string {
		c, err := net.DialUDP("udp4", nil, conn.LocalAddr().(*net.UDPAddr))
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		c.Write([]byte(msg))
		c.SetReadDeadline(time.Now().Add(time.Second))
		buf := make([]byte, 512)
		n, err := c.Read(buf)
		if err != nil {
			return ""
		}
		return string(buf[:n])
	}
	found := ask(discoveryProbe)
	if !strings.Contains(found, `"name":"pc"`) || strings.Contains(found, testMaster) || strings.Contains(found, hex.EncodeToString(secret)) {
		t.Fatalf("descoberta: %s", found)
	}
	if !strings.Contains(ask(presenceProbe+testNonce), presenceProof(secret, testNonce, runtime.GOOS)) {
		t.Fatal("desafio de presença sem prova")
	}
	if got := ask("qualquer coisa"); got != "" {
		t.Fatalf("respondeu a lixo: %s", got)
	}
}

func TestPresenceExportHasNoMasterToken(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	cfg := defaultConfig()
	cfg.Token = testMaster
	if err := saveConfig(cfgPath, cfg); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(dir, "presence.json")
	if err := presenceExportCmd(cfgPath, []string{"-out", out}); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(out)
	if strings.Contains(string(raw), testMaster) {
		t.Fatal("o arquivo de presença contém o token mestre")
	}
	if !strings.Contains(string(raw), hex.EncodeToString(presenceSecret(testMaster))) {
		t.Fatalf("arquivo sem o segredo: %s", raw)
	}
	if fi, _ := os.Stat(out); runtime.GOOS != "windows" && fi.Mode().Perm() != 0o600 {
		t.Fatalf("permissão %v, esperado 0600", fi.Mode().Perm())
	}
}

func TestPresenceKeyNeedsAuth(t *testing.T) {
	srv := &Server{cfg: Config{Name: "pc", Token: testMaster}, hub: NewHub()}
	ts := httptest.NewServer(srv.routes())
	defer ts.Close()
	res, _ := http.Get(ts.URL + "/api/presence")
	res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("sem credencial: %d", res.StatusCode)
	}
	req, _ := http.NewRequest("GET", ts.URL+"/api/presence", nil)
	req.Header.Set("Authorization", "Bearer "+testMaster)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]string
	json.NewDecoder(res.Body).Decode(&body)
	if body["secret"] != hex.EncodeToString(presenceSecret(testMaster)) {
		t.Fatalf("segredo: %v", body)
	}
}
