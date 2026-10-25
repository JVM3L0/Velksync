package main

import (
	"net/http"
	"runtime"
	"sync"
)

// Stats é um retrato do uso do PC. Campos que o sistema não expõe (ex.:
// temperatura no Windows) vêm nulos e o app esconde o medidor.
type Stats struct {
	CPUName       string   `json:"cpu_name,omitempty"`
	CPUPercent    float64  `json:"cpu_percent"`
	CPUThreads    int      `json:"cpu_threads"`
	MemUsed       uint64   `json:"mem_used"`
	MemTotal      uint64   `json:"mem_total"`
	DiskUsed      uint64   `json:"disk_used"`
	DiskTotal     uint64   `json:"disk_total"`
	GPU           *GPUStat `json:"gpu"`
	CPUTemp       *float64 `json:"cpu_temp"`
	UptimeSeconds uint64   `json:"uptime_seconds"`
}

type GPUStat struct {
	Name      string   `json:"name,omitempty"`
	Percent   float64  `json:"percent"`
	VRAMUsed  uint64   `json:"vram_used"`
	VRAMTotal uint64   `json:"vram_total"`
	Temp      *float64 `json:"temp"`
}

// cpuSampler guarda a leitura anterior: uso de CPU é sempre a diferença entre
// duas amostras (o app consulta a cada ~2 s).
type cpuSampler struct {
	mu          sync.Mutex
	idle, total uint64
}

func (c *cpuSampler) percent(idle, total uint64) float64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	// Primeira amostra ou contador reiniciado: ainda não há intervalo para medir.
	reset := c.total == 0 || total < c.total || idle < c.idle
	dIdle, dTotal := idle-c.idle, total-c.total
	c.idle, c.total = idle, total
	if reset || dTotal == 0 {
		return 0
	}
	return clampPercent(100 * float64(dTotal-dIdle) / float64(dTotal))
}

func clampPercent(v float64) float64 {
	switch {
	case v < 0:
		return 0
	case v > 100:
		return 100
	}
	return v
}

// Criados no primeiro pedido: comandos como token e pair não pagam o custo.
var (
	statsCollector = sync.OnceValue(newCollector)
	cpuName        = sync.OnceValue(readCPUName)
)

// GET /api/stats (credencial de celular ou mestre): só leitura.
func (s *Server) stats(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, currentStats())
}

func currentStats() any {
	st := statsCollector().collect()
	st.CPUThreads = runtime.NumCPU()
	st.CPUName = cpuName()
	return st
}
