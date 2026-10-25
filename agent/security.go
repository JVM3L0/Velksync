package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"net"
	"strings"
	"sync"
	"time"
)

// Tudo é derivado do token mestre da config. Como o dual boot usa o mesmo
// token nos dois sistemas, Windows e Linux têm a mesma chave TLS (mesmo pin)
// e aceitam as mesmas credenciais de celular sem sincronizar nada.

func derive(master, label string) []byte {
	m := hmac.New(sha256.New, []byte(master))
	m.Write([]byte(label))
	return m.Sum(nil)
}

// tlsKey deriva uma chave ECDSA P-256 determinística do token mestre.
func tlsKey(master string) (*ecdsa.PrivateKey, error) {
	n := elliptic.P256().Params().N
	d := new(big.Int).SetBytes(derive(master, "velksync tls key v1"))
	d.Mod(d, new(big.Int).Sub(n, big.NewInt(1)))
	d.Add(d, big.NewInt(1)) // 1 <= d < n
	return ecdsa.ParseRawPrivateKey(elliptic.P256(), d.FillBytes(make([]byte, 32)))
}

// tlsCertificate gera um certificado autoassinado para a chave derivada. O
// certificado muda a cada início (serial e validade), mas a chave pública não:
// o app fixa o hash da chave pública (SPKI), não o certificado.
func tlsCertificate(master, name string) (tls.Certificate, string, error) {
	key, err := tlsKey(master)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 64))
	tpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "Velksync " + name},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().AddDate(10, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key, Leaf: cert}, spkiPin(cert), nil
}

// pinFor calcula o pin a partir do token mestre (é o mesmo do certificado).
func pinFor(master string) (string, error) {
	key, err := tlsKey(master)
	if err != nil {
		return "", err
	}
	spki, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(spki)
	return hex.EncodeToString(sum[:]), nil
}

func spkiPin(cert *x509.Certificate) string {
	sum := sha256.Sum256(cert.RawSubjectPublicKeyInfo)
	return hex.EncodeToString(sum[:])
}

// pinnedTLS aceita só o certificado cuja chave pública tem o pin dado. Usado
// pelos comandos locais (send, pair, revoke) para falar com o próprio agente.
func pinnedTLS(pin string) *tls.Config {
	return &tls.Config{
		InsecureSkipVerify: true, // a verificação real é o pin abaixo
		VerifyConnection: func(cs tls.ConnectionState) error {
			if len(cs.PeerCertificates) == 0 || spkiPin(cs.PeerCertificates[0]) != pin {
				return errors.New("certificado do agente não confere com o pin")
			}
			return nil
		},
	}
}

// Credencial de celular: "<id>:<token>", com token = HMAC(mestre, id).
// O agente não guarda tokens; recalcula e compara. Revogar = listar o id.

func deviceToken(master, id string) string {
	return hex.EncodeToString(derive(master, "velksync device v1:"+id))
}

func newDeviceID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

type authResult int

const (
	authDenied authResult = iota
	authMaster            // token mestre via localhost (comandos do próprio PC)
	authDevice            // credencial de um celular pareado
)

// checkAuth valida o header Authorization. O token mestre só vale vindo do
// próprio PC; de fora, só credenciais de celular não revogadas.
func checkAuth(header, master string, remote net.IP, revoked func(id string) bool) (authResult, string) {
	cred, ok := strings.CutPrefix(header, "Bearer ")
	if !ok {
		return authDenied, ""
	}
	if remote != nil && remote.IsLoopback() && subtle.ConstantTimeCompare([]byte(cred), []byte(master)) == 1 {
		return authMaster, ""
	}
	id, token, ok := strings.Cut(cred, ":")
	if !ok || len(id) != 16 || revoked(id) {
		return authDenied, ""
	}
	if subtle.ConstantTimeCompare([]byte(token), []byte(deviceToken(master, id))) != 1 {
		return authDenied, ""
	}
	return authDevice, id
}

// Limiter bloqueia por alguns minutos um IP que erra a autenticação demais.
type Limiter struct {
	mu    sync.Mutex
	fails map[string]*failState
}

type failState struct {
	count int
	first time.Time
	until time.Time
}

const (
	maxFails    = 10
	failWindow  = time.Minute
	blockPeriod = 5 * time.Minute
)

func newLimiter() *Limiter { return &Limiter{fails: map[string]*failState{}} }

func (l *Limiter) Blocked(ip string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	f := l.fails[ip]
	if f == nil || time.Now().After(f.until) {
		return false, 0
	}
	return true, time.Until(f.until).Round(time.Second)
}

func (l *Limiter) Fail(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	f := l.fails[ip]
	if f == nil || now.Sub(f.first) > failWindow {
		f = &failState{first: now}
		l.fails[ip] = f
	}
	f.count++
	if f.count >= maxFails {
		f.until = now.Add(blockPeriod)
		f.count, f.first = 0, now
	}
	if len(l.fails) > 1024 { // não deixa um varredor encher a memória
		for k, v := range l.fails {
			if now.After(v.until) && now.Sub(v.first) > failWindow {
				delete(l.fails, k)
			}
		}
	}
}

func (l *Limiter) Success(ip string) {
	l.mu.Lock()
	delete(l.fails, ip)
	l.mu.Unlock()
}

func shortPin(pin string) string {
	if len(pin) < 16 {
		return pin
	}
	return fmt.Sprintf("%s %s %s %s", pin[0:4], pin[4:8], pin[8:12], pin[12:16])
}
