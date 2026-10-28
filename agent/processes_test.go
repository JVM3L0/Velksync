package main

import (
	"math"
	"os"
	"testing"
	"time"
)

func TestProcessTopAggregatesAndSorts(t *testing.T) {
	prev := []procSample{
		{PID: 1, Name: "chrome.exe", CPUTime: 1 * time.Second},
		{PID: 2, Name: "chrome.exe", CPUTime: 2 * time.Second},
		{PID: 3, Name: "Code.exe", CPUTime: 5 * time.Second},
		{PID: 9, Name: "velho.exe", CPUTime: 1 * time.Second},
	}
	cur := []procSample{
		{PID: 1, Name: "chrome.exe", CPUTime: 1400 * time.Millisecond, Mem: 300 << 20},
		{PID: 2, Name: "Chrome.exe", CPUTime: 2400 * time.Millisecond, Mem: 500 << 20}, // mesmo programa
		{PID: 3, Name: "Code.exe", CPUTime: 5200 * time.Millisecond, Mem: 900 << 20},
		{PID: 9, Name: "outro.exe", CPUTime: 50 * time.Second, Mem: 1 << 20}, // PID reaproveitado: não conta
		{PID: 4, Name: "novo.exe", CPUTime: 3 * time.Second, Mem: 10 << 20},  // sem leitura anterior
		{PID: 0, Name: "System Idle Process"},
	}
	top := processTop(prev, cur, time.Second, 4, false)
	byCPU, byMem := top["by_cpu"].([]ProcessInfo), top["by_mem"].([]ProcessInfo)
	if _, ok := top["by_gpu"]; ok {
		t.Error("sem GPU por processo, não deveria ter by_gpu")
	}
	// chrome: (0,4 + 0,4) s em 1 s × 4 núcleos = 20%; Code: 0,2 s → 5%.
	if byCPU[0].Name != "chrome.exe" || byCPU[0].Count != 2 || math.Abs(byCPU[0].CPU-20) > 0.01 {
		t.Errorf("1º por CPU: %+v", byCPU[0])
	}
	if byCPU[1].Name != "Code.exe" || math.Abs(byCPU[1].CPU-5) > 0.01 {
		t.Errorf("2º por CPU: %+v", byCPU[1])
	}
	for _, p := range byCPU {
		if (p.Name == "outro.exe" || p.Name == "novo.exe") && p.CPU != 0 {
			t.Errorf("%s ganhou CPU sem leitura anterior válida: %+v", p.Name, p)
		}
		if p.Name == "System Idle Process" {
			t.Error("PID 0 não entra")
		}
	}
	if byMem[0].Name != "Code.exe" || byMem[1].Name != "chrome.exe" || byMem[1].Mem != 800<<20 {
		t.Errorf("por memória: %+v", byMem[:2])
	}
}

func TestProcessTopLimitsToTen(t *testing.T) {
	var cur []procSample
	for i := range 30 {
		cur = append(cur, procSample{PID: uint32(i + 1), Name: string(rune('a'+i%26)) + "x.exe", Mem: uint64(i)})
	}
	top := processTop(nil, cur, time.Second, 8, true)
	for _, k := range []string{"by_cpu", "by_mem", "by_gpu", "by_vram"} {
		if n := len(top[k].([]ProcessInfo)); n != topProcesses {
			t.Errorf("%s: %d", k, n)
		}
	}
}

func TestProcessWatchMeasuresAndCaches(t *testing.T) {
	clock := time.Unix(1000, 0)
	reads, waited := 0, time.Duration(0)
	w := &processWatch{
		now:  func() time.Time { return clock },
		wait: func(d time.Duration) { waited += d; clock = clock.Add(d) },
		read: func() ([]procSample, bool, error) {
			reads++
			return []procSample{{PID: 7, Name: "a.exe", CPUTime: time.Duration(reads) * 100 * time.Millisecond, Mem: 1}}, false, nil
		},
	}
	top, err := w.Top()
	if err != nil || reads != 2 || waited == 0 {
		t.Fatalf("primeira leitura: reads %d, espera %s, erro %v", reads, waited, err)
	}
	if cpu := top["by_cpu"].([]ProcessInfo)[0].CPU; cpu <= 0 {
		t.Errorf("CPU = %v", cpu)
	}
	w.Top() // logo em seguida: reaproveita
	if reads != 2 {
		t.Errorf("não reaproveitou: %d leituras", reads)
	}
	clock = clock.Add(3 * time.Second)
	w.Top() // seção aberta: só uma leitura nova, sem esperar
	if reads != 3 || waited != 700*time.Millisecond {
		t.Errorf("leitura seguinte: %d leituras, espera %s", reads, waited)
	}
}

func TestReadProcessesFindsItself(t *testing.T) {
	ps, _, err := readProcesses()
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range ps {
		if p.PID == uint32(os.Getpid()) {
			if p.Mem == 0 || p.Name == "" {
				t.Errorf("o próprio processo veio incompleto: %+v", p)
			}
			return
		}
	}
	t.Error("o próprio processo não apareceu")
}

func TestProcessTopGPU(t *testing.T) {
	cur := []procSample{
		{PID: 1, Name: "game.exe", GPU: 70, VRAM: 3 << 30, Mem: 2 << 30},
		{PID: 2, Name: "chrome.exe", GPU: 5, VRAM: 300 << 20, Mem: 500 << 20},
		{PID: 3, Name: "chrome.exe", GPU: 3, VRAM: 200 << 20, Mem: 400 << 20},
		{PID: 4, Name: "obs64.exe", GPU: 9, VRAM: 100 << 20, Mem: 300 << 20},
	}
	top := processTop(nil, cur, time.Second, 8, true)
	byGPU, byVRAM := top["by_gpu"].([]ProcessInfo), top["by_vram"].([]ProcessInfo)
	if byGPU[0].Name != "game.exe" || byGPU[1].Name != "obs64.exe" || byGPU[2].Name != "chrome.exe" || byGPU[2].GPU != 8 {
		t.Errorf("por GPU: %+v", byGPU[:3])
	}
	if byVRAM[1].Name != "chrome.exe" || byVRAM[1].VRAM != 500<<20 {
		t.Errorf("por VRAM: %+v", byVRAM[:2])
	}
}
