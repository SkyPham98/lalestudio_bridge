@echo off
title Lale Studio - Fujifilm SDK Daemon (Port 5514)
color 0a
echo ========================================================================
echo  LALE STUDIO - FUJIFILM CAMERA CONTROL DAEMON (PORT 5514)
echo  Ket noi truc tiep may anh FUJIFILM X-T4 qua USB Tether
echo ========================================================================
echo.

cd /d "%~dp0bin\fujifilm_win64"

if not exist fuji_bridge.exe (
    echo [INFO] Chua co fuji_bridge.exe. Dang tien hanh bien dich tu dong...
    call build_fuji_bridge.bat
)

:loop
echo [INFO] Dang khoi dong Fujifilm Bridge Daemon tren cong 5514...
fuji_bridge.exe daemon 5514

echo.
echo [CANH BAO] Daemon bi dong! Tu dong khoi dong lai sau 2 giay...
timeout /t 2 /nobreak >nul
goto loop
