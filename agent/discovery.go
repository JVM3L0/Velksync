package main

import (
	"log"
	"net"
)

const (
	discoveryPort  = 41101
	discoveryProbe = "VELKSYNC_DISCOVER"
)

// serveDiscovery answers UDP broadcasts from the app so it can find PCs on
// the LAN, and presence challenges. The reply never contains the token, only
// what the app needs to list the PC and wake it later.
func serveDiscovery(cfg Config) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{Port: discoveryPort})
	if err != nil {
		// Normal com o sinal de presença instalado: ele já atende esta porta.
		log.Printf("descoberta a cargo de outro processo: %v", err)
		return
	}
	serveUDP(conn, discoveryHandler(cfg.Name, cfg.Port, presenceSecret(cfg.Token)))
}
