# Auxiliar de mídia do velksync-agent no Windows. Embutido no binário e
# executado oculto; conversa por stdin/stdout, uma requisição JSON por linha.
# Usa os controles de mídia do sistema (SMTC, o painel de mídia do Windows) e
# o volume do dispositivo de saída padrão (Core Audio).
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]

$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

function Await($op, [Type]$type) {
    $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    if (-not $task.Wait(5000)) { throw 'tempo esgotado' }
    $task.Result
}

$Manager = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$Props = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
$mgr = Await ($Manager::RequestAsync()) $Manager

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
// [ComImport] e [PreserveSig] são obrigatórios: sem eles o .NET monta a chamada
// COM de outro jeito e o SetMasterVolumeLevelScalar "dava certo" sem mudar nada.
namespace Velksync {
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr p);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr p);
        [PreserveSig] int GetChannelCount(out int n);
        [PreserveSig] int SetMasterVolumeLevel(float level, ref Guid ctx);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
        [PreserveSig] int GetMasterVolumeLevel(out float level);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint ch, float level, ref Guid ctx);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint ch, float level, ref Guid ctx);
        [PreserveSig] int GetChannelVolumeLevel(uint ch, out float level);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint ch, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumerator { }

    public static class Audio {
        static IAudioEndpointVolume Endpoint() {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            IMMDevice device;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0 /* render */, 1 /* multimedia */, out device));
            var iid = typeof(IAudioEndpointVolume).GUID;
            object o;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out o));
            return (IAudioEndpointVolume)o;
        }
        public static float GetVolume() { float v; Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out v)); return v; }
        public static bool GetMute() { bool m; Marshal.ThrowExceptionForHR(Endpoint().GetMute(out m)); return m; }
        public static void SetVolume(float v) { var g = Guid.Empty; Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(v, ref g)); }
        public static void SetMute(bool m) { var g = Guid.Empty; Marshal.ThrowExceptionForHR(Endpoint().SetMute(m, ref g)); }
    }
}
'@

function Volume {
    try { @{ volume = [Math]::Round([double][Velksync.Audio]::GetVolume(), 3); muted = [Velksync.Audio]::GetMute() } }
    catch { @{ volume = $null; muted = $null } }
}

function Session {
    $s = $mgr.GetCurrentSession()
    if (-not $s) { throw 'nada tocando no PC' }
    $s
}

function State {
    $v = Volume
    $s = $mgr.GetCurrentSession()
    if (-not $s) { return @{ available = $false; status = 'stopped'; volume = $v.volume; muted = $v.muted } }
    $p = Await ($s.TryGetMediaPropertiesAsync()) $Props
    $info = $s.GetPlaybackInfo()
    $tl = $s.GetTimelineProperties()
    $status = switch ([int]$info.PlaybackStatus) { 4 { 'playing' } 5 { 'paused' } default { 'stopped' } }
    $dur = [Math]::Max(0.0, ($tl.EndTime - $tl.StartTime).TotalMilliseconds)
    $pos = $tl.Position.TotalMilliseconds
    # A posição vale para LastUpdatedTime; tocando, soma o tempo desde então.
    if ($status -eq 'playing') { $pos += ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalMilliseconds }
    if ($dur -gt 0) { $pos = [Math]::Min($pos, $dur) }
    $artId = ''
    if ($p.Thumbnail) { $artId = ('{0:x8}' -f ("$($p.Title)|$($p.Artist)|$($p.AlbumTitle)").GetHashCode()) }
    @{
        available   = $true
        player      = $s.SourceAppUserModelId
        status      = $status
        title       = $p.Title
        artist      = $p.Artist
        album       = $p.AlbumTitle
        position_ms = [int64][Math]::Max(0.0, $pos)
        duration_ms = [int64]$dur
        can_seek    = [bool]$info.Controls.IsPlaybackPositionEnabled
        can_control = [bool]$info.Controls.IsPlayPauseToggleEnabled
        art_id      = $artId
        volume      = $v.volume
        muted       = $v.muted
    }
}

function Art {
    $p = Await ((Session).TryGetMediaPropertiesAsync()) $Props
    if (-not $p.Thumbnail) { throw 'sem capa' }
    $stream = Await ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
    # O PowerShell não enxerga os membros do stream WinRT (__ComObject); por
    # reflexão na interface .NET o runtime faz o QueryInterface sozinho.
    $size = [Windows.Storage.Streams.IRandomAccessStream].GetProperty('Size').GetValue($stream)
    if ($size -gt 5MB) { throw 'capa grande demais' }
    $ctor = [Windows.Storage.Streams.DataReader].GetConstructor([Type[]]@([Windows.Storage.Streams.IInputStream]))
    $reader = $ctor.Invoke(@($stream))
    $n = Await ($reader.LoadAsync([uint32]$size)) ([uint32])
    $bytes = New-Object byte[] $n
    $reader.ReadBytes($bytes)
    @{ data = [Convert]::ToBase64String($bytes) }
}

function Command([string]$action) {
    $s = Session
    $op = switch ($action) {
        'play_pause' { $s.TryTogglePlayPauseAsync() }
        'next' { $s.TrySkipNextAsync() }
        'previous' { $s.TrySkipPreviousAsync() }
        default { throw 'ação inválida' }
    }
    if (-not (Await $op ([bool]))) { throw 'o player recusou o comando' }
    @{ ok = $true }
}

function Seek([int64]$ms) {
    if ($ms -lt 0) { throw 'posição inválida' }
    $s = Session
    if (-not (Await ($s.TryChangePlaybackPositionAsync($ms * 10000)) ([bool]))) { throw 'o player não permite mudar a posição' }
    @{ ok = $true }
}

function SetVolume($req) {
    # 1.0/0.0, não 1/0: com o inteiro o PowerShell escolhe Math.Min(int, int) e
    # arredonda o volume (0.98 virava 1, 0.4 virava 0).
    if ($null -ne $req.volume) { [Velksync.Audio]::SetVolume([float][Math]::Min(1.0, [Math]::Max(0.0, [double]$req.volume))) }
    if ($null -ne $req.muted) { [Velksync.Audio]::SetMute([bool]$req.muted) }
    @{ ok = $true }
}

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    try {
        $req = $line | ConvertFrom-Json
        $res = switch ($req.cmd) {
            'state' { State }
            'art' { Art }
            'command' { Command $req.action }
            'seek' { Seek $req.position_ms }
            'volume' { SetVolume $req }
            default { throw 'comando desconhecido' }
        }
    }
    catch { $res = @{ error = $_.Exception.Message } }
    [Console]::Out.WriteLine(($res | ConvertTo-Json -Compress -Depth 3))
    [Console]::Out.Flush()
}
