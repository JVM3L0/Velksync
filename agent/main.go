package main

import (
	"bytes"
	"crypto/tls"
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

const version = "0.4.0"

const usage = `velksync-agent %s

Uso:
  velksync-agent [-config arquivo]                 inicia o agente
  velksync-agent init [-token T] [-force]          cria a config (use o mesmo token nos dois sistemas do dual boot)
  velksync-agent token                             mostra o token mestre (não compartilhe; celulares usam o QR)
  velksync-agent pair [-host IP]                   mostra um QR para parear um celular
  velksync-agent devices                           lista os celulares pareados e revogados
  velksync-agent revoke <id ou nome>               revoga um celular (no dual boot, revogue nos dois sistemas)
  velksync-agent fingerprint                       mostra o pin do certificado TLS deste PC
  velksync-agent send <tipo> [texto]               envia ao celular: notify, open_url, clipboard, vibrate
  velksync-agent presence-export -out <arquivo>    gera o arquivo do sinal de presença (usado pelo instalador)
  velksync-agent presence -file <arquivo>          sinal de presença: só diz "ligado", roda antes do login

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
	case "devices":
		err = devicesCmd(*configPath)
	case "revoke":
		err = revokeCmd(*configPath, args)
	case "fingerprint":
		var cfg Config
		if cfg, err = loadConfig(*configPath); err == nil {
			var pin string
			if pin, err = pinFor(cfg.Token); err == nil {
				fmt.Printf("%s\n(no app: %s)\n", pin, shortPin(pin))
			}
		}
	case "send":
		err = sendCmd(*configPath, args)
	case "presence-export":
		err = presenceExportCmd(*configPath, args)
	case "presence":
		err = presenceCmd(args)
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
		// Nunca registrar o token: logs são lidos e copiados por aí.
		log.Printf("para parear um celular: velksync-agent pair")
	} else if err != nil {
		return err
	}

	cert, pin, err := tlsCertificate(cfg.Token, cfg.Name)
	if err != nil {
		return fmt.Errorf("certificado TLS: %w", err)
	}

	go serveDiscovery(cfg)
	srv := &Server{cfg: cfg, configPath: configPath, hub: NewHub()}
	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("velksync-agent %s ouvindo em https://%s (terminal livre: %v, pin %s)", version, addr, cfg.AllowShell, shortPin(pin))
	hs := newHTTPServer(addr, srv.routes(), cert)
	return hs.ListenAndServeTLS("", "")
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

// localAPI calls the agent running on this machine over HTTPS, pinned to the
// key derived from the config and authenticated with the master token (only
// accepted from localhost). Used by the send, pair, devices and revoke commands.
func localAPI(cfg Config, method, path string, body, out any) error {
	var rd io.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		rd = bytes.NewReader(data)
	}
	pin, err := pinFor(cfg.Token)
	if err != nil {
		return err
	}
	req, _ := http.NewRequest(method, fmt.Sprintf("https://127.0.0.1:%d%s", cfg.Port, path), rd)
	req.Header.Set("Authorization", "Bearer "+cfg.Token)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: pinnedTLS(pin)}}
	resp, err := client.Do(req)
	if err != nil {
		if strings.Contains(err.Error(), "HTTP response to HTTPS client") {
			return errors.New("o agente rodando é uma versão antiga, sem HTTPS; reinstale")
		}
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

func devicesCmd(configPath string) error {
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	var out struct {
		Devices []PairedDevice `json:"devices"`
		Revoked []string       `json:"revoked"`
	}
	if err := localAPI(cfg, "GET", "/api/devices", nil, &out); err != nil {
		// Agente parado: mostra o que está na config.
		out.Devices, out.Revoked = cfg.Devices, cfg.Revoked
	}
	if len(out.Devices) == 0 {
		fmt.Println("Nenhum celular pareado neste sistema.")
	}
	for _, d := range out.Devices {
		fmt.Printf("%s  %-24s pareado em %s\n", d.ID, d.Name, d.PairedAt.Local().Format("02/01/2006 15:04"))
	}
	if len(out.Revoked) > 0 {
		fmt.Printf("Revogados: %s\n", strings.Join(out.Revoked, ", "))
	}
	return nil
}

func revokeCmd(configPath string, args []string) error {
	if len(args) != 1 {
		return errors.New("uso: velksync-agent revoke <id ou nome>")
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	var out struct {
		Revoked []string `json:"revoked"`
	}
	if err := localAPI(cfg, "POST", "/api/devices/revoke", map[string]string{"target": args[0]}, &out); err != nil {
		if !strings.Contains(err.Error(), "não está rodando") {
			return err
		}
		// Agente parado: revoga direto na config; vale quando ele subir.
		srv := &Server{cfg: cfg, configPath: configPath}
		if out.Revoked = srv.revoke(args[0]); len(out.Revoked) == 0 {
			return errors.New("nenhum celular com esse id ou nome")
		}
	}
	fmt.Printf("Revogado: %s\nNo dual boot, rode o mesmo comando no outro sistema.\n", strings.Join(out.Revoked, ", "))
	return nil
}

// newHTTPServer não tem WriteTimeout: o SSE e os comandos longos (até
// CommandTimeout) ficariam cortados. Leitura, cabeçalhos e conexões ociosas
// têm limite para que um cliente lento (slowloris) não segure o agente.
// Só TLS 1.3: os dois lados são nossos, então não há legado a atender.
func newHTTPServer(addr string, h http.Handler, cert tls.Certificate) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		IdleTimeout:       2 * time.Minute,
		MaxHeaderBytes:    16 << 10,
		TLSConfig:         &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13},
	}
}
