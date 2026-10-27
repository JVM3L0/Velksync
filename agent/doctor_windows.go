package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"strings"
)

//go:embed doctor_windows.ps1
var doctorScript string

// readWolFacts roda o script embutido (via -EncodedCommand, como o de mídia).
// $ip e $fix vêm validados: um IPv4 e nomes da lista doctorFixes.
func readWolFacts(ip net.IP, fixes []string) (wolFacts, error) {
	quoted := make([]string, len(fixes))
	for i, f := range fixes {
		quoted[i] = "'" + f + "'"
	}
	script := fmt.Sprintf("$ip = '%s'\n$fix = @(%s)\n%s", ip, strings.Join(quoted, ","), doctorScript)
	cmd := hidden(exec.Command("powershell.exe", "-NoProfile", "-NonInteractive",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand", encodedCommand(script)))
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && len(ee.Stderr) > 0 {
			return wolFacts{}, fmt.Errorf("lendo a placa de rede: %s", strings.TrimSpace(outputText(ee.Stderr)))
		}
		return wolFacts{}, fmt.Errorf("lendo a placa de rede: %w", err)
	}
	var f wolFacts
	if err := json.Unmarshal(out, &f); err != nil {
		return wolFacts{}, fmt.Errorf("resposta inesperada do PowerShell: %w", err)
	}
	return f, nil
}
