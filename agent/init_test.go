package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// O instalador passa o token do outro sistema por arquivo, não pela linha de comando.
func TestInitTokenFile(t *testing.T) {
	dir := t.TempDir()
	token := strings.Repeat("a1", 24)
	tf := filepath.Join(dir, "token.txt")
	// Como o PowerShell grava: BOM e quebra de linha no fim.
	if err := os.WriteFile(tf, []byte("\xef\xbb\xbf"+token+"\r\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfgPath := filepath.Join(dir, "config.json")
	if err := initCmd(cfgPath, []string{"-token-file", tf}); err != nil {
		t.Fatal(err)
	}
	cfg, err := loadConfig(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Token != token {
		t.Errorf("token = %q, queria %q", cfg.Token, token)
	}
	if err := os.WriteFile(tf, []byte("curto"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := initCmd(filepath.Join(dir, "outro.json"), []string{"-token-file", tf}); err == nil {
		t.Error("aceitou token curto")
	}
}
