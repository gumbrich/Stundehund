# Run from PowerShell on a Windows x64 build machine with Flutter 3.41.5,
# Visual Studio (Desktop development with C++) and the Windows SDK installed.
[CmdletBinding()]
param([switch]$SkipChecks)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    if (-not [System.Environment]::Is64BitOperatingSystem -or $env:OS -ne 'Windows_NT') {
        throw 'Build this application on 64-bit Windows.'
    }
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Install Flutter 3.41.5 and add its bin directory to PATH first.'
    }
    flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    if (-not $SkipChecks) {
        dart format --output=none --set-exit-if-changed lib test
        if ($LASTEXITCODE -ne 0) { throw 'Formatting check failed.' }
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
        flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows compilation failed.' }

    $bundle = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw 'Visual Studio Installer (vswhere.exe) was not found.' }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Install the Visual Studio C++ desktop workload.' }
    $crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $crt) { throw 'Visual C++ redistributable runtime was not found.' }
    Copy-Item "$($crt.FullName)\*.dll" $bundle
    Copy-Item 'docs\WINDOWS-START.txt' (Join-Path $bundle 'LIESMICH.txt')
    $archive = Join-Path $projectRoot 'Stundehund-Windows-x64.zip'
    Compress-Archive -Path "$bundle\*" -DestinationPath $archive -Force
    Write-Host "Windows application packaged: $archive"
} finally {
    Pop-Location
}
