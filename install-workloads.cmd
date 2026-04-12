@echo off
echo Installing VS 2022 C++ and UWP workloads...
echo This takes 10-20 minutes. A progress window will appear.
echo.

"C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify ^
  --installPath "C:\Program Files\Microsoft Visual Studio\2022\Community" ^
  --add Microsoft.VisualStudio.Workload.NativeDesktop ^
  --add Microsoft.VisualStudio.Workload.Universal ^
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
  --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 ^
  --add Microsoft.VisualStudio.Component.VC.Tools.ARM64EC ^
  --add Microsoft.VisualStudio.Component.VC.Tools.ARM ^
  --add Microsoft.VisualStudio.Component.Windows11SDK.22621 ^
  --add Microsoft.VisualStudio.ComponentGroup.MSIX.Packaging ^
  --add Microsoft.VisualStudio.ComponentGroup.UWP.VC ^
  --add Microsoft.VisualStudio.Component.UWP.VC.ARM64 ^
  --add Microsoft.VisualStudio.Component.UWP.VC.ARM64EC ^
  --add Microsoft.Component.NetFX.Native ^
  --add Microsoft.VisualStudio.ComponentGroup.UWP.Support ^
  --add Microsoft.VisualStudio.ComponentGroup.UWP.NetCoreAndStandard ^
  --add Microsoft.VisualStudio.Component.Vcpkg ^
  --includeRecommended ^
  --passive ^
  --norestart ^
  --wait

echo.
echo Exit code: %ERRORLEVEL%
if %ERRORLEVEL% EQU 0 (
    echo SUCCESS
) else (
    echo FAILED - code %ERRORLEVEL%
)
pause
