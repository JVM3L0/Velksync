package main

import (
	"testing"
	"time"
)

func TestParseProcStat(t *testing.T) {
	line := "1234 (Web Content (x)) S 1 2 3 4 5 6 7 8 9 10 150 50 0 0 20 0 1 0"
	p, ok := parseProcStat(line)
	if !ok || p.Name != "Web Content (x)" || p.CPUTime != 2*time.Second {
		t.Errorf("parseProcStat = %+v %v", p, ok)
	}
	if _, ok := parseProcStat("lixo"); ok {
		t.Error("aceitou lixo")
	}
}
