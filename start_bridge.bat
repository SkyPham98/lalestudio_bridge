@echo off
title Lale Studio - Hardware Camera Bridge (Canon R50 + Flash)
color 0b
echo ========================================================================
echo  LALE PHOTO STUDIO - HARDWARE CAMERA BRIDGE
echo  Dieu khien may anh Canon EOS R50, Man trap co hoc va Den Flash Studio
echo ========================================================================
echo.

cd /d "%~dp0"

if not exist node_modules (
    echo [INFO] Dang cai dat thu vien bridge lan dau...
    call npm install
)

echo [INFO] Dang khoi dong Local Camera Bridge tren cong 4000...
echo [INFO] Vui long dam bao da mo phan mem digiCamControl tren may tinh!
echo.

node server.js

pause
