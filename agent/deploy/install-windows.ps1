# Execute como administrador:  powershell -ExecutionPolicy Bypass -File install-windows.ps1 [-Token <token do Linux>]
# O agente roda na sua sessão ao fazer logon (necessário para comandos que abrem janelas).
param([string]$Token = "")
$ErrorActionPreference = "Stop"
$dir = Join-Path $env:LOCALAPPDATA "Velksync"
$exe = Join-Path $dir "velksync-agent.exe"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Get-ScheduledTask -TaskName "Velksync Agent" -ErrorAction SilentlyContinue | Stop-ScheduledTask
# Stop-ScheduledTask não espera o processo sair; sem isso o .exe continua em uso.
Get-Process velksync-agent -ErrorAction SilentlyContinue | Stop-Process -Force -PassThru | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
Copy-Item (Join-Path $PSScriptRoot "velksync-agent.exe") $exe -Force

$cfg = Join-Path $env:APPDATA "velksync\config.json"
if (-not (Test-Path $cfg)) {
    if ($Token) { & $exe init -token $Token | Write-Host } else { & $exe init | Write-Host }
}

foreach ($r in @(@{n="Velksync TCP"; p="TCP"; port=41100}, @{n="Velksync UDP"; p="UDP"; port=41101})) {
    Remove-NetFirewallRule -DisplayName $r.n -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $r.n -Direction Inbound -Protocol $r.p -LocalPort $r.port -Program $exe -Profile Private -Action Allow | Out-Null
}

$action = New-ScheduledTaskAction -Execute $exe
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName "Velksync Agent" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName "Velksync Agent"

Write-Host "Instalado em $exe"
# Lido do arquivo: o .exe é GUI e o PowerShell nem sempre captura a saída dele.
Write-Host "Token: $((Get-Content $cfg -Raw | ConvertFrom-Json).token)"
Write-Host "Lembre: a rede do Windows precisa estar como 'Privada' e o Fast Startup desativado para o Wake-on-LAN."
