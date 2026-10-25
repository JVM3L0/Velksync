package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

// Command is a preset command the app can trigger by id. Linux and Windows
// variants live side by side so the same config works on both sides of a
// dual boot; a command with no variant for the running OS is hidden.
type Command struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Linux   string `json:"linux,omitempty"`
	Windows string `json:"windows,omitempty"`
}

func (c Command) ForCurrentOS() string {
	if runtime.GOOS == "windows" {
		return c.Windows
	}
	return c.Linux
}

type Config struct {
	Name           string    `json:"name"`
	Port           int       `json:"port"`
	Token          string    `json:"token"`
	AllowShell     bool      `json:"allow_shell"`
	CommandTimeout int       `json:"command_timeout_seconds"`
	Commands       []Command `json:"commands"`
	// Celulares pareados neste sistema (só para listar) e ids revogados.
	// No dual boot, revogue nos dois sistemas.
	Devices []PairedDevice `json:"devices,omitempty"`
	Revoked []string       `json:"revoked,omitempty"`
}

type PairedDevice struct {
	ID       string    `json:"id"`
	Name     string    `json:"name"`
	PairedAt time.Time `json:"paired_at"`
}

func defaultConfigPath() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = "."
	}
	return filepath.Join(dir, "velksync", "config.json")
}

func newToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

func defaultConfig() Config {
	host, _ := os.Hostname()
	return Config{
		Name:           host,
		Port:           41100,
		Token:          newToken(),
		AllowShell:     false,
		CommandTimeout: 30,
		Commands: []Command{
			{ID: "lock", Name: "Bloquear tela", Linux: "loginctl lock-session", Windows: "rundll32.exe user32.dll,LockWorkStation"},
			{ID: "mute", Name: "Mutar áudio", Linux: "pactl set-sink-mute @DEFAULT_SINK@ toggle", Windows: "powershell -NoProfile -Command \"(New-Object -ComObject WScript.Shell).SendKeys([char]173)\""},
		},
	}
}

func loadConfig(path string) (Config, error) {
	var cfg Config
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, err
	}
	// Editores do Windows (e o Set-Content do PowerShell 5) gravam UTF-8 com BOM.
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))
	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("config inválida em %s: %w", path, err)
	}
	if len(cfg.Token) < 32 {
		return cfg, errors.New("token ausente ou curto demais (mínimo 32 caracteres)")
	}
	if cfg.Port == 0 {
		cfg.Port = 41100
	}
	if cfg.CommandTimeout <= 0 {
		cfg.CommandTimeout = 30
	}
	return cfg, nil
}

func saveConfig(path string, cfg Config) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}
