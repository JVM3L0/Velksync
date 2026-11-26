package main

import (
	"bufio"
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Atualização: uma vez por dia o agente pergunta ao GitHub qual é a última
// versão publicada. Havendo uma mais nova, avisa (ícone no Windows, /api/info
// para o app). Instalar só acontece pelo menu do ícone, no próprio PC, e só
// depois de conferir a assinatura do SHA256SUMS com a chave pública abaixo.

const (
	releasesAPI    = "https://api.github.com/repos/JVM3L0/Velksync/releases/latest"
	updateInterval = 24 * time.Hour
	maxSetupBytes  = 64 << 20
)

// Chave pública Ed25519 das releases (a privada só existe nos Secrets do
// GitHub e com quem publica). Gerada com openssl; ver README.
//
//go:embed release_key.pem
var releaseKeyPEM []byte

func releasePublicKey() (ed25519.PublicKey, error) {
	block, _ := pem.Decode(releaseKeyPEM)
	if block == nil {
		return nil, errors.New("chave das releases ausente")
	}
	k, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	pub, ok := k.(ed25519.PublicKey)
	if !ok {
		return nil, errors.New("chave das releases não é Ed25519")
	}
	return pub, nil
}

// ---------- Versões ----------

// parseVersion lê "v0.6.0", "0.6.0" ou "0.6.0+7"; sufixo de pré-versão
// ("-beta") não conta como versão publicada.
func parseVersion(v string) ([3]int, bool) {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	if i := strings.IndexAny(v, "+"); i >= 0 {
		v = v[:i]
	}
	parts := strings.Split(v, ".")
	var out [3]int
	if len(parts) != 3 {
		return out, false
	}
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return out, false
		}
		out[i] = n
	}
	return out, true
}

// versionNewer diz se candidate é mais nova que current.
func versionNewer(candidate, current string) bool {
	c, ok1 := parseVersion(candidate)
	r, ok2 := parseVersion(current)
	if !ok1 || !ok2 {
		return false
	}
	for i := range c {
		if c[i] != r[i] {
			return c[i] > r[i]
		}
	}
	return false
}

// ---------- Release ----------

type releaseAsset struct {
	Name string `json:"name"`
	URL  string `json:"browser_download_url"`
	Size int64  `json:"size"`
}

type releaseInfo struct {
	Tag     string         `json:"tag_name"`
	Page    string         `json:"html_url"`
	Notes   string         `json:"body"`
	Draft   bool           `json:"draft"`
	Pre     bool           `json:"prerelease"`
	Assets  []releaseAsset `json:"assets"`
	Checked time.Time      `json:"checked_at"`
}

func (r releaseInfo) Version() string { return strings.TrimPrefix(r.Tag, "v") }

func (r releaseInfo) asset(name string) (releaseAsset, bool) {
	for _, a := range r.Assets {
		if a.Name == name {
			return a, true
		}
	}
	return releaseAsset{}, false
}

// downloadURLOK: só HTTPS e só do GitHub (o download redireciona para o
// servidor de arquivos dele).
func downloadURLOK(u *url.URL) bool {
	h := strings.ToLower(u.Hostname())
	return u.Scheme == "https" && u.User == nil &&
		(h == "github.com" || h == "api.github.com" || strings.HasSuffix(h, ".githubusercontent.com"))
}

// parseSums lê o SHA256SUMS ("<hash>  <arquivo>") num mapa arquivo → hash.
func parseSums(data []byte) map[string]string {
	out := map[string]string{}
	sc := bufio.NewScanner(bytes.NewReader(data))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) == 2 && len(f[0]) == 64 {
			out[strings.TrimPrefix(f[1], "*")] = strings.ToLower(f[0])
		}
	}
	return out
}

// verifyDownload confere a assinatura do SHA256SUMS e o hash do arquivo.
func verifyDownload(pub ed25519.PublicKey, sums, sig []byte, name string, data []byte) error {
	if len(sig) != ed25519.SignatureSize || !ed25519.Verify(pub, sums, sig) {
		return errors.New("assinatura do SHA256SUMS não confere")
	}
	want, ok := parseSums(sums)[name]
	if !ok {
		return fmt.Errorf("%s não está no SHA256SUMS", name)
	}
	got := sha256.Sum256(data)
	if hex.EncodeToString(got[:]) != want {
		return fmt.Errorf("%s não bate com o SHA256SUMS", name)
	}
	return nil
}

// ---------- Verificador ----------

type updater struct {
	statePath string
	enabled   func() bool
	onNew     func(releaseInfo) // chamado uma vez por versão nova
	fetch     func() (releaseInfo, error)
	now       func() time.Time
	client    *http.Client
	backoff   time.Duration // espera antes de tentar de novo

	mu       sync.Mutex
	latest   releaseInfo
	notified string
}

func newUpdater(configPath string, enabled func() bool, onNew func(releaseInfo)) *updater {
	u := &updater{
		statePath: filepath.Join(filepath.Dir(configPath), "update.json"),
		enabled:   enabled, onNew: onNew, now: time.Now, backoff: 2 * time.Second,
		client: &http.Client{Timeout: 2 * time.Minute, CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if len(via) > 5 || !downloadURLOK(r.URL) {
				return errOutsideGitHub
			}
			return nil
		}},
	}
	u.fetch = u.fetchLatest
	if data, err := os.ReadFile(u.statePath); err == nil {
		json.Unmarshal(data, &u.latest)
	}
	return u
}

// Available devolve a versão nova, se houver e a checagem estiver ligada.
func (u *updater) Available() (releaseInfo, bool) {
	if u == nil || !u.enabled() {
		return releaseInfo{}, false
	}
	u.mu.Lock()
	defer u.mu.Unlock()
	return u.latest, versionNewer(u.latest.Version(), version)
}

// due diz se já passou um dia desde a última consulta.
func (u *updater) due() bool {
	u.mu.Lock()
	defer u.mu.Unlock()
	return u.latest.Checked.IsZero() || u.now().Sub(u.latest.Checked) >= updateInterval
}

// Check consulta o GitHub se for a hora; erros só vão para o log.
func (u *updater) Check() {
	if !u.enabled() || !u.due() {
		u.announce()
		return
	}
	if _, err := u.refresh(); err != nil {
		log.Printf("atualização: %v", err)
		return
	}
	u.announce()
}

// CheckNow consulta o GitHub na hora, mesmo com a checagem automática
// desligada ou já feita hoje (o "Procurar atualizações agora").
func (u *updater) CheckNow() (releaseInfo, bool, error) {
	r, err := u.refresh()
	if err != nil {
		return releaseInfo{}, false, err
	}
	return r, versionNewer(r.Version(), version), nil
}

// Pending é a versão nova já conhecida, independente da checagem automática.
func (u *updater) Pending() (releaseInfo, bool) {
	u.mu.Lock()
	defer u.mu.Unlock()
	return u.latest, versionNewer(u.latest.Version(), version)
}

func (u *updater) refresh() (releaseInfo, error) {
	r, err := u.fetch()
	if err != nil {
		return releaseInfo{}, err
	}
	r.Checked = u.now()
	u.mu.Lock()
	u.latest = r
	u.mu.Unlock()
	if data, err := json.Marshal(r); err == nil {
		if err := os.WriteFile(u.statePath, data, 0o600); err != nil {
			log.Printf("atualização: não guardei o resultado: %v", err)
		}
	}
	return r, nil
}

func (u *updater) announce() {
	r, ok := u.Available()
	if !ok {
		return
	}
	u.mu.Lock()
	first := u.notified != r.Version()
	u.notified = r.Version()
	u.mu.Unlock()
	if first && u.onNew != nil {
		log.Printf("atualização disponível: %s", r.Version())
		u.onNew(r)
	}
}

// Loop confere logo depois de subir (sem atrasar o início) e depois a cada
// hora se já deu um dia: o PC desligado à noite não acumula atraso.
func (u *updater) Loop() {
	time.Sleep(time.Minute)
	for {
		u.Check()
		time.Sleep(time.Hour)
	}
}

var errOutsideGitHub = errors.New("redirecionamento para fora do GitHub")

// transientError é uma falha que vale tentar de novo (rede, servidor).
type transientError struct{ error }

func (e transientError) Unwrap() error { return e.error }

// retry repete f só nas falhas passageiras, esperando um pouco mais a cada vez.
func (u *updater) retry(f func() error) error {
	var err error
	for attempt := 1; ; attempt++ {
		err = f()
		var t transientError
		if attempt == 3 || !errors.As(err, &t) {
			return err
		}
		time.Sleep(time.Duration(attempt) * u.backoff)
	}
}

// get faz um GET no GitHub e traduz as falhas para quem vai ler o aviso.
func (u *updater) get(link, accept string, limit int64) ([]byte, error) {
	req, err := http.NewRequest("GET", link, nil)
	if err != nil {
		return nil, err
	}
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	req.Header.Set("User-Agent", "velksync-agent/"+version)
	res, err := u.client.Do(req)
	if errors.Is(err, errOutsideGitHub) {
		return nil, errors.New("a rede desviou o download para fora do GitHub (portal de Wi-Fi?)")
	}
	if err != nil {
		return nil, transientError{fmt.Errorf("sem conexão com o GitHub: %w", err)}
	}
	defer res.Body.Close()
	switch {
	case res.StatusCode == http.StatusTooManyRequests,
		res.StatusCode == http.StatusForbidden && res.Header.Get("X-RateLimit-Remaining") == "0":
		return nil, errors.New("o GitHub limitou as consultas; tente de novo em uma hora")
	case res.StatusCode >= 500:
		return nil, transientError{fmt.Errorf("o GitHub está fora do ar (%s)", res.Status)}
	case res.StatusCode != http.StatusOK:
		return nil, fmt.Errorf("o GitHub respondeu %s", res.Status)
	}
	data, err := io.ReadAll(io.LimitReader(res.Body, limit+1))
	if err != nil {
		return nil, transientError{fmt.Errorf("a conexão caiu no meio do download: %w", err)}
	}
	if int64(len(data)) > limit {
		return nil, errors.New("resposta grande demais")
	}
	return data, nil
}

func (u *updater) fetchLatest() (releaseInfo, error) {
	var data []byte
	err := u.retry(func() (err error) {
		data, err = u.get(releasesAPI, "application/vnd.github+json", 1<<20)
		return err
	})
	if err != nil {
		return releaseInfo{}, err
	}
	var r releaseInfo
	if err := json.Unmarshal(data, &r); err != nil {
		return releaseInfo{}, fmt.Errorf("resposta inesperada do GitHub: %w", err)
	}
	if r.Draft || r.Pre {
		return releaseInfo{}, errors.New("a última release é rascunho ou pré-versão")
	}
	if _, ok := parseVersion(r.Tag); !ok {
		return releaseInfo{}, fmt.Errorf("tag inesperada: %q", r.Tag)
	}
	return r, nil
}

func (u *updater) download(a releaseAsset, limit int64) ([]byte, error) {
	link, err := url.Parse(a.URL)
	if err != nil || !downloadURLOK(link) {
		return nil, fmt.Errorf("endereço inesperado para %s", a.Name)
	}
	if a.Size > limit {
		return nil, fmt.Errorf("%s grande demais", a.Name)
	}
	var data []byte
	err = u.retry(func() (err error) {
		data, err = u.get(link.String(), "", limit)
		return err
	})
	if err != nil {
		return nil, fmt.Errorf("%s: %w", a.Name, err)
	}
	return data, nil
}

// fetchVerified baixa o arquivo, o SHA256SUMS e a assinatura, e só devolve
// o arquivo se tudo conferir.
func (u *updater) fetchVerified(r releaseInfo, name string) ([]byte, error) {
	pub, err := releasePublicKey()
	if err != nil {
		return nil, err
	}
	get := func(n string, limit int64) ([]byte, error) {
		a, ok := r.asset(n)
		if !ok {
			return nil, fmt.Errorf("a release %s não tem %s", r.Tag, n)
		}
		return u.download(a, limit)
	}
	sums, err := get("SHA256SUMS", 64<<10)
	if err != nil {
		return nil, err
	}
	sig, err := get("SHA256SUMS.sig", 1<<10)
	if err != nil {
		return nil, err
	}
	data, err := get(name, maxSetupBytes)
	if err != nil {
		return nil, err
	}
	if err := verifyDownload(pub, sums, sig, name, data); err != nil {
		return nil, err
	}
	return data, nil
}

// releaseNotes resume as novidades para uma janela.
func releaseNotes(r releaseInfo, max int) string {
	notes := strings.TrimSpace(r.Notes)
	if notes == "" {
		return "Veja as novidades na página de versões."
	}
	notes = strings.ReplaceAll(notes, "\r\n", "\n")
	if r := []rune(notes); len(r) > max {
		notes = strings.TrimSpace(string(r[:max-1])) + "…"
	}
	return notes
}
