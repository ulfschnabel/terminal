# Run this script as Administrator:
#   Right-click PowerShell -> Run as Administrator
#   cd C:\Users\Ulf\terminal
#   powershell -ExecutionPolicy Bypass -File .\install-workloads.ps1

Write-Host "Installing VS 2022 workloads from .vsconfig..." -ForegroundColor Cyan
Write-Host "This will take 10-20 minutes depending on internet speed." -ForegroundColor Yellow

$installer = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$installPath = "C:\Program Files\Microsoft Visual Studio\2022\Community"
$config = "C:\Users\Ulf\terminal\.vsconfig"

& $installer modify `
    --installPath $installPath `
    --config $config `
    --passive `
    --norestart

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nWorkloads installed successfully!" -ForegroundColor Green
} else {
    Write-Host "`nInstaller exited with code $LASTEXITCODE" -ForegroundColor Red
}
