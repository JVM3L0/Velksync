package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

type artOnlyBackend struct {
	mediaBackend
	id string
}

func (b artOnlyBackend) Art() ([]byte, string, string, error) {
	return pngHeader, "image/png", b.id, nil
}

// O app pede a capa pelo art_id que viu; se ela trocou nesse meio tempo, o
// agente recusa em vez de entregar a nova (que o app guardaria no id antigo).
func TestMediaArtChecksID(t *testing.T) {
	old := media
	t.Cleanup(func() { media = old })
	media = func() mediaBackend { return artOnlyBackend{id: "novo"} }
	s := &Server{}

	for path, want := range map[string]int{
		"/api/media/art":          http.StatusOK, // apps antigos não mandam o id
		"/api/media/art?id=novo":  http.StatusOK,
		"/api/media/art?id=velho": http.StatusConflict,
	} {
		w := httptest.NewRecorder()
		s.mediaArt(w, httptest.NewRequest("GET", path, nil))
		if w.Code != want {
			t.Errorf("%s: %d, queria %d", path, w.Code, want)
		}
		if want == http.StatusOK && w.Header().Get("X-Art-Id") != "novo" {
			t.Errorf("%s: X-Art-Id %q", path, w.Header().Get("X-Art-Id"))
		}
	}
}
