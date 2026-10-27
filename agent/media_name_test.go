package main

import "testing"

func TestFriendlyApp(t *testing.T) {
	for id, want := range map[string]string{
		"Helium._crx_cinhimbnkkghhklpknlkffjgod":                "YouTube Music",
		"Chrome._crx_cinhimbnkkghhklpknlkffjgod":                "YouTube Music",
		"com.github.th-ch.youtube-music":                        "YouTube Music",
		"Spotify.exe":                                           "Spotify",
		"SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify":          "Spotify",
		"Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic": "Media Player",
		"308046B0AF4A39CB":                                      "Firefox",
		"MSEdge":                                                "Edge",
		"Chrome":                                                "Chrome",
		"Helium":                                                "Helium",
		"Helium._crx_abcdefghijklmnopabcdefghijklmnop":          "Helium (app)",
		`C:\\Program Files\\Foo\\foobar2000.exe`:                "foobar2000",
		"Contoso.Player_1a2b3c!App":                             "Player",
		"com.empresa.tocador":                                   "tocador",
	} {
		if got := friendlyApp(id); got != want {
			t.Errorf("friendlyApp(%q) = %q, queria %q", id, got, want)
		}
	}
}
