//go:build !windows && !linux

package main

// Fora do Windows e do Linux não há ícone na bandeja: energia na hora e sem avisos.
func startDesktop(*Server) desktop { return noDesktop{} }
