package main

import (
	"errors"
	"fmt"
	"log"
	"net/http"
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

// Trocados nos testes, para não abrir o navegador nem mexer na área de
// transferência de verdade.
var (
	openLink = openURL
	copyText = writeClipboard
)

// POST /api/inbox {"text": "..."}: texto vindo do celular (menu Compartilhar
// do Android). Um link http(s) abre no navegador do PC; outro texto vai para
// a área de transferência. Nada é executado.
func (s *Server) inbox(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Text string `json:"text"`
	}
	if err := decode(r, &req); err != nil || strings.TrimSpace(req.Text) == "" {
		writeErr(w, http.StatusBadRequest, "texto vazio")
		return
	}
	if len(req.Text) > maxSendText {
		writeErr(w, http.StatusRequestEntityTooLarge, "texto grande demais (limite de 64 KB)")
		return
	}
	by := s.deviceName(clientOf(r))
	if isLink(req.Text) {
		link := strings.TrimSpace(req.Text)
		if err := openLink(link); err != nil {
			log.Printf("inbox: abrir link de %s: %v", by, err)
			writeErr(w, http.StatusInternalServerError, "não deu para abrir o link no PC")
			return
		}
		log.Printf("inbox: %s abriu um link", by)
		s.notice(by, "abriu um link: "+clip(link, 60))
		s.history.Add(by, histReceive, "abriu um link no PC", false)
		writeJSON(w, http.StatusOK, map[string]string{"result": "opened"})
		return
	}
	if err := copyText(req.Text); err != nil {
		writeErr(w, http.StatusNotImplemented, err.Error())
		return
	}
	log.Printf("inbox: %s enviou um texto (%d caracteres)", by, len([]rune(req.Text)))
	s.notice(by, fmt.Sprintf("enviou um texto: \u201c%s\u201d (copiado)", clip(req.Text, 50)))
	s.history.Add(by, histReceive, "enviou um texto (copiado no PC)", false)
	writeJSON(w, http.StatusOK, map[string]string{"result": "copied"})
}
