package main

import (
	"context"
	"fmt"
	"os/exec"
)

func powerCommand(action string) (*exec.Cmd, error) {
	switch action {
	case "shutdown":
		return exec.Command("systemctl", "poweroff"), nil
	case "reboot":
		return exec.Command("systemctl", "reboot"), nil
	case "sleep":
		return exec.Command("systemctl", "suspend"), nil
	}
	return nil, fmt.Errorf("ação desconhecida: %s", action)
}

func shellCommand(ctx context.Context, line string) *exec.Cmd {
	return exec.CommandContext(ctx, "/bin/sh", "-c", line)
}

func attachConsole() {}

// No Linux os comandos sempre rodam num terminal.
const hasConsole = true

func allowForeground() {}

// No Linux os comandos rodam no terminal: a saída já basta.
func notifyUser(string, bool) {}

func defaultLogPath(string) string { return "" }

// openURL abre um link http(s) já conferido no navegador da sessão.
func openURL(link string) error { return exec.Command("xdg-open", link).Start() }

// No Linux o QR já aparece no terminal.
func openFile(string) bool { return false }

func outputText(b []byte) string { return string(b) }
