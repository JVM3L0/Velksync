package main

import (
	"bufio"
	"encoding/base64"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/prop"
)

// Player MPRIS falso num barramento D-Bus privado: testa o backend Linux sem
// depender de um player de verdade.

type fakePlayer struct{ props *prop.Properties }

func (f *fakePlayer) PlayPause() *dbus.Error {
	next := "Playing"
	if v, _ := f.props.Get(mprisPlayer, "PlaybackStatus"); v.Value() == "Playing" {
		next = "Paused"
	}
	f.props.SetMust(mprisPlayer, "PlaybackStatus", next)
	return nil
}
func (f *fakePlayer) Next() *dbus.Error     { return nil }
func (f *fakePlayer) Previous() *dbus.Error { return nil }
func (f *fakePlayer) SetPosition(track dbus.ObjectPath, pos int64) *dbus.Error {
	f.props.SetMust(mprisPlayer, "Position", pos)
	return nil
}

func startPrivateBus(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("dbus-daemon"); err != nil {
		t.Skip("dbus-daemon não instalado")
	}
	cmd := exec.Command("dbus-daemon", "--session", "--nofork", "--print-address")
	out, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		t.Skip(err)
	}
	t.Cleanup(func() { cmd.Process.Kill(); cmd.Wait() })
	addr, err := bufio.NewReader(out).ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", strings.TrimSpace(addr))
}

func exportFakePlayer(t *testing.T, artURL string) {
	t.Helper()
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	meta := map[string]dbus.Variant{
		"mpris:trackid": dbus.MakeVariant(dbus.ObjectPath("/track/1")),
		"xesam:title":   dbus.MakeVariant("Proof of a Hero"),
		"xesam:artist":  dbus.MakeVariant([]string{"Monster Hunter Orchestra"}),
		"xesam:album":   dbus.MakeVariant("Iceborne"),
		"mpris:length":  dbus.MakeVariant(int64(245_000_000)),
		"mpris:artUrl":  dbus.MakeVariant(artURL),
	}
	props, err := prop.Export(conn, mprisPath, prop.Map{
		mprisRoot: {"Identity": {Value: "Fake Player", Emit: prop.EmitTrue}},
		mprisPlayer: {
			"PlaybackStatus": {Value: "Paused", Emit: prop.EmitTrue},
			"Metadata":       {Value: meta, Emit: prop.EmitTrue},
			"Position":       {Value: int64(30_000_000), Emit: prop.EmitFalse},
			"CanSeek":        {Value: true, Emit: prop.EmitTrue},
			"CanControl":     {Value: true, Emit: prop.EmitTrue},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := conn.Export(&fakePlayer{props}, mprisPath, mprisPlayer); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.RequestName(mprisPrefix+"fake", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
}

// PNG 1x1 válido.
var tinyPNG, _ = base64.StdEncoding.DecodeString(
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

func TestMPRISStateAndControls(t *testing.T) {
	startPrivateBus(t)
	art := filepath.Join(t.TempDir(), "capa.png")
	os.WriteFile(art, tinyPNG, 0o600)
	exportFakePlayer(t, "file://"+art)

	m := &mprisBackend{}
	st, err := m.State()
	if err != nil {
		t.Fatal(err)
	}
	if !st.Available || st.Player != "Fake Player" || st.Title != "Proof of a Hero" ||
		st.Artist != "Monster Hunter Orchestra" || st.Status != "paused" ||
		st.DurationMs != 245_000 || st.PositionMs != 30_000 || !st.CanSeek || st.ArtID == "" {
		t.Fatalf("estado inesperado: %+v", st)
	}
	if err := m.Command("play_pause"); err != nil {
		t.Fatal(err)
	}
	if st, _ = m.State(); st.Status != "playing" {
		t.Fatalf("play_pause não alternou: %s", st.Status)
	}
	if err := m.SeekTo(-1); err == nil {
		t.Fatal("aceitou posição negativa")
	}
	if err := m.SeekTo(90_000); err != nil {
		t.Fatal(err)
	}
	if st, _ = m.State(); st.PositionMs != 90_000 {
		t.Fatalf("seek: posição %d", st.PositionMs)
	}
	data, ctype, err := m.Art()
	if err != nil || ctype != "image/png" || len(data) != len(tinyPNG) {
		t.Fatalf("capa: %v %s %d", err, ctype, len(data))
	}
}

func TestMPRISArtOnlyServesImages(t *testing.T) {
	startPrivateBus(t)
	secret := filepath.Join(t.TempDir(), "id_ed25519")
	os.WriteFile(secret, []byte("-----BEGIN OPENSSH PRIVATE KEY-----\nsegredo\n"), 0o600)
	exportFakePlayer(t, "file://"+secret)
	if data, _, err := (&mprisBackend{}).Art(); err == nil {
		t.Fatalf("serviu um arquivo que não é imagem (%d bytes)", len(data))
	}
}

func TestFetchArtRejectsPlainHTTP(t *testing.T) {
	for _, u := range []string{"http://192.168.0.1/admin", "ftp://x/y.png", "gopher://x"} {
		if _, err := fetchArt(u); err == nil {
			t.Errorf("aceitou %s", u)
		}
	}
}

func TestNoPlayer(t *testing.T) {
	startPrivateBus(t)
	if st, err := (&mprisBackend{}).State(); err != errNoMedia || st.Available {
		t.Fatalf("sem player: %+v %v", st, err)
	}
}
