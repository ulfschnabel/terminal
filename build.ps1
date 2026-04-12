# Build Windows Terminal from source
# Run from a regular (non-admin) PowerShell:
#   cd C:\Users\Ulf\terminal
#   .\build.ps1

param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64"
)

Write-Host "Building Windows Terminal ($Configuration|$Platform)..." -ForegroundColor Cyan

Import-Module .\tools\OpenConsole.psm1

Set-MsbuildDevEnvironment

$msbuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe'
$root = Get-Location

& $root\dep\nuget\nuget.exe restore "$root\OpenConsole.slnx" 2>$null

& $msbuild "$root\OpenConsole.slnx" /p:Configuration=$Configuration /p:Platform=$Platform /m /nologo /v:minimal

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild succeeded!" -ForegroundColor Green
    Write-Host "Binaries: bin\$Platform\$Configuration\" -ForegroundColor Yellow
    Write-Host "To deploy dev package (if not already deployed):" -ForegroundColor Yellow
    Write-Host "  src\cascadia\CascadiaPackage\AppPackages\*_Test\Add-AppDevPackage.ps1" -ForegroundColor Yellow
} else {
    Write-Host "`nBuild failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
