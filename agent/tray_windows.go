package main

import (
	_ "embed"
	"encoding/binary"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	qrcode "github.com/skip2/go-qrcode"
	"golang.org/x/sys/windows"
)

// Ícone na bandeja do Windows, avisos, a contagem antes de desligar e a
// janela do QR, direto sobre a API do Windows (sem biblioteca de interface).
// Tudo que é janela roda numa thread travada com laço de mensagens próprio:
// o ícone e a janela do QR na thread da bandeja; cada caixa de diálogo
// (TaskDialog) na sua.

//go:embed deploy/installer/velksync.ico
var appIcon []byte

var (
	user32    = windows.NewLazySystemDLL("user32.dll")
	shell32   = windows.NewLazySystemDLL("shell32.dll")
	gdi32     = windows.NewLazySystemDLL("gdi32.dll")
	kernel32w = windows.NewLazySystemDLL("kernel32.dll")
	// Sem caminho de sistema de propósito: o comctl32 v6 (o dos botões
	// modernos e do TaskDialog) vem do contexto de ativação, pelo nome.
	comctl32 = windows.NewLazyDLL("comctl32.dll")

	procRegisterClassEx        = user32.NewProc("RegisterClassExW")
	procCreateWindowEx         = user32.NewProc("CreateWindowExW")
	procDefWindowProc          = user32.NewProc("DefWindowProcW")
	procDestroyWindow          = user32.NewProc("DestroyWindow")
	procGetMessage             = user32.NewProc("GetMessageW")
	procTranslateMessage       = user32.NewProc("TranslateMessage")
	procDispatchMessage        = user32.NewProc("DispatchMessageW")
	procPostMessage            = user32.NewProc("PostMessageW")
	procSendMessage            = user32.NewProc("SendMessageW")
	procRegisterWindowMessage  = user32.NewProc("RegisterWindowMessageW")
	procCreatePopupMenu        = user32.NewProc("CreatePopupMenu")
	procAppendMenu             = user32.NewProc("AppendMenuW")
	procTrackPopupMenu         = user32.NewProc("TrackPopupMenu")
	procDestroyMenu            = user32.NewProc("DestroyMenu")
	procSetForegroundWindow    = user32.NewProc("SetForegroundWindow")
	procGetCursorPos           = user32.NewProc("GetCursorPos")
	procSetTimer               = user32.NewProc("SetTimer")
	procKillTimer              = user32.NewProc("KillTimer")
	procShowWindow             = user32.NewProc("ShowWindow")
	procSetWindowPos           = user32.NewProc("SetWindowPos")
	procBeginPaint             = user32.NewProc("BeginPaint")
	procEndPaint               = user32.NewProc("EndPaint")
	procFillRect               = user32.NewProc("FillRect")
	procDrawText               = user32.NewProc("DrawTextW")
	procInvalidateRect         = user32.NewProc("InvalidateRect")
	procGetClientRect          = user32.NewProc("GetClientRect")
	procLoadCursor             = user32.NewProc("LoadCursorW")
	procGetDpiForWindow        = user32.NewProc("GetDpiForWindow")
	procGetDpiForSystem        = user32.NewProc("GetDpiForSystem")
	procGetSystemMetricsForDpi = user32.NewProc("GetSystemMetricsForDpi")
	procAdjustWindowRectExDpi  = user32.NewProc("AdjustWindowRectExForDpi")
	procSystemParametersInfo   = user32.NewProc("SystemParametersInfoW")
	procSetProcessDpiAwareCtx  = user32.NewProc("SetProcessDpiAwarenessContext")
	procCreateIconFromResEx    = user32.NewProc("CreateIconFromResourceEx")
	procOpenInputDesktop       = user32.NewProc("OpenInputDesktop")
	procCloseDesktop           = user32.NewProc("CloseDesktop")
	procGetUserObjectInfo      = user32.NewProc("GetUserObjectInformationW")
	procShellNotifyIcon        = shell32.NewProc("Shell_NotifyIconW")
	procShellExecuteEx         = shell32.NewProc("ShellExecuteExW")
	procCreateFont             = gdi32.NewProc("CreateFontW")
	procSelectObject           = gdi32.NewProc("SelectObject")
	procDeleteObject           = gdi32.NewProc("DeleteObject")
	procGetStockObject         = gdi32.NewProc("GetStockObject")
	procSetBkMode              = gdi32.NewProc("SetBkMode")
	procSetTextColor           = gdi32.NewProc("SetTextColor")
	procGetModuleHandle        = kernel32w.NewProc("GetModuleHandleW")
	procCreateActCtx           = kernel32w.NewProc("CreateActCtxW")
	procActivateActCtx         = kernel32w.NewProc("ActivateActCtx")
	procDeactivateActCtx       = kernel32w.NewProc("DeactivateActCtx")
	procTaskDialogIndirect     = comctl32.NewProc("TaskDialogIndirect")
)

const (
	wmNull        = 0x0000
	wmDestroy     = 0x0002
	wmPaint       = 0x000F
	wmClose       = 0x0010
	wmContextMenu = 0x007B
	wmKeyDown     = 0x0100
	wmTimer       = 0x0113
	wmDpiChanged  = 0x02E0
	wmUser        = 0x0400
	wmApp         = 0x8000
	wmTrayIcon    = wmApp + 1
	wmTrayCall    = wmApp + 2

	ninSelect    = wmUser + 0
	ninKeySelect = wmUser + 1

	nimAdd        = 0
	nimModify     = 1
	nimDelete     = 2
	nimSetVersion = 4
	nifMessage    = 0x01
	nifIcon       = 0x02
	nifTip        = 0x04
	nifInfo       = 0x10
	nifShowTip    = 0x80
	niifUser      = 0x04
	niifLargeIcon = 0x20

	mfString    = 0x0000
	mfGrayed    = 0x0001
	mfChecked   = 0x0008
	mfPopup     = 0x0010
	mfSeparator = 0x0800

	tpmRightButton = 0x0002
	tpmNoNotify    = 0x0080
	tpmReturnCmd   = 0x0100

	wsOverlapped  = 0x00000000
	wsCaption     = 0x00C00000
	wsSysMenu     = 0x00080000
	wsMinimizeBox = 0x00020000

	swShow     = 5
	swHide     = 0
	swpNoSize  = 0x0001
	swpNoMove  = 0x0002
	swpNoZOrd  = 0x0004
	swpNoActiv = 0x0010

	smCxSmIcon = 49
	smCxIcon   = 11

	dtCenter    = 0x0001
	dtWordBreak = 0x0010
	dtNoPrefix  = 0x0800

	vkEscape = 0x1B
)

var hwndTopmost = ^uintptr(0) // HWND_TOPMOST (-1)

type point struct{ X, Y int32 }

type rect struct{ Left, Top, Right, Bottom int32 }

type winMsg struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
	Private uint32
}

type wndClassEx struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

type paintStruct struct {
	Hdc       uintptr
	Erase     int32
	Paint     rect
	Restore   int32
	IncUpdate int32
	Reserved  [32]byte
}

type notifyIconData struct {
	Size            uint32
	Wnd             uintptr
	ID              uint32
	Flags           uint32
	CallbackMessage uint32
	Icon            uintptr
	Tip             [128]uint16
	State           uint32
	StateMask       uint32
	Info            [256]uint16
	Version         uint32
	InfoTitle       [64]uint16
	InfoFlags       uint32
	GUIDItem        windows.GUID
	BalloonIcon     uintptr
}

func toUTF16(s string) []uint16 {
	u, err := windows.UTF16FromString(s)
	if err != nil { // NUL no meio: corta ali
		u, _ = windows.UTF16FromString(strings.ReplaceAll(s, "\x00", ""))
	}
	return u
}

func copyUTF16(dst []uint16, s string) {
	u := toUTF16(s)
	if len(u) > len(dst) {
		u = append(u[:len(dst)-1:len(dst)-1], 0)
	}
	copy(dst, u)
}

func moduleHandle() uintptr {
	h, _, _ := procGetModuleHandle.Call(0)
	return h
}

// ---------- Contexto de ativação: comctl32 v6 ----------

// O TaskDialog e os botões com o visual atual vêm do comctl32 v6, que um
// .exe sem manifesto não recebe. O shell32 traz um manifesto pedindo o v6
// (recurso 124); ativá-lo na thread tem o mesmo efeito.
type actCtxW struct {
	Size              uint32
	Flags             uint32
	Source            *uint16
	ProcessorArch     uint16
	LangID            uint16
	AssemblyDirectory *uint16
	ResourceName      uintptr
	ApplicationName   *uint16
	Module            uintptr
}

var (
	actCtxOnce   sync.Once
	actCtxHandle uintptr
)

func activateCommonControls() uintptr {
	actCtxOnce.Do(func() {
		sys, err := windows.GetSystemDirectory()
		if err != nil {
			return
		}
		src, _ := windows.UTF16PtrFromString(filepath.Join(sys, "shell32.dll"))
		const resourceNameValid = 0x08
		ac := actCtxW{Flags: resourceNameValid, Source: src, ResourceName: 124}
		ac.Size = uint32(unsafe.Sizeof(ac))
		h, _, err := procCreateActCtx.Call(uintptr(unsafe.Pointer(&ac)))
		if h == uintptr(windows.InvalidHandle) {
			log.Printf("bandeja: sem comctl32 v6: %v", err)
			return
		}
		actCtxHandle = h
	})
	var cookie uintptr
	if actCtxHandle != 0 {
		procActivateActCtx.Call(actCtxHandle, uintptr(unsafe.Pointer(&cookie)))
	}
	return cookie
}

func deactivateCommonControls(cookie uintptr) {
	if cookie != 0 {
		procDeactivateActCtx.Call(0, cookie)
	}
}

// ---------- Ícone ----------

// iconFromICO escolhe no .ico embutido a imagem do tamanho pedido (ou a
// menor maior que ele) e cria o ícone.
func iconFromICO(data []byte, size int) uintptr {
	if len(data) < 6 {
		return 0
	}
	count := int(binary.LittleEndian.Uint16(data[4:]))
	best, bestW := -1, 0
	for i := range count {
		e := data[6+16*i:]
		w := int(e[0])
		if w == 0 {
			w = 256
		}
		if best < 0 || (w >= size && (bestW < size || w < bestW)) || (bestW < size && w > bestW) {
			best, bestW = i, w
		}
	}
	if best < 0 {
		return 0
	}
	e := data[6+16*best:]
	n, off := binary.LittleEndian.Uint32(e[8:]), binary.LittleEndian.Uint32(e[12:])
	if int(off)+int(n) > len(data) {
		return 0
	}
	img := data[off : off+n]
	h, _, _ := procCreateIconFromResEx.Call(uintptr(unsafe.Pointer(&img[0])), uintptr(n), 1, 0x00030000,
		uintptr(size), uintptr(size), 0)
	return h
}

func systemMetric(index int) int {
	dpi, _, _ := procGetDpiForSystem.Call()
	v, _, _ := procGetSystemMetricsForDpi.Call(uintptr(index), dpi)
	return int(v)
}

// ---------- Bandeja ----------

type tray struct {
	srv            *Server
	hwnd           uintptr
	icon, bigIcon  uintptr
	taskbarCreated uint32
	calls          chan func()
	nidMu          sync.Mutex
	shown          bool
	menuDevices    []PairedDevice
	pair           *pairWindow
	updating       atomic.Bool
}

var theTray *tray

var trayWndProc = windows.NewCallback(func(hwnd, m, wp, lp uintptr) uintptr {
	if t := theTray; t != nil && hwnd == t.hwnd {
		if r, ok := t.handle(uint32(m), wp, lp); ok {
			return r
		}
	}
	r, _, _ := procDefWindowProc.Call(hwnd, m, wp, lp)
	return r
})

func startDesktop(s *Server) desktop {
	t := &tray{srv: s, calls: make(chan func(), 16)}
	theTray = t
	ready := make(chan error, 1)
	go t.loop(ready)
	if err := <-ready; err != nil {
		theTray = nil
		log.Printf("bandeja: %v (seguindo sem ícone)", err)
		return noDesktop{}
	}
	return t
}

func (t *tray) loop(ready chan<- error) {
	runtime.LockOSThread()
	activateCommonControls()                    // ativo para sempre nesta thread
	procSetProcessDpiAwareCtx.Call(^uintptr(3)) // PER_MONITOR_AWARE_V2 (-4)
	if err := procTaskDialogIndirect.Find(); err != nil {
		log.Printf("bandeja: TaskDialog indisponível: %v", err)
	}

	inst := moduleHandle()
	cls, _ := windows.UTF16PtrFromString("VelksyncTray")
	wc := wndClassEx{WndProc: trayWndProc, Instance: inst, ClassName: cls}
	wc.Size = uint32(unsafe.Sizeof(wc))
	if r, _, err := procRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc))); r == 0 {
		ready <- fmt.Errorf("RegisterClassEx: %w", err)
		return
	}
	title, _ := windows.UTF16PtrFromString("Velksync")
	hwnd, _, err := procCreateWindowEx.Call(0, uintptr(unsafe.Pointer(cls)), uintptr(unsafe.Pointer(title)), 0,
		0, 0, 0, 0, 0, 0, inst, 0)
	if hwnd == 0 {
		ready <- fmt.Errorf("CreateWindowEx: %w", err)
		return
	}
	t.hwnd = hwnd
	tc, _ := windows.UTF16PtrFromString("TaskbarCreated")
	r, _, _ := procRegisterWindowMessage.Call(uintptr(unsafe.Pointer(tc)))
	t.taskbarCreated = uint32(r)
	t.icon = iconFromICO(appIcon, systemMetric(smCxSmIcon))
	t.bigIcon = iconFromICO(appIcon, systemMetric(smCxIcon))
	// No logon a barra de tarefas pode ainda não existir: tenta de novo a
	// cada 2 s (e o TaskbarCreated avisa quando ela subir).
	if !t.addIcon() {
		procSetTimer.Call(hwnd, 1, 2000, 0)
	}
	ready <- nil

	var m winMsg
	for {
		r, _, _ := procGetMessage.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) <= 0 {
			return
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessage.Call(uintptr(unsafe.Pointer(&m)))
	}
}

// call roda f na thread da bandeja (janelas só podem ser mexidas por ela).
func (t *tray) call(f func()) {
	t.calls <- f
	procPostMessage.Call(t.hwnd, wmTrayCall, 0, 0)
}

func (t *tray) handle(m uint32, wp, lp uintptr) (uintptr, bool) {
	switch {
	case m == wmTrayIcon:
		switch lp & 0xFFFF {
		case wmContextMenu, ninSelect, ninKeySelect:
			t.showMenu()
		}
		return 0, true
	case m == wmTrayCall:
		for {
			select {
			case f := <-t.calls:
				f()
			default:
				return 0, true
			}
		}
	case m == wmTimer && wp == 1:
		if t.addIcon() {
			procKillTimer.Call(t.hwnd, 1)
		}
		return 0, true
	case m == t.taskbarCreated && m != 0:
		t.shown = false
		t.addIcon()
		return 0, true
	}
	return 0, false
}

func (t *tray) nid() notifyIconData {
	n := notifyIconData{Wnd: t.hwnd, ID: 1}
	n.Size = uint32(unsafe.Sizeof(n))
	return n
}

func (t *tray) addIcon() bool {
	t.nidMu.Lock()
	defer t.nidMu.Unlock()
	n := t.nid()
	n.Flags = nifMessage | nifIcon | nifTip | nifShowTip
	n.CallbackMessage = wmTrayIcon
	n.Icon = t.icon
	copyUTF16(n.Tip[:], "Velksync "+version)
	if r, _, _ := procShellNotifyIcon.Call(nimAdd, uintptr(unsafe.Pointer(&n))); r == 0 {
		// Já existe (o Explorer reiniciou rápido): atualiza no lugar.
		if r, _, _ := procShellNotifyIcon.Call(nimModify, uintptr(unsafe.Pointer(&n))); r == 0 {
			return false
		}
	}
	n.Version = 4 // NOTIFYICON_VERSION_4: clique e teclado como o resto do sistema
	procShellNotifyIcon.Call(nimSetVersion, uintptr(unsafe.Pointer(&n)))
	t.shown = true
	return true
}

func (t *tray) removeIcon() {
	t.nidMu.Lock()
	defer t.nidMu.Unlock()
	n := t.nid()
	procShellNotifyIcon.Call(nimDelete, uintptr(unsafe.Pointer(&n)))
}

// Notify mostra um aviso do Windows saindo do ícone.
func (t *tray) Notify(title, text string) {
	t.nidMu.Lock()
	defer t.nidMu.Unlock()
	if !t.shown {
		return
	}
	n := t.nid()
	n.Flags = nifInfo
	copyUTF16(n.InfoTitle[:], title)
	copyUTF16(n.Info[:], text)
	n.InfoFlags = niifUser | niifLargeIcon
	n.BalloonIcon = t.bigIcon
	procShellNotifyIcon.Call(nimModify, uintptr(unsafe.Pointer(&n)))
}

// Present: a sessão está desbloqueada. Com a tela bloqueada, a área de
// trabalho de entrada é a do Winlogon, que um programa comum não abre.
func (t *tray) Present() bool {
	const desktopReadObjects, uoiName = 0x0001, 2
	h, _, _ := procOpenInputDesktop.Call(0, 0, desktopReadObjects)
	if h == 0 {
		return false
	}
	defer procCloseDesktop.Call(h)
	var name [64]uint16
	var need uint32
	r, _, _ := procGetUserObjectInfo.Call(h, uoiName, uintptr(unsafe.Pointer(&name[0])),
		uintptr(len(name)*2), uintptr(unsafe.Pointer(&need)))
	return r != 0 && strings.EqualFold(windows.UTF16ToString(name[:]), "Default")
}

func (t *tray) ShowPair() error {
	t.call(t.openPairWindow)
	return nil
}

// ---------- Menu ----------

func (t *tray) state() trayState {
	s := t.srv
	s.mu.Lock()
	devices := slices.Clone(s.cfg.Devices)
	notices := s.cfg.trayNotices()
	updateCheck := s.cfg.updateCheck()
	s.mu.Unlock()
	st := trayState{Version: version, Devices: devices, Notices: notices, Schedule: s.schedule.Current(),
		UpdateCheck: updateCheck}
	// Pending, não Available: a versão achada pelo "Procurar agora" aparece
	// mesmo com a checagem automática desligada.
	if r, ok := s.updates.Pending(); ok {
		st.Update = r.Version()
	}
	st.Updating = t.updating.Load()
	if ip, err := lanIP(); err == nil {
		st.IP = ip.String()
	}
	if s.live != nil {
		st.Clients = s.live.Clients()
	}
	return st
}

func buildMenu(items []menuItem) uintptr {
	h, _, _ := procCreatePopupMenu.Call()
	for _, it := range items {
		if it.Sep {
			procAppendMenu.Call(h, mfSeparator, 0, 0)
			continue
		}
		var flags uintptr = mfString
		if it.Disabled {
			flags |= mfGrayed
		}
		if it.Checked {
			flags |= mfChecked
		}
		// & marca a tecla de atalho no menu; nos nomes vira um & de verdade.
		text := toUTF16(strings.ReplaceAll(it.Text, "&", "&&"))
		id := uintptr(it.ID)
		if len(it.Sub) > 0 {
			flags |= mfPopup
			id = buildMenu(it.Sub)
		}
		procAppendMenu.Call(h, flags, id, uintptr(unsafe.Pointer(&text[0])))
	}
	return h
}

func (t *tray) showMenu() {
	st := t.state()
	t.menuDevices = st.Devices
	h := buildMenu(trayMenu(st))
	defer procDestroyMenu.Call(h)
	var pt point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	// Sem isso o menu não fecha ao clicar fora (comportamento documentado).
	procSetForegroundWindow.Call(t.hwnd)
	cmd, _, _ := procTrackPopupMenu.Call(h, tpmReturnCmd|tpmNoNotify|tpmRightButton,
		uintptr(pt.X), uintptr(pt.Y), 0, t.hwnd, 0)
	procPostMessage.Call(t.hwnd, wmNull, 0, 0)
	t.command(int(cmd))
}

func (t *tray) command(cmd int) {
	s := t.srv
	switch {
	case cmd == menuPair:
		t.openPairWindow()
	case cmd == menuDoctor:
		go t.doctor()
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
	case cmd == menuCheckUpdates:
		go t.checkUpdatesNow()
	case cmd == menuHistory:
		go t.showHistory()
	case cmd == menuUpdate:
		go t.offerUpdate()
	case cmd == menuUpdateCheck:
		s.mu.Lock()
		on := !s.cfg.updateCheck()
		s.cfg.UpdateCheck = &on
		s.persist()
		s.mu.Unlock()
		if on {
			go s.updates.Check()
		}
	case cmd == menuLog:
		shellOpen(defaultLogPath(s.configPath))
	case cmd == menuConfig:
		shellOpen(filepath.Dir(s.configPath))
	case cmd == menuQuit:
		go t.confirmQuit()
	case cmd >= menuRevokeBase && cmd-menuRevokeBase < len(t.menuDevices):
		d := t.menuDevices[cmd-menuRevokeBase]
		go t.confirmRevoke(d)
	}
}

func shellOpen(path string) {
	verb, _ := windows.UTF16PtrFromString("open")
	file, _ := windows.UTF16PtrFromString(path)
	if err := windows.ShellExecute(0, verb, file, nil, nil, windows.SW_SHOWNORMAL); err != nil {
		log.Printf("bandeja: abrir %s: %v", path, err)
	}
}

// ---------- Caixas de diálogo ----------

const (
	idOK      = 1
	idCancel  = 2
	idClose   = 8
	idPrimary = 100

	tdcbfOK     = 0x01
	tdcbfCancel = 0x08
	tdcbfClose  = 0x20

	tdIconWarning uintptr = 0xFFFF // TD_WARNING_ICON
	tdIconInfo    uintptr = 0xFFFD // TD_INFORMATION_ICON
	tdIconShield  uintptr = 0xFFFC // TD_SHIELD_ICON
)

type taskDialogOpts struct {
	instruction, content, footer string
	icon                         uintptr
	button                       string // botão principal (idPrimary), opcional
	common                       uint32
	defaultID                    int32
	progress                     bool
	onCreated                    func(hwnd uintptr)
	onTimer                      func(hwnd uintptr, ms uint32)
}

// Os textos e botões ficam aqui (memória do heap, que não se move) enquanto
// o TaskDialog lê os ponteiros que estão dentro da configuração.
var (
	dialogMu   sync.Mutex
	dialogs    = map[uintptr]*dialogState{}
	dialogNext uintptr
)

type dialogState struct {
	opts *taskDialogOpts
	keep [][]uint16
	cfg  []byte
	btns []byte
}

var taskDialogCallback = windows.NewCallback(func(hwnd, m, wp, lp, ref uintptr) uintptr {
	dialogMu.Lock()
	d := dialogs[ref]
	dialogMu.Unlock()
	if d == nil {
		return 0
	}
	const tdnCreated, tdnTimer = 0, 4
	switch m {
	case tdnCreated:
		if d.opts.onCreated != nil {
			d.opts.onCreated(hwnd)
		}
	case tdnTimer:
		if d.opts.onTimer != nil {
			d.opts.onTimer(hwnd, uint32(wp))
		}
	}
	return 0
})

// taskDialog mostra uma caixa padrão do Windows e devolve o botão clicado.
// A configuração do TaskDialog é empacotada (pshpack1), por isso é montada
// byte a byte e não como struct do Go.
func taskDialog(o taskDialogOpts) (int32, error) {
	if err := procTaskDialogIndirect.Find(); err != nil {
		return 0, err
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	defer deactivateCommonControls(activateCommonControls())

	d := &dialogState{opts: &o, cfg: make([]byte, 160)}
	str := func(s string) uint64 {
		if s == "" {
			return 0
		}
		u := toUTF16(s)
		d.keep = append(d.keep, u)
		return uint64(uintptr(unsafe.Pointer(&u[0])))
	}
	c := d.cfg
	put32 := func(off int, v uint32) { binary.LittleEndian.PutUint32(c[off:], v) }
	put64 := func(off int, v uint64) { binary.LittleEndian.PutUint64(c[off:], v) }

	const (
		tdfAllowCancel   = 0x0008
		tdfProgressBar   = 0x0200
		tdfCallbackTimer = 0x0800
		tdfSizeToContent = 0x01000000
	)
	flags := uint32(tdfAllowCancel | tdfSizeToContent)
	if o.progress {
		flags |= tdfProgressBar
	}
	if o.onTimer != nil {
		flags |= tdfCallbackTimer
	}
	dialogMu.Lock()
	dialogNext++
	id := dialogNext
	dialogs[id] = d
	dialogMu.Unlock()
	defer func() {
		dialogMu.Lock()
		delete(dialogs, id)
		dialogMu.Unlock()
	}()

	put32(0, 160)                 // cbSize
	put32(20, flags)              // dwFlags
	put32(24, o.common)           // dwCommonButtons
	put64(28, str("Velksync"))    // pszWindowTitle
	put64(36, uint64(o.icon))     // pszMainIcon
	put64(44, str(o.instruction)) // pszMainInstruction
	put64(52, str(o.content))     // pszContent
	if o.button != "" {
		d.btns = make([]byte, 12)
		binary.LittleEndian.PutUint32(d.btns[0:], idPrimary)
		binary.LittleEndian.PutUint64(d.btns[4:], str(o.button))
		put32(60, 1)                                           // cButtons
		put64(64, uint64(uintptr(unsafe.Pointer(&d.btns[0])))) // pButtons
	}
	put32(72, uint32(o.defaultID)) // nDefaultButton
	if o.footer != "" {
		put64(124, uint64(tdIconInfo)) // pszFooterIcon
		put64(132, str(o.footer))      // pszFooter
	}
	put64(140, uint64(taskDialogCallback)) // pfCallback
	put64(148, uint64(id))                 // lpCallbackData

	var pressed int32
	hr, _, _ := procTaskDialogIndirect.Call(uintptr(unsafe.Pointer(&d.cfg[0])), uintptr(unsafe.Pointer(&pressed)), 0, 0)
	runtime.KeepAlive(d)
	if hr != 0 {
		return 0, fmt.Errorf("TaskDialogIndirect: 0x%x", uint32(hr))
	}
	return pressed, nil
}

func setDialogText(hwnd uintptr, s string) {
	const tdmSetElementText, tdeContent = wmUser + 108, 0
	u := toUTF16(s)
	procSendMessage.Call(hwnd, tdmSetElementText, tdeContent, uintptr(unsafe.Pointer(&u[0])))
}

func bringToFront(hwnd uintptr) {
	procSetWindowPos.Call(hwnd, hwndTopmost, 0, 0, 0, 0, swpNoMove|swpNoSize)
	procSetForegroundWindow.Call(hwnd)
}

// AskPower mostra a contagem. Enter e Esc cancelam: o padrão é não desligar
// uma máquina em uso.
func (t *tray) AskPower(action, by string, grace time.Duration) bool {
	const tdmClickButton, tdmSetRange, tdmSetPos = wmUser + 102, wmUser + 105, wmUser + 106
	instruction, content := powerPrompt(action, by, grace)
	total := uint32(grace / time.Millisecond)
	lastSecs, fired := -1, false
	verb := powerVerb(action)
	pressed, err := taskDialog(taskDialogOpts{
		instruction: instruction, content: content, icon: tdIconWarning,
		button: strings.ToUpper(verb[:1]) + verb[1:] + " agora", common: tdcbfCancel, defaultID: idCancel,
		progress: true,
		onCreated: func(hwnd uintptr) {
			procSendMessage.Call(hwnd, tdmSetRange, 0, uintptr(total/100)<<16)
			bringToFront(hwnd)
		},
		onTimer: func(hwnd uintptr, ms uint32) {
			if ms >= total {
				if !fired {
					fired = true
					procSendMessage.Call(hwnd, tdmClickButton, idPrimary, 0)
				}
				return
			}
			procSendMessage.Call(hwnd, tdmSetPos, uintptr(ms/100), 0)
			left := grace - time.Duration(ms)*time.Millisecond
			if secs := int((left + time.Second - 1) / time.Second); secs != lastSecs {
				lastSecs = secs
				_, c := powerPrompt(action, by, left)
				setDialogText(hwnd, c)
			}
		},
	})
	if err != nil {
		// Sem a caixa, ninguém consegue cancelar: segue como antes da contagem.
		log.Printf("bandeja: contagem: %v", err)
		return true
	}
	return pressed == idPrimary
}

func (t *tray) info(instruction, content string) {
	if _, err := taskDialog(taskDialogOpts{instruction: instruction, content: content, icon: tdIconInfo,
		common: tdcbfOK}); err != nil {
		log.Printf("bandeja: %s: %v", instruction, err)
	}
}

func (t *tray) confirmQuit() {
	pressed, _ := taskDialog(taskDialogOpts{
		instruction: "Sair do agente?",
		content: "O celular deixa de controlar este PC até você entrar no Windows de novo. " +
			"Ligar pelo celular e o sinal de presença continuam funcionando.",
		icon: tdIconWarning, button: "Sair", common: tdcbfCancel, defaultID: idCancel,
	})
	if pressed == idPrimary {
		log.Printf("bandeja: saindo a pedido de quem está no PC")
		t.call(func() {
			t.removeIcon()
			os.Exit(0)
		})
	}
}

func (t *tray) confirmRevoke(d PairedDevice) {
	pressed, _ := taskDialog(taskDialogOpts{
		instruction: "Revogar " + d.Name + "?",
		content: "Ele perde o acesso a este PC na hora; para usar de novo, pareie pelo QR. " +
			"No dual boot, revogue também no outro sistema.",
		icon: tdIconWarning, button: "Revogar", common: tdcbfCancel, defaultID: idCancel,
	})
	if pressed != idPrimary {
		return
	}
	ids := t.srv.revoke(d.ID)
	log.Printf("revogado no PC: %v", ids)
	t.srv.history.Add("Este PC", histRevoke, "revogou "+d.Name, false)
	t.Notify("Celular revogado", d.Name)
}

// doctor confere o Wake-on-LAN e oferece corrigir, pedindo administrador
// (UAC) só para isso.
func (t *tray) doctor() {
	ip, err := lanIP()
	if err != nil {
		t.info("Wake-on-LAN", "Não achei a placa da rede local.")
		return
	}
	facts, err := readWolFacts(ip, nil)
	if err != nil {
		t.info("Wake-on-LAN", err.Error())
		return
	}
	checks := wolChecks(facts)
	fix := fixableIDs(checks)
	opts := taskDialogOpts{
		instruction: "Wake-on-LAN", icon: tdIconInfo, common: tdcbfClose, defaultID: idClose,
		content: "Placa: " + facts.Adapter + " (" + facts.Description + ")\n\n" + checksText(checks),
	}
	if len(fix) > 0 {
		opts.instruction = "Wake-on-LAN: há o que corrigir"
		opts.icon = tdIconShield
		opts.button = "Corrigir (pede administrador)"
		opts.defaultID = idPrimary
		opts.footer = "As correções valem a partir do próximo desligamento."
	}
	pressed, err := taskDialog(opts)
	if err != nil || pressed != idPrimary {
		return
	}
	exe, err := os.Executable()
	if err != nil {
		t.info("Wake-on-LAN", err.Error())
		return
	}
	if code, err := runElevated(exe, "doctor -fix "+strings.Join(fix, ","), true); err != nil || code != 0 {
		if err == nil {
			err = fmt.Errorf("saiu com o código %d", code)
		}
		if !errors.Is(err, windows.ERROR_CANCELLED) {
			t.info("Wake-on-LAN", "Nem tudo foi corrigido: "+err.Error())
		}
		return
	}
	t.doctor() // mostra como ficou
}

type shellExecuteInfo struct {
	Size       uint32
	Mask       uint32
	Hwnd       uintptr
	Verb       *uint16
	File       *uint16
	Parameters *uint16
	Directory  *uint16
	Show       int32
	InstApp    uintptr
	IDList     uintptr
	Class      *uint16
	KeyClass   uintptr
	HotKey     uint32
	Icon       uintptr
	Process    windows.Handle
}

// runElevated roda um programa como administrador (o Windows pergunta). Com
// wait, espera terminar e devolve o código de saída; ERROR_CANCELLED se a
// pessoa recusou o UAC.
func runElevated(file, args string, wait bool) (uint32, error) {
	const seeMaskNoCloseProcess, seeMaskNoAsync = 0x40, 0x100
	sei := shellExecuteInfo{Mask: seeMaskNoCloseProcess | seeMaskNoAsync, Show: swHide}
	if !wait {
		sei.Show = swShow // o instalador mostra o progresso
	}
	sei.Size = uint32(unsafe.Sizeof(sei))
	sei.Verb, _ = windows.UTF16PtrFromString("runas")
	sei.File, _ = windows.UTF16PtrFromString(file)
	sei.Parameters, _ = windows.UTF16PtrFromString(args)
	if r, _, err := procShellExecuteEx.Call(uintptr(unsafe.Pointer(&sei))); r == 0 {
		return 0, err
	}
	defer windows.CloseHandle(sei.Process)
	if !wait {
		return 0, nil
	}
	windows.WaitForSingleObject(sei.Process, windows.INFINITE)
	var code uint32
	err := windows.GetExitCodeProcess(sei.Process, &code)
	return code, err
}

// checkUpdatesNow procura versão nova na hora e oferece instalar.
func (t *tray) checkUpdatesNow() {
	r, newer, err := t.srv.updates.CheckNow()
	switch {
	case err != nil:
		t.info("Não deu para procurar atualizações", err.Error())
	case newer:
		t.offerUpdate()
	default:
		t.info("Nenhuma atualização", "O Velksync "+version+" é a versão mais recente (última publicada: "+r.Version()+").")
	}
}

// showHistory mostra as últimas ações (sem o terminal se ele estiver desligado).
func (t *tray) showHistory() {
	s := t.srv
	entries := s.history.List(15, s.cfg.AllowShell)
	content := "Nada por enquanto."
	if len(entries) > 0 {
		now := time.Now()
		lines := make([]string, len(entries))
		for i, e := range entries {
			lines[i] = historyLine(e, now)
		}
		content = strings.Join(lines, "\n")
	}
	t.info("Histórico", content)
}

// offerUpdate mostra as novidades e, se a pessoa quiser, baixa o instalador,
// confere a assinatura e o roda. O instalador para este agente e sobe o novo.
func (t *tray) offerUpdate() {
	// Um clique de cada vez: o download leva alguns segundos sem janela, e
	// dois instaladores juntos brigam pelo mesmo .exe.
	if !t.updating.CompareAndSwap(false, true) {
		return
	}
	defer t.updating.Store(false)
	u := t.srv.updates
	r, ok := u.Pending()
	if !ok {
		return
	}
	pressed, _ := taskDialog(taskDialogOpts{
		instruction: "Velksync " + r.Version() + " disponível",
		content:     releaseNotes(r, 700),
		footer:      "O Windows vai pedir permissão de administrador. A configuração e os celulares pareados continuam.",
		icon:        tdIconInfo, button: "Atualizar", common: tdcbfCancel, defaultID: idPrimary,
	})
	if pressed != idPrimary {
		return
	}
	t.Notify("Baixando o Velksync "+r.Version(), "Leva alguns segundos; o instalador abre em seguida.")
	name := "velksync-setup-" + r.Version() + "-windows-amd64.exe"
	data, err := u.fetchVerified(r, name)
	if err != nil {
		log.Printf("atualização: %v", err)
		t.info("Não deu para atualizar", err.Error()+"\n\nNada foi instalado. Dá para baixar pela página de versões.")
		return
	}
	dir, err := os.MkdirTemp("", "velksync-update")
	if err == nil {
		path := filepath.Join(dir, name)
		if err = os.WriteFile(path, data, 0o600); err == nil {
			log.Printf("atualização: instalando %s (assinatura conferida)", r.Version())
			t.srv.history.Add("Este PC", histUpdate, "instalou a versão "+r.Version(), false)
			_, err = runElevated(path, "/SILENT /SUPPRESSMSGBOXES /NORESTART", false)
		}
	}
	if err != nil {
		os.RemoveAll(dir)
		if !errors.Is(err, windows.ERROR_CANCELLED) {
			t.info("Não deu para atualizar", err.Error())
		}
	}
}

// ---------- Janela do QR ----------

type pairWindow struct {
	t       *tray
	hwnd    uintptr
	code    string
	bits    [][]bool
	expires time.Time
	font    uintptr
	dpi     int
	secs    int
	expired bool
}

var pairClassOnce sync.Once

var pairWndProc = windows.NewCallback(func(hwnd, m, wp, lp uintptr) uintptr {
	if t := theTray; t != nil && t.pair != nil && t.pair.hwnd == hwnd {
		if r, ok := t.pair.handle(uint32(m), wp, lp); ok {
			return r
		}
	}
	r, _, _ := procDefWindowProc.Call(hwnd, m, wp, lp)
	return r
})

const (
	pairStyle = wsOverlapped | wsCaption | wsSysMenu | wsMinimizeBox
	pairCell  = 6  // pixels por módulo do QR a 96 dpi
	pairPad   = 24 // margem a 96 dpi
	pairText  = 64 // altura do texto a 96 dpi
)

func (t *tray) openPairWindow() {
	if t.pair != nil {
		procSetForegroundWindow.Call(t.pair.hwnd)
		return
	}
	s := t.srv
	ip, err := lanIP()
	if err != nil {
		go t.info("Parear um celular", "Não achei o IP da rede local. Confira o cabo ou o Wi-Fi.")
		return
	}
	code := s.pairs.start()
	link, err := pairLink(s.cfg, ip, code)
	if err != nil {
		go t.info("Parear um celular", err.Error())
		return
	}
	qr, err := qrcode.New(link, qrcode.Medium)
	if err != nil {
		go t.info("Parear um celular", err.Error())
		return
	}

	inst := moduleHandle()
	cls, _ := windows.UTF16PtrFromString("VelksyncPair")
	pairClassOnce.Do(func() {
		cursor, _, _ := procLoadCursor.Call(0, 32512) // IDC_ARROW
		white, _, _ := procGetStockObject.Call(0)     // WHITE_BRUSH
		wc := wndClassEx{WndProc: pairWndProc, Instance: inst, ClassName: cls, Cursor: cursor,
			Background: white, Icon: t.bigIcon, IconSm: t.icon}
		wc.Size = uint32(unsafe.Sizeof(wc))
		procRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))
	})
	title, _ := windows.UTF16PtrFromString("Parear um celular")
	hwnd, _, err := procCreateWindowEx.Call(0, uintptr(unsafe.Pointer(cls)), uintptr(unsafe.Pointer(title)),
		pairStyle, 0, 0, 100, 100, 0, 0, inst, 0)
	if hwnd == 0 {
		log.Printf("bandeja: janela do QR: %v", err)
		return
	}
	p := &pairWindow{t: t, hwnd: hwnd, code: code, bits: qr.Bitmap(), expires: time.Now().Add(pairTTL), secs: -1}
	t.pair = p
	p.layout(true)
	procShowWindow.Call(hwnd, swShow)
	procSetForegroundWindow.Call(hwnd)
	procSetTimer.Call(hwnd, 1, 500, 0)
}

func (p *pairWindow) scale(v int) int { return v * p.dpi / 96 }

// layout dimensiona a janela para o QR na escala da tela; center na abertura.
func (p *pairWindow) layout(center bool) {
	dpi, _, _ := procGetDpiForWindow.Call(p.hwnd)
	p.dpi = max(int(dpi), 96)
	if p.font != 0 {
		procDeleteObject.Call(p.font)
	}
	face, _ := windows.UTF16PtrFromString("Segoe UI")
	p.font, _, _ = procCreateFont.Call(uintptr(-int32(p.scale(15))), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0,
		uintptr(unsafe.Pointer(face)))

	qr := len(p.bits) * p.scale(pairCell)
	w := max(qr, p.scale(300)) + 2*p.scale(pairPad)
	h := p.scale(pairPad) + qr + p.scale(pairText) + p.scale(pairPad)
	r := rect{0, 0, int32(w), int32(h)}
	procAdjustWindowRectExDpi.Call(uintptr(unsafe.Pointer(&r)), pairStyle, 0, 0, uintptr(p.dpi))
	ww, wh := r.Right-r.Left, r.Bottom-r.Top
	if !center {
		procSetWindowPos.Call(p.hwnd, 0, 0, 0, uintptr(ww), uintptr(wh), swpNoMove|swpNoZOrd|swpNoActiv)
		return
	}
	var work rect
	const spiGetWorkArea = 0x0030
	procSystemParametersInfo.Call(spiGetWorkArea, 0, uintptr(unsafe.Pointer(&work)), 0)
	x := work.Left + (work.Right-work.Left-ww)/2
	y := work.Top + (work.Bottom-work.Top-wh)/2
	procSetWindowPos.Call(p.hwnd, 0, uintptr(x), uintptr(y), uintptr(ww), uintptr(wh), swpNoZOrd)
}

func (p *pairWindow) text() string {
	if p.expired {
		return "O código expirou sem ser lido.\nFeche e escolha \"Parear um celular\" de novo."
	}
	left := max(time.Until(p.expires), 0)
	return fmt.Sprintf("No app: Adicionar PC → Escanear QR do PC\nVale por %d:%02d e uma única leitura.",
		int(left.Minutes()), int(left.Seconds())%60)
}

func (p *pairWindow) handle(m uint32, wp, lp uintptr) (uintptr, bool) {
	switch m {
	case wmPaint:
		p.paint()
		return 0, true
	case wmTimer:
		claimed, expired, _ := p.t.srv.pairs.status(p.code)
		switch {
		case claimed:
			// O aviso "Novo celular pareado" sai do próprio pareamento.
			procDestroyWindow.Call(p.hwnd)
		case expired:
			p.expired = true
			procKillTimer.Call(p.hwnd, 1)
			procInvalidateRect.Call(p.hwnd, 0, 1)
		default:
			if secs := int(time.Until(p.expires).Seconds()); secs != p.secs {
				p.secs = secs
				procInvalidateRect.Call(p.hwnd, 0, 1)
			}
		}
		return 0, true
	case wmKeyDown:
		if wp == vkEscape {
			procDestroyWindow.Call(p.hwnd)
			return 0, true
		}
	case wmDpiChanged:
		p.layout(false)
		return 0, true
	case wmClose:
		procDestroyWindow.Call(p.hwnd)
		return 0, true
	case wmDestroy:
		procKillTimer.Call(p.hwnd, 1)
		procDeleteObject.Call(p.font)
		p.t.pair = nil
		return 0, true
	}
	return 0, false
}

func (p *pairWindow) paint() {
	var ps paintStruct
	hdc, _, _ := procBeginPaint.Call(p.hwnd, uintptr(unsafe.Pointer(&ps)))
	defer procEndPaint.Call(p.hwnd, uintptr(unsafe.Pointer(&ps)))
	var client rect
	procGetClientRect.Call(p.hwnd, uintptr(unsafe.Pointer(&client)))

	cell := int32(p.scale(pairCell))
	size := int32(len(p.bits)) * cell
	x0 := (client.Right - size) / 2
	y0 := int32(p.scale(pairPad))
	if !p.expired {
		black, _, _ := procGetStockObject.Call(4) // BLACK_BRUSH
		for y, row := range p.bits {
			for x, on := range row {
				if on {
					r := rect{x0 + int32(x)*cell, y0 + int32(y)*cell, x0 + int32(x+1)*cell, y0 + int32(y+1)*cell}
					procFillRect.Call(hdc, uintptr(unsafe.Pointer(&r)), black)
				}
			}
		}
	}
	procSelectObject.Call(hdc, p.font)
	procSetBkMode.Call(hdc, 1) // TRANSPARENT
	procSetTextColor.Call(hdc, 0x00303030)
	r := rect{int32(p.scale(pairPad)), y0 + size + int32(p.scale(12)), client.Right - int32(p.scale(pairPad)), client.Bottom}
	if p.expired {
		r.Top = y0 + size/2 - int32(p.scale(20))
	}
	text := toUTF16(p.text())
	procDrawText.Call(hdc, uintptr(unsafe.Pointer(&text[0])), uintptr(len(text)-1), uintptr(unsafe.Pointer(&r)),
		dtCenter|dtWordBreak|dtNoPrefix)
}
