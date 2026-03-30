# Build Windows Terminal from source
# Run from a regular (non-admin) PowerShell:
#   cd C:\Users\Ulf\terminal
#   .\build.ps1

Write-Host "Building Windows Terminal..." -ForegroundColor Cyan

# Import the build module
Import-Module .\tools\OpenConsole.psm1

# Set up the VS build environment
Set-MsBuildDevEnvironment

# Build (Release x64)
Invoke-OpenConsoleBuild

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild succeeded!" -ForegroundColor Green
    Write-Host "To deploy: right-click CascadiaPackage in VS Solution Explorer -> Deploy" -ForegroundColor Yellow
} else {
    Write-Host "`nBuild failed with code $LASTEXITCODE" -ForegroundColor Red
}
