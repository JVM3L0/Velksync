package main

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

// Energia agendada: "desligar em 30 min" ou "quando a mídia parar". O relógio
// fica no agente, então vale igual no Windows e no Linux e dá para cancelar.
// Fica só na memória de propósito: se o agente reiniciar, nada desliga sozinho.

var scheduleActions = map[string]bool{"shutdown": true, "sleep": true}

type PowerSchedule struct {
	Action string `json:"action"`
	// Quando executa (unix, segundos); 0 enquanto espera a mídia parar.
	At             int64 `json:"at,omitempty"`
	WhenMediaStops bool  `json:"when_media_stops,omitempty"`
}

type Scheduler struct {
	run   func(action string) // executa de verdade; trocado nos testes
	warn  func(text string)   // aviso no celular
	media func() MediaState

	minDelay, maxDelay time.Duration
	warning            time.Duration // aviso antes de executar
	stoppedFor         time.Duration // mídia parada por isso conta como "acabou"
	maxWatch           time.Duration // desiste de esperar a mídia depois disso
	poll               time.Duration // intervalo para olhar a mídia

	mu     sync.Mutex
	cur    *PowerSchedule
	cancel chan struct{}
}

func newScheduler(run func(string), warn func(string), media func() MediaState) *Scheduler {
	return &Scheduler{
		run: run, warn: warn, media: media,
		minDelay: time.Minute, maxDelay: 24 * time.Hour,
		warning: time.Minute, stoppedFor: 10 * time.Second,
		maxWatch: 12 * time.Hour, poll: 2 * time.Second,
	}
}

func (s *Scheduler) Current() *PowerSchedule {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cur == nil {
		return nil
	}
	c := *s.cur
	return &c
}

func (s *Scheduler) Cancel() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cur == nil {
		return false
	}
	close(s.cancel)
	s.cur, s.cancel = nil, nil
	return true
}

// After agenda a ação para daqui a delay, com aviso 1 min antes.
func (s *Scheduler) After(action string, delay time.Duration) (*PowerSchedule, error) {
	if !scheduleActions[action] {
		return nil, fmt.Errorf("só dá para agendar shutdown ou sleep")
	}
	if delay < s.minDelay || delay > s.maxDelay {
		return nil, errors.New("o atraso precisa ficar entre 1 minuto e 24 horas")
	}
	stop := s.replace(&PowerSchedule{Action: action, At: time.Now().Add(delay).Unix()})
	go func() {
		if !sleepOrCancel(delay-s.warning, stop) {
			return
		}
		s.warn(fmt.Sprintf("O PC vai %s em 1 minuto. Cancele pelo app se quiser.", actionVerb(action)))
		if sleepOrCancel(min(s.warning, delay), stop) && s.finish(stop) {
			s.run(action)
		}
	}()
	return s.Current(), nil
}

// WhenMediaStops espera a mídia que está tocando parar, avisa e executa
// 1 min depois, a não ser que ela volte a tocar nesse meio-tempo.
func (s *Scheduler) WhenMediaStops(action string) (*PowerSchedule, error) {
	if !scheduleActions[action] {
		return nil, fmt.Errorf("só dá para agendar shutdown ou sleep")
	}
	if s.media().Status != "playing" {
		return nil, errors.New("nada tocando no PC agora")
	}
	stop := s.replace(&PowerSchedule{Action: action, WhenMediaStops: true})
	go func() {
		deadline := time.Now().Add(s.maxWatch)
		for time.Now().Before(deadline) {
			if !s.waitMediaStop(stop) {
				return
			}
			s.warn(fmt.Sprintf("A mídia parou: o PC vai %s em 1 minuto.", actionVerb(action)))
			s.setAt(stop, time.Now().Add(s.warning).Unix())
			if !s.quietFor(s.warning, stop) {
				continue // voltou a tocar: espera parar de novo
			}
			if s.finish(stop) {
				s.run(action)
			}
			return
		}
		s.finish(stop)
	}()
	return s.Current(), nil
}

// waitMediaStop volta true quando a mídia fica parada por mediaStoppedFor.
func (s *Scheduler) waitMediaStop(stop chan struct{}) bool {
	var since time.Time
	for {
		if s.media().Status != "playing" {
			if since.IsZero() {
				since = time.Now()
			}
			if time.Since(since) >= s.stoppedFor {
				return true
			}
		} else {
			since = time.Time{}
		}
		if !sleepOrCancel(s.poll, stop) {
			return false
		}
	}
}

// quietFor espera d sem a mídia voltar a tocar; false se voltou ou cancelou.
func (s *Scheduler) quietFor(d time.Duration, stop chan struct{}) bool {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		if !sleepOrCancel(min(s.poll, time.Until(end)), stop) {
			return false
		}
		if s.media().Status == "playing" {
			s.setAt(stop, 0)
			return false
		}
	}
	return true
}

func (s *Scheduler) replace(p *PowerSchedule) chan struct{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cancel != nil {
		close(s.cancel)
	}
	s.cur, s.cancel = p, make(chan struct{})
	return s.cancel
}

func (s *Scheduler) setAt(stop chan struct{}, at int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cancel == stop {
		s.cur.At = at
	}
}

// finish limpa o agendamento se ainda for o mesmo; false se foi trocado.
func (s *Scheduler) finish(stop chan struct{}) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cancel != stop {
		return false
	}
	s.cur, s.cancel = nil, nil
	return true
}

func sleepOrCancel(d time.Duration, stop chan struct{}) bool {
	if d <= 0 {
		return true
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return true
	case <-stop:
		return false
	}
}

func actionVerb(action string) string {
	if action == "sleep" {
		return "suspender"
	}
	return "desligar"
}

func runPower(action string) {
	cmd, err := powerCommand(action)
	if err != nil {
		log.Printf("energia agendada: %v", err)
		return
	}
	log.Printf("energia agendada: %s", action)
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("falha em %s: %v %s", action, err, out)
	}
}

func (s *Server) schedulePower(w http.ResponseWriter, r *http.Request, action string, delayS int, when string) {
	var p *PowerSchedule
	var err error
	switch {
	case when == "media_stopped" && delayS == 0:
		p, err = s.schedule.WhenMediaStops(action)
	case when == "" && delayS > 0:
		p, err = s.schedule.After(action, time.Duration(delayS)*time.Second)
	default:
		err = errors.New(`use delay_s (segundos) ou when: "media_stopped"`)
	}
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	log.Printf("energia agendada: %+v (pedido de %s)", *p, r.RemoteAddr)
	writeJSON(w, http.StatusAccepted, p)
}

// DELETE /api/power/schedule
func (s *Server) cancelSchedule(w http.ResponseWriter, r *http.Request) {
	if !s.schedule.Cancel() {
		writeErr(w, http.StatusNotFound, "nada agendado")
		return
	}
	log.Printf("energia agendada cancelada por %s", r.RemoteAddr)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
