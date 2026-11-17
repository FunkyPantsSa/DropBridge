# Read-only check of how the target adapter's Wi-Fi interface is bound.
# Writes nothing. Exit codes: 0 = bound to WinUSB, 1 = still vendor/other driver,
# 2 = target interface not present.
#
# Supported hardware:
#   RTL8811CU  0bda:c811  single-function, the whole device is the Wi-Fi interface
#   RTL8821CU  0bda:c820  composite, the Wi-Fi function is MI_02
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-DeviceProperty {
    param([string]$InstanceId, [string]$Key)
    return (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $Key -ErrorAction SilentlyContinue).Data
}

$c811All = @(Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -like 'USB\VID_0BDA&PID_C811*' })
# On a single-function 8811CU the node has no &MI_. If a board ever exposes a
# composite device, prefer a function node over the composite parent.
$c811 = @($c811All | Where-Object { $_.InstanceId -notmatch '&MI_' }) | Select-Object -First 1
if (-not $c811) { $c811 = $c811All | Select-Object -First 1 }

$c820 = @(Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -like 'USB\VID_0BDA&PID_C820&MI_02*' }) | Select-Object -First 1

if ($c811) {
    $target = $c811
    $label = 'RTL8811CU Wi-Fi (whole device)'
} elseif ($c820) {
    $target = $c820
    $label = 'RTL8821CU Wi-Fi (MI_02)'
} else {
    Write-Output 'MISSING: no RTL8811CU (0bda:c811) or RTL8821CU (0bda:c820, MI_02) is present.'
    Write-Output 'Plug the adapter into a direct USB port and re-run; check tools/Inspect-Hardware.ps1.'
    exit 2
}

$inf = Get-DeviceProperty -InstanceId $target.InstanceId -Key 'DEVPKEY_Device_DriverInfPath'
$service = Get-DeviceProperty -InstanceId $target.InstanceId -Key 'DEVPKEY_Device_Service'
$version = Get-DeviceProperty -InstanceId $target.InstanceId -Key 'DEVPKEY_Device_DriverVersion'
$provider = Get-DeviceProperty -InstanceId $target.InstanceId -Key 'DEVPKEY_Device_DriverProvider'
$problem = Get-DeviceProperty -InstanceId $target.InstanceId -Key 'DEVPKEY_Device_ProblemCode'

$isWinUsb = ($service -match '^(WinUSB|libusbK|libusb0)$') -or ($inf -match 'winusb')

Write-Output ''
Write-Output ("Target Wi-Fi interface: {0}" -f $label)
Write-Output ("  instance   : {0}" -f $target.InstanceId)
Write-Output ("  status     : {0}  (problem code {1})" -f $target.Status, $problem)
Write-Output ("  driver inf : {0}" -f $inf)
Write-Output ("  driver     : {0} {1}" -f $provider, $version)
Write-Output ("  service    : {0}" -f $service)
Write-Output ''
if ($c820) {
    $bt = @(Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -like 'USB\VID_0BDA&PID_C820&MI_00*' }) | Select-Object -First 1
    Write-Output 'Bluetooth interface (RTL8821CU MI_00, must stay untouched)'
    if ($bt) {
        Write-Output ("  status     : {0}" -f $bt.Status)
    } else {
        Write-Output '  not present (adapter may be unplugged or BT disabled)'
    }
} else {
    Write-Output 'Bluetooth: not applicable (RTL8811CU has no Bluetooth;'
    Write-Output '           the AirDrop beacon uses the PC''s own BLE adapter)'
}
Write-Output ''

$net = @(Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -match '8811CU|8821CU|RTL8811|RTL8821' })
if ($net.Count -gt 0) {
    Write-Output 'Realtek network adapter(s):'
    $net | Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize
} else {
    Write-Output 'No Realtek 8811CU/8821CU network adapter (expected once WinUSB owns the Wi-Fi interface).'
}
Write-Output ''

if ($isWinUsb) {
    Write-Output 'RESULT: the Wi-Fi interface is bound to WinUSB. libusb should be able to claim it.'
    Write-Output 'Next: run the read-only USB open probe. Do NOT run Init yet.'
    exit 0
}

Write-Output 'RESULT: the Wi-Fi interface is still bound to a non-WinUSB driver.'
Write-Output 'Follow docs/BINDING_RUNBOOK.md to bind it, then re-run this check.'
exit 1
