package main

import (
	"errors"
	"net"
)

func readWolFacts(net.IP, []string) (wolFacts, error) {
	return wolFacts{}, errors.New("o doctor ainda só existe no Windows; no Linux, veja o README (ethtool)")
}
