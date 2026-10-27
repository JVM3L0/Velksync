# Remove o Velksync do Windows. Execute como administrador:
#   powershell -ExecutionPolicy Bypass -File uninstall-windows.ps1 [-RemoveConfig]
# Sem -RemoveConfig, a configuração (token e celulares pareados) fica em
# %APPDATA%\velksync: reinstalar não exige parear de novo.
param([switch]$RemoveConfig, [string]$LogFile = "")
$ErrorActionPreference = "Stop"
if ($LogFile) { Start-Transcript -Path $LogFile -Force | Out-Null }

foreach ($t in "Velksync Agent", "Velksync Presence") {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $t
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
    }
}
# Stop-ScheduledTask não espera o processo sair; sem isso os arquivos continuam em uso.
Get-Process velksync-agent -ErrorAction SilentlyContinue | Stop-Process -Force -PassThru | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue

foreach ($r in "Velksync TCP", "Velksync UDP", "Velksync Presence UDP") {
    Remove-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue
}

# O segredo de presença sai sempre: sem a tarefa, ele não serve para nada.
$paths = @(
    (Join-Path $env:LOCALAPPDATA "Velksync"),
    (Join-Path $env:ProgramData "Velksync"),
    (Join-Path $env:ProgramFiles "Velksync\velksync-agent.exe")
)
if ($RemoveConfig) { $paths += Join-Path $env:APPDATA "velksync" }
foreach ($p in $paths) {
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}

if ($RemoveConfig) { Write-Host "Velksync removido, com a configuração." }
else { Write-Host "Velksync removido. A configuração ficou em $(Join-Path $env:APPDATA 'velksync')." }
if ($LogFile) { Stop-Transcript | Out-Null }
