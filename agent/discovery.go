package main

import (
	"encoding/json"
	"log"
	"net"
	"os"
	"runtime"
)

const (
	discoveryPort  = 41101
	discoveryProbe = "VELKSYNC_DISCOVER"
)

// serveDiscovery answers UDP broadcasts from the app so it can find PCs on
// the LAN. The reply never contains the token, only what the app needs to
// list the PC and wake it later.
func serveDiscovery(cfg Config) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{Port: discoveryPort})
	if err != nil {
		log.Printf("descoberta desativada: %v", err)
		return
	}
	host, _ := os.Hostname()
	buf := make([]byte, 64)
	for {
		n, from, err := conn.ReadFromUDP(buf)
		if err != nil {
			continue
		}
		if string(buf[:n]) != discoveryProbe {
			continue
		}
		reply, _ := json.Marshal(map[string]any{
			"name":     cfg.Name,
			"hostname": host,
			"os":       runtime.GOOS,
			"port":     cfg.Port,
			"mac":      macFor(from.IP, true),
		})
		conn.WriteToUDP(reply, from)
	}
}
