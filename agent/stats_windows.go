package main

import (
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

// Coleta no Windows com APIs nativas (as mesmas fontes do Gerenciador de
// Tarefas): GetSystemTimes, GlobalMemoryStatusEx e os contadores de desempenho
// (PDH) de GPU. O Windows não expõe temperaturas sem driver de terceiros.

var (
	kernel32                 = syscall.NewLazyDLL("kernel32.dll")
	procGetSystemTimes       = kernel32.NewProc("GetSystemTimes")
	procGlobalMemoryStatusEx = kernel32.NewProc("GlobalMemoryStatusEx")
	procGetDiskFreeSpaceExW  = kernel32.NewProc("GetDiskFreeSpaceExW")
	procGetTickCount64       = kernel32.NewProc("GetTickCount64")

	pdh                              = syscall.NewLazyDLL("pdh.dll")
	procPdhOpenQueryW                = pdh.NewProc("PdhOpenQueryW")
	procPdhAddEnglishCounterW        = pdh.NewProc("PdhAddEnglishCounterW")
	procPdhCollectQueryData          = pdh.NewProc("PdhCollectQueryData")
	procPdhGetFormattedCounterArrayW = pdh.NewProc("PdhGetFormattedCounterArrayW")
)

const (
	pdhFmtDouble   = 0x00000200
	pdhFmtNoCap100 = 0x00008000
	pdhMoreData    = 0x800007D2
)

type collector struct {
	cpu cpuSampler

	mu        sync.Mutex
	gpuQuery  uintptr
	gpu3D     uintptr // \GPU Engine(*engtype_3D)\Utilization Percentage
	gpuMem    uintptr // \GPU Adapter Memory(*)\Dedicated Usage
	gpuName   string
	vramTotal uint64
}

func newCollector() *collector {
	c := &collector{}
	c.gpuName, c.vramTotal = displayAdapter()
	if procPdhOpenQueryW.Find() != nil {
		return c
	}
	var q uintptr
	if r, _, _ := procPdhOpenQueryW.Call(0, 0, uintptr(unsafe.Pointer(&q))); r != 0 {
		return c
	}
	c.gpuQuery = q
	c.gpu3D = addCounter(q, `\GPU Engine(*engtype_3D)\Utilization Percentage`)
	c.gpuMem = addCounter(q, `\GPU Adapter Memory(*)\Dedicated Usage`)
	procPdhCollectQueryData.Call(q) // primeira amostra (uso é diferença entre duas)
	return c
}

func addCounter(q uintptr, path string) uintptr {
	p, _ := syscall.UTF16PtrFromString(path)
	var h uintptr
	if r, _, _ := procPdhAddEnglishCounterW.Call(q, uintptr(unsafe.Pointer(p)), 0, uintptr(unsafe.Pointer(&h))); r != 0 {
		return 0
	}
	return h
}

// pdhItem espelha PDH_FMT_COUNTERVALUE_ITEM_W com valor double (amd64).
type pdhItem struct {
	name   *uint16
	status uint32
	_      uint32
	value  float64
}

// counterValues devolve os valores de todas as instâncias do contador.
func counterValues(h uintptr) []float64 {
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
	out := make([]float64, 0, count)
	for _, it := range items {
		if it.status == 0 { // PDH_CSTATUS_VALID_DATA
			out = append(out, it.value)
		}
	}
	return out
}

func (c *collector) collect() Stats {
	var st Stats

	var idle, kern, user syscall.Filetime
	if r, _, _ := procGetSystemTimes.Call(uintptr(unsafe.Pointer(&idle)), uintptr(unsafe.Pointer(&kern)),
		uintptr(unsafe.Pointer(&user))); r != 0 {
		ft := func(f syscall.Filetime) uint64 { return uint64(f.HighDateTime)<<32 | uint64(f.LowDateTime) }
		// O tempo de kernel já inclui o ocioso.
		st.CPUPercent = c.cpu.percent(ft(idle), ft(kern)+ft(user))
	}

	var mem struct {
		length, load              uint32
		totalPhys, availPhys      uint64
		totalPage, availPage      uint64
		totalVirtual, availVirtal uint64
		availExtended             uint64
	}
	mem.length = uint32(unsafe.Sizeof(mem))
	if r, _, _ := procGlobalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&mem))); r != 0 {
		st.MemTotal, st.MemUsed = mem.totalPhys, mem.totalPhys-mem.availPhys
	}

	var freeAvail, total, totalFree uint64
	drive, _ := syscall.UTF16PtrFromString(`C:\`)
	if r, _, _ := procGetDiskFreeSpaceExW.Call(uintptr(unsafe.Pointer(drive)), uintptr(unsafe.Pointer(&freeAvail)),
		uintptr(unsafe.Pointer(&total)), uintptr(unsafe.Pointer(&totalFree))); r != 0 {
		st.DiskTotal, st.DiskUsed = total, total-totalFree
	}

	ms, _, _ := procGetTickCount64.Call()
	st.UptimeSeconds = uint64(ms) / 1000

	c.mu.Lock()
	defer c.mu.Unlock()
	if c.gpuQuery != 0 {
		if r, _, _ := procPdhCollectQueryData.Call(c.gpuQuery); r == 0 {
			g := &GPUStat{Name: c.gpuName, VRAMTotal: c.vramTotal}
			for _, v := range counterValues(c.gpu3D) {
				g.Percent += v // soma dos motores 3D, como o Gerenciador de Tarefas
			}
			g.Percent = clampPercent(g.Percent)
			for _, v := range counterValues(c.gpuMem) {
				g.VRAMUsed = max(g.VRAMUsed, uint64(v)) // placa dedicada = maior uso
			}
			st.GPU = g
		}
	}
	return st
}

// displayAdapter lê nome e VRAM da placa de vídeo com mais memória no registro.
func displayAdapter() (string, uint64) {
	const class = `SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`
	var root syscall.Handle
	p, _ := syscall.UTF16PtrFromString(class)
	if syscall.RegOpenKeyEx(syscall.HKEY_LOCAL_MACHINE, p, 0, syscall.KEY_READ, &root) != nil {
		return "", 0
	}
	defer syscall.RegCloseKey(root)
	var best string
	var bestMem uint64
	for i := uint32(0); ; i++ {
		var name [256]uint16
		n := uint32(len(name))
		if syscall.RegEnumKeyEx(root, i, &name[0], &n, nil, nil, nil, nil) != nil {
			break
		}
		var k syscall.Handle
		if syscall.RegOpenKeyEx(root, &name[0], 0, syscall.KEY_READ, &k) != nil {
			continue
		}
		desc := regString(k, "DriverDesc")
		mem := regUint64(k, "HardwareInformation.qwMemorySize")
		syscall.RegCloseKey(k)
		if desc != "" && mem >= bestMem {
			best, bestMem = desc, mem
		}
	}
	return best, bestMem
}

func regString(k syscall.Handle, name string) string {
	n, _ := syscall.UTF16PtrFromString(name)
	var buf [512]uint16
	size := uint32(len(buf) * 2)
	if syscall.RegQueryValueEx(k, n, nil, nil, (*byte)(unsafe.Pointer(&buf[0])), &size) != nil {
		return ""
	}
	return syscall.UTF16ToString(buf[:])
}

func regUint64(k syscall.Handle, name string) uint64 {
	n, _ := syscall.UTF16PtrFromString(name)
	var v uint64
	size := uint32(8)
	if syscall.RegQueryValueEx(k, n, nil, nil, (*byte)(unsafe.Pointer(&v)), &size) != nil {
		return 0
	}
	return v
}

func readCPUName() string {
	var k syscall.Handle
	p, _ := syscall.UTF16PtrFromString(`HARDWARE\DESCRIPTION\System\CentralProcessor\0`)
	if syscall.RegOpenKeyEx(syscall.HKEY_LOCAL_MACHINE, p, 0, syscall.KEY_READ, &k) != nil {
		return ""
	}
	defer syscall.RegCloseKey(k)
	return strings.TrimSpace(regString(k, "ProcessorNameString"))
}
