#!/bin/bash
echo "========================================================================"
echo " 🌸 LALÉ PHOTO STUDIO - HARDWARE CAMERA BRIDGE (AUTO-RECONNECT)"
echo " Điều khiển máy ảnh Canon EOS R50, Màn trập & Đèn Flash Studio"
echo "========================================================================"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

if [ ! -d "node_modules" ]; then
    echo "[INFO] Đang cài đặt thư viện bridge lần đầu..."
    npm install
fi

while true; do
    echo "[INFO] Đang khởi động Local Camera Bridge trên cổng 4000..."
    node server.js
    echo ""
    echo "========================================================================"
    echo "[CẢNH BÁO] Bridge đã dừng hoặc ngắt kết nối!"
    echo "Tự động kết nối lại từ đầu sau 3 giây..."
    echo "(Nhấn Ctrl+C để thoát hoàn toàn)"
    echo "========================================================================"
    sleep 3
done
