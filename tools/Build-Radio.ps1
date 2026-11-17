[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Prepare-Devourer.ps1')
if ($LASTEXITCODE -ne 0) { throw 'prepare devourer failed' }
function Find-CMake {
    if ($env:CMAKE_EXE -and (Test-Path $env:CMAKE_EXE)) { return $env:CMAKE_EXE }
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        'D:\VSBuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'CMake not found. Set CMAKE_EXE or install the VS 2022 CMake component.'
}
$cmake = Find-CMake
$vcpkg = Join-Path $root 'build\deps\vcpkg'

# VS 2022 is still what the docs test against, but CI images move: GitHub's
# windows-latest no longer ships VS 17, so a hard-coded generator fails with
# "could not find any instance of Visual Studio". Force 17 only when vswhere
# actually reports a 17.x install; otherwise let CMake pick the newest VS.
function Get-GeneratorArgs {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $version = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationVersion 2>$null
        if ($version -and $version.Trim().StartsWith('17.')) {
            return @('-G', 'Visual Studio 17 2022')
        }
        if ($version) {
            Write-Host "Visual Studio $($version.Trim()) found; using CMake's default generator"
        }
    } else {
        Write-Warning 'vswhere not found; using CMake default generator'
    }
    return @()
}

$generatorArgs = Get-GeneratorArgs
& $cmake -S (Join-Path $root 'src\radio_usb') -B (Join-Path $root 'build\radio_usb') `
    @generatorArgs -A x64 `
    "-DCMAKE_TOOLCHAIN_FILE=$vcpkg\scripts\buildsystems\vcpkg.cmake" `
    "-DPKG_CONFIG_EXECUTABLE=$vcpkg\installed\x64-windows\tools\pkgconf\pkgconf.exe" `
    '-DPKG_CONFIG_ARGN=--msvc-syntax'
if ($LASTEXITCODE -ne 0) { throw 'radio configure failed' }
& $cmake --build (Join-Path $root 'build\radio_usb') --config Release --parallel 8 `
    --target airbridge_radio radio_pipe_bridge peer_telemetry_test channel_completion_test
if ($LASTEXITCODE -ne 0) { throw 'radio build failed' }
& (Join-Path (Split-Path $cmake) 'ctest.exe') --test-dir (Join-Path $root 'build\radio_usb') `
    -C Release -R '^(peer_telemetry|channel_completion)$' --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'radio offline regression failed' }
