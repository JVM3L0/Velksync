package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func targz(t *testing.T, name string, data []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o755, Size: int64(len(data)), Typeflag: tar.TypeReg}); err != nil {
		t.Fatal(err)
	}
	tw.Write(data)
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func TestExtractAgent(t *testing.T) {
	got, err := extractAgent(targz(t, "./velksync-agent", []byte("binário")))
	if err != nil || string(got) != "binário" {
		t.Fatalf("extractAgent = %q, %v", got, err)
	}
	for name, data := range map[string][]byte{
		"sem o binário":   targz(t, "./outro", []byte("x")),
		"em subpasta":     targz(t, "x/velksync-agent", []byte("x")),
		"não é um pacote": []byte("<html>"),
	} {
		if _, err := extractAgent(data); err == nil {
			t.Errorf("%s: aceitou", name)
		}
	}
}

func TestReplaceBinary(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "velksync-agent")
	os.WriteFile(target, []byte("antigo"), 0o755)
	read := func(p string) string { b, _ := os.ReadFile(p); return string(b) }

	for name, bin := range map[string]string{
		"não roda":     "lixo",
		"sai com erro": "#!/bin/sh\nexit 1\n",
		"outra versão": "#!/bin/sh\necho velksync-agent 0.0.1\n",
	} {
		if err := replaceBinary(target, []byte(bin), "9.9.9"); err == nil {
			t.Errorf("%s: aceitou", name)
		}
		if read(target) != "antigo" {
			t.Fatalf("%s: trocou o binário", name)
		}
	}

	novo := "#!/bin/sh\necho velksync-agent 9.9.9\n"
	if err := replaceBinary(target, []byte(novo), "9.9.9"); err != nil {
		t.Fatal(err)
	}
	if read(target) != novo || read(target+".old") != "antigo" {
		t.Error("troca ou cópia da anterior errada")
	}
	if err := replaceBinary(target, []byte(novo), "9.9.9"); err != nil || read(target+".old") != "antigo" {
		t.Errorf("instalar de novo perdeu a anterior: %v", err)
	}
	if left, _ := filepath.Glob(filepath.Join(dir, ".velksync-*")); len(left) != 0 {
		t.Errorf("sobraram temporários: %v", left)
	}
}

type roundTrip func(*http.Request) (*http.Response, error)

func (f roundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestDownloadRetries(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status []int // 0 = sem rede
		calls  int
		ok     bool
	}{
		{"volta depois de falhas passageiras", []int{0, 502, 200}, 3, true},
		{"desiste na terceira", []int{500, 500, 500}, 3, false},
		{"404 não repete", []int{404}, 1, false},
		{"limite do GitHub não repete", []int{429}, 1, false},
	} {
		calls := 0
		u := &updater{client: &http.Client{Transport: roundTrip(func(*http.Request) (*http.Response, error) {
			code := tc.status[calls]
			calls++
			if code == 0 {
				return nil, errors.New("sem rede")
			}
			return &http.Response{StatusCode: code, Header: http.Header{}, Body: io.NopCloser(strings.NewReader("ok"))}, nil
		})}}
		_, err := u.download(releaseAsset{Name: "x", URL: "https://github.com/x"}, 10)
		if calls != tc.calls || (err == nil) != tc.ok {
			t.Errorf("%s: %d chamadas, erro %v", tc.name, calls, err)
		}
	}
}

func TestInAgentUnit(t *testing.T) {
	base := "0::/user.slice/user-1000.slice/user@1000.service/app.slice/"
	if !inAgentUnit(base + "velksync-agent.service\n") {
		t.Error("não reconheceu o próprio serviço")
	}
	for _, other := range []string{"app-kitty.scope", "outro.service", "meu-velksync-agent.service", ""} {
		if inAgentUnit(base + other + "\n") {
			t.Errorf("aceitou %q", other)
		}
	}
}

func TestBlockedRedirect(t *testing.T) {
	calls := 0
	u := newUpdater(filepath.Join(t.TempDir(), "config.json"), func() bool { return true }, nil)
	u.client.Transport = roundTrip(func(*http.Request) (*http.Response, error) {
		calls++
		return &http.Response{StatusCode: 302, Header: http.Header{"Location": {"https://portal.example/"}}, Body: http.NoBody}, nil
	})
	_, err := u.download(releaseAsset{Name: "x", URL: "https://github.com/x"}, 10)
	if calls != 1 || err == nil || !strings.Contains(err.Error(), "fora do GitHub") {
		t.Errorf("%d chamadas, erro %v", calls, err)
	}
}
