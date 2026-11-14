@echo off
title Lale Photo Studio - Camera Bridge (Native Windows - Canon R50 & Fujifilm X-T4)
color 0b
echo ========================================================================
echo  LALE PHOTO STUDIO - NATIVE HARDWARE CAMERA BRIDGE
echo  Dieu khien may anh Canon EOS R50 & FUJIFILM X-T4, Man trap va Den Flash Studio
echo  (Phien ban Native Windows - KHONG CAN CAI DAT NODEJS HOAC BAT CU THU VIEN NAO)
echo ========================================================================
echo.

cd /d "%~dp0"

:loop
echo [INFO] Dang khoi dong Native Bridge tren cong 4000...
echo [INFO] Ho tro tu dong nhan dien Canon EOS R50 hoac FUJIFILM X-T4!
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge_windows.ps1"

echo.
echo ========================================================================
echo [CANH BAO] Native Bridge da bi thoat hoac dung dot ngot!
echo Dang tu dong khoi dong va ket noi lai tu dau sau 3 giay...
echo (Neu muon thoat hoan toan, hay dong cua so hoac bam Ctrl + C)
echo ========================================================================
timeout /t 3 /nobreak >nul
goto loop
