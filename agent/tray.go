package main

import (
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

// desktop é o lado do PC que alguém vê: ícone na bandeja, avisos e a
// contagem antes de desligar. Só o Windows tem um (tray_windows.go); nos
// outros sistemas fica o noDesktop, que não mostra nada.
type desktop interface {
	// Present diz se há alguém para ver a tela: sessão desbloqueada.
	Present() bool
	Notify(title, text string)
	// AskPower mostra a contagem e devolve false se alguém cancelou no PC.
	AskPower(action, by string, grace time.Duration) bool
	// ShowPair abre a janela com o QR de pareamento.
	ShowPair() error
}

type noDesktop struct{}

func (noDesktop) Present() bool                               { return false }
func (noDesktop) Notify(string, string)                       {}
func (noDesktop) AskPower(string, string, time.Duration) bool { return true }
func (noDesktop) ShowPair() error                             { return errors.New("este sistema não tem a janela do QR") }

// ---------- Textos ----------

func powerVerb(action string) string {
	switch action {
	case "reboot":
		return "reiniciar"
	case "sleep":
		return "suspender"
	}
	return "desligar"
}

func powerGerund(action string) string {
	switch action {
	case "reboot":
		return "Reiniciando"
	case "sleep":
		return "Suspendendo"
	}
	return "Desligando"
}

// powerPrompt é o texto da contagem: quem pediu e quanto falta.
func powerPrompt(action, by string, left time.Duration) (instruction, content string) {
	secs := int((left + time.Second - 1) / time.Second)
	return fmt.Sprintf("%s pediu para %s este PC", by, powerVerb(action)),
		fmt.Sprintf("%s em %d s. Cancele se ainda estiver usando.", powerGerund(action), max(secs, 0))
}

// clip corta textos de comando para caber num aviso.
func clip(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	if r := []rune(s); len(r) > n {
		return string(r[:n-1]) + "…"
	}
	return s
}

func scheduleText(p *PowerSchedule) string {
	if p.WhenMediaStops {
		return fmt.Sprintf("%s quando a mídia parar", powerVerb(p.Action))
	}
	return fmt.Sprintf("%s às %s", powerVerb(p.Action), time.Unix(p.At, 0).Format("15:04"))
}

// ---------- Avisos ----------

// noticeBatcher evita uma rajada de avisos (vários comandos seguidos, por
// exemplo): no máximo um a cada gap; o que chega no meio sai num resumo.
type noticeBatcher struct {
	show  func(title, text string)
	gap   time.Duration
	now   func() time.Time
	after func(time.Duration, func())

	mu      sync.Mutex
	last    time.Time
	pending [][2]string
	waiting bool
}

func newNoticeBatcher(show func(title, text string)) *noticeBatcher {
	return &noticeBatcher{
		show: show, gap: 5 * time.Second, now: time.Now,
		after: func(d time.Duration, f func()) { time.AfterFunc(d, f) },
	}
}

func (b *noticeBatcher) Add(title, text string) {
	b.mu.Lock()
	now := b.now()
	if !b.waiting && now.Sub(b.last) >= b.gap {
		b.last = now
		b.mu.Unlock()
		b.show(title, text)
		return
	}
	b.pending = append(b.pending, [2]string{title, text})
	if !b.waiting {
		b.waiting = true
		b.after(b.gap-now.Sub(b.last), b.flush)
	}
	b.mu.Unlock()
}

func (b *noticeBatcher) flush() {
	b.mu.Lock()
	p := b.pending
	b.pending, b.waiting, b.last = nil, false, b.now()
	b.mu.Unlock()
	switch len(p) {
	case 0:
	case 1:
		b.show(p[0][0], p[0][1])
	default:
		last := p[len(p)-1]
		b.show(fmt.Sprintf("%d ações dos celulares", len(p)), fmt.Sprintf("A última: %s %s", last[0], last[1]))
	}
}

// ---------- Menu ----------

const (
	menuPair = 1 + iota
	menuDoctor
	menuCancelSchedule
	menuNotices
	menuLog
	menuConfig
	menuQuit
	menuRevokeBase = 1000 // + índice do celular em trayState.Devices
)

type menuItem struct {
	ID       int // 0: texto ou separador
	Text     string
	Disabled bool
	Checked  bool
	Sep      bool
	Sub      []menuItem
}

type trayState struct {
	Version  string
	IP       string
	Clients  int
	Devices  []PairedDevice
	Schedule *PowerSchedule
	Notices  bool
}

var sep = menuItem{Sep: true}

func trayMenu(st trayState) []menuItem {
	status := []menuItem{{Text: "Velksync " + st.Version + ", rodando", Disabled: true}}
	if st.IP != "" {
		conn := "nenhum celular conectado"
		switch {
		case st.Clients == 1:
			conn = "1 celular conectado"
		case st.Clients > 1:
			conn = fmt.Sprintf("%d celulares conectados", st.Clients)
		}
		status = append(status, menuItem{Text: st.IP + " · " + conn, Disabled: true})
	}

	devices := menuItem{Text: "Celulares pareados"}
	for i, d := range st.Devices {
		devices.Sub = append(devices.Sub, menuItem{
			Text: d.Name + " · desde " + d.PairedAt.Local().Format("02/01/2006"),
			Sub:  []menuItem{{ID: menuRevokeBase + i, Text: "Revogar…"}},
		})
	}
	if len(st.Devices) == 0 {
		devices = menuItem{Text: "Nenhum celular pareado", Disabled: true}
	}

	items := append(status, sep,
		menuItem{ID: menuPair, Text: "Parear um celular…"},
		devices,
		menuItem{ID: menuDoctor, Text: "Conferir Wake-on-LAN…"},
	)
	if st.Schedule != nil {
		items = append(items, sep, menuItem{ID: menuCancelSchedule, Text: "Cancelar: " + scheduleText(st.Schedule)})
	}
	return append(items, sep,
		menuItem{ID: menuNotices, Text: "Avisar o que os celulares fazem", Checked: st.Notices},
		menuItem{ID: menuLog, Text: "Abrir o log"},
		menuItem{ID: menuConfig, Text: "Abrir a pasta da configuração"},
		sep,
		menuItem{ID: menuQuit, Text: "Sair do agente…"},
	)
}

// checksText resume o doctor para uma janela: um item por linha.
func checksText(checks []wolCheck) string {
	var b strings.Builder
	for _, c := range checks {
		fmt.Fprintf(&b, "%s  %s", c.symbol(), c.Label)
		if c.Hint != "" {
			fmt.Fprintf(&b, ": %s", c.Hint)
		}
		b.WriteByte('\n')
	}
	b.WriteString("?  BIOS/UEFI: \"Wake on LAN\" ou \"Power On By PCI-E\" (não dá para ver daqui)")
	return b.String()
}
