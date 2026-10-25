package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

const createNoWindow = 0x08000000

func hidden(cmd *exec.Cmd) *exec.Cmd {
	if cmd.SysProcAttr == nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{}
	}
	cmd.SysProcAttr.HideWindow = true
	cmd.SysProcAttr.CreationFlags |= createNoWindow
	return cmd
}

func powerCommand(action string) (*exec.Cmd, error) {
	switch action {
	case "shutdown":
		return hidden(exec.Command("shutdown.exe", "/s", "/t", "0")), nil
	case "reboot":
		return hidden(exec.Command("shutdown.exe", "/r", "/t", "0")), nil
	case "sleep":
		// Hiberna em vez de suspender se a hibernação estiver ativa (powercfg /h off).
		return hidden(exec.Command("rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0")), nil
	}
	return nil, fmt.Errorf("ação desconhecida: %s", action)
}

// Passa a linha crua para o cmd.exe; o escape padrão do Go quebraria as aspas.
func shellCommand(ctx context.Context, line string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, "cmd.exe")
	cmd.SysProcAttr = &syscall.SysProcAttr{CmdLine: `cmd.exe /S /C "` + line + `"`}
	return hidden(cmd)
}

// O binário do Windows é compilado como GUI (sem janela de console). Quando
// chamado de um terminal (token, send...), pega o console do processo pai.
func attachConsole() {
	if h, _ := syscall.GetStdHandle(syscall.STD_OUTPUT_HANDLE); h != 0 && h != syscall.InvalidHandle {
		return // saída já redirecionada (pipe ou arquivo)
	}
	attach := syscall.NewLazyDLL("kernel32.dll").NewProc("AttachConsole")
	if r, _, _ := attach.Call(uintptr(^uint32(0))); r == 0 {
		return
	}
	if f, err := os.OpenFile("CONOUT$", os.O_RDWR, 0); err == nil {
		os.Stdout, os.Stderr = f, f
	}
}

func defaultLogPath(configPath string) string {
	return filepath.Join(filepath.Dir(configPath), "agent.log")
}

// O PowerShell não espera binários GUI, então o QR no console pode sair
// embaralhado com o prompt; abrir a imagem é o caminho confiável.
func openFile(path string) bool {
	return hidden(exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", path)).Start() == nil
}
