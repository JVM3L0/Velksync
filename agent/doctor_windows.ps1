# Lê (e, se pedido, corrige) o que o Wake-on-LAN precisa na placa da rede
# local. O agente define $ip e $fix antes deste script e lê o JSON da saída.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ifIndex = (Get-NetIPAddress -IPAddress $ip).InterfaceIndex
$a = Get-NetAdapter -InterfaceIndex $ifIndex
$powerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
$errors = @()

function Try-Fix([string]$name, [scriptblock]$action) {
    if ($fix -notcontains $name) { return }
    try { & $action } catch { $script:errors += "${name}: $($_.Exception.Message)" }
}

# -NoRestart: sem derrubar a rede agora; o driver aplica no próximo desligamento.
Try-Fix 'magic' {
    if (Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*WakeOnMagicPacket' -ErrorAction SilentlyContinue) {
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*WakeOnMagicPacket' -RegistryValue 1 -NoRestart
    }
    Set-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Enabled -NoRestart
}
Try-Fix 'wake' {
    powercfg /deviceenablewake "$($a.InterfaceDescription)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /deviceenablewake falhou ($LASTEXITCODE)" }
}
Try-Fix 'faststartup' { Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value 0 -Type DWord }
Try-Fix 'private' { Set-NetConnectionProfile -InterfaceIndex $ifIndex -NetworkCategory Private }

$adv = Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*WakeOnMagicPacket' -ErrorAction SilentlyContinue
$pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
$armed = @(powercfg /devicequery wake_armed) | ForEach-Object { "$_".Trim() }
$netProfile = Get-NetConnectionProfile -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
$hiberboot = (Get-ItemProperty -Path $powerKey -ErrorAction SilentlyContinue).HiberbootEnabled
$hibernate = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue).HibernateEnabled

[ordered]@{
    adapter     = $a.Name
    description = $a.InterfaceDescription
    media       = "$($a.PhysicalMediaType)"
    magic       = if ($adv) { "$($adv.RegistryValue)" } else { '' }
    pm_magic    = if ($pm) { "$($pm.WakeOnMagicPacket)" } else { '' }
    wake_armed  = $armed -contains $a.InterfaceDescription
    hiberboot   = $hiberboot
    hibernate   = $hibernate
    network     = if ($netProfile) { $netProfile.Name } else { '' }
    category    = if ($netProfile) { "$($netProfile.NetworkCategory)" } else { '' }
    fix_errors  = $errors
} | ConvertTo-Json -Compress
