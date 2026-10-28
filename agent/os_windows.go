package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unicode/utf8"
	"unsafe"

	"golang.org/x/text/encoding/charmap"
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

// hasConsole diz se alguém lê a saída. Aberto pelo instalador ou com dois
// cliques, ninguém lê: o resultado vai numa caixa de mensagem.
var hasConsole bool

// O binário do Windows é compilado como GUI (sem janela de console). Quando
// chamado de um terminal (token, send...), pega o console do processo pai.
func attachConsole() {
	if h, _ := syscall.GetStdHandle(syscall.STD_OUTPUT_HANDLE); h != 0 && h != syscall.InvalidHandle {
		hasConsole = true // saída já redirecionada (pipe ou arquivo)
		return
	}
	attach := syscall.NewLazyDLL("kernel32.dll").NewProc("AttachConsole")
	if r, _, _ := attach.Call(uintptr(^uint32(0))); r == 0 {
		return
	}
	if f, err := os.OpenFile("CONOUT$", os.O_RDWR, 0); err == nil {
		os.Stdout, os.Stderr = f, f
		hasConsole = true
	}
}

// openURL abre um link http(s) já conferido no navegador padrão.
func openURL(link string) error {
	return hidden(exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", link)).Start()
}

// allowForeground deixa o agente trazer a janela do QR para a frente: sem
// isso o Windows só pisca o ícone na barra de tarefas.
func allowForeground() {
	const asfwAny = ^uintptr(0)
	syscall.NewLazyDLL("user32.dll").NewProc("AllowSetForegroundWindow").Call(asfwAny)
}

// notifyUser mostra uma mensagem quando não há console para ler a saída.
func notifyUser(text string, isError bool) {
	if hasConsole {
		return
	}
	const mbIconInformation, mbIconError, mbSetForeground = 0x40, 0x10, 0x10000
	flags := uintptr(mbIconInformation | mbSetForeground)
	if isError {
		flags = mbIconError | mbSetForeground
	}
	t, _ := syscall.UTF16PtrFromString(text)
	c, _ := syscall.UTF16PtrFromString("Velksync")
	syscall.NewLazyDLL("user32.dll").NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(c)), flags)
}

func defaultLogPath(configPath string) string {
	return filepath.Join(filepath.Dir(configPath), "agent.log")
}

// O PowerShell não espera binários GUI, então o QR no console pode sair
// embaralhado com o prompt; abrir a imagem é o caminho confiável.
func openFile(path string) bool {
	return hidden(exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", path)).Start() == nil
}

// Programas de console do Windows escrevem na code page OEM (CP850 no
// Windows em português), não em UTF-8. Sem converter, "Configuração" chega
// ao app como "Configura��o".
func outputText(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	getOEMCP := syscall.NewLazyDLL("kernel32.dll").NewProc("GetOEMCP")
	cp, _, _ := getOEMCP.Call()
	var enc *charmap.Charmap
	switch cp {
	case 437:
		enc = charmap.CodePage437
	case 850:
		enc = charmap.CodePage850
	case 852:
		enc = charmap.CodePage852
	case 860:
		enc = charmap.CodePage860
	case 1252:
		enc = charmap.Windows1252
	default:
		enc = charmap.CodePage850
	}
	out, err := enc.NewDecoder().Bytes(b)
	if err != nil {
		return strings.ToValidUTF8(string(b), "?")
	}
	return string(out)
}
