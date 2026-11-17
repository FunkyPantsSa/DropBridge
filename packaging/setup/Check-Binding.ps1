# One-time setup check for DropBridge: is the Wi-Fi interface of the
# RTL8811CU / RTL8821CU bound to WinUSB? Read-only: this script changes
# nothing and needs no admin.
#
#   exit 0  already bound (nothing to do)
#   exit 1  present, but still on the Realtek driver (binding needed)
#   exit 3  the card is not plugged in
param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
$c811All = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like 'USB\VID_0BDA&PID_C811*' })
$c811 = @($c811All | Where-Object { $_.InstanceId -match '&MI_' }) | Select-Object -First 1
if (-not $c811) { $c811 = $c811All | Select-Object -First 1 }
$c820 = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like 'USB\VID_0BDA&PID_C820&MI_02\*' }) | Select-Object -First 1

if ($c811) {
    $device = $c811
    $label = 'RTL8811CU Wi-Fi (whole device)'
} elseif ($c820) {
    $device = $c820
    $label = 'RTL8821CU Wi-Fi (MI_02)'
} else {
    if (-not $Quiet) {
        Write-Host 'NOT PRESENT: no RTL8811CU (0bda:c811) or RTL8821CU (0bda:c820) is plugged in.'
        Write-Host 'Plug it into a rear USB port and run this again.'
    }
    exit 3
}

$service = (Get-PnpDeviceProperty -InstanceId $device.InstanceId `
        -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data

if ($service -eq 'WinUSB') {
    if (-not $Quiet) {
        Write-Host ('OK: ' + $label + ' is bound to WinUSB.') -ForegroundColor Green
        Write-Host ('    ' + $device.InstanceId)
    }
    exit 0
}

if (-not $Quiet) {
    Write-Host ('NOT YET: ' + $label + ' is using ' + $service + ', so libusb cannot open it.') -ForegroundColor Yellow
    Write-Host 'Run setup\Bind-WinUSB.cmd to bind it to WinUSB (one time per machine).'
}
exit 1
