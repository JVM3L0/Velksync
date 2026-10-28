package main

import (
	"errors"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Área de transferência do Windows (só texto). A memória dela não é do Go:
// os bytes passam por RtlMoveMemory, sem converter endereço em ponteiro.

var (
	procOpenClipboard     = user32.NewProc("OpenClipboard")
	procCloseClipboard    = user32.NewProc("CloseClipboard")
	procEmptyClipboard    = user32.NewProc("EmptyClipboard")
	procGetClipboardData  = user32.NewProc("GetClipboardData")
	procSetClipboardData  = user32.NewProc("SetClipboardData")
	procIsClipboardFormat = user32.NewProc("IsClipboardFormatAvailable")
	procGlobalAlloc       = kernel32w.NewProc("GlobalAlloc")
	procGlobalFree        = kernel32w.NewProc("GlobalFree")
	procGlobalLock        = kernel32w.NewProc("GlobalLock")
	procGlobalUnlock      = kernel32w.NewProc("GlobalUnlock")
	procGlobalSize        = kernel32w.NewProc("GlobalSize")
	procRtlMoveMemory     = kernel32w.NewProc("RtlMoveMemory")
)

const cfUnicodeText = 13

// openClipboard tenta algumas vezes: outro programa pode estar com ela aberta.
func openClipboard() error {
	for i := 0; i < 10; i++ {
		if r, _, _ := procOpenClipboard.Call(0); r != 0 {
			return nil
		}
		time.Sleep(20 * time.Millisecond)
	}
	return errors.New("a área de transferência está em uso por outro programa")
}

func readClipboard() (string, error) {
	if r, _, _ := procIsClipboardFormat.Call(cfUnicodeText); r == 0 {
		return "", nil
	}
	if err := openClipboard(); err != nil {
		return "", err
	}
	defer procCloseClipboard.Call()
	h, _, _ := procGetClipboardData.Call(cfUnicodeText)
	if h == 0 {
		return "", nil
	}
	size, _, _ := procGlobalSize.Call(h)
	// Lê no máximo um pouco além do limite: o resto seria recusado de qualquer jeito.
	n := min(int(size)/2, maxSendText+2)
	if n == 0 {
		return "", nil
	}
	p, _, _ := procGlobalLock.Call(h)
	if p == 0 {
		return "", errors.New("não deu para ler a área de transferência")
	}
	defer procGlobalUnlock.Call(h)
	buf := make([]uint16, n)
	procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&buf[0])), p, uintptr(n*2))
	return windows.UTF16ToString(buf), nil
}

func writeClipboard(text string) error {
	u, err := windows.UTF16FromString(text)
	if err != nil {
		return err
	}
	if err := openClipboard(); err != nil {
		return err
	}
	defer procCloseClipboard.Call()
	procEmptyClipboard.Call()
	const gmemMoveable = 0x0002
	size := uintptr(len(u) * 2)
	h, _, _ := procGlobalAlloc.Call(gmemMoveable, size)
	if h == 0 {
		return errors.New("sem memória para a área de transferência")
	}
	p, _, _ := procGlobalLock.Call(h)
	if p == 0 {
		procGlobalFree.Call(h)
		return errors.New("não deu para escrever na área de transferência")
	}
	procRtlMoveMemory.Call(p, uintptr(unsafe.Pointer(&u[0])), size)
	procGlobalUnlock.Call(h)
	// Dando certo, a memória passa a ser do Windows.
	if r, _, _ := procSetClipboardData.Call(cfUnicodeText, h); r == 0 {
		procGlobalFree.Call(h)
		return errors.New("o Windows recusou o texto")
	}
	return nil
}
