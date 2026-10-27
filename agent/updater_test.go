package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestVersionNewer(t *testing.T) {
	for _, tc := range []struct {
		a, b string
		want bool
	}{
		{"v0.6.0", "0.5.0", true},
		{"0.5.1", "0.5.0", true},
		{"1.0.0", "0.99.9", true},
		{"0.10.0", "0.9.0", true},
		{"0.5.0", "0.5.0", false},
		{"0.4.9", "0.5.0", false},
		{"0.6.0+7", "0.5.0", true},
		{"0.6.0-beta", "0.5.0", false}, // pré-versão não conta
		{"lixo", "0.5.0", false},
		{"0.6", "0.5.0", false},
	} {
		if got := versionNewer(tc.a, tc.b); got != tc.want {
			t.Errorf("versionNewer(%q, %q) = %v", tc.a, tc.b, got)
		}
	}
}

func signedRelease(t *testing.T, files map[string][]byte) (ed25519.PublicKey, []byte, []byte) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var sums strings.Builder
	for name, data := range files {
		h := sha256.Sum256(data)
		sums.WriteString(hex.EncodeToString(h[:]) + "  " + name + "\n")
	}
	return pub, []byte(sums.String()), ed25519.Sign(priv, []byte(sums.String()))
}

func TestVerifyDownload(t *testing.T) {
	setup := []byte("instalador de verdade")
	pub, sums, sig := signedRelease(t, map[string][]byte{"velksync-setup-0.6.0-windows-amd64.exe": setup})
	name := "velksync-setup-0.6.0-windows-amd64.exe"

	if err := verifyDownload(pub, sums, sig, name, setup); err != nil {
		t.Fatalf("release legítima recusada: %v", err)
	}
	// Arquivo trocado (o hash não bate).
	if err := verifyDownload(pub, sums, sig, name, []byte("malware")); err == nil {
		t.Error("aceitou instalador trocado")
	}
	// SHA256SUMS trocado junto com o arquivo, sem a chave privada.
	evil := []byte("malware")
	h := sha256.Sum256(evil)
	forged := []byte(hex.EncodeToString(h[:]) + "  " + name + "\n")
	if err := verifyDownload(pub, forged, sig, name, evil); err == nil {
		t.Error("aceitou SHA256SUMS adulterado")
	}
	// Assinado com outra chave.
	_, other, _ := ed25519.GenerateKey(rand.Reader)
	if err := verifyDownload(pub, sums, ed25519.Sign(other, sums), name, setup); err == nil {
		t.Error("aceitou assinatura de outra chave")
	}
	// Arquivo que não está na lista.
	if err := verifyDownload(pub, sums, sig, "outro.exe", setup); err == nil {
		t.Error("aceitou arquivo fora do SHA256SUMS")
	}
	if err := verifyDownload(pub, sums, sig[:10], name, setup); err == nil {
		t.Error("aceitou assinatura truncada")
	}
}

func TestParseSums(t *testing.T) {
	h := strings.Repeat("ab", 32)
	got := parseSums([]byte(h + "  a.exe\n" + strings.ToUpper(h) + " *b.apk\nlixo\n"))
	if got["a.exe"] != h || got["b.apk"] != h || len(got) != 2 {
		t.Errorf("parseSums = %v", got)
	}
}

func TestDownloadURLOK(t *testing.T) {
	for raw, want := range map[string]bool{
		"https://github.com/JVM3L0/Velksync/releases/download/v0.6.0/x.exe":       true,
		"https://objects.githubusercontent.com/github-production-release-asset/x": true,
		"https://release-assets.githubusercontent.com/x":                          true,
		"http://github.com/x":                 false,
		"https://github.com.evil.com/x":       false,
		"https://evilgithubusercontent.com/x": false,
		"https://user@github.com/x":           false,
	} {
		u, _ := url.Parse(raw)
		if got := downloadURLOK(u); got != want {
			t.Errorf("%s = %v", raw, got)
		}
	}
}

func TestUpdaterChecksOncePerDay(t *testing.T) {
	dir := t.TempDir()
	clock := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	enabled := true
	var announced []string
	u := newUpdater(filepath.Join(dir, "config.json"), func() bool { return enabled },
		func(r releaseInfo) { announced = append(announced, r.Version()) })
	u.now = func() time.Time { return clock }
	fetches := 0
	u.fetch = func() (releaseInfo, error) {
		fetches++
		return releaseInfo{Tag: "v99.0.0", Page: "https://github.com/x"}, nil
	}

	u.Check()
	u.Check() // mesma hora: não consulta de novo
	clock = clock.Add(23 * time.Hour)
	u.Check()
	if fetches != 1 {
		t.Fatalf("consultou %d vezes em menos de um dia", fetches)
	}
	if r, ok := u.Available(); !ok || r.Version() != "99.0.0" {
		t.Fatalf("Available = %v %v", r, ok)
	}
	if len(announced) != 1 {
		t.Errorf("avisou %d vezes da mesma versão", len(announced))
	}
	clock = clock.Add(2 * time.Hour)
	u.Check()
	if fetches != 2 {
		t.Errorf("depois de um dia: %d consultas", fetches)
	}

	// O estado sobrevive a reiniciar o agente: não consulta de novo no mesmo dia.
	u2 := newUpdater(filepath.Join(dir, "config.json"), func() bool { return true }, nil)
	u2.now = func() time.Time { return clock.Add(time.Hour) }
	u2.fetch = func() (releaseInfo, error) { t.Error("consultou logo depois de reiniciar"); return releaseInfo{}, nil }
	u2.Check()

	// Desligado: não consulta nem anuncia.
	enabled = false
	clock = clock.Add(48 * time.Hour)
	u.Check()
	if _, ok := u.Available(); ok || fetches != 2 {
		t.Errorf("desligado, mas consultou ou anunciou (consultas %d)", fetches)
	}
}

func TestUpdaterIgnoresOlderAndErrors(t *testing.T) {
	u := newUpdater(filepath.Join(t.TempDir(), "config.json"), func() bool { return true }, nil)
	u.fetch = func() (releaseInfo, error) { return releaseInfo{Tag: "v0.0.1"}, nil }
	u.Check()
	if _, ok := u.Available(); ok {
		t.Error("versão antiga anunciada como nova")
	}
	u2 := newUpdater(filepath.Join(t.TempDir(), "config.json"), func() bool { return true }, nil)
	u2.fetch = func() (releaseInfo, error) { return releaseInfo{}, errors.New("sem internet") }
	u2.Check()
	if _, ok := u2.Available(); ok || !u2.due() {
		t.Error("erro de rede deveria permitir tentar de novo")
	}
}

func TestReleaseKeyLoads(t *testing.T) {
	if _, err := releasePublicKey(); err != nil {
		t.Fatalf("chave pública das releases: %v", err)
	}
}

func TestReleaseNotes(t *testing.T) {
	if got := releaseNotes(releaseInfo{Notes: "linha 1\r\nlinha 2"}, 100); got != "linha 1\nlinha 2" {
		t.Errorf("%q", got)
	}
	if got := releaseNotes(releaseInfo{Notes: strings.Repeat("a", 50)}, 10); len([]rune(got)) != 10 {
		t.Errorf("%q", got)
	}
}
