//go:build !windows

package main

// Fora do Windows não há ícone na bandeja: energia na hora e sem avisos.
func startDesktop(*Server) desktop { return noDesktop{} }
