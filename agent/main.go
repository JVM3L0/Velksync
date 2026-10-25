package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const version = "0.1.0"

const usage = `velksync-agent %s

Uso:
  velksync-agent [-config arquivo]                 inicia o agente
  velksync-agent init [-token T] [-force]          cria a config (use o mesmo token nos dois sistemas do dual boot)
  velksync-agent token                             mostra o token
  velksync-agent pair [-host IP]                   mostra um QR para parear o app
  velksync-agent send <tipo> [texto]               envia ao celular: notify, open_url, clipboard, vibrate

Config padrão: %s
`

func main() {
	attachConsole()
	configPath := flag.String("config", defaultConfigPath(), "arquivo de configuração")
	logPath := flag.String("log", "", "arquivo de log (padrão: stderr; no Windows, agent.log ao lado da config)")
	flag.Usage = func() { fmt.Fprintf(os.Stderr, usage, version, defaultConfigPath()) }
	flag.Parse()

	args := flag.Args()
	cmd := ""
	if len(args) > 0 {
		cmd, args = args[0], args[1:]
	}

	var err error
	switch cmd {
	case "":
		err = run(*configPath, *logPath)
	case "init":
		err = initCmd(*configPath, args)
	case "token":
		var cfg Config
		if cfg, err = loadConfig(*configPath); err == nil {
			fmt.Println(cfg.Token)
		}
	case "pair":
		err = pairCmd(*configPath, args)
	case "send":
		err = sendCmd(*configPath, args)
	default:
		flag.Usage()
		os.Exit(2)
	}
	if err != nil {
		if cmd == "" {
			log.Printf("erro: %v", err) // no Windows o stderr não aparece; isso vai para o agent.log
		}
		fmt.Fprintln(os.Stderr, "erro:", err)
		os.Exit(1)
	}
}

func initCmd(path string, args []string) error {
	fl := flag.NewFlagSet("init", flag.ExitOnError)
	token := fl.String("token", "", "token a usar (padrão: gera um novo)")
	force := fl.Bool("force", false, "sobrescreve a config existente")
	fl.Parse(args)

	if _, err := os.Stat(path); err == nil && !*force {
		return fmt.Errorf("%s já existe (use -force para sobrescrever)", path)
	}
	cfg := defaultConfig()
	if *token != "" {
		if len(*token) < 32 {
			return errors.New("o token precisa ter pelo menos 32 caracteres")
		}
		cfg.Token = *token
	}
	if err := saveConfig(path, cfg); err != nil {
		return err
	}
	fmt.Printf("Config criada em %s\nToken: %s\n", path, cfg.Token)
	return nil
}

func run(configPath, logPath string) error {
	if logPath == "" {
		logPath = defaultLogPath(configPath)
	}
	if logPath != "" {
		f, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
		if err != nil {
			return err
		}
		// Sem defer Close: main ainda grava o erro de saída neste arquivo.
		// Arquivo primeiro: no Windows (binário GUI) o stderr é inválido e o
		// MultiWriter para no primeiro erro.
		log.SetOutput(io.MultiWriter(f, os.Stderr))
	}

	cfg, err := loadConfig(configPath)
	if errors.Is(err, fs.ErrNotExist) {
		cfg = defaultConfig()
		if err := saveConfig(configPath, cfg); err != nil {
			return err
		}
		log.Printf("primeira execução: config criada em %s", configPath)
		log.Printf("token para parear o app: %s", cfg.Token)
	} else if err != nil {
		return err
	}

	go serveDiscovery(cfg)
	srv := &Server{cfg: cfg, hub: NewHub()}
	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("velksync-agent %s ouvindo em %s (terminal livre: %v)", version, addr, cfg.AllowShell)
	return (&http.Server{Addr: addr, Handler: srv.routes(), ReadHeaderTimeout: 10 * time.Second}).ListenAndServe()
}

func sendCmd(configPath string, args []string) error {
	if len(args) == 0 {
		return errors.New("informe o tipo: notify, open_url, clipboard ou vibrate")
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	e := Event{Type: args[0], Text: strings.Join(args[1:], " ")}
	if e.Type == "open_url" {
		e.URL, e.Text = e.Text, ""
	}
	var out struct {
		Delivered int `json:"delivered"`
	}
	if err := localAPI(cfg, "POST", "/api/push", e, &out); err != nil {
		return err
	}
	if out.Delivered == 0 {
		return errors.New("nenhum celular conectado (o app precisa estar aberto)")
	}
	fmt.Printf("entregue a %d celular(es)\n", out.Delivered)
	return nil
}

// localAPI calls the agent running on this machine, authenticated with the
// token from the config. Used by the send and pair commands.
func localAPI(cfg Config, method, path string, body, out any) error {
	var rd io.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		rd = bytes.NewReader(data)
	}
	req, _ := http.NewRequest(method, fmt.Sprintf("http://127.0.0.1:%d%s", cfg.Port, path), rd)
	req.Header.Set("Authorization", "Bearer "+cfg.Token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 5 * time.Second}).Do(req)
	if err != nil {
		return fmt.Errorf("agente não está rodando? %w", err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		var e struct {
			Error string `json:"error"`
		}
		json.Unmarshal(data, &e)
		if e.Error == "" {
			e.Error = resp.Status
		}
		if resp.StatusCode == http.StatusNotFound {
			e.Error += " (o agente rodando é uma versão antiga? reinstale)"
		}
		return errors.New(e.Error)
	}
	return json.Unmarshal(data, out)
}
