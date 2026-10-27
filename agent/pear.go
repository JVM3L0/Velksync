package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"
)

// O Pear Desktop (cliente do YouTube Music) entrega ao Windows a capa já
// reduzida pelo Chromium (~120 px), mas a API dele (plugin API Server) diz o
// endereço da imagem grande. Na primeira vez que ele toca, o agente pede
// acesso: o próprio Pear pergunta "Permitir / Negar" na tela. Só fala com o
// Pear deste PC (127.0.0.1) e só baixa imagens dos servidores do Google.

const (
	pearBase     = "http://127.0.0.1:26538"
	pearClientID = "Velksync"
	// Sem resposta da API (plugin desligado): tenta de novo depois disso.
	pearRetry = 5 * time.Minute
)

var pearImageHosts = []string{"lh3.googleusercontent.com", "i.ytimg.com", "yt3.ggpht.com", "yt3.googleusercontent.com"}

// isPear diz se o player do Windows é o Pear Desktop (antes de virar nome amigável).
func isPear(appID string) bool {
	return strings.Contains(strings.ToLower(appID), "th-ch.youtube-music")
}

type pearClient struct {
	base   string
	api    *http.Client // só 127.0.0.1
	images *http.Client // só os servidores de imagem
	// imageOK confere o endereço da capa (trocado nos testes, que não têm HTTPS).
	imageOK func(*url.URL) bool
	now     func() time.Time
	// save grava o token (ou a recusa) na config; nunca vai para o log.
	save func(token string, denied bool)

	mu        sync.Mutex
	token     string
	denied    bool
	asking    bool
	lastTry   time.Time
	cacheKey  string
	cacheData []byte
	cacheType string
}

func newPearClient(token string, denied bool, save func(string, bool)) *pearClient {
	return &pearClient{
		base: pearBase, token: token, denied: denied, save: save, now: time.Now, imageOK: pearImageURLOK,
		api: &http.Client{Timeout: 5 * time.Second},
		images: &http.Client{Timeout: 8 * time.Second, CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if len(via) > 3 || !pearImageURLOK(r.URL) {
				return errors.New("redirecionamento para fora dos servidores de imagem")
			}
			return nil
		}},
	}
}

// Ready: já tem acesso. O art_id ganha um sufixo para o app buscar a capa de
// novo quando o acesso chega.
func (p *pearClient) Ready() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.token != ""
}

// MaybeAuthorize pede acesso em segundo plano, uma vez: o Pear mostra a
// pergunta e a resposta pode demorar o quanto a pessoa quiser.
func (p *pearClient) MaybeAuthorize() {
	p.mu.Lock()
	if p.token != "" || p.denied || p.asking || (!p.lastTry.IsZero() && p.now().Sub(p.lastTry) < pearRetry) {
		p.mu.Unlock()
		return
	}
	p.asking, p.lastTry = true, p.now()
	p.mu.Unlock()
	go func() {
		token, denied, err := p.authorize()
		p.mu.Lock()
		p.asking = false
		if err != nil {
			p.mu.Unlock()
			log.Printf("pear: sem acesso à API (%v); o plugin API Server está ligado?", err)
			return
		}
		p.token, p.denied = token, denied
		p.mu.Unlock()
		if denied {
			log.Printf("pear: acesso negado no Pear; capas ficam no tamanho do Windows")
		} else {
			log.Printf("pear: acesso liberado; capas em alta")
		}
		p.save(token, denied)
	}()
}

func (p *pearClient) authorize() (token string, denied bool, err error) {
	// Sem tempo limite: a resposta espera alguém clicar no Pear.
	res, err := http.Post(p.base+"/auth/"+url.PathEscape(pearClientID), "application/json", nil)
	if err != nil {
		return "", false, err
	}
	defer res.Body.Close()
	switch res.StatusCode {
	case http.StatusOK:
		var body struct {
			AccessToken string `json:"accessToken"`
		}
		if err := json.NewDecoder(io.LimitReader(res.Body, 64<<10)).Decode(&body); err != nil || body.AccessToken == "" {
			return "", false, errors.New("resposta sem token")
		}
		return body.AccessToken, false, nil
	case http.StatusForbidden:
		return "", true, nil
	}
	return "", false, fmt.Errorf("HTTP %d", res.StatusCode)
}

// As imagens do Google aceitam o tamanho no próprio endereço ("=w544-h544"):
// pede uma maior, que fica nítida na tela do celular.
var googleImageSize = regexp.MustCompile(`=w\d+-h\d+`)

func biggerImage(u *url.URL) {
	if strings.HasSuffix(u.Hostname(), "googleusercontent.com") || strings.HasSuffix(u.Hostname(), "ggpht.com") {
		u.Path = googleImageSize.ReplaceAllString(u.Path, "=w1200-h1200")
	}
}

func pearImageURLOK(u *url.URL) bool {
	return u.Scheme == "https" && u.User == nil && slices.Contains(pearImageHosts, strings.ToLower(u.Hostname()))
}

// sameSong compara o título do Pear com o do Windows: só usa a capa se for a
// mesma música (o Pear pode ter acabado de trocar).
func sameSong(a, b string) bool {
	norm := func(s string) string { return strings.ToLower(strings.Join(strings.Fields(s), " ")) }
	return a != "" && norm(a) == norm(b)
}

// Art devolve a capa grande da música com este título.
func (p *pearClient) Art(title string) ([]byte, string, error) {
	p.mu.Lock()
	token := p.token
	if p.cacheKey != "" && sameSong(p.cacheKey, title) {
		data, ctype := p.cacheData, p.cacheType
		p.mu.Unlock()
		return data, ctype, nil
	}
	p.mu.Unlock()
	if token == "" {
		return nil, "", errors.New("pear: sem acesso")
	}

	req, _ := http.NewRequest("GET", p.base+"/api/v1/song", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := p.api.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusUnauthorized || res.StatusCode == http.StatusForbidden {
		// Acesso revogado no Pear (ou segredo trocado): pede de novo depois.
		p.mu.Lock()
		p.token, p.lastTry = "", p.now()
		p.mu.Unlock()
		p.save("", false)
		return nil, "", errors.New("pear: acesso revogado")
	}
	if res.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("pear: HTTP %d", res.StatusCode)
	}
	var song struct {
		Title    string `json:"title"`
		ImageSrc string `json:"imageSrc"`
	}
	if err := json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(&song); err != nil {
		return nil, "", err
	}
	if !sameSong(song.Title, title) {
		return nil, "", errors.New("pear: outra música")
	}
	u, err := url.Parse(song.ImageSrc)
	if err != nil || !p.imageOK(u) {
		return nil, "", errors.New("pear: endereço de capa fora dos servidores de imagem")
	}
	biggerImage(u)
	img, err := p.images.Get(u.String())
	if err != nil {
		return nil, "", err
	}
	defer img.Body.Close()
	if img.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("pear: capa HTTP %d", img.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(img.Body, maxArtBytes+1))
	if err != nil || len(data) > maxArtBytes {
		return nil, "", errors.New("pear: capa grande demais")
	}
	ctype := http.DetectContentType(data)
	if !strings.HasPrefix(ctype, "image/") {
		return nil, "", errors.New("pear: capa não é imagem")
	}
	p.mu.Lock()
	p.cacheKey, p.cacheData, p.cacheType = title, data, ctype
	p.mu.Unlock()
	return data, ctype, nil
}

// pear é ligado pelo run() com o token da config; nil nos testes e no Linux.
var pear *pearClient
