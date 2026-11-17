# Add the RTL8811CU (0bda:c811) hardware ID to the WinUSB INF, then rebuild and
# re-sign the driver catalog. Windows-only: makecat/signtool come from the
# Windows SDK, so this is the one packaging step that cannot run on macOS.
#
#   powershell -ExecutionPolicy Bypass -File tools\Enable-8811CU-Driver.ps1
#   powershell -ExecutionPolicy Bypass -File tools\Enable-8811CU-Driver.ps1 -NewCert
#
# -NewCert asks Build-DriverPackage.ps1 to create a fresh self-signed cert (use
# it when the original private key is not in CurrentUser\My; the installer
# imports whatever .cer ships next to the INF).
#
# This assumes the usual single-function 8811CU (whole device, no &MI_). If the
# board enumerates as composite, inspect it first and use its Wi-Fi MI_xx in the
# added model line instead.
#
# After it succeeds:
#   pnputil /add-driver packaging\driver\airbridge-winusb.inf /install
#   tools\Check-Binding.ps1
# then commit packaging\driver\airbridge-winusb.inf, .cat and .cer together.
[CmdletBinding()]
param(
    [switch]$NewCert
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$inf = Join-Path $root 'packaging\driver\airbridge-winusb.inf'
if (-not (Test-Path -LiteralPath $inf)) { throw "missing INF: $inf" }

$text = Get-Content -LiteralPath $inf -Raw
# Keep the INF LF-only regardless of how this checkout was made; the catalog
# hashes the exact bytes and .gitattributes stores this file as -text.
$text = $text -replace "`r`n", "`n"
if ($text -match 'PID_C811') {
    Write-Host 'INF already lists RTL8811CU; rebuilding the catalog only.'
} else {
    if ($text -notmatch '(?m)^%DEVICE% = Install, USB\\VID_0BDA&PID_C820&MI_02\s*$') {
        throw 'unexpected INF layout: C820 model line not found'
    }
    $text = [regex]::Replace(
        $text,
        '(?m)^(%DEVICE% = Install, USB\\VID_0BDA&PID_C820&MI_02)\s*$',
        "`$1`n%DEVICE8811% = Install, USB\VID_0BDA&PID_C811")

    if ($text -notmatch '(?m)^DEVICE\s*=') {
        throw 'unexpected INF layout: [Strings] DEVICE not found'
    }
    $text = [regex]::Replace(
        $text,
        '(?m)^(DEVICE\s*=\s*".*")\s*$',
        "`$1`nDEVICE8811 = `"DropBridge AWDL radio (RTL8811CU Wi-Fi interface)`"")

    # The INF is stored LF-only (.gitattributes: -text, the catalog hashes the
    # exact bytes), so keep LF rather than PowerShell's default CRLF.
    Set-Content -LiteralPath $inf -Value $text -Encoding ascii -NoNewline
    Write-Host "added RTL8811CU hardware ID to $inf"
}

$build = Join-Path $PSScriptRoot 'Build-DriverPackage.ps1'
if ($NewCert) {
    & $build -Force
} else {
    & $build
}

Write-Host ''
Write-Host 'Driver package rebuilt. Next: install it on a test machine, run'
Write-Host 'tools\Check-Binding.ps1, then commit INF + .cat + .cer together.'
