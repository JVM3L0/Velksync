package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

// MPRIS: o padrão de controle de mídia do Linux (Spotify, navegadores, VLC...).

const (
	mprisPrefix = "org.mpris.MediaPlayer2."
	mprisPath   = dbus.ObjectPath("/org/mpris/MediaPlayer2")
	mprisRoot   = "org.mpris.MediaPlayer2"
	mprisPlayer = "org.mpris.MediaPlayer2.Player"
)

type mprisBackend struct {
	mu   sync.Mutex
	conn *dbus.Conn
	art  struct {
		url   string
		data  []byte
		ctype string
	}
}

func newMediaBackend() mediaBackend { return &mprisBackend{} }

func (m *mprisBackend) bus() (*dbus.Conn, error) {
	if m.conn != nil && m.conn.Connected() {
		return m.conn, nil
	}
	c, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, fmt.Errorf("sem sessão D-Bus: %w", err)
	}
	m.conn = c
	return c, nil
}

// player escolhe o player ativo: o que está tocando, senão um pausado.
func (m *mprisBackend) player() (string, dbus.BusObject, error) {
	conn, err := m.bus()
	if err != nil {
		return "", nil, err
	}
	var names []string
	if err := conn.BusObject().Call("org.freedesktop.DBus.ListNames", 0).Store(&names); err != nil {
		return "", nil, err
	}
	var players []string
	for _, n := range names {
		if strings.HasPrefix(n, mprisPrefix) {
			players = append(players, n)
		}
	}
	if len(players) == 0 {
		return "", nil, errNoMedia
	}
	slices.Sort(players)
	best, rank := players[0], 3
	for _, n := range players {
		v, err := conn.Object(n, mprisPath).GetProperty(mprisPlayer + ".PlaybackStatus")
		if err != nil {
			continue
		}
		r := 2
		switch asString(v) {
		case "Playing":
			r = 0
		case "Paused":
			r = 1
		}
		if r < rank {
			best, rank = n, r
		}
	}
	return best, conn.Object(best, mprisPath), nil
}

func asString(v dbus.Variant) string {
	s, _ := v.Value().(string)
	return s
}

func asInt64(v any) int64 {
	switch n := v.(type) {
	case int64:
		return n
	case uint64:
		return int64(n)
	case int32:
		return int64(n)
	case uint32:
		return int64(n)
	case float64:
		return int64(n)
	}
	return 0
}

func metaString(meta map[string]dbus.Variant, key string) string {
	v, ok := meta[key]
	if !ok {
		return ""
	}
	switch x := v.Value().(type) {
	case string:
		return x
	case []string:
		return strings.Join(x, ", ")
	}
	return ""
}

func (m *mprisBackend) State() (MediaState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := MediaState{Status: "stopped"}
	st.Volume, st.Muted = systemVolume()
	name, obj, err := m.player()
	if err != nil {
		return st, err
	}
	props := map[string]dbus.Variant{}
	if err := obj.Call("org.freedesktop.DBus.Properties.GetAll", 0, mprisPlayer).Store(&props); err != nil {
		return st, err
	}
	st.Available = true
	st.Player = strings.TrimPrefix(name, mprisPrefix)
	if v, err := obj.GetProperty(mprisRoot + ".Identity"); err == nil && asString(v) != "" {
		st.Player = asString(v)
	}
	st.Status = strings.ToLower(asString(props["PlaybackStatus"]))
	meta, _ := props["Metadata"].Value().(map[string]dbus.Variant)
	st.Title = metaString(meta, "xesam:title")
	st.Artist = metaString(meta, "xesam:artist")
	st.Album = metaString(meta, "xesam:album")
	if v, ok := meta["mpris:length"]; ok {
		st.DurationMs = asInt64(v.Value()) / 1000
	}
	// Position não emite sinal de mudança: lê na hora em vez de usar o GetAll.
	if v, err := obj.GetProperty(mprisPlayer + ".Position"); err == nil {
		st.PositionMs = asInt64(v.Value()) / 1000
	}
	st.CanSeek, _ = props["CanSeek"].Value().(bool)
	st.CanControl, _ = props["CanControl"].Value().(bool)
	if art := metaString(meta, "mpris:artUrl"); art != "" {
		sum := sha256.Sum256([]byte(art))
		st.ArtID = hex.EncodeToString(sum[:8])
	}
	return st, nil
}

func (m *mprisBackend) Art() ([]byte, string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, obj, err := m.player()
	if err != nil {
		return nil, "", err
	}
	v, err := obj.GetProperty(mprisPlayer + ".Metadata")
	if err != nil {
		return nil, "", err
	}
	meta, _ := v.Value().(map[string]dbus.Variant)
	artURL := metaString(meta, "mpris:artUrl")
	if artURL == "" {
		return nil, "", errNoMedia
	}
	if m.art.url == artURL {
		return m.art.data, m.art.ctype, nil
	}
	data, err := fetchArt(artURL)
	if err != nil {
		return nil, "", err
	}
	// Só entrega imagens: um artUrl malicioso não pode vazar outro arquivo.
	ctype := http.DetectContentType(data)
	if !strings.HasPrefix(ctype, "image/") {
		return nil, "", errors.New("capa não é imagem")
	}
	m.art.url, m.art.data, m.art.ctype = artURL, data, ctype
	return data, ctype, nil
}

// fetchArt lê a capa de file:// ou https://, com limite de tamanho e tempo.
func fetchArt(raw string) ([]byte, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	switch u.Scheme {
	case "file":
		f, err := os.Open(u.Path)
		if err != nil {
			return nil, err
		}
		defer f.Close()
		return io.ReadAll(io.LimitReader(f, maxArtBytes))
	case "https":
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Get(u.String())
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("capa: %s", resp.Status)
		}
		return io.ReadAll(io.LimitReader(resp.Body, maxArtBytes))
	}
	return nil, fmt.Errorf("esquema de capa não suportado: %s", u.Scheme)
}

func (m *mprisBackend) Command(action string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, obj, err := m.player()
	if err != nil {
		return err
	}
	method := map[string]string{"play_pause": "PlayPause", "next": "Next", "previous": "Previous"}[action]
	return obj.Call(mprisPlayer+"."+method, 0).Err
}

func (m *mprisBackend) SeekTo(positionMs int64) error {
	if positionMs < 0 {
		return errors.New("posição inválida")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	_, obj, err := m.player()
	if err != nil {
		return err
	}
	v, err := obj.GetProperty(mprisPlayer + ".Metadata")
	if err != nil {
		return err
	}
	meta, _ := v.Value().(map[string]dbus.Variant)
	track, ok := meta["mpris:trackid"].Value().(dbus.ObjectPath)
	if !ok {
		return errors.New("o player não informa a faixa atual")
	}
	return obj.Call(mprisPlayer+".SetPosition", 0, track, positionMs*1000).Err
}

func (m *mprisBackend) SetVolume(volume *float64, muted *bool) error {
	if _, err := exec.LookPath("wpctl"); err == nil { // PipeWire
		if volume != nil {
			if out, err := exec.Command("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", strconv.FormatFloat(*volume, 'f', 2, 64)).CombinedOutput(); err != nil {
				return fmt.Errorf("wpctl: %v %s", err, out)
			}
		}
		if muted != nil {
			return exec.Command("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", map[bool]string{true: "1", false: "0"}[*muted]).Run()
		}
		return nil
	}
	if _, err := exec.LookPath("pactl"); err == nil { // PulseAudio
		if volume != nil {
			if err := exec.Command("pactl", "set-sink-volume", "@DEFAULT_SINK@", fmt.Sprintf("%d%%", int(*volume*100+0.5))).Run(); err != nil {
				return err
			}
		}
		if muted != nil {
			return exec.Command("pactl", "set-sink-mute", "@DEFAULT_SINK@", map[bool]string{true: "1", false: "0"}[*muted]).Run()
		}
		return nil
	}
	return errors.New("controle de volume indisponível (instale wireplumber ou pulseaudio-utils)")
}

var (
	wpctlVolume = regexp.MustCompile(`Volume:\s*([0-9.]+)`)
	pactlVolume = regexp.MustCompile(`(\d+)%`)
)

func systemVolume() (*float64, *bool) {
	if out, err := exec.Command("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@").Output(); err == nil {
		if m := wpctlVolume.FindSubmatch(out); m != nil {
			v, _ := strconv.ParseFloat(string(m[1]), 64)
			v = min(v, 1)
			muted := strings.Contains(string(out), "MUTED")
			return &v, &muted
		}
	}
	if out, err := exec.Command("pactl", "get-sink-volume", "@DEFAULT_SINK@").Output(); err == nil {
		if m := pactlVolume.FindSubmatch(out); m != nil {
			p, _ := strconv.Atoi(string(m[1]))
			v := min(float64(p)/100, 1)
			mo, _ := exec.Command("pactl", "get-sink-mute", "@DEFAULT_SINK@").Output()
			muted := strings.Contains(string(mo), "yes")
			return &v, &muted
		}
	}
	return nil, nil
}
