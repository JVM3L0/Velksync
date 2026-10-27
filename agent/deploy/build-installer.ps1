# Compila o instalador (velksync-setup-<versão>-windows-amd64.exe) com o Inno Setup 6.
#   powershell -ExecutionPolicy Bypass -File build-installer.ps1 -Version 0.5.0 -AgentExe ..\dist\windows\velksync-agent.exe [-OutDir ..\..\out]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$AgentExe,
    [string]$OutDir = (Join-Path $PSScriptRoot "..\..\out")
)
$ErrorActionPreference = "Stop"
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Versão inválida: $Version (use 0.5.0, sem o v)" }

$iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    # Instalado para todos ou só para o usuário (o winget faz assim).
    $iscc = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) { throw "Inno Setup 6 não encontrado (https://jrsoftware.org/isdl.php)" }

$exe = (Resolve-Path $AgentExe).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& $iscc /Q "/DAppVersion=$Version" "/DAgentExe=$exe" "/O$((Resolve-Path $OutDir).Path)" (Join-Path $PSScriptRoot "velksync.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC falhou ($LASTEXITCODE)" }
Get-ChildItem $OutDir -Filter "velksync-setup-$Version-*.exe"
