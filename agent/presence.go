package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"
)

// Sinal de presença: um processo mínimo que sobe no boot, antes do login, e
// só sabe provar "este PC está ligado". Não lê a config principal nem o token
// mestre; tem apenas um segredo derivado dele, que serve para nada além disso.
// Quando a sessão começa, o agente completo atende o resto pela HTTPS.

const presenceProbe = "VELKSYNC_PRESENCE "

// PresenceFile é o que o serviço de presença lê: nada que dê acesso ao PC.
type PresenceFile struct {
	Secret string `json:"secret"`
	Name   string `json:"name"`
	Port   int    `json:"port"`
}

func presenceSecret(master string) []byte { return derive(master, "velksync presence v1") }

// presenceProof liga a resposta ao desafio do celular e ao sistema que
// respondeu, para uma resposta antiga não servir de novo nem trocar de SO.
func presenceProof(secret []byte, nonce, osName string) string {
	m := hmac.New(sha256.New, secret)
	fmt.Fprintf(m, "presence|%s|%s", nonce, osName)
	return hex.EncodeToString(m.Sum(nil))
}

// answerPresence devolve a resposta a um desafio "VELKSYNC_PRESENCE <nonce>",
// com nonce de 32 caracteres hex (128 bits) escolhido pelo celular.
func answerPresence(secret []byte, msg string) ([]byte, bool) {
	nonce, ok := strings.CutPrefix(msg, presenceProbe)
	if !ok || len(nonce) != 32 {
		return nil, false
	}
	if _, err := hex.DecodeString(nonce); err != nil {
		return nil, false
	}
	reply, _ := json.Marshal(map[string]string{
		"os":    runtime.GOOS,
		"nonce": nonce,
		"proof": presenceProof(secret, nonce, runtime.GOOS),
	})
	return reply, true
}

// udpLimiter segura respostas por IP: UDP não tem handshake, então sem isso
// o agente poderia ser usado para refletir tráfego contra outra máquina.
type udpLimiter struct {
	mu     sync.Mutex
	window time.Time
	counts map[string]int
}

const udpRepliesPerSecond = 10

func (l *udpLimiter) allow(ip net.IP) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if now.Sub(l.window) >= time.Second || l.counts == nil {
		l.window, l.counts = now, map[string]int{}
	}
	key := ip.String()
	if l.counts[key] >= udpRepliesPerSecond {
		return false
	}
	l.counts[key]++
	return true
}

// serveUDP responde na porta de descoberta com handle; sem resposta, ignora.
func serveUDP(conn *net.UDPConn, handle func(msg string, from *net.UDPAddr) []byte) {
	var limit udpLimiter
	buf := make([]byte, 128)
	for {
		n, from, err := conn.ReadFromUDP(buf)
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			continue
		}
		if reply := handle(string(buf[:n]), from); reply != nil && limit.allow(from.IP) {
			conn.WriteToUDP(reply, from)
		}
	}
}

// discoveryHandler atende a busca da rede e o desafio de presença; serve
// tanto ao agente completo quanto ao serviço de presença.
func discoveryHandler(name string, port int, secret []byte) func(string, *net.UDPAddr) []byte {
	host, _ := os.Hostname()
	return func(msg string, from *net.UDPAddr) []byte {
		if msg == discoveryProbe {
			reply, _ := json.Marshal(map[string]any{
				"name":     name,
				"hostname": host,
				"os":       runtime.GOOS,
				"port":     port,
				"mac":      macFor(from.IP, true),
			})
			return reply
		}
		if reply, ok := answerPresence(secret, msg); ok {
			return reply
		}
		return nil
	}
}

// presenceExportCmd grava o arquivo do serviço de presença. Roda como você
// (precisa da config); o instalador depois restringe quem pode lê-lo.
func presenceExportCmd(configPath string, args []string) error {
	fl := flag.NewFlagSet("presence-export", flag.ExitOnError)
	out := fl.String("out", "", "arquivo a gravar")
	fl.Parse(args)
	if *out == "" {
		return errors.New("use: presence-export -out <arquivo>")
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	data, _ := json.Marshal(PresenceFile{Secret: hex.EncodeToString(presenceSecret(cfg.Token)), Name: cfg.Name, Port: cfg.Port})
	return os.WriteFile(*out, data, 0o600)
}

// presenceCmd é o serviço que sobe no boot. Se o agente completo já estiver
// com a porta, sai com erro e o agendador tenta de novo mais tarde.
func presenceCmd(args []string) error {
	fl := flag.NewFlagSet("presence", flag.ExitOnError)
	file := fl.String("file", "", "arquivo gerado por presence-export")
	fl.Parse(args)
	raw, err := os.ReadFile(*file)
	if err != nil {
		return err
	}
	var pf PresenceFile
	if err := json.Unmarshal(raw, &pf); err != nil {
		return err
	}
	secret, err := hex.DecodeString(pf.Secret)
	if err != nil || len(secret) < 32 {
		return errors.New("segredo de presença inválido")
	}
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{Port: discoveryPort})
	if err != nil {
		return err
	}
	serveUDP(conn, discoveryHandler(pf.Name, pf.Port, secret))
	return nil
}

// presenceKey entrega o segredo de presença ao celular já autenticado, para
// ele verificar o PC antes do login sem precisar parear de novo.
func (s *Server) presenceKey(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"secret": hex.EncodeToString(presenceSecret(s.cfg.Token))})
}
