package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"slices"
	"strings"
	"unicode/utf16"
)

// O doctor confere o que o Wake-on-LAN precisa neste PC e, se pedido, corrige.
// A leitura do sistema fica em doctor_<so>.go; daqui para baixo é só decisão,
// testável em qualquer sistema.

// wolFacts é o que foi lido da placa de rede usada na rede local.
type wolFacts struct {
	Adapter     string   `json:"adapter"`
	Description string   `json:"description"`
	Media       string   `json:"media"`      // "802.3" (cabo), "Native 802.11" (Wi-Fi)
	Magic       string   `json:"magic"`      // *WakeOnMagicPacket do driver: "1", "0" ou "" (não tem)
	PMMagic     string   `json:"pm_magic"`   // gerenciamento de energia: Enabled, Disabled, Unsupported
	WakeArmed   bool     `json:"wake_armed"` // "Permitir que este dispositivo ative o computador"
	Hiberboot   *int     `json:"hiberboot"`  // Inicialização Rápida; sem o valor, o Windows considera ligada
	Hibernate   *int     `json:"hibernate"`  // sem hibernação não existe Inicialização Rápida
	Network     string   `json:"network"`    // nome do perfil de rede
	Category    string   `json:"category"`   // Private, Public, DomainAuthenticated
	FixErrors   []string `json:"fix_errors"` // correções pedidas que falharam
}

type checkStatus string

const (
	statusOK      checkStatus = "ok"
	statusFail    checkStatus = "fail"
	statusWarn    checkStatus = "warn"
	statusUnknown checkStatus = "unknown"
)

type wolCheck struct {
	ID      string
	Label   string
	Status  checkStatus
	Hint    string
	Fixable bool
}

// Correções que o doctor sabe aplicar; o instalador manda só destas.
var doctorFixes = []string{"magic", "wake", "faststartup", "private"}

func parseFixes(s string) ([]string, error) {
	var out []string
	for f := range strings.SplitSeq(s, ",") {
		f = strings.TrimSpace(f)
		if f == "" {
			continue
		}
		if !slices.Contains(doctorFixes, f) {
			return nil, fmt.Errorf("correção desconhecida: %s (use %s)", f, strings.Join(doctorFixes, ", "))
		}
		if !slices.Contains(out, f) {
			out = append(out, f)
		}
	}
	return out, nil
}

func wolChecks(f wolFacts) []wolCheck {
	cable := wolCheck{ID: "cable", Label: "Conectado por cabo", Status: statusUnknown}
	switch {
	case f.Media == "802.3":
		cable.Status = statusOK
	case strings.Contains(f.Media, "802.11"):
		cable.Status = statusWarn
		cable.Hint = "Wi-Fi: o Wake-on-LAN quase nunca funciona sem cabo"
	}

	magic := wolCheck{ID: "magic", Label: "Placa de rede: Wake on Magic Packet", Status: statusUnknown}
	switch {
	case f.Magic == "0" || f.PMMagic == "Disabled":
		magic.Status, magic.Fixable = statusFail, true
		magic.Hint = "desativado no driver da placa"
	case f.Magic == "1" || f.PMMagic == "Enabled":
		magic.Status = statusOK
	case f.PMMagic == "Unsupported":
		magic.Status = statusFail
		magic.Hint = "a placa não suporta"
	}

	wake := wolCheck{ID: "wake", Label: "Placa pode ligar o computador", Status: statusOK}
	if !f.WakeArmed {
		wake.Status, wake.Fixable = statusFail, true
		wake.Hint = "desmarcado no Gerenciamento de Energia da placa"
	}

	fast := wolCheck{ID: "faststartup", Label: "Inicialização Rápida desligada", Status: statusOK}
	hibernate := f.Hibernate == nil || *f.Hibernate != 0
	hiberboot := f.Hiberboot == nil || *f.Hiberboot != 0
	if hibernate && hiberboot {
		fast.Status, fast.Fixable = statusFail, true
		fast.Hint = "com ela, desligar vira hibernar e a placa costuma não acordar"
	}

	private := wolCheck{ID: "private", Label: "Rede como Privada", Status: statusUnknown}
	switch f.Category {
	case "Private":
		private.Status = statusOK
	case "Public":
		private.Status, private.Fixable = statusFail, true
		private.Hint = "o firewall só libera o Velksync em redes privadas"
	case "DomainAuthenticated":
		private.Status = statusWarn
		private.Hint = "rede de domínio: o firewall só libera o Velksync em redes privadas"
	}
	if f.Network != "" {
		private.Label = fmt.Sprintf("Rede \"%s\" como Privada", f.Network)
	}

	return []wolCheck{cable, magic, wake, fast, private}
}

func (c wolCheck) symbol() string {
	switch c.Status {
	case statusOK:
		return "✓"
	case statusFail:
		return "✗"
	case statusWarn:
		return "!"
	}
	return "?"
}

func formatChecks(f wolFacts, checks []wolCheck) string {
	var b strings.Builder
	if f.Description != "" {
		fmt.Fprintf(&b, "Placa: %s (%s)\n", f.Adapter, f.Description)
	}
	for _, c := range checks {
		fmt.Fprintf(&b, "  %s %s", c.symbol(), c.Label)
		if c.Hint != "" {
			fmt.Fprintf(&b, ": %s", c.Hint)
		}
		b.WriteByte('\n')
	}
	fmt.Fprintln(&b, "  ? BIOS/UEFI: \"Wake on LAN\" ou \"Power On By PCI-E\" ativado (não dá para ver daqui)")
	for _, e := range f.FixErrors {
		fmt.Fprintf(&b, "erro ao corrigir: %s\n", e)
	}
	if fixable := fixableIDs(checks); len(fixable) > 0 {
		fmt.Fprintf(&b, "Para corrigir (como administrador): velksync-agent doctor -fix %s\n", strings.Join(fixable, ","))
	}
	return b.String()
}

func fixableIDs(checks []wolCheck) []string {
	var ids []string
	for _, c := range checks {
		if c.Fixable {
			ids = append(ids, c.ID)
		}
	}
	return ids
}

// iniChecks é o formato que o instalador lê (GetIniString do Inno Setup).
// UTF-16 com BOM: é o único jeito de a API de INI do Windows ler acentos.
func iniChecks(f wolFacts, checks []wolCheck) []byte {
	var s strings.Builder
	ids := make([]string, len(checks))
	for i, c := range checks {
		ids[i] = c.ID
	}
	fmt.Fprintf(&s, "[summary]\r\nchecks=%s\r\nadapter=%s\r\nerrors=%d\r\n", strings.Join(ids, ","), iniValue(f.Adapter), len(f.FixErrors))
	for _, c := range checks {
		fixable := 0
		if c.Fixable {
			fixable = 1
		}
		fmt.Fprintf(&s, "[%s]\r\nstatus=%s\r\nlabel=%s\r\nhint=%s\r\nfixable=%d\r\n", c.ID, c.Status, iniValue(c.Label), iniValue(c.Hint), fixable)
	}
	u := utf16.Encode([]rune(s.String()))
	var b bytes.Buffer
	b.Write([]byte{0xFF, 0xFE})
	binary.Write(&b, binary.LittleEndian, u)
	return b.Bytes()
}

// Valores de INI vão numa linha só.
func iniValue(s string) string { return strings.NewReplacer("\r", " ", "\n", " ").Replace(s) }

func doctorCmd(args []string) error {
	fl := flag.NewFlagSet("doctor", flag.ExitOnError)
	fixFlag := fl.String("fix", "", "corrige (precisa de administrador): "+strings.Join(doctorFixes, ","))
	hostFlag := fl.String("host", "", "IP da placa a conferir (padrão: IP da rede local)")
	outFlag := fl.String("out", "", "grava o resultado em INI (usado pelo instalador)")
	fl.Parse(args)

	fixes, err := parseFixes(*fixFlag)
	if err != nil {
		return err
	}
	var ip net.IP
	if *hostFlag != "" {
		if ip = net.ParseIP(*hostFlag).To4(); ip == nil {
			return fmt.Errorf("IP inválido: %s", *hostFlag)
		}
	} else if ip, err = lanIP(); err != nil {
		return errors.New("não achei o IP da rede local; informe com -host")
	}

	facts, err := readWolFacts(ip, fixes)
	if err != nil {
		return err
	}
	checks := wolChecks(facts)
	if *outFlag != "" {
		if err := os.WriteFile(*outFlag, iniChecks(facts, checks), 0o600); err != nil {
			return err
		}
	}
	fmt.Print(formatChecks(facts, checks))
	if len(facts.FixErrors) > 0 {
		return errors.New("nem todas as correções foram aplicadas")
	}
	return nil
}
