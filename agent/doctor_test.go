package main

import (
	"bytes"
	"encoding/json"
	"maps"
	"strings"
	"testing"
	"unicode/utf16"
)

func intp(v int) *int { return &v }

// Como o PowerShell entrega: um PC com tudo certo.
const goodFacts = `{"adapter":"Ethernet","description":"Realtek PCIe GbE Family Controller","media":"802.3",
"magic":"1","pm_magic":"Enabled","wake_armed":true,"hiberboot":0,"hibernate":1,"network":"Casa",
"category":"Private","fix_errors":[]}`

func statuses(checks []wolCheck) map[string]checkStatus {
	m := map[string]checkStatus{}
	for _, c := range checks {
		m[c.ID] = c.Status
	}
	return m
}

func TestWolChecksAllGood(t *testing.T) {
	var f wolFacts
	if err := json.Unmarshal([]byte(goodFacts), &f); err != nil {
		t.Fatal(err)
	}
	checks := wolChecks(f)
	for _, c := range checks {
		if c.Status != statusOK || c.Fixable {
			t.Errorf("%s = %s (fixable %v), queria ok", c.ID, c.Status, c.Fixable)
		}
	}
	if got := fixableIDs(checks); len(got) != 0 {
		t.Errorf("nada a corrigir, veio %v", got)
	}
}

func TestWolChecksProblems(t *testing.T) {
	f := wolFacts{Media: "Native 802.11", Magic: "0", PMMagic: "Enabled", Category: "Public", Network: "Casa"}
	checks := wolChecks(f)
	want := map[string]checkStatus{
		"cable": statusWarn, "magic": statusFail, "wake": statusFail, "faststartup": statusFail, "private": statusFail,
	}
	if got := statuses(checks); !maps.Equal(got, want) {
		t.Errorf("status %v, queria %v", got, want)
	}
	if got := strings.Join(fixableIDs(checks), ","); got != "magic,wake,faststartup,private" {
		t.Errorf("corrigíveis = %s", got)
	}
}

func TestWolChecksEdgeCases(t *testing.T) {
	cases := []struct {
		name string
		f    wolFacts
		id   string
		want checkStatus
		fix  bool
	}{
		// Sem a chave no registro, o Windows trata a Inicialização Rápida como ligada.
		{"hiberboot ausente", wolFacts{Hibernate: intp(1)}, "faststartup", statusFail, true},
		{"sem hibernação", wolFacts{Hiberboot: intp(1), Hibernate: intp(0)}, "faststartup", statusOK, false},
		{"driver sem a opção, energia ligada", wolFacts{PMMagic: "Enabled"}, "magic", statusOK, false},
		{"placa sem suporte", wolFacts{PMMagic: "Unsupported"}, "magic", statusFail, false},
		{"energia desligada", wolFacts{Magic: "1", PMMagic: "Disabled"}, "magic", statusFail, true},
		{"nada lido", wolFacts{}, "magic", statusUnknown, false},
		{"domínio", wolFacts{Category: "DomainAuthenticated"}, "private", statusWarn, false},
		{"sem perfil", wolFacts{}, "private", statusUnknown, false},
		{"tipo de mídia desconhecido", wolFacts{Media: "Unspecified"}, "cable", statusUnknown, false},
	}
	for _, tc := range cases {
		for _, c := range wolChecks(tc.f) {
			if c.ID == tc.id && (c.Status != tc.want || c.Fixable != tc.fix) {
				t.Errorf("%s: %s = %s (fixable %v), queria %s (%v)", tc.name, c.ID, c.Status, c.Fixable, tc.want, tc.fix)
			}
		}
	}
}

func TestParseFixes(t *testing.T) {
	got, err := parseFixes(" magic, wake,,magic ")
	if err != nil || strings.Join(got, ",") != "magic,wake" {
		t.Errorf("parseFixes = %v, %v", got, err)
	}
	// Tudo o que vai para o script precisa estar na lista: nada de texto livre.
	for _, bad := range []string{"all", "magic;rm", "'x'"} {
		if _, err := parseFixes(bad); err == nil {
			t.Errorf("parseFixes(%q) aceitou", bad)
		}
	}
}

func TestIniChecks(t *testing.T) {
	f := wolFacts{Adapter: "Ethernet\r\n[x]", Category: "Public", Network: "Café"}
	b := iniChecks(f, wolChecks(f))
	if !bytes.HasPrefix(b, []byte{0xFF, 0xFE}) || len(b)%2 != 0 {
		t.Fatal("sem BOM UTF-16LE")
	}
	u := make([]uint16, (len(b)-2)/2)
	for i := range u {
		u[i] = uint16(b[2+2*i]) | uint16(b[3+2*i])<<8
	}
	s := string(utf16.Decode(u))
	for _, want := range []string{
		"[summary]\r\nchecks=cable,magic,wake,faststartup,private\r\n",
		"adapter=Ethernet  [x]\r\n",
		"[private]\r\nstatus=fail\r\nlabel=Rede \"Café\" como Privada\r\n",
		"fixable=1\r\n",
	} {
		if !strings.Contains(s, want) {
			t.Errorf("INI sem %q:\n%s", want, s)
		}
	}
}

func TestFormatChecksSuggestsFix(t *testing.T) {
	f := wolFacts{Category: "Public", WakeArmed: true, Hiberboot: intp(0), Magic: "1", Media: "802.3",
		FixErrors: []string{"private: acesso negado"}}
	out := formatChecks(f, wolChecks(f))
	for _, want := range []string{"✗ Rede como Privada", "doctor -fix private", "erro ao corrigir: private: acesso negado"} {
		if !strings.Contains(out, want) {
			t.Errorf("saída sem %q:\n%s", want, out)
		}
	}
}
