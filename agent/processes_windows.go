package main

import (
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

// readProcesses lista os processos com tempo de CPU e memória. Os que o
// usuário não pode consultar (do sistema, protegidos) entram só pelo nome.
func readProcesses() ([]procSample, error) {
	snap, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return nil, err
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
	return out, nil
}
