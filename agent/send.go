package main

import (
	"errors"
	"net/url"
	"strings"
)

// Textos trocados entre PC e celular (área de transferência dos dois lados).

const maxSendText = 64 << 10

var errNothingCopied = errors.New("nada copiado")

// isLink: um endereço http(s) sozinho, sem espaços; vira "abrir no navegador".
func isLink(text string) bool {
	t := strings.TrimSpace(text)
	if t == "" || len(t) > 4096 || strings.ContainsAny(t, " \t\r\n") {
		return false
	}
	u, err := url.Parse(t)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

// clipEvent transforma o que está copiado no PC no evento para o celular.
func clipEvent(text string) (Event, error) {
	switch t := strings.TrimSpace(text); {
	case t == "":
		return Event{}, errNothingCopied
	case len(text) > maxSendText:
		return Event{}, errors.New("texto grande demais (limite de 64 KB)")
	case isLink(t):
		return Event{Type: "open_url", URL: t}, nil
	}
	return Event{Type: "clipboard", Text: text}, nil
}

// clipPreview é o começo do que vai ser enviado, para o menu.
func clipPreview(text string) string {
	if strings.TrimSpace(text) == "" {
		return "Nada copiado"
	}
	if isLink(text) {
		return "Link: " + clip(text, 48)
	}
	return "Texto: “" + clip(text, 40) + "”"
}
