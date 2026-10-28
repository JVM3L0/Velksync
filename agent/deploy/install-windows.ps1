# Execute como administrador:  powershell -ExecutionPolicy Bypass -File install-windows.ps1 [-Token <token do Linux>]
# O agente roda na sua sessão ao fazer logon (necessário para comandos que abrem janelas);
# o sinal de presença roda no boot, antes do login. Rode de novo após trocar o token mestre.
# O instalador (velksync-setup) chama este script com -TokenFile e -LogFile.
param([string]$Token = "", [string]$TokenFile = "", [string]$LogFile = "")
$ErrorActionPreference = "Stop"
if ($LogFile) { Start-Transcript -Path $LogFile -Force | Out-Null }

# O processo encerrado pode segurar o .exe por alguns segundos (e o antivírus
# também lê arquivos novos): tenta de novo antes de desistir.
function Copy-Retry([string]$from, [string]$to) {
    for ($i = 1; ; $i++) {
        try { Copy-Item $from $to -Force; return }
        catch [System.IO.IOException] {
            if ($i -ge 10) { throw }
            Start-Sleep -Seconds 1
        }
    }
}

$dir = Join-Path $env:LOCALAPPDATA "Velksync"
$exe = Join-Path $dir "velksync-agent.exe"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Get-ScheduledTask -TaskName "Velksync Agent" -ErrorAction SilentlyContinue | Stop-ScheduledTask
# Stop-ScheduledTask não espera o processo sair; sem isso o .exe continua em uso.
Get-Process velksync-agent -ErrorAction SilentlyContinue | Stop-Process -Force -PassThru | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
Copy-Retry (Join-Path $PSScriptRoot "velksync-agent.exe") $exe

$cfg = Join-Path $env:APPDATA "velksync\config.json"
if (-not (Test-Path $cfg)) {
    # Saída descartada: o init mostra o token, e ele não deve parar em log.
    if ($TokenFile) { $init = @("init", "-token-file", "`"$TokenFile`"") }
    elseif ($Token) { $init = @("init", "-token", $Token) }
    else { $init = @("init") }
    $p = Start-Process $exe -ArgumentList $init -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { throw "init falhou ($($p.ExitCode)); o token tem pelo menos 32 caracteres?" }
}

foreach ($r in @(@{n="Velksync TCP"; p="TCP"; port=41100}, @{n="Velksync UDP"; p="UDP"; port=41101})) {
    Remove-NetFirewallRule -DisplayName $r.n -ErrorAction SilentlyContinue
    # Só redes privadas e só a sub-rede local: nada de fora da sua LAN alcança o agente.
    New-NetFirewallRule -DisplayName $r.n -Direction Inbound -Protocol $r.p -LocalPort $r.port -Program $exe -Profile Private -RemoteAddress LocalSubnet -Action Allow | Out-Null
}

# Sinal de presença: sobe no boot, antes do login, com a conta restrita
# LocalService. Fica em Arquivos de Programas porque essa conta não lê a sua
# pasta de usuário, e só recebe o segredo de presença, nunca o token mestre.
$pdir = Join-Path $env:ProgramFiles "Velksync"
$pexe = Join-Path $pdir "velksync-agent.exe"
$pdata = Join-Path $env:ProgramData "Velksync"
$pfile = Join-Path $pdata "presence.json"
Get-ScheduledTask -TaskName "Velksync Presence" -ErrorAction SilentlyContinue | Stop-ScheduledTask
Get-Process velksync-agent -ErrorAction SilentlyContinue | Where-Object Path -eq $pexe | Stop-Process -Force -PassThru | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $pdir, $pdata | Out-Null
Copy-Retry (Join-Path $PSScriptRoot "velksync-agent.exe") $pexe
# Pasta do segredo: só SYSTEM e Administradores escrevem; LocalService só lê.
icacls $pdata /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-19:(OI)(CI)R" | Out-Null
# O .exe é GUI: sem -Wait o PowerShell não espera ele terminar.
$p = Start-Process $exe -ArgumentList "presence-export", "-out", "`"$pfile`"" -Wait -PassThru -WindowStyle Hidden
if ($p.ExitCode -ne 0) { throw "presence-export falhou ($($p.ExitCode))" }
icacls $pfile /reset | Out-Null
Remove-NetFirewallRule -DisplayName "Velksync Presence UDP" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Velksync Presence UDP" -Direction Inbound -Protocol UDP -LocalPort 41101 -Program $pexe -Profile Private -RemoteAddress LocalSubnet -Action Allow | Out-Null
# Nome da conta pelo SID: em português ela se chama "SERVIÇO LOCAL".
$localService = ([Security.Principal.SecurityIdentifier]"S-1-5-19").Translate([Security.Principal.NTAccount]).Value
$paction = New-ScheduledTaskAction -Execute $pexe -Argument "presence -file `"$pfile`""
$ptrigger = New-ScheduledTaskTrigger -AtStartup
$pprincipal = New-ScheduledTaskPrincipal -UserId $localService -LogonType ServiceAccount
$psettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Velksync Presence" -Action $paction -Trigger $ptrigger -Principal $pprincipal -Settings $psettings -Force | Out-Null
# Antes do agente: quem sobe primeiro fica com a porta de descoberta.
Start-ScheduledTask -TaskName "Velksync Presence"

$action = New-ScheduledTaskAction -Execute $exe
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName "Velksync Agent" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName "Velksync Agent"

Write-Host "Instalado em $exe"
Write-Host "Para parear um celular: & `"$exe`" pair"
Write-Host "Para conferir o Wake-on-LAN: & `"$exe`" doctor"
Write-Host "Token mestre, só para instalar no outro sistema do dual boot: & `"$exe`" token"
if ($LogFile) { Stop-Transcript | Out-Null }
