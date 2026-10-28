//go:build !windows

package main

import "errors"

// No Linux a área de transferência depende do ambiente gráfico (X11,
// Wayland); por enquanto o texto do celular só chega no Windows.
var errNoClipboard = errors.New("área de transferência do PC ainda só no Windows")

func readClipboard() (string, error) { return "", errNoClipboard }

func writeClipboard(string) error { return errNoClipboard }
