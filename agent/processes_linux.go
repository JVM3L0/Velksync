package main

import (
	"os"
	"strconv"
	"strings"
	"time"
)

// readProcesses lê /proc: tempo de CPU (campos 14 e 15 do stat, em ticks de
// 1/100 s) e memória residente (statm × tamanho da página). GPU por processo
// ainda não (depende do driver).
func readProcesses() ([]procSample, bool, error) {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil, false, err
	}
	page := uint64(os.Getpagesize())
	var out []procSample
	for _, e := range entries {
		pid, err := strconv.ParseUint(e.Name(), 10, 32)
		if err != nil {
			continue
		}
		p, ok := parseProcStat(readSmall("/proc/" + e.Name() + "/stat"))
		if !ok {
			continue // processo terminou no meio da leitura
		}
		p.PID = uint32(pid)
		if f := strings.Fields(readSmall("/proc/" + e.Name() + "/statm")); len(f) > 1 {
			rss, _ := strconv.ParseUint(f[1], 10, 64)
			p.Mem = rss * page
		}
		out = append(out, p)
	}
	return out, false, nil
}

func readSmall(path string) string {
	b, _ := os.ReadFile(path)
	return string(b)
}

// parseProcStat: "pid (nome com espaços) estado ... utime stime ...".
func parseProcStat(s string) (procSample, bool) {
	open, close := strings.IndexByte(s, '('), strings.LastIndexByte(s, ')')
	if open < 0 || close < open {
		return procSample{}, false
	}
	f := strings.Fields(s[close+1:])
	if len(f) < 13 {
		return procSample{}, false
	}
	ut, err1 := strconv.ParseUint(f[11], 10, 64)
	st, err2 := strconv.ParseUint(f[12], 10, 64)
	if err1 != nil || err2 != nil {
		return procSample{}, false
	}
	return procSample{Name: s[open+1 : close], CPUTime: time.Duration(ut+st) * 10 * time.Millisecond}, true
}
