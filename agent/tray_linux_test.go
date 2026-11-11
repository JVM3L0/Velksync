//go:build linux

package main

import "testing"

func TestIconPixmaps(t *testing.T) {
	pix, err := iconPixmaps(trayIconPNG, 22, 64)
	if err != nil {
		t.Fatal(err)
	}
	if len(pix) != 2 || pix[0].W != 22 || len(pix[0].Pix) != 22*22*4 || len(pix[1].Pix) != 64*64*4 {
		t.Fatalf("tamanhos inesperados: %+v", pix)
	}
	opaque := false
	for i := 0; i < len(pix[1].Pix); i += 4 {
		if pix[1].Pix[i] > 0 { // alfa
			opaque = true
			break
		}
	}
	if !opaque {
		t.Error("ícone todo transparente")
	}
}

func TestLinuxMenu(t *testing.T) {
	items := linuxMenu(trayState{Version: "1", NoSend: true, IP: "192.168.0.2", Notices: true})
	for i, it := range items {
		switch it.ID {
		case menuDoctor, menuLog:
			t.Errorf("item %q não existe no Linux", it.Text)
		}
		if it.Sep && (i == 0 || i == len(items)-1 || items[i-1].Sep) {
			t.Errorf("separador solto na posição %d", i)
		}
		if it.Text == "Enviar para o celular" {
			t.Error("Enviar para o celular não existe no Linux")
		}
	}
	if items[len(items)-1].ID != menuQuit {
		t.Errorf("o último item deveria ser Sair, é %q", items[len(items)-1].Text)
	}
}

func TestBuildDM(t *testing.T) {
	items := []menuItem{
		{Text: "a_b", Disabled: true},
		{Sep: true},
		{ID: menuNotices, Text: "Avisar", Checked: true},
		{Text: "Celulares", Sub: []menuItem{{Text: "Moto", Sub: []menuItem{{ID: menuRevokeBase, Text: "Revogar…"}}}}},
	}
	root, byID := buildDM(items)
	if root.id != 0 || len(root.kids) != 4 {
		t.Fatalf("raiz: %+v", root)
	}
	if got := root.kids[0].props["label"].Value(); got != "a__b" {
		t.Errorf("label = %v (o _ vira __ no dbusmenu)", got)
	}
	if got := root.kids[1].props["type"].Value(); got != "separator" {
		t.Errorf("type = %v", got)
	}
	if got := root.kids[2].props["toggle-state"].Value(); got != int32(1) {
		t.Errorf("toggle-state = %v", got)
	}
	revoke := root.kids[3].kids[0].kids[0]
	if revoke.cmd != menuRevokeBase || byID[revoke.id] != revoke {
		t.Errorf("revogar: %+v", revoke)
	}
	if l := root.layout(1); len(l.Children) != 4 {
		t.Errorf("profundidade 1: %d filhos", len(l.Children))
	}
	if l := root.layout(0); len(l.Children) != 0 {
		t.Errorf("profundidade 0 devia vir sem filhos")
	}
}
