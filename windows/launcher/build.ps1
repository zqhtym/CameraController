# Builds the three launcher exes into the windows\ folder using the C# compiler of .NET Framework 4.x
# (present on every Windows 10/11). Usage: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$outDir = Split-Path -Parent $here
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "csc.exe not found: $csc" }

$targets = @(
    @{ Define = 'SETUP';     Name = 'CameraController-Setup.exe' },
    @{ Define = 'START';     Name = 'CameraController-Start.exe' },
    @{ Define = 'UNINSTALL'; Name = 'CameraController-Uninstall.exe' }
)
foreach ($t in $targets) {
    $out = Join-Path $outDir $t.Name
    & $csc /nologo /target:exe /platform:anycpu /optimize+ /codepage:65001 "/define:$($t.Define)" "/win32manifest:$(Join-Path $here 'admin.manifest')" "/out:$out" (Join-Path $here 'Launcher.cs')
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $($t.Name)" }
    Write-Host "Built $out"
}
