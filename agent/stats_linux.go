package main

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

type collector struct{ cpu cpuSampler }

func newCollector() *collector { return &collector{} }

func (c *collector) collect() Stats {
	var st Stats
	if idle, total, ok := procStat(); ok {
		st.CPUPercent = c.cpu.percent(idle, total)
	}
	mem := meminfo()
	st.MemTotal = mem["MemTotal"]
	if avail, ok := mem["MemAvailable"]; ok && st.MemTotal >= avail {
		st.MemUsed = st.MemTotal - avail
	}
	var fs syscall.Statfs_t
	if syscall.Statfs("/", &fs) == nil {
		st.DiskTotal = fs.Blocks * uint64(fs.Bsize)
		st.DiskUsed = st.DiskTotal - fs.Bavail*uint64(fs.Bsize)
	}
	if b, err := os.ReadFile("/proc/uptime"); err == nil {
		if f := strings.Fields(string(b)); len(f) > 0 {
			up, _ := strconv.ParseFloat(f[0], 64)
			st.UptimeSeconds = uint64(up)
		}
	}
	st.CPUTemp = hwmonTemp("k10temp", "coretemp", "zenpower")
	st.GPU = amdGPU()
	return st
}

// procStat devolve os jiffies ociosos e totais da linha "cpu" de /proc/stat.
func procStat() (idle, total uint64, ok bool) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return 0, 0, false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	if !sc.Scan() {
		return 0, 0, false
	}
	fields := strings.Fields(sc.Text())
	if len(fields) < 5 || fields[0] != "cpu" {
		return 0, 0, false
	}
	for i, v := range fields[1:] {
		n, _ := strconv.ParseUint(v, 10, 64)
		total += n
		if i == 3 || i == 4 { // idle + iowait
			idle += n
		}
	}
	return idle, total, true
}

func meminfo() map[string]uint64 {
	out := map[string]uint64{}
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return out
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), ":")
		if !ok {
			continue
		}
		f := strings.Fields(v)
		if len(f) == 0 {
			continue
		}
		n, _ := strconv.ParseUint(f[0], 10, 64)
		out[k] = n * 1024 // kB
	}
	return out
}

func readUint(path string) (uint64, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	n, err := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
	return n, err == nil
}

// hwmonTemp lê temp1_input (milésimos de °C) do primeiro sensor com um dos nomes.
func hwmonTemp(names ...string) *float64 {
	dirs, _ := filepath.Glob("/sys/class/hwmon/hwmon*")
	for _, d := range dirs {
		b, err := os.ReadFile(filepath.Join(d, "name"))
		if err != nil {
			continue
		}
		name := strings.TrimSpace(string(b))
		for _, want := range names {
			if name == want {
				if v, ok := readUint(filepath.Join(d, "temp1_input")); ok {
					t := float64(v) / 1000
					return &t
				}
			}
		}
	}
	return nil
}

// amdGPU usa os arquivos do driver amdgpu. Outras placas: sem medidor.
func amdGPU() *GPUStat {
	cards, _ := filepath.Glob("/sys/class/drm/card[0-9]*/device")
	for _, dev := range cards {
		busy, ok := readUint(filepath.Join(dev, "gpu_busy_percent"))
		if !ok {
			continue
		}
		g := &GPUStat{Name: "AMD Radeon", Percent: clampPercent(float64(busy))}
		g.VRAMUsed, _ = readUint(filepath.Join(dev, "mem_info_vram_used"))
		g.VRAMTotal, _ = readUint(filepath.Join(dev, "mem_info_vram_total"))
		if hw, _ := filepath.Glob(filepath.Join(dev, "hwmon", "hwmon*", "temp1_input")); len(hw) > 0 {
			if v, ok := readUint(hw[0]); ok {
				t := float64(v) / 1000
				g.Temp = &t
			}
		}
		return g
	}
	return nil
}

func readCPUName() string {
	b, _ := os.ReadFile("/proc/cpuinfo")
	for _, line := range strings.Split(string(b), "\n") {
		if k, v, ok := strings.Cut(line, ":"); ok && strings.TrimSpace(k) == "model name" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
