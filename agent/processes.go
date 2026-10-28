package main

import (
	"net/http"
	"runtime"
	"slices"
	"strings"
	"sync"
	"time"
)

// Processos que mais usam CPU e memória, só para ver (nada é encerrado por
// aqui). Mesmo programa com vários processos (navegadores) vira uma linha.

// procSample é uma leitura de um processo: tempo de CPU acumulado e memória.
type procSample struct {
	PID     uint32
	Name    string
	CPUTime time.Duration // usuário + sistema desde que o processo começou
	Mem     uint64        // bytes em uso (working set no Windows, RSS no Linux)
}

type ProcessInfo struct {
	Name  string  `json:"name"`
	Count int     `json:"count"` // quantos processos com esse nome
	CPU   float64 `json:"cpu"`   // % do total do PC (todos os núcleos = 100)
	Mem   uint64  `json:"mem"`
}

const topProcesses = 10

// processTop compara duas leituras e devolve os que mais usam CPU e memória.
func processTop(prev, cur []procSample, elapsed time.Duration, cpus int) (byCPU, byMem []ProcessInfo) {
	before := make(map[uint32]procSample, len(prev))
	for _, p := range prev {
		before[p.PID] = p
	}
	agg := map[string]*ProcessInfo{}
	var order []string
	wall := float64(elapsed) * float64(max(cpus, 1))
	for _, p := range cur {
		name := strings.TrimSpace(p.Name)
		if name == "" || p.PID == 0 {
			continue
		}
		key := strings.ToLower(name)
		info := agg[key]
		if info == nil {
			info = &ProcessInfo{Name: name}
			agg[key] = info
			order = append(order, key)
		}
		info.Count++
		info.Mem += p.Mem
		// Só conta CPU de quem já estava na leitura anterior (e é o mesmo processo).
		if b, ok := before[p.PID]; ok && strings.EqualFold(b.Name, p.Name) && p.CPUTime >= b.CPUTime && wall > 0 {
			info.CPU += float64(p.CPUTime-b.CPUTime) / wall * 100
		}
	}
	all := make([]ProcessInfo, 0, len(order))
	for _, k := range order {
		info := *agg[k]
		info.CPU = min(info.CPU, 100)
		all = append(all, info)
	}
	byCPU = slices.Clone(all)
	slices.SortStableFunc(byCPU, func(a, b ProcessInfo) int {
		if a.CPU != b.CPU {
			if a.CPU > b.CPU {
				return -1
			}
			return 1
		}
		return compareMem(a, b)
	})
	byMem = slices.Clone(all)
	slices.SortStableFunc(byMem, compareMem)
	return byCPU[:min(topProcesses, len(byCPU))], byMem[:min(topProcesses, len(byMem))]
}

func compareMem(a, b ProcessInfo) int {
	switch {
	case a.Mem > b.Mem:
		return -1
	case a.Mem < b.Mem:
		return 1
	}
	return strings.Compare(a.Name, b.Name)
}

// processWatch guarda a leitura anterior: a CPU sai da diferença entre duas.
// Só lê quando alguém pede (a seção aberta no app) e reaproveita o
// resultado por 2 s se vários pedirem juntos.
type processWatch struct {
	read func() ([]procSample, error)
	now  func() time.Time
	wait func(time.Duration)

	mu     sync.Mutex
	prev   []procSample
	prevAt time.Time
	last   map[string]any
	lastAt time.Time
}

func newProcessWatch() *processWatch {
	return &processWatch{read: readProcesses, now: time.Now, wait: time.Sleep}
}

func (w *processWatch) Top() (map[string]any, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	now := w.now()
	if w.last != nil && now.Sub(w.lastAt) < 2*time.Second {
		return w.last, nil
	}
	// Leitura antiga demais (seção fechada há tempo): mede de novo agora.
	if w.prev == nil || now.Sub(w.prevAt) > 30*time.Second {
		prev, err := w.read()
		if err != nil {
			return nil, err
		}
		w.prev, w.prevAt = prev, now
		w.wait(700 * time.Millisecond)
		now = w.now()
	}
	cur, err := w.read()
	if err != nil {
		return nil, err
	}
	byCPU, byMem := processTop(w.prev, cur, now.Sub(w.prevAt), runtime.NumCPU())
	w.prev, w.prevAt = cur, now
	w.last = map[string]any{"by_cpu": byCPU, "by_mem": byMem, "total": len(cur)}
	w.lastAt = now
	return w.last, nil
}

// GET /api/processes
func (s *Server) processes(w http.ResponseWriter, r *http.Request) {
	top, err := s.procs.Top()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "não deu para ler os processos: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, top)
}
