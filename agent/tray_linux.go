//go:build linux

package main

import (
	"bytes"
	_ "embed"
	"errors"
	"fmt"
	"image"
	"image/draw"
	"image/png"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
	"github.com/godbus/dbus/v5/prop"
	"github.com/skip2/go-qrcode"
)

// Bandeja do Linux: ícone StatusNotifierItem (o protocolo que KDE, GNOME com
// a extensão AppIndicator, waybar, Caelestia e afins entendem), menu
// com.canonical.dbusmenu e avisos pelo org.freedesktop.Notifications. Tudo
// por D-Bus, sem biblioteca gráfica. Fica de fora o que depende de janela
// ou de área de transferência (QR em janela, "Enviar para o celular",
// contagem antes de desligar, doctor do Wake-on-LAN).

//go:embed deploy/tray-icon.png
var trayIconPNG []byte

const (
	sniPath      = "/StatusNotifierItem"
	sniIface     = "org.kde.StatusNotifierItem"
	menuPath     = "/MenuBar"
	menuIface    = "com.canonical.dbusmenu"
	watcherName  = "org.kde.StatusNotifierWatcher"
	watcherPath  = "/StatusNotifierWatcher"
	notifyName   = "org.freedesktop.Notifications"
	notifyPath   = "/org/freedesktop/Notifications"
	releasesPage = "https://github.com/JVM3L0/Velksync/releases/"
)

type linuxTray struct {
	srv  *Server
	conn *dbus.Conn
	name string // nome do item no barramento

	mu          sync.Mutex
	items       []menuItem
	root        *dmNode
	byID        map[int32]*dmNode
	rev         uint32
	menuDevices []PairedDevice
	waiters     map[uint32]chan string // notificações esperando resposta
}

var _ desktop = (*linuxTray)(nil)

func startDesktop(s *Server) desktop {
	t := &linuxTray{srv: s, waiters: map[uint32]chan string{}}
	if err := t.start(); err != nil {
		log.Printf("bandeja: %v (seguindo sem ícone)", err)
		return noDesktop{}
	}
	return t
}

func (t *linuxTray) start() error {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return err
	}
	t.conn = conn
	pix, err := iconPixmaps(trayIconPNG, 22, 32, 48, 64)
	if err != nil {
		return fmt.Errorf("ícone: %w", err)
	}
	t.rebuild()

	// StatusNotifierItem.
	item := &sniObject{t: t}
	if err := conn.Export(item, sniPath, sniIface); err != nil {
		return err
	}
	sniProps, err := prop.Export(conn, sniPath, map[string]map[string]*prop.Prop{sniIface: {
		"Category":   {Value: "ApplicationStatus"},
		"Id":         {Value: "velksync-agent"},
		"Title":      {Value: "Velksync"},
		"Status":     {Value: "Active"},
		"WindowId":   {Value: uint32(0)},
		"IconName":   {Value: ""},
		"IconPixmap": {Value: pix},
		"ItemIsMenu": {Value: true},
		"Menu":       {Value: dbus.ObjectPath(menuPath)},
		"ToolTip":    {Value: sniToolTip{Title: "Velksync", Text: "Agente rodando"}},
	}})
	if err != nil {
		return err
	}
	sniNode := &introspect.Node{Name: sniPath, Interfaces: []introspect.Interface{
		introspect.IntrospectData, prop.IntrospectData,
		{Name: sniIface, Methods: introspect.Methods(item), Properties: sniProps.Introspection(sniIface)},
	}}
	if err := conn.Export(introspect.NewIntrospectable(sniNode), sniPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		return err
	}

	// dbusmenu.
	menu := &menuObject{t: t}
	if err := conn.Export(menu, menuPath, menuIface); err != nil {
		return err
	}
	menuProps, err := prop.Export(conn, menuPath, map[string]map[string]*prop.Prop{menuIface: {
		"Version":       {Value: uint32(3)},
		"TextDirection": {Value: "ltr"},
		"Status":        {Value: "normal"},
		"IconThemePath": {Value: []string{}},
	}})
	if err != nil {
		return err
	}
	menuNode := &introspect.Node{Name: menuPath, Interfaces: []introspect.Interface{
		introspect.IntrospectData, prop.IntrospectData,
		{Name: menuIface, Methods: introspect.Methods(menu), Properties: menuProps.Introspection(menuIface),
			Signals: []introspect.Signal{
				{Name: "LayoutUpdated", Args: []introspect.Arg{{Name: "revision", Type: "u"}, {Name: "parent", Type: "i"}}},
			}},
	}}
	if err := conn.Export(introspect.NewIntrospectable(menuNode), menuPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		return err
	}

	t.name = fmt.Sprintf("org.kde.StatusNotifierItem-%d-1", os.Getpid())
	reply, err := conn.RequestName(t.name, dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		return fmt.Errorf("não consegui o nome %s no D-Bus", t.name)
	}

	// Sinais: respostas das notificações e o host da bandeja aparecendo
	// (o agente costuma subir antes da barra no login).
	for _, opt := range [][]dbus.MatchOption{
		{dbus.WithMatchInterface(notifyName), dbus.WithMatchSender(notifyName)},
		{dbus.WithMatchSender("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, watcherName)},
	} {
		if err := conn.AddMatchSignal(opt...); err != nil {
			log.Printf("bandeja: %v", err)
		}
	}
	signals := make(chan *dbus.Signal, 32)
	conn.Signal(signals)
	go t.dispatch(signals)

	if err := t.register(); err != nil {
		log.Printf("bandeja: sem host de bandeja por enquanto (%v); o ícone aparece quando ele subir", err)
	}
	go t.refreshLoop()
	return nil
}

// register avisa o host da bandeja que o ícone existe.
func (t *linuxTray) register() error {
	return t.conn.Object(watcherName, watcherPath).
		Call(watcherName+".RegisterStatusNotifierItem", 0, t.name).Err
}

func (t *linuxTray) dispatch(ch <-chan *dbus.Signal) {
	for sig := range ch {
		switch sig.Name {
		case "org.freedesktop.DBus.NameOwnerChanged":
			if len(sig.Body) == 3 {
				if owner, _ := sig.Body[2].(string); owner != "" {
					if err := t.register(); err != nil {
						log.Printf("bandeja: %v", err)
					}
				}
			}
		case notifyName + ".ActionInvoked":
			if len(sig.Body) == 2 {
				id, _ := sig.Body[0].(uint32)
				key, _ := sig.Body[1].(string)
				t.answer(id, key)
			}
		case notifyName + ".NotificationClosed":
			if len(sig.Body) >= 1 {
				id, _ := sig.Body[0].(uint32)
				t.answer(id, "")
			}
		}
	}
}

func (t *linuxTray) answer(id uint32, key string) {
	t.mu.Lock()
	ch := t.waiters[id]
	delete(t.waiters, id)
	t.mu.Unlock()
	if ch != nil {
		ch <- key
	}
}

// refreshLoop mantém o texto do menu em dia (celulares conectados, agendamento)
// para os hosts que guardam o menu em vez de pedir de novo a cada abertura.
func (t *linuxTray) refreshLoop() {
	for range time.Tick(10 * time.Second) {
		if t.rebuild() {
			t.emitLayoutUpdated()
		}
	}
}

func (t *linuxTray) emitLayoutUpdated() {
	t.mu.Lock()
	rev := t.rev
	t.mu.Unlock()
	if err := t.conn.Emit(menuPath, menuIface+".LayoutUpdated", rev, int32(0)); err != nil {
		log.Printf("bandeja: %v", err)
	}
}

// ---------- desktop ----------

func (t *linuxTray) Notify(title, text string) {
	if _, err := t.notify(title, text, nil, 8000); err != nil {
		log.Printf("bandeja: aviso: %v", err)
	}
}

// No Linux a energia é na hora: não há contagem para cancelar.
func (t *linuxTray) Present() bool { return false }

func (t *linuxTray) AskPower(string, string, time.Duration) bool { return true }

// ShowPair grava o QR numa imagem e a abre no visualizador da sessão; ela
// some quando o código vence.
func (t *linuxTray) ShowPair() error {
	s := t.srv
	ip, err := lanIP()
	if err != nil {
		return errors.New("não achei o IP da rede local")
	}
	code := s.pairs.start()
	s.mu.Lock()
	cfg := s.cfg
	s.mu.Unlock()
	link, err := pairLink(cfg, ip, code)
	if err != nil {
		return err
	}
	qr, err := qrcode.New(link, qrcode.Medium)
	if err != nil {
		return err
	}
	data, err := qr.PNG(512)
	if err != nil {
		return err
	}
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	path := filepath.Join(dir, "velksync-pair-"+code+".png")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return err
	}
	time.AfterFunc(pairTTL, func() { os.Remove(path) })
	if err := exec.Command("xdg-open", path).Start(); err != nil {
		os.Remove(path)
		return fmt.Errorf("não consegui abrir o QR: %w", err)
	}
	t.Notify("Parear um celular", "Escaneie o QR no app do Velksync. Ele vale por "+fmt.Sprint(int(pairTTL.Minutes()))+" minutos.")
	return nil
}

// ---------- Notificações ----------

func (t *linuxTray) notify(title, text string, actions []string, timeoutMs int32) (uint32, error) {
	if actions == nil {
		actions = []string{}
	}
	var id uint32
	err := t.conn.Object(notifyName, notifyPath).Call(notifyName+".Notify", 0,
		"Velksync", uint32(0), "", title, text, actions, map[string]dbus.Variant{}, timeoutMs).Store(&id)
	return id, err
}

// confirm mostra um aviso com um botão de ação e espera a resposta (ou o
// aviso sumir). Só a ação explícita vale como "sim".
func (t *linuxTray) confirm(title, text, action string) bool {
	id, err := t.notify(title, text, []string{"yes", action, "no", "Cancelar"}, 30000)
	if err != nil {
		log.Printf("bandeja: confirmação: %v", err)
		return false
	}
	ch := make(chan string, 1)
	t.mu.Lock()
	t.waiters[id] = ch
	t.mu.Unlock()
	select {
	case key := <-ch:
		return key == "yes"
	case <-time.After(35 * time.Second):
		t.mu.Lock()
		delete(t.waiters, id)
		t.mu.Unlock()
		return false
	}
}

// ---------- Menu ----------

func (t *linuxTray) state() trayState {
	s := t.srv
	s.mu.Lock()
	devices := slices.Clone(s.cfg.Devices)
	notices := s.cfg.trayNotices()
	updateCheck := s.cfg.updateCheck()
	s.mu.Unlock()
	st := trayState{Version: version, Devices: devices, Notices: notices, UpdateCheck: updateCheck, NoSend: true}
	if s.schedule != nil {
		st.Schedule = s.schedule.Current()
	}
	if s.updates != nil {
		if r, ok := s.updates.Pending(); ok {
			st.Update = r.Version()
		}
	}
	if s.hub != nil {
		for _, id := range s.hub.Clients() {
			st.SendTargets = append(st.SendTargets, s.deviceName(id))
		}
	}
	if ip, err := lanIP(); err == nil {
		st.IP = ip.String()
	}
	if s.live != nil {
		st.Clients = s.live.Clients()
	}
	return st
}

// linuxMenu é o menu do Windows sem o que não existe aqui (doctor, log em
// arquivo: o do Linux fica no journal) e sem separadores soltos.
func linuxMenu(st trayState) []menuItem {
	hide := map[int]bool{menuDoctor: true, menuLog: true}
	var out []menuItem
	for _, it := range trayMenu(st) {
		if hide[it.ID] {
			continue
		}
		if it.Sep && (len(out) == 0 || out[len(out)-1].Sep) {
			continue
		}
		out = append(out, it)
	}
	for len(out) > 0 && out[len(out)-1].Sep {
		out = out[:len(out)-1]
	}
	return out
}

// rebuild refaz o menu a partir do estado; devolve true se mudou.
func (t *linuxTray) rebuild() bool {
	st := t.state()
	items := linuxMenu(st)
	root, byID := buildDM(items)
	t.mu.Lock()
	defer t.mu.Unlock()
	changed := !reflect.DeepEqual(t.items, items)
	if changed {
		t.rev++
	}
	t.items, t.root, t.byID, t.menuDevices = items, root, byID, st.Devices
	return changed
}

func (t *linuxTray) command(cmd int) {
	s := t.srv
	switch {
	case cmd == menuPair:
		if err := t.ShowPair(); err != nil {
			t.Notify("Parear um celular", err.Error())
		}
	case cmd == menuCancelSchedule:
		if p := s.schedule.Current(); p != nil && s.schedule.Cancel() {
			log.Printf("energia agendada cancelada no PC")
			s.history.Add("Este PC", histSchedule, "cancelou o agendamento", false)
			s.hub.Publish(Event{Type: "notify", Text: "Cancelado no PC: " + scheduleText(p) + "."})
		}
	case cmd == menuNotices:
		s.mu.Lock()
		on := !s.cfg.trayNotices()
		s.cfg.TrayNotices = &on
		s.persist()
		s.mu.Unlock()
	case cmd == menuUpdateCheck:
		s.mu.Lock()
		on := !s.cfg.updateCheck()
		s.cfg.UpdateCheck = &on
		s.persist()
		s.mu.Unlock()
		if on {
			go s.updates.Check()
		}
	case cmd == menuCheckUpdates:
		go t.checkUpdatesNow()
	case cmd == menuUpdate:
		if r, ok := s.updates.Pending(); ok && strings.HasPrefix(r.Page, releasesPage) {
			exec.Command("xdg-open", r.Page).Start()
		} else {
			exec.Command("xdg-open", releasesPage+"latest").Start()
		}
	case cmd == menuHistory:
		go t.showHistory()
	case cmd == menuConfig:
		exec.Command("xdg-open", filepath.Dir(s.configPath)).Start()
	case cmd == menuQuit:
		go t.confirmQuit()
	case cmd >= menuRevokeBase && cmd-menuRevokeBase < len(t.menuDevicesSnapshot()):
		go t.confirmRevoke(t.menuDevicesSnapshot()[cmd-menuRevokeBase])
	}
	if t.rebuild() {
		t.emitLayoutUpdated()
	}
}

func (t *linuxTray) menuDevicesSnapshot() []PairedDevice {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.menuDevices
}

func (t *linuxTray) checkUpdatesNow() {
	r, newer, err := t.srv.updates.CheckNow()
	switch {
	case err != nil:
		t.Notify("Não deu para procurar atualizações", err.Error())
	case newer:
		t.Notify("Velksync "+r.Version()+" disponível", "Baixe a versão nova na página de versões e rode o install-linux.sh.")
	default:
		t.Notify("Nenhuma atualização", "O Velksync "+version+" é a versão mais recente (última publicada: "+r.Version()+").")
	}
}

func (t *linuxTray) showHistory() {
	s := t.srv
	entries := s.history.List(15, s.cfg.AllowShell)
	text := "Nada por enquanto."
	if len(entries) > 0 {
		now := time.Now()
		lines := make([]string, len(entries))
		for i, e := range entries {
			lines[i] = historyLine(e, now)
		}
		text = strings.Join(lines, "\n")
	}
	t.Notify("Histórico", text)
}

func (t *linuxTray) confirmRevoke(d PairedDevice) {
	if !t.confirm("Revogar "+d.Name+"?",
		"Ele perde o acesso a este PC na hora; para usar de novo, pareie pelo QR. No dual boot, revogue também no outro sistema.",
		"Revogar") {
		return
	}
	ids := t.srv.revoke(d.ID)
	log.Printf("revogado no PC: %v", ids)
	t.srv.history.Add("Este PC", histRevoke, "revogou "+d.Name, false)
	t.Notify("Celular revogado", d.Name)
	if t.rebuild() {
		t.emitLayoutUpdated()
	}
}

func (t *linuxTray) confirmQuit() {
	if !t.confirm("Sair do agente?",
		"O celular deixa de controlar este PC até o agente subir de novo (no próximo login, ou com systemctl --user start velksync-agent). "+
			"Ligar pelo celular e o sinal de presença continuam funcionando.",
		"Sair") {
		return
	}
	log.Printf("bandeja: saindo a pedido de quem está no PC")
	t.conn.Close()
	// Parar pelo systemd evita o Restart=on-failure e mantém o serviço
	// desligado até a próxima sessão; sem systemd, sai direto.
	if err := exec.Command("systemctl", "--user", "stop", "velksync-agent").Run(); err != nil {
		os.Exit(0)
	}
}

// ---------- StatusNotifierItem ----------

type sniToolTip struct {
	IconName string
	Pixmaps  []sniPixmap
	Title    string
	Text     string
}

type sniPixmap struct {
	W, H int32
	Pix  []byte
}

type sniObject struct{ t *linuxTray }

// O menu abre no clique (ItemIsMenu); os outros gestos não fazem nada.
func (*sniObject) Activate(x, y int32) *dbus.Error          { return nil }
func (*sniObject) SecondaryActivate(x, y int32) *dbus.Error { return nil }
func (*sniObject) ContextMenu(x, y int32) *dbus.Error       { return nil }
func (*sniObject) Scroll(delta int32, orientation string) *dbus.Error {
	return nil
}

// iconPixmaps reduz o PNG para cada tamanho, no formato do protocolo: ARGB,
// um byte por canal, ordem de rede.
func iconPixmaps(data []byte, sizes ...int) ([]sniPixmap, error) {
	src, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	b := src.Bounds()
	rgba := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	draw.Draw(rgba, rgba.Bounds(), src, b.Min, draw.Src)
	out := make([]sniPixmap, 0, len(sizes))
	for _, n := range sizes {
		out = append(out, sniPixmap{W: int32(n), H: int32(n), Pix: scaleARGB(rgba, n)})
	}
	return out, nil
}

// scaleARGB faz a média por área (as cores já vêm multiplicadas pelo alfa,
// então a média não suja as bordas transparentes).
func scaleARGB(src *image.RGBA, n int) []byte {
	sw, sh := src.Bounds().Dx(), src.Bounds().Dy()
	pix := make([]byte, 0, n*n*4)
	for y := 0; y < n; y++ {
		y0, y1 := y*sh/n, max((y+1)*sh/n, y*sh/n+1)
		for x := 0; x < n; x++ {
			x0, x1 := x*sw/n, max((x+1)*sw/n, x*sw/n+1)
			var r, g, bl, a, cnt uint32
			for yy := y0; yy < y1; yy++ {
				for xx := x0; xx < x1; xx++ {
					i := src.PixOffset(xx, yy)
					r += uint32(src.Pix[i])
					g += uint32(src.Pix[i+1])
					bl += uint32(src.Pix[i+2])
					a += uint32(src.Pix[i+3])
					cnt++
				}
			}
			r, g, bl, a = r/cnt, g/cnt, bl/cnt, a/cnt
			if a > 0 { // desmultiplica: o protocolo quer cor direta
				r, g, bl = min(r*255/a, 255), min(g*255/a, 255), min(bl*255/a, 255)
			}
			pix = append(pix, byte(a), byte(r), byte(g), byte(bl))
		}
	}
	return pix
}

// ---------- dbusmenu ----------

type dmNode struct {
	id    int32
	cmd   int // menuItem.ID; 0 para texto, separador e submenu
	props map[string]dbus.Variant
	kids  []*dmNode
}

type dmLayout struct {
	ID       int32
	Props    map[string]dbus.Variant
	Children []dbus.Variant
}

type dmProps struct {
	ID    int32
	Props map[string]dbus.Variant
}

type dmEvent struct {
	ID        int32
	EventID   string
	Data      dbus.Variant
	Timestamp uint32
}

// buildDM converte o menu para a árvore do dbusmenu, com ids sequenciais
// (a raiz é 0).
func buildDM(items []menuItem) (*dmNode, map[int32]*dmNode) {
	byID := map[int32]*dmNode{}
	var next int32
	var build func(its []menuItem) []*dmNode
	build = func(its []menuItem) []*dmNode {
		var nodes []*dmNode
		for _, it := range its {
			next++
			n := &dmNode{id: next, cmd: it.ID, props: map[string]dbus.Variant{}}
			byID[n.id] = n
			if it.Sep {
				n.props["type"] = dbus.MakeVariant("separator")
			} else {
				n.props["label"] = dbus.MakeVariant(strings.ReplaceAll(it.Text, "_", "__"))
				n.props["enabled"] = dbus.MakeVariant(!it.Disabled)
				if it.ID == menuNotices || it.ID == menuUpdateCheck {
					n.props["toggle-type"] = dbus.MakeVariant("checkmark")
					state := int32(0)
					if it.Checked {
						state = 1
					}
					n.props["toggle-state"] = dbus.MakeVariant(state)
				}
				if len(it.Sub) > 0 {
					n.props["children-display"] = dbus.MakeVariant("submenu")
					n.kids = build(it.Sub)
				}
			}
			nodes = append(nodes, n)
		}
		return nodes
	}
	root := &dmNode{props: map[string]dbus.Variant{"children-display": dbus.MakeVariant("submenu")}}
	root.kids = build(items)
	byID[0] = root
	return root, byID
}

func (n *dmNode) layout(depth int) dmLayout {
	l := dmLayout{ID: n.id, Props: n.props, Children: []dbus.Variant{}}
	if depth != 0 {
		for _, k := range n.kids {
			l.Children = append(l.Children, dbus.MakeVariant(k.layout(depth-1)))
		}
	}
	return l
}

type menuObject struct{ t *linuxTray }

func (m *menuObject) GetLayout(parent, depth int32, names []string) (uint32, dmLayout, *dbus.Error) {
	if parent == 0 {
		m.t.rebuild()
	}
	m.t.mu.Lock()
	defer m.t.mu.Unlock()
	n := m.t.byID[parent]
	if n == nil {
		return m.t.rev, dmLayout{}, dbus.MakeFailedError(fmt.Errorf("item %d não existe", parent))
	}
	return m.t.rev, n.layout(int(depth)), nil
}

func (m *menuObject) GetGroupProperties(ids []int32, names []string) ([]dmProps, *dbus.Error) {
	m.t.mu.Lock()
	defer m.t.mu.Unlock()
	if len(ids) == 0 {
		for id := range m.t.byID {
			ids = append(ids, id)
		}
	}
	out := []dmProps{}
	for _, id := range ids {
		if n := m.t.byID[id]; n != nil {
			out = append(out, dmProps{ID: id, Props: n.props})
		}
	}
	return out, nil
}

func (m *menuObject) GetProperty(id int32, name string) (dbus.Variant, *dbus.Error) {
	m.t.mu.Lock()
	defer m.t.mu.Unlock()
	if n := m.t.byID[id]; n != nil {
		if v, ok := n.props[name]; ok {
			return v, nil
		}
	}
	return dbus.MakeVariant(""), dbus.MakeFailedError(fmt.Errorf("propriedade %q não existe", name))
}

func (m *menuObject) Event(id int32, event string, data dbus.Variant, ts uint32) *dbus.Error {
	if event != "clicked" {
		return nil
	}
	m.t.mu.Lock()
	n := m.t.byID[id]
	m.t.mu.Unlock()
	if n != nil && n.cmd != 0 {
		go m.t.command(n.cmd)
	}
	return nil
}

func (m *menuObject) EventGroup(events []dmEvent) ([]int32, *dbus.Error) {
	for _, e := range events {
		m.Event(e.ID, e.EventID, e.Data, e.Timestamp)
	}
	return []int32{}, nil
}

func (m *menuObject) AboutToShow(id int32) (bool, *dbus.Error) {
	return m.t.rebuild(), nil
}

func (m *menuObject) AboutToShowGroup(ids []int32) ([]int32, []int32, *dbus.Error) {
	if m.t.rebuild() {
		return []int32{0}, []int32{}, nil
	}
	return []int32{}, []int32{}, nil
}
