package main

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// O auxiliar de mídia do Windows é PowerShell e só roda no Windows; estas
// verificações pegam, em qualquer sistema, erros que já passaram calados.
func TestWindowsMediaScriptPitfalls(t *testing.T) {
	raw, err := os.ReadFile("media_windows.ps1")
	if err != nil {
		t.Fatal(err)
	}
	script := string(raw)
	// [Math]::Min(1, x) escolhe a versão inteira e arredonda x (volume 0.98 virava 1).
	if m := regexp.MustCompile(`\[Math\]::(Min|Max)\(\s*-?\d+\s*,`).FindString(script); m != "" {
		t.Fatalf("literal inteiro em %q: use 1.0/0.0", m)
	}
	// Sem [ComImport] e [PreserveSig] a chamada COM do volume "funciona" sem efeito.
	for _, iface := range []string{"IAudioEndpointVolume", "IMMDevice", "IMMDeviceEnumerator"} {
		i := strings.Index(script, "interface "+iface+" {")
		if i < 0 || !strings.Contains(script[max(0, i-200):i], "[ComImport") {
			t.Errorf("%s sem [ComImport]", iface)
		}
	}
	if regexp.MustCompile(`(?m)^\s+int \w+\(`).MatchString(script) {
		t.Error("método COM sem [PreserveSig]")
	}
	// O agente esconde mídia pausada há muito tempo usando a hora da pausa.
	if !strings.Contains(script, "paused_ms") {
		t.Error("o auxiliar não informa paused_ms")
	}
	// O art_id vem do conteúdo da capa: pelo título, a capa da faixa anterior
	// (que o Chrome ainda mostra logo depois da troca) ficava na faixa nova.
	if strings.Contains(script, "GetHashCode") || !strings.Contains(script, "ComputeHash($bytes)") {
		t.Error("art_id não vem do conteúdo da capa")
	}
}
