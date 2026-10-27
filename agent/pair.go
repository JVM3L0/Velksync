package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

// lanIP returns the address of the interface used to reach the LAN. Dialing
// UDP sends nothing; it only asks the OS which source address it would use.
func lanIP() (net.IP, error) {
	conn, err := net.Dial("udp4", "192.0.2.1:9")
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	return conn.LocalAddr().(*net.UDPAddr).IP, nil
}

func broadcastFor(ip net.IP) string {
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok || !ipnet.IP.Equal(ip) || ipnet.IP.To4() == nil {
				continue
			}
			b := make(net.IP, 4)
			for i := range b {
				b[i] = ipnet.IP.To4()[i] | ^ipnet.Mask[len(ipnet.Mask)-4+i]
			}
			return b.String()
		}
	}
	return "255.255.255.255"
}

// pairCmd shows a QR code with everything the app needs to add this PC.
func pairCmd(configPath string, args []string) error {
	fl := flag.NewFlagSet("pair", flag.ExitOnError)
	hostFlag := fl.String("host", "", "IP a anunciar (padrão: IP da rede local)")
	fl.Parse(args)

	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	var ip net.IP
	if *hostFlag != "" {
		if ip = net.ParseIP(*hostFlag); ip == nil {
			return fmt.Errorf("IP inválido: %s", *hostFlag)
		}
	} else if ip, err = lanIP(); err != nil {
		return errors.New("não achei o IP da rede local; informe com -host")
	}

	var start struct {
		Code      string `json:"code"`
		ExpiresIn int    `json:"expires_in"`
	}
	// Logo depois de instalar, o agente pode ainda estar subindo.
	for wait := 0; ; wait++ {
		err = localAPI(cfg, "POST", "/api/pair/start", nil, &start)
		var ue *url.Error
		if err == nil || !errors.As(err, &ue) || wait == 15 {
			break
		}
		time.Sleep(time.Second)
	}
	if err != nil {
		return err
	}

	pin, err := pinFor(cfg.Token)
	if err != nil {
		return err
	}

	q := url.Values{}
	q.Set("name", cfg.Name)
	q.Set("host", ip.String())
	q.Set("port", fmt.Sprint(cfg.Port))
	q.Set("code", start.Code)
	q.Set("fp", pin)
	q.Set("mac", macFor(ip, false))
	q.Set("broadcast", broadcastFor(ip))
	link := "velksync://pair?" + q.Encode()

	qr, err := qrcode.New(link, qrcode.Medium)
	if err != nil {
		return err
	}
	fmt.Println(qr.ToSmallString(false))
	fmt.Printf("%s em %s:%d — no app: Adicionar PC → Escanear QR do PC\n", cfg.Name, ip, cfg.Port)
	fmt.Printf("O código vale por %d minutos e uma única leitura.\n", start.ExpiresIn/60)

	png := filepath.Join(filepath.Dir(configPath), "pair.png")
	if err := qr.WriteFile(512, png); err != nil {
		return err
	}
	defer os.Remove(png)
	openFile(png)

	// Espera o app usar o código; ao sair (pareado, expirado ou Ctrl+C) o PNG é apagado.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			fmt.Println("Cancelado. QR apagado.")
			return nil
		case <-tick.C:
		}
		var st struct {
			Claimed bool   `json:"claimed"`
			Expired bool   `json:"expired"`
			By      string `json:"by"`
		}
		if err := localAPI(cfg, "GET", "/api/pair/status?code="+start.Code, nil, &st); err != nil {
			return err
		}
		switch {
		case st.Claimed:
			fmt.Printf("Pareado com %s. QR apagado.\n", st.By)
			notifyUser(fmt.Sprintf("Pareado com %s.\n\nPode fechar a imagem do QR: ele já foi apagado.", st.By), false)
			return nil
		case st.Expired:
			return errors.New("código expirou sem ser lido; rode pair de novo")
		}
	}
}
