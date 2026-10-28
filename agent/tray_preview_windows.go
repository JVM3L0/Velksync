//go:build uipreview

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// ui-preview mostra a bandeja e as janelas com dados de mentira, sem subir o
// servidor: para conferir a interface no Windows sem mexer no agente instalado.
//
//	go build -tags uipreview -ldflags -H=windowsgui -o preview.exe .
//	preview.exe ui-preview [tray|countdown|pair|notify|doctor]
func init() {
	devCommands["ui-preview"] = func(args []string) error {
		dir, err := os.MkdirTemp("", "velksync-preview")
		if err != nil {
			return err
		}
		defer os.RemoveAll(dir)
		cfg := defaultConfig()
		cfg.Name = "Prévia"
		cfg.Devices = []PairedDevice{
			{ID: "aaaaaaaaaaaaaaaa", Name: "Pixel 9", PairedAt: time.Now().AddDate(0, 0, -2)},
			{ID: "bbbbbbbbbbbbbbbb", Name: "Galaxy & Cia", PairedAt: time.Now().AddDate(0, -1, 0)},
		}
		path := filepath.Join(dir, "config.json")
		if err := saveConfig(path, cfg); err != nil {
			return err
		}
		s := &Server{cfg: cfg, configPath: path, hub: NewHub()}
		s.routes()
		s.ui = startDesktop(s)
		what := "tray"
		if len(args) > 0 {
			what = args[0]
		}
		switch what {
		case "countdown":
			fmt.Println("desligar:", s.ui.AskPower("shutdown", "Pixel 9", 10*time.Second))
			return nil
		case "pair":
			s.ui.ShowPair()
		case "notify":
			s.notice("Pixel 9", `rodou "Abrir Steam"`)
			s.notice("Galaxy", "rodou no terminal: dir C:\\")
			s.notice("Pixel 9", "agendou desligar às 23:00")
		case "clipboard":
			// Só tamanho e tipo: o conteúdo copiado é da pessoa.
			text, err := readClipboard()
			e, cerr := clipEvent(text)
			fmt.Printf("área de transferência: %d caracteres, tipo %q, erro %v / %v\n", len([]rune(text)), e.Type, err, cerr)
			return nil
		case "processes":
			// Só números: quais programas rodam é da pessoa.
			top, err := newProcessWatch().Top()
			if err != nil {
				return err
			}
			gpu, _ := top["by_gpu"].([]ProcessInfo)
			vram, _ := top["by_vram"].([]ProcessInfo)
			fmt.Printf("processos: %v · com GPU por processo: %v\n", top["total"], gpu != nil)
			if len(gpu) > 0 && len(vram) > 0 {
				fmt.Printf("maior GPU: %.1f%% · maior VRAM: %d MB\n", gpu[0].GPU, vram[0].VRAM>>20)
			}
			return nil
		case "doctor":
			theTray.doctor()
			return nil
		}
		select {} // tray, pair e notify: feche pelo menu "Sair do agente…"
	}
}
