package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"
)

const maxOutput = 64 << 10

type Server struct {
	cfg        Config
	configPath string
	hub        *Hub
	pairs      *Pairings
	limiter    *Limiter
	live       *Live
	schedule   *Scheduler
	ui         desktop
	notices    *noticeBatcher
	mu         sync.Mutex // protege cfg.Devices, cfg.Revoked e cfg.TrayNotices
}

func (s *Server) routes() http.Handler {
	if s.pairs == nil {
		s.pairs = newPairings()
	}
	if s.limiter == nil {
		s.limiter = newLimiter()
	}
	if s.live == nil {
		s.live = newLive(currentStats, currentMedia)
	}
	if s.ui == nil {
		s.ui = noDesktop{}
	}
	if s.notices == nil {
		s.notices = newNoticeBatcher(func(title, text string) { s.ui.Notify(title, text) })
	}
	if s.schedule == nil {
		s.schedule = newScheduler(func(action string) {
			if s.confirmPower(action, "O agendamento") {
				runPower(action)
			}
		}, func(text string) {
			s.hub.Publish(Event{Type: "notify", Text: text})
		}, currentMedia)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/pair/start", masterOnly(s.pairStart))
	mux.HandleFunc("GET /api/pair/status", masterOnly(s.pairStatus))
	mux.HandleFunc("POST /api/pair/window", masterOnly(s.pairWindow))
	mux.HandleFunc("GET /api/devices", masterOnly(s.listDevices))
	mux.HandleFunc("POST /api/devices/revoke", masterOnly(s.revokeDevice))
	mux.HandleFunc("GET /api/info", s.info)
	mux.HandleFunc("GET /api/stats", s.stats)
	mux.HandleFunc("GET /api/presence", s.presenceKey)
	mux.HandleFunc("GET /api/media", s.mediaState)
	mux.HandleFunc("GET /api/media/art", s.mediaArt)
	mux.HandleFunc("POST /api/media/seek", s.mediaSeek)
	mux.HandleFunc("POST /api/media/volume", s.mediaVolume)
	mux.HandleFunc("POST /api/media/{action}", s.mediaCommand)
	mux.HandleFunc("POST /api/power", s.power)
	mux.HandleFunc("DELETE /api/power/schedule", s.cancelSchedule)
	mux.HandleFunc("GET /api/commands", s.listCommands)
	mux.HandleFunc("POST /api/commands/{id}", s.runCommand)
	mux.HandleFunc("POST /api/shell", s.shell)
	mux.HandleFunc("GET /api/events", s.events)
	mux.HandleFunc("GET /api/live", s.liveFeed)
	mux.HandleFunc("POST /api/push", s.push)

	// Única rota sem credencial: protegida pelo código de uso único do QR.
	root := http.NewServeMux()
	root.HandleFunc("POST /api/pair/claim", s.limited(s.pairClaim))
	root.Handle("/", s.auth(mux))
	return root
}

func remoteIP(r *http.Request) net.IP {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return nil
	}
	return net.ParseIP(host)
}

// limited recusa IPs bloqueados por excesso de falhas.
func (s *Server) limited(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if blocked, wait := s.limiter.Blocked(remoteIP(r).String()); blocked {
			w.Header().Set("Retry-After", fmt.Sprint(int(wait.Seconds())))
			writeErr(w, http.StatusTooManyRequests, fmt.Sprintf("muitas tentativas inválidas; tente de novo em %s", wait))
			return
		}
		next(w, r)
	}
}

func (s *Server) auth(next http.Handler) http.Handler {
	return s.limited(func(w http.ResponseWriter, r *http.Request) {
		ip := remoteIP(r)
		a, id := checkAuth(r.Header.Get("Authorization"), s.cfg.Token, ip, s.isRevoked)
		if a == authDenied {
			s.limiter.Fail(ip.String())
			log.Printf("401 %s %s de %s", r.Method, r.URL.Path, r.RemoteAddr)
			writeErr(w, http.StatusUnauthorized, "credencial inválida ou revogada; pareie de novo pelo QR")
			return
		}
		s.limiter.Success(ip.String())
		next.ServeHTTP(w, withAuth(r, a, id))
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func decode(r *http.Request, v any) error {
	return json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20)).Decode(v)
}

func (s *Server) info(w http.ResponseWriter, r *http.Request) {
	host, _ := os.Hostname()
	local, _ := r.Context().Value(http.LocalAddrContextKey).(net.Addr)
	writeJSON(w, http.StatusOK, map[string]any{
		"name":        s.cfg.Name,
		"hostname":    host,
		"os":          runtime.GOOS,
		"version":     version,
		"mac":         macFor(addrIP(local), false),
		"allow_shell": s.cfg.AllowShell,
		// O app usa o que existir aqui e cai no comportamento antigo no resto.
		"features": []string{"live", "presence", "schedule"},
		"schedule": s.schedule.Current(),
	})
}

func (s *Server) power(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Action string `json:"action"`
		// Opcionais: agendam em vez de executar agora.
		DelayS int    `json:"delay_s"`
		When   string `json:"when"` // "media_stopped"
	}
	if err := decode(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "json inválido")
		return
	}
	if req.DelayS != 0 || req.When != "" {
		s.schedulePower(w, r, req.Action, req.DelayS, req.When)
		return
	}
	cmd, err := powerCommand(req.Action)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	by := s.deviceName(clientOf(r))
	// Com alguém no PC (sessão desbloqueada), dá tempo de cancelar; o app
	// mostra "desliga em N s" a partir de grace_s.
	var grace time.Duration
	if s.ui.Present() {
		grace = s.cfg.powerGrace()
	}
	log.Printf("energia: %s (pedido de %s, %s, contagem %s)", req.Action, by, r.RemoteAddr, grace)
	writeJSON(w, http.StatusAccepted, map[string]any{"status": "ok", "grace_s": int(grace.Seconds())})
	go func() {
		if grace > 0 {
			if !s.ui.AskPower(req.Action, by, grace) {
				s.powerCancelled(req.Action)
				return
			}
		} else {
			// Dá tempo da resposta chegar no celular antes da máquina cair.
			time.Sleep(500 * time.Millisecond)
		}
		if out, err := cmd.CombinedOutput(); err != nil {
			log.Printf("falha em %s: %v %s", req.Action, err, out)
		}
	}()
}

// confirmPower é a contagem para quem já esperou (agendamentos): na hora se
// ninguém está no PC, senão espera a contagem.
func (s *Server) confirmPower(action, by string) bool {
	grace := s.cfg.powerGrace()
	if grace == 0 || !s.ui.Present() || s.ui.AskPower(action, by, grace) {
		return true
	}
	s.powerCancelled(action)
	return false
}

func (s *Server) powerCancelled(action string) {
	log.Printf("energia: %s cancelado no PC", action)
	s.hub.Publish(Event{Type: "notify", Text: fmt.Sprintf("Cancelado no PC: ele não vai %s.", powerVerb(action))})
}

// notice mostra um aviso no PC, se estiverem ligados no menu do ícone.
func (s *Server) notice(title, text string) {
	s.mu.Lock()
	on := s.cfg.trayNotices()
	s.mu.Unlock()
	if on {
		s.notices.Add(title, text)
	}
}

// deviceName traduz o id da credencial no nome dado ao parear.
func (s *Server) deviceName(client string) string {
	if client == "master" {
		return "Este PC"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, d := range s.cfg.Devices {
		if d.ID == client {
			return d.Name
		}
	}
	return "Um celular"
}

func (s *Server) listCommands(w http.ResponseWriter, r *http.Request) {
	type item struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	list := []item{}
	for _, c := range s.cfg.Commands {
		if c.ForCurrentOS() != "" {
			list = append(list, item{c.ID, c.Name})
		}
	}
	writeJSON(w, http.StatusOK, list)
}

func (s *Server) runCommand(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	for _, c := range s.cfg.Commands {
		if c.ID == id && c.ForCurrentOS() != "" {
			log.Printf("comando %q (pedido de %s)", id, r.RemoteAddr)
			s.notice(s.deviceName(clientOf(r)), fmt.Sprintf("rodou \"%s\"", clip(c.Name, 60)))
			writeJSON(w, http.StatusOK, s.execute(r.Context(), c.ForCurrentOS()))
			return
		}
	}
	writeErr(w, http.StatusNotFound, "comando não encontrado para este sistema")
}

func (s *Server) shell(w http.ResponseWriter, r *http.Request) {
	if !s.cfg.AllowShell {
		writeErr(w, http.StatusForbidden, "terminal livre desativado (allow_shell=false na config do agente)")
		return
	}
	var req struct {
		Command string `json:"command"`
	}
	if err := decode(r, &req); err != nil || strings.TrimSpace(req.Command) == "" {
		writeErr(w, http.StatusBadRequest, "comando vazio")
		return
	}
	log.Printf("shell %q (pedido de %s)", req.Command, r.RemoteAddr)
	s.notice(s.deviceName(clientOf(r)), "rodou no terminal: "+clip(req.Command, 80))
	writeJSON(w, http.StatusOK, s.execute(r.Context(), req.Command))
}

type limitedBuffer struct{ bytes.Buffer }

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if room := maxOutput - b.Len(); room > 0 {
		if len(p) > room {
			b.Buffer.Write(p[:room])
		} else {
			b.Buffer.Write(p)
		}
	}
	return len(p), nil
}

type runResult struct {
	ExitCode   int    `json:"exit_code"`
	Output     string `json:"output"`
	DurationMs int64  `json:"duration_ms"`
	TimedOut   bool   `json:"timed_out"`
}

func (s *Server) execute(parent context.Context, line string) runResult {
	ctx, cancel := context.WithTimeout(parent, time.Duration(s.cfg.CommandTimeout)*time.Second)
	defer cancel()
	cmd := shellCommand(ctx, line)
	var out limitedBuffer
	cmd.Stdout, cmd.Stderr = &out, &out
	// Processos filhos que herdam o stdout não podem segurar a resposta para sempre.
	cmd.WaitDelay = 2 * time.Second
	start := time.Now()
	err := cmd.Run()
	res := runResult{Output: outputText(out.Bytes()), DurationMs: time.Since(start).Milliseconds()}
	var exitErr *exec.ExitError
	switch {
	case err == nil:
	case errors.Is(ctx.Err(), context.DeadlineExceeded):
		res.TimedOut, res.ExitCode = true, -1
	case errors.As(err, &exitErr):
		res.ExitCode = exitErr.ExitCode()
	default:
		res.ExitCode = -1
		res.Output += fmt.Sprintf("\n[velksync] %v", err)
	}
	return res
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErr(w, http.StatusInternalServerError, "streaming não suportado")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	ch := s.hub.Subscribe()
	defer s.hub.Unsubscribe(ch)
	log.Printf("app conectado aos eventos: %s", r.RemoteAddr)
	fmt.Fprint(w, ": conectado\n\n")
	flusher.Flush()
	ping := time.NewTicker(20 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			log.Printf("app desconectado dos eventos: %s", r.RemoteAddr)
			return
		case <-ping.C:
			fmt.Fprint(w, ": ping\n\n")
		case e := <-ch:
			data, _ := json.Marshal(e)
			fmt.Fprintf(w, "data: %s\n\n", data)
		}
		flusher.Flush()
	}
}

func (s *Server) push(w http.ResponseWriter, r *http.Request) {
	var e Event
	if err := decode(r, &e); err != nil || !validEventTypes[e.Type] {
		writeErr(w, http.StatusBadRequest, "evento inválido (tipos: notify, open_url, clipboard, vibrate)")
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"delivered": s.hub.Publish(e)})
}
