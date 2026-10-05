@echo off
title Lale Photo Studio - Camera Bridge (Native Windows - No Node.js)
color 0b
echo ========================================================================
echo  LALE PHOTO STUDIO - NATIVE HARDWARE CAMERA BRIDGE
echo  Dieu khien may anh Canon EOS R50, Man trap co hoc va Den Flash Studio
echo  (Phien ban Native Windows - KHONG CAN CAI DAT NODEJS HOAC BAT CU THU VIEN NAO)
echo ========================================================================
echo.

cd /d "%~dp0"

echo [INFO] Dang khoi dong Native Bridge tren cong 4000...
echo [INFO] Vui long dam bao da mo phan mem digiCamControl tren may tinh!
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge_windows.ps1"

pause
