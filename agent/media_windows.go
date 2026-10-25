package main

import (
	"bufio"
	_ "embed"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"sync"
	"time"
	"unicode/utf16"
)

// No Windows, os controles de mídia do sistema (SMTC) são WinRT. Um PowerShell
// auxiliar embutido faz a ponte: iniciado sob demanda, oculto, conversando por
// stdin/stdout, e encerrado depois de um tempo sem uso.

//go:embed media_windows.ps1
var smtcScript string

const (
	smtcTimeout = 8 * time.Second
	smtcIdle    = 2 * time.Minute
)

type smtcBackend struct {
	mu      sync.Mutex
	cmd     *exec.Cmd
	stdin   io.WriteCloser
	stdout  *bufio.Reader
	idle    *time.Timer
	lastArt struct {
		id    string
		data  []byte
		ctype string
	}
}

func newMediaBackend() mediaBackend { return &smtcBackend{} }

// encodedCommand: o script vai pela linha de comando em UTF-16LE base64, sem
// arquivo temporário que outro processo pudesse trocar.
func encodedCommand(script string) string {
	u := utf16.Encode([]rune(script))
	b := make([]byte, len(u)*2)
	for i, c := range u {
		binary.LittleEndian.PutUint16(b[i*2:], c)
	}
	return base64.StdEncoding.EncodeToString(b)
}

func (b *smtcBackend) start() error {
	cmd := hidden(exec.Command("powershell.exe", "-NoProfile", "-NonInteractive",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand", encodedCommand(smtcScript)))
	in, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	b.cmd, b.stdin, b.stdout = cmd, in, bufio.NewReaderSize(out, 64<<10)
	return nil
}

func (b *smtcBackend) stop() {
	if b.cmd == nil {
		return
	}
	b.stdin.Close()
	b.cmd.Process.Kill()
	b.cmd.Wait()
	b.cmd, b.stdin, b.stdout = nil, nil, nil
}

// call envia uma requisição e decodifica a resposta. Um auxiliar travado ou
// morto é encerrado e recriado na próxima chamada.
func (b *smtcBackend) call(req map[string]any, out any) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.cmd == nil {
		if err := b.start(); err != nil {
			return err
		}
	}
	if b.idle == nil {
		b.idle = time.AfterFunc(smtcIdle, func() {
			b.mu.Lock()
			b.stop()
			b.mu.Unlock()
		})
	} else {
		b.idle.Reset(smtcIdle)
	}

	line, _ := json.Marshal(req)
	type result struct {
		data []byte
		err  error
	}
	done := make(chan result, 1)
	go func() {
		if _, err := b.stdin.Write(append(line, '\n')); err != nil {
			done <- result{err: err}
			return
		}
		data, err := b.stdout.ReadBytes('\n')
		done <- result{data, err}
	}()
	var r result
	select {
	case r = <-done:
	case <-time.After(smtcTimeout):
		b.stop()
		return errors.New("o auxiliar de mídia não respondeu")
	}
	if r.err != nil {
		b.stop()
		return r.err
	}
	var e struct {
		Error string `json:"error"`
	}
	if json.Unmarshal(r.data, &e) == nil && e.Error != "" {
		if strings.Contains(e.Error, "nada tocando") {
			return errNoMedia
		}
		return errors.New(e.Error)
	}
	return json.Unmarshal(r.data, out)
}

func (b *smtcBackend) State() (MediaState, error) {
	var st MediaState
	err := b.call(map[string]any{"cmd": "state"}, &st)
	if st.Player != "" {
		st.Player = friendlyApp(st.Player)
	}
	return st, err
}

// "Spotify.exe" → "Spotify"; "308046B0AF4A39CB" (Firefox) fica como está.
func friendlyApp(id string) string {
	id = strings.TrimSuffix(id, ".exe")
	if i := strings.LastIndex(id, "!"); i >= 0 { // AppUserModelId de app da loja
		id = id[i+1:]
	}
	if i := strings.Index(id, "_"); i > 0 && strings.Contains(id[:i], ".") {
		id = id[strings.LastIndex(id[:i], ".")+1 : i]
	}
	return id
}

func (b *smtcBackend) Art() ([]byte, string, error) {
	st, err := b.State()
	if err != nil {
		return nil, "", err
	}
	if st.ArtID == "" {
		return nil, "", errNoMedia
	}
	b.mu.Lock()
	cached := b.lastArt
	b.mu.Unlock()
	if cached.id == st.ArtID {
		return cached.data, cached.ctype, nil
	}
	var res struct {
		Data string `json:"data"`
	}
	if err := b.call(map[string]any{"cmd": "art"}, &res); err != nil {
		return nil, "", err
	}
	data, err := base64.StdEncoding.DecodeString(res.Data)
	if err != nil || len(data) > maxArtBytes {
		return nil, "", errors.New("capa inválida")
	}
	ctype := http.DetectContentType(data)
	if !strings.HasPrefix(ctype, "image/") {
		return nil, "", errors.New("capa não é imagem")
	}
	b.mu.Lock()
	b.lastArt.id, b.lastArt.data, b.lastArt.ctype = st.ArtID, data, ctype
	b.mu.Unlock()
	return data, ctype, nil
}

func (b *smtcBackend) Command(action string) error {
	return b.call(map[string]any{"cmd": "command", "action": action}, &struct{}{})
}

func (b *smtcBackend) SeekTo(positionMs int64) error {
	if positionMs < 0 {
		return errors.New("posição inválida")
	}
	return b.call(map[string]any{"cmd": "seek", "position_ms": positionMs}, &struct{}{})
}

func (b *smtcBackend) SetVolume(volume *float64, muted *bool) error {
	req := map[string]any{"cmd": "volume"}
	if volume != nil {
		req["volume"] = *volume
	}
	if muted != nil {
		req["muted"] = *muted
	}
	return b.call(req, &struct{}{})
}
