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

func defaultLogPath(string) string { return "" }
