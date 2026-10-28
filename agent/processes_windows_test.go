package main

import "testing"

func TestPidOfInstance(t *testing.T) {
	for name, want := range map[string]uint32{
		"pid_1234_luid_0x00000000_0x0000D1C5_phys_0_eng_0_engtype_3D": 1234,
		"pid_8_luid_0x0_phys_0": 8,
	} {
		if got, ok := pidOfInstance(name); !ok || got != want {
			t.Errorf("pidOfInstance(%q) = %d %v", name, got, ok)
		}
	}
	for _, bad := range []string{"_Total", "luid_0x0", "pid_x_luid"} {
		if _, ok := pidOfInstance(bad); ok {
			t.Errorf("aceitou %q", bad)
		}
	}
}
