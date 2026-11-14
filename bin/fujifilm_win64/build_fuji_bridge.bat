@echo off
chcp 65001 >nul
echo ========================================================================
echo   🌸 LALE STUDIO - BIEN DICH FUJIFILM CAMERA BRIDGE (WIN 64-BIT)
echo ========================================================================
cd /d "%~dp0"

set CSC_PATH=
if exist "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" (
    set "CSC_PATH=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
) else if exist "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
    set "CSC_PATH=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) else (
    where csc >nul 2>&1
    if %errorlevel% equ 0 set "CSC_PATH=csc"
)

if "%CSC_PATH%"=="" (
    echo [LOI] Khong tim thay trinh bien dich csc.exe cua Microsoft .NET Framework!
    echo Vui long kiem tra Windows co ho tro .NET Framework 4.0 tro len.
    pause
    exit /b 1
)

echo [INFO] Dang su dung trinh bien dich: %CSC_PATH%
echo [INFO] Dang bien dich FujiBridge.cs -> fuji_bridge.exe (x64)...

"%CSC_PATH%" /target:exe /platform:x64 /optimize+ /out:fuji_bridge.exe FujiBridge.cs

if %errorlevel% equ 0 (
    echo.
    echo ========================================================================
    echo  [THANH CONG] Da tao thanh cong file: fuji_bridge.exe (64-bit)
    echo  Ban co the chay:
    echo    fuji_bridge.exe status
    echo    fuji_bridge.exe daemon 5514
    echo ========================================================================
) else (
    echo.
    echo [LOI] Bien dich that bai! Vui long kiem tra ma nguon FujiBridge.cs.
    pause
    exit /b %errorlevel%
)
