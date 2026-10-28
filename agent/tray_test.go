package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestPowerPrompt(t *testing.T) {
	ins, content := powerPrompt("shutdown", "Pixel 9", 9200*time.Millisecond)
	if ins != "Pixel 9 pediu para desligar este PC" || !strings.HasPrefix(content, "Desligando em 10 s.") {
		t.Errorf("%q / %q", ins, content)
	}
	ins, content = powerPrompt("reboot", "O agendamento", -time.Second)
	if ins != "O agendamento pediu para reiniciar este PC" || !strings.HasPrefix(content, "Reiniciando em 0 s.") {
		t.Errorf("%q / %q", ins, content)
	}
	if _, c := powerPrompt("sleep", "x", time.Second); !strings.HasPrefix(c, "Suspendendo") {
		t.Errorf("sleep: %q", c)
	}
}

func TestClip(t *testing.T) {
	if got := clip("  dir \n /s   c:\\ ", 80); got != `dir /s c:\` {
		t.Errorf("clip = %q", got)
	}
	if got := clip("abcdefghij", 5); got != "abcd…" {
		t.Errorf("clip = %q", got)
	}
}

// fakeClock controla o noticeBatcher sem esperar de verdade.
type fakeClock struct {
	now     time.Time
	pending []func()
}

func (c *fakeClock) after(_ time.Duration, f func()) { c.pending = append(c.pending, f) }
func (c *fakeClock) fire() {
	p := c.pending
	c.pending = nil
	for _, f := range p {
		f()
	}
}

func TestNoticeBatcher(t *testing.T) {
	clock := &fakeClock{now: time.Unix(1000, 0)}
	var shown []string
	b := newNoticeBatcher(func(title, text string) { shown = append(shown, title+": "+text) })
	b.now = func() time.Time { return clock.now }
	b.after = clock.after

	b.Add("Pixel", "rodou \"Steam\"")
	if len(shown) != 1 {
		t.Fatalf("o primeiro aviso sai na hora: %v", shown)
	}
	// Rajada: nada sai até o intervalo passar, depois um resumo.
	b.Add("Pixel", "rodou \"Bloquear\"")
	b.Add("Galaxy", "rodou \"Mutar\"")
	if len(shown) != 1 || len(clock.pending) != 1 {
		t.Fatalf("rajada saiu antes do intervalo: %v", shown)
	}
	clock.now = clock.now.Add(5 * time.Second)
	clock.fire()
	if len(shown) != 2 || shown[1] != `2 ações dos celulares: A última: Galaxy rodou "Mutar"` {
		t.Fatalf("resumo: %v", shown)
	}
	// Um só no intervalo sai como ele mesmo.
	b.Add("Pixel", "agendou desligar às 23:00")
	clock.now = clock.now.Add(5 * time.Second)
	clock.fire()
	if len(shown) != 3 || shown[2] != "Pixel: agendou desligar às 23:00" {
		t.Fatalf("aviso único: %v", shown)
	}
	// Depois de um tempo quieto, volta a sair na hora.
	clock.now = clock.now.Add(time.Minute)
	b.Add("Pixel", "rodou \"Steam\"")
	if len(shown) != 4 || len(clock.pending) != 0 {
		t.Fatalf("depois do intervalo: %v", shown)
	}
}

func menuTexts(items []menuItem) []string {
	var out []string
	for _, it := range items {
		if it.Sep {
			out = append(out, "-")
			continue
		}
		out = append(out, it.Text)
	}
	return out
}

func TestTrayMenu(t *testing.T) {
	paired := time.Date(2026, 10, 25, 12, 0, 0, 0, time.Local)
	items := trayMenu(trayState{
		Version: "0.5.0", IP: "192.168.3.5", Clients: 1, Notices: true,
		Devices:  []PairedDevice{{ID: "a", Name: "Pixel 9", PairedAt: paired}, {ID: "b", Name: "Galaxy", PairedAt: paired}},
		Schedule: &PowerSchedule{Action: "shutdown", WhenMediaStops: true},
	})
	want := []string{
		"Velksync 0.5.0, rodando", "192.168.3.5 · 1 celular conectado", "-",
		"Parear um celular…", "Celulares pareados", "Conferir Wake-on-LAN…", "-",
		"Cancelar: desligar quando a mídia parar", "-",
		"Avisar o que os celulares fazem", "Procurar atualizações", "Abrir o log", "Abrir a pasta da configuração", "-", "Sair do agente…",
	}
	if got := menuTexts(items); strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("menu:\n%v\nqueria\n%v", got, want)
	}
	devices := items[4].Sub
	if len(devices) != 2 || devices[1].Text != "Galaxy · desde 25/10/2026" || devices[1].Sub[0].ID != menuRevokeBase+1 {
		t.Errorf("celulares: %+v", devices)
	}
	if !items[9].Checked || !items[0].Disabled {
		t.Error("marcação ou status errados")
	}

	empty := trayMenu(trayState{Version: "0.5.0", IP: "10.0.0.2", Clients: 3})
	texts := strings.Join(menuTexts(empty), "|")
	for _, want := range []string{"3 celulares conectados", "Nenhum celular pareado"} {
		if !strings.Contains(texts, want) {
			t.Errorf("sem %q em %s", want, texts)
		}
	}
	if strings.Contains(texts, "Cancelar:") || empty[9].Checked {
		t.Errorf("sem agendamento e avisos desligados: %s", texts)
	}
}

// fakeDesktop faz o papel da bandeja; cancel=true simula alguém cancelando
// no PC, para nenhum teste desligar a máquina de verdade.
type fakeDesktop struct {
	present bool
	asked   chan string
	notices []string
}

func (d *fakeDesktop) Present() bool { return d.present }
func (d *fakeDesktop) Notify(title, text string) {
	d.notices = append(d.notices, title+": "+text)
}
func (d *fakeDesktop) AskPower(action, by string, grace time.Duration) bool {
	d.asked <- action + "|" + by + "|" + grace.String()
	return false
}
func (d *fakeDesktop) ShowPair() error { return nil }

func TestPowerAsksAndCanBeCancelledAtThePC(t *testing.T) {
	d := &fakeDesktop{present: true, asked: make(chan string, 1)}
	s := &Server{cfg: Config{Token: testMaster, Devices: []PairedDevice{{ID: "dev1", Name: "Pixel 9"}}}, hub: NewHub(), ui: d}
	s.routes()
	events := s.hub.Subscribe()

	req := withAuth(httptest.NewRequest("POST", "/api/power", strings.NewReader(`{"action":"reboot"}`)), authDevice, "dev1")
	rec := httptest.NewRecorder()
	s.power(rec, req)
	var body struct {
		Grace int `json:"grace_s"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || rec.Code != http.StatusAccepted || body.Grace != 10 {
		t.Fatalf("resposta %d %s", rec.Code, rec.Body)
	}
	select {
	case got := <-d.asked:
		if got != "reboot|Pixel 9|10s" {
			t.Errorf("contagem pedida: %s", got)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("não mostrou a contagem")
	}
	select {
	case e := <-events:
		if e.Type != "notify" || !strings.Contains(e.Text, "não vai reiniciar") {
			t.Errorf("aviso ao celular: %+v", e)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("o celular não soube do cancelamento")
	}
}

func TestConfirmPowerRules(t *testing.T) {
	zero := 0
	cases := []struct {
		name    string
		present bool
		grace   *int
		ask     bool
		want    bool
	}{
		{"tela bloqueada: na hora", false, nil, false, true},
		{"contagem desligada: na hora", true, &zero, false, true},
		{"desbloqueada: pergunta e cancelam", true, nil, true, false},
	}
	for _, tc := range cases {
		d := &fakeDesktop{present: tc.present, asked: make(chan string, 1)}
		s := &Server{cfg: Config{Token: testMaster, PowerGraceSeconds: tc.grace}, hub: NewHub(), ui: d}
		if got := s.confirmPower("shutdown", "O agendamento"); got != tc.want {
			t.Errorf("%s: confirmPower = %v", tc.name, got)
		}
		if asked := len(d.asked) == 1; asked != tc.ask {
			t.Errorf("%s: perguntou = %v", tc.name, asked)
		}
	}
}

func TestNoticesFollowTheMenuSwitch(t *testing.T) {
	d := &fakeDesktop{}
	off := false
	s := &Server{cfg: Config{Token: testMaster, TrayNotices: &off}, hub: NewHub(), ui: d}
	s.routes()
	s.notice("Pixel", "rodou \"Steam\"")
	if len(d.notices) != 0 {
		t.Fatalf("avisos desligados, mas mostrou %v", d.notices)
	}
	s.cfg.TrayNotices = nil
	s.notice("Pixel", "rodou \"Steam\"")
	if len(d.notices) != 1 || d.notices[0] != "Pixel: rodou \"Steam\"" {
		t.Fatalf("avisos: %v", d.notices)
	}
}

func TestPowerGraceConfig(t *testing.T) {
	big, neg := 999, -5
	for _, tc := range []struct {
		v    *int
		want time.Duration
	}{{nil, 10 * time.Second}, {&big, 120 * time.Second}, {&neg, 0}} {
		if got := (Config{PowerGraceSeconds: tc.v}).powerGrace(); got != tc.want {
			t.Errorf("powerGrace(%v) = %s", tc.v, got)
		}
	}
}

func TestTrayMenuUpdate(t *testing.T) {
	ready := trayMenu(trayState{Version: "0.6.1", Update: "0.6.2"})
	if ready[2].ID != menuUpdate || ready[2].Text != "Atualizar para 0.6.2…" || ready[2].Disabled {
		t.Errorf("com versão nova: %+v", ready[2])
	}
	busy := trayMenu(trayState{Version: "0.6.1", Update: "0.6.2", Updating: true})
	if busy[2].ID != 0 || !busy[2].Disabled || busy[2].Text != "Atualizando para 0.6.2…" {
		t.Errorf("atualizando: o item deveria estar desativado: %+v", busy[2])
	}
}
