package main

import (
	"bytes"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const testMaster = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func TestTLSKeyIsDeterministic(t *testing.T) {
	// Dual boot: o mesmo token mestre tem que gerar o mesmo pin nos dois sistemas.
	_, pin1, err := tlsCertificate(testMaster, "a")
	if err != nil {
		t.Fatal(err)
	}
	_, pin2, _ := tlsCertificate(testMaster, "b")
	pin3, _ := pinFor(testMaster)
	if pin1 != pin2 || pin1 != pin3 {
		t.Fatalf("pins diferentes para o mesmo token: %s %s %s", pin1, pin2, pin3)
	}
	other, _ := pinFor(strings.Repeat("f", 64))
	if other == pin1 {
		t.Fatal("tokens diferentes geraram o mesmo pin")
	}
}

func TestCheckAuth(t *testing.T) {
	loopback, lan := net.ParseIP("127.0.0.1"), net.ParseIP("192.168.3.5")
	id := "0011223344556677"
	cred := id + ":" + deviceToken(testMaster, id)
	none := func(string) bool { return false }
	cases := []struct {
		name   string
		header string
		ip     net.IP
		revoke bool
		want   authResult
	}{
		{"mestre no localhost", "Bearer " + testMaster, loopback, false, authMaster},
		{"mestre pela rede é recusado", "Bearer " + testMaster, lan, false, authDenied},
		{"celular pela rede", "Bearer " + cred, lan, false, authDevice},
		{"celular revogado", "Bearer " + cred, lan, true, authDenied},
		{"token de outro id", "Bearer ffffffffffffffff:" + deviceToken(testMaster, id), lan, false, authDenied},
		{"token adulterado", "Bearer " + cred[:len(cred)-1] + "0", lan, false, authDenied},
		{"id com tamanho errado", "Bearer abc:" + deviceToken(testMaster, "abc"), lan, false, authDenied},
		{"sem Bearer", cred, lan, false, authDenied},
		{"vazio", "", lan, false, authDenied},
	}
	for _, c := range cases {
		revoked := none
		if c.revoke {
			revoked = func(x string) bool { return x == id }
		}
		if got, _ := checkAuth(c.header, testMaster, c.ip, revoked); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestLimiterBlocksAndResets(t *testing.T) {
	l := newLimiter()
	for i := 0; i < maxFails-1; i++ {
		l.Fail("1.2.3.4")
	}
	if blocked, _ := l.Blocked("1.2.3.4"); blocked {
		t.Fatal("bloqueou antes do limite")
	}
	l.Fail("1.2.3.4")
	if blocked, _ := l.Blocked("1.2.3.4"); !blocked {
		t.Fatal("não bloqueou no limite")
	}
	if blocked, _ := l.Blocked("5.6.7.8"); blocked {
		t.Fatal("bloqueou outro IP")
	}
	l.Success("1.2.3.4")
	if blocked, _ := l.Blocked("1.2.3.4"); blocked {
		t.Fatal("sucesso não limpou o bloqueio")
	}
}

func TestPairingCodeIsSingleUseAndExpires(t *testing.T) {
	p := newPairings()
	code := p.start()
	if !p.claim(code, "a") {
		t.Fatal("código válido recusado")
	}
	if p.claim(code, "b") {
		t.Fatal("código aceito duas vezes")
	}
	expired := p.start()
	p.codes[expired].expires = time.Now().Add(-time.Second)
	if p.claim(expired, "c") {
		t.Fatal("código expirado aceito")
	}
	if p.claim("inexistente", "d") {
		t.Fatal("código inventado aceito")
	}
}

// Fluxo HTTP completo: pareamento, uso da credencial, revogação e rotas só do PC.
func TestPairingFlowOverHTTP(t *testing.T) {
	srv := &Server{cfg: Config{Name: "pc", Token: testMaster, CommandTimeout: 5}, hub: NewHub()}
	ts := httptest.NewServer(srv.routes())
	defer ts.Close()

	call := func(method, path, auth string, body any) (int, map[string]any) {
		var buf bytes.Buffer
		if body != nil {
			json.NewEncoder(&buf).Encode(body)
		}
		req, _ := http.NewRequest(method, ts.URL+path, &buf)
		if auth != "" {
			req.Header.Set("Authorization", "Bearer "+auth)
		}
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]any
		json.NewDecoder(res.Body).Decode(&out)
		return res.StatusCode, out
	}

	if code, _ := call("GET", "/api/info", "", nil); code != http.StatusUnauthorized {
		t.Fatalf("sem credencial: %d", code)
	}
	_, start := call("POST", "/api/pair/start", testMaster, nil)
	code, claim := call("POST", "/api/pair/claim", "", map[string]string{"code": start["code"].(string), "device": "teste"})
	if code != http.StatusOK || claim["token"] == testMaster {
		t.Fatalf("claim: %d %v (nunca pode devolver o token mestre)", code, claim)
	}
	cred := claim["device_id"].(string) + ":" + claim["token"].(string)
	if code, _ := call("GET", "/api/info", cred, nil); code != http.StatusOK {
		t.Fatalf("credencial do celular: %d", code)
	}
	if code, _ := call("POST", "/api/pair/start", cred, nil); code != http.StatusForbidden {
		t.Fatalf("celular gerando pareamento: %d", code)
	}
	if code, _ := call("POST", "/api/devices/revoke", cred, map[string]string{"target": "teste"}); code != http.StatusForbidden {
		t.Fatalf("celular revogando: %d", code)
	}
	if code, _ := call("POST", "/api/devices/revoke", testMaster, map[string]string{"target": "teste"}); code != http.StatusOK {
		t.Fatalf("revogar pelo PC: %d", code)
	}
	if code, _ := call("GET", "/api/info", cred, nil); code != http.StatusUnauthorized {
		t.Fatalf("credencial revogada ainda aceita: %d", code)
	}
}

func TestShellDisabledByDefault(t *testing.T) {
	if defaultConfig().AllowShell {
		t.Fatal("terminal livre não pode vir ligado por padrão")
	}
}
