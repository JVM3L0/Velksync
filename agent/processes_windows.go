package main

import (
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var procGetProcessMemoryInfo = kernel32w.NewProc("K32GetProcessMemoryInfo")

type processMemoryCounters struct {
	Size                       uint32
	PageFaultCount             uint32
	PeakWorkingSetSize         uintptr
	WorkingSetSize             uintptr
	QuotaPeakPagedPoolUsage    uintptr
	QuotaPagedPoolUsage        uintptr
	QuotaPeakNonPagedPoolUsage uintptr
	QuotaNonPagedPoolUsage     uintptr
	PagefileUsage              uintptr
	PeakPagefileUsage          uintptr
}

func filetimeDuration(f windows.Filetime) time.Duration {
	return time.Duration((uint64(f.HighDateTime)<<32 | uint64(f.LowDateTime)) * 100)
}

// GPU por processo: os mesmos contadores do Gerenciador de Tarefas. A
// consulta fica aberta (o uso é a diferença entre duas coletas).
var gpuProcs struct {
	once         sync.Once
	mu           sync.Mutex
	query        uintptr
	engine, vram uintptr
}

// gpuByPID devolve % de GPU (motores 3D somados) e VRAM dedicada por PID.
func gpuByPID() (map[uint32]float64, map[uint32]uint64, bool) {
	g := &gpuProcs
	g.once.Do(func() {
		if procPdhOpenQueryW.Find() != nil {
			return
		}
		var q uintptr
		if r, _, _ := procPdhOpenQueryW.Call(0, 0, uintptr(unsafe.Pointer(&q))); r != 0 {
			return
		}
		g.query = q
		g.engine = addCounter(q, `\GPU Engine(*engtype_3D)\Utilization Percentage`)
		g.vram = addCounter(q, `\GPU Process Memory(*)\Dedicated Usage`)
	})
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.query == 0 || (g.engine == 0 && g.vram == 0) {
		return nil, nil, false
	}
	if r, _, _ := procPdhCollectQueryData.Call(g.query); r != 0 {
		return nil, nil, false
	}
	use := map[uint32]float64{}
	for name, v := range counterNamedValues(g.engine) {
		if pid, ok := pidOfInstance(name); ok {
			use[pid] += v
		}
	}
	mem := map[uint32]uint64{}
	for name, v := range counterNamedValues(g.vram) {
		if pid, ok := pidOfInstance(name); ok {
			mem[pid] += uint64(v)
		}
	}
	return use, mem, true
}

// pidOfInstance lê o PID do nome da instância: "pid_1234_luid_0x…_phys_0…".
func pidOfInstance(name string) (uint32, bool) {
	rest, ok := strings.CutPrefix(name, "pid_")
	if !ok {
		return 0, false
	}
	n, _, _ := strings.Cut(rest, "_")
	pid, err := strconv.ParseUint(n, 10, 32)
	return uint32(pid), err == nil
}

// counterNamedValues: valores de todas as instâncias, pelo nome. Uma
// instância pode aparecer mais de uma vez (motores diferentes): soma.
func counterNamedValues(h uintptr) map[string]float64 {
	if h == 0 {
		return nil
	}
	var size, count uint32
	r, _, _ := procPdhGetFormattedCounterArrayW.Call(h, pdhFmtDouble|pdhFmtNoCap100,
		uintptr(unsafe.Pointer(&size)), uintptr(unsafe.Pointer(&count)), 0)
	if uint32(r) != pdhMoreData || size == 0 {
		return nil
	}
	buf := make([]byte, size)
	r, _, _ = procPdhGetFormattedCounterArrayW.Call(h, pdhFmtDouble|pdhFmtNoCap100,
		uintptr(unsafe.Pointer(&size)), uintptr(unsafe.Pointer(&count)), uintptr(unsafe.Pointer(&buf[0])))
	if r != 0 {
		return nil
	}
	items := unsafe.Slice((*pdhItem)(unsafe.Pointer(&buf[0])), count)
	out := make(map[string]float64, count)
	for _, it := range items {
		if it.status == 0 && it.name != nil {
			out[windows.UTF16PtrToString(it.name)] += it.value
		}
	}
	return out
}

// readProcesses lista os processos com tempo de CPU, memória e, quando o
// Windows informa, GPU e VRAM. Os que o usuário não pode consultar (do
// sistema, protegidos) entram só pelo nome.
func readProcesses() ([]procSample, bool, error) {
	snap, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return nil, false, err
	}
	defer windows.CloseHandle(snap)
	var e windows.ProcessEntry32
	e.Size = uint32(unsafe.Sizeof(e))
	var out []procSample
	for err = windows.Process32First(snap, &e); err == nil; err = windows.Process32Next(snap, &e) {
		p := procSample{PID: e.ProcessID, Name: windows.UTF16ToString(e.ExeFile[:])}
		if h, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, e.ProcessID); err == nil {
			var c, x, k, u windows.Filetime
			if windows.GetProcessTimes(h, &c, &x, &k, &u) == nil {
				p.CPUTime = filetimeDuration(k) + filetimeDuration(u)
			}
			var m processMemoryCounters
			m.Size = uint32(unsafe.Sizeof(m))
			if r, _, _ := procGetProcessMemoryInfo.Call(uintptr(h), uintptr(unsafe.Pointer(&m)), uintptr(m.Size)); r != 0 {
				p.Mem = uint64(m.WorkingSetSize)
			}
			windows.CloseHandle(h)
		}
		out = append(out, p)
	}
	gpu, vram, withGPU := gpuByPID()
	for i := range out {
		out[i].GPU, out[i].VRAM = gpu[out[i].PID], vram[out[i].PID]
	}
	return out, withGPU, nil
}
