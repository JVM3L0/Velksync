package main

import "net"

// macFor returns the MAC of the interface that owns ip (match == exact) or
// whose subnet contains ip (match == subnet). Used so the app learns the MAC
// it needs for Wake-on-LAN without the user typing it.
func macFor(ip net.IP, subnet bool) string {
	ifaces, err := net.Interfaces()
	if err != nil || ip == nil {
		return ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || len(iface.HardwareAddr) == 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			if (subnet && ipnet.Contains(ip)) || (!subnet && ipnet.IP.Equal(ip)) {
				return iface.HardwareAddr.String()
			}
		}
	}
	return ""
}

func addrIP(a net.Addr) net.IP {
	switch v := a.(type) {
	case *net.TCPAddr:
		return v.IP
	case *net.UDPAddr:
		return v.IP
	}
	return nil
}
