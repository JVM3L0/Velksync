# Teste do instalador no CI (máquina Windows descartável): instala sem
# interface, confere tudo, atualiza por cima, desinstala e confere que não
# sobrou nada além da configuração. Não rode no seu PC.
param([Parameter(Mandatory)][string]$Setup)
$ErrorActionPreference = "Stop"
$appId = "{141A2B8E-A02E-46C9-A895-40AD37BF0BD0}_is1"
$uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$appId"
$config = Join-Path $env:APPDATA "velksync\config.json"

function Check([bool]$ok, [string]$what) {
    if (-not $ok) { throw "falhou: $what" }
    Write-Host "ok: $what"
}
function Count-Tasks { @(Get-ScheduledTask -TaskName "Velksync*" -ErrorAction SilentlyContinue).Count }
function Count-Rules { @(Get-NetFirewallRule -DisplayName "Velksync*" -ErrorAction SilentlyContinue).Count }
function Install([string]$log) {
    $p = Start-Process $Setup -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG=`"$log`"" -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Get-Content $log -Tail 40
        Get-Content (Join-Path $env:TEMP "velksync-install.log") -ErrorAction SilentlyContinue
        throw "instalador saiu com $($p.ExitCode)"
    }
}

$log1 = Join-Path $env:TEMP "velksync-setup-1.log"
Install $log1
Check ((Count-Tasks) -eq 2) "duas tarefas agendadas"
Check ((Count-Rules) -eq 3) "três regras de firewall"
Check (Test-Path (Join-Path $env:ProgramFiles "Velksync\velksync-agent.exe")) "sinal de presença em Arquivos de Programas (64 bits)"
Check (Test-Path (Join-Path $env:ProgramFiles "Velksync\uninstall-windows.ps1")) "desinstalador junto"
Check (Test-Path (Join-Path $env:LOCALAPPDATA "Velksync\velksync-agent.exe")) "agente na pasta do usuário"
Check (Test-Path (Join-Path $env:ProgramData "Velksync\presence.json")) "segredo de presença"
Check (Test-Path $config) "configuração criada"
Check ((Get-ItemProperty $uninstallKey).DisplayName -eq "Velksync") "aparece em Aplicativos"
$token = (Get-Content $config -Raw | ConvertFrom-Json).token
Check (-not (Select-String -Path $log1 -SimpleMatch $token -Quiet)) "token fora do log"

$log2 = Join-Path $env:TEMP "velksync-setup-2.log"
Install $log2
Check ((Get-Content $config -Raw | ConvertFrom-Json).token -eq $token) "atualização mantém o token"
Check ((Count-Tasks) -eq 2 -and (Count-Rules) -eq 3) "atualização não duplica tarefas nem regras"

$uninstaller = (Get-ItemProperty $uninstallKey).UninstallString.Trim('"')
Start-Process $uninstaller -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES" -Wait
# O desinstalador se copia para a pasta temporária e roda de lá; ele sai de
# Aplicativos antes de apagar o próprio unins000.exe.
$appDir = Join-Path $env:ProgramFiles "Velksync"
for ($i = 0; $i -lt 60 -and ((Test-Path $uninstallKey) -or (Test-Path $appDir)); $i++) { Start-Sleep 1 }
if (Test-Path $appDir) { Get-ChildItem $appDir -Recurse -Force | Select-Object FullName, Length | Format-Table -AutoSize | Out-Host }
Check (-not (Test-Path $uninstallKey)) "saiu de Aplicativos"
Check ((Count-Tasks) -eq 0) "nenhuma tarefa"
Check ((Count-Rules) -eq 0) "nenhuma regra de firewall"
Check (-not (Test-Path $appDir)) "Arquivos de Programas limpo"
Check (-not (Test-Path (Join-Path $env:ProgramData "Velksync"))) "segredo de presença apagado"
Check (-not (Test-Path (Join-Path $env:LOCALAPPDATA "Velksync"))) "pasta do agente apagada"
Check (-not (Get-Process velksync-agent -ErrorAction SilentlyContinue)) "nenhum agente rodando"
Check (Test-Path $config) "configuração mantida (padrão do modo silencioso)"
