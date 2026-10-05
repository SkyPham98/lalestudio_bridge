# 🌸 LALÉ STUDIO - HARDWARE CAMERA BRIDGE
> Cầu nối phần cứng điều khiển Máy ảnh Canon EOS R50, Màn trập cơ học & Đèn Flash Studio cho phòng chụp Kiosk (`/room/[roomId]`).

---

## 📸 Tổng Quan Giải Pháp (Phương Án 2)

Hệ thống cho phép:
1. **Live View mượt mà (30fps)**: Khách đứng trước màn hình Kiosk soi gương và tạo dáng như bình thường.
2. **1 Nút bấm Remote duy nhất**: Khách bấm Remote Bluetooth -> Màn hình đếm ngược **3... 2... 1...**
3. **Màn trập cơ học nhảy thật**: Hết 3 giây, Bridge kích hoạt máy ảnh Canon qua USB.
4. **Đèn Flash Studio nổ chớp sáng**: Chân Hotshoe máy ảnh truyền tín hiệu tới Cục phát Trigger (Godox) -> Kích nổ đèn Flash Studio.
5. **Ảnh gốc 24.2 Megapixel (6000 x 4000)**: File ảnh chất lượng cao nhất lưu về máy tính và tải lên hệ thống Lalé Studio, in photostrip sắc nét chuẩn Studio chuyên nghiệp.

---

## 🛠 Hướng Dẫn Cài Đặt Trên Máy Tính Kiosk Phòng Chụp (Windows)

### Bước 1: Cài đặt phần mềm digiCamControl (Miễn phí 100%)
1. Tải và cài đặt phần mềm **digiCamControl**: [http://digicamcontrol.com/download](http://digicamcontrol.com/download)
2. Mở phần mềm digiCamControl:
   - Vào menu **File > Settings > Webserver**.
   - Tích chọn: **[x] Enable web server**.
   - Cổng mặc định: **5513**.
   - Thư mục lưu ảnh (Session Folder): Đặt là `C:\LalePhotos` (hoặc thư mục tùy chọn).
   - Bấm **Save** và khởi động lại digiCamControl.

### Bước 2: Kết nối Máy ảnh Canon EOS R50
1. Cắm cáp USB Type-C từ Canon R50 vào cổng USB 3.0 của máy tính.
2. Trên Menu máy ảnh Canon R50:
   - Tab Cài đặt (Icon cái cờ lê màu vàng) > **Choose USB connection app** > Chọn **Photo import/Remote control** (hoặc **PC connection**).
   - Xoay bánh xe chế độ chụp sang **M (Manual)** hoặc **Av/P**:
     - *Khẩu độ (Aperture)*: f/8.0 - f/11 (để chụp nhóm nhiều người không bị mờ hậu cảnh).
     - *Tốc độ (Shutter Speed)*: 1/160s hoặc 1/200s (tốc độ đồng bộ flash chuẩn của Canon).
     - *ISO*: 100 hoặc 200.
3. Gắn cục phát sóng Flash (**Godox X2T-C** hoặc **Godox Xpro-C**) lên chân Hotshoe trên đỉnh máy ảnh. Bật nguồn trigger và đèn flash studio cùng kênh (Channel) và nhóm (Group).

### Bước 3: Chạy Lalé Camera Bridge

Bạn có thể chọn **1 trong 2 cách** tùy theo máy tính của bạn:

- **Cách 1 (Khuyên dùng - KHÔNG CẦN CÀI ĐẶT NODE.JS)**:
  - Máy tính Windows 10/11 thông thường **không cần cài Node.js hay bất cứ thư viện nào**.
  - Nhấp đúp chuột vào file:
    ```cmd
    start_bridge_windows_native.bat
    ```
  - File sẽ tự động chạy trực tiếp bằng Windows PowerShell & .NET có sẵn trên mọi máy Windows, mở cổng `4000` ngay tức thì.

- **Cách 2 (Nếu máy đã có sẵn Node.js)**:
  - Nhấp đúp file:
    ```cmd
    start_bridge.bat
    ```

### Bước 4: Kích hoạt trên Giao diện Phòng Chụp
1. Mở trang Kiosk phòng chụp: `http://localhost:3000/room/1`
2. Bấm vào nút **Cấu hình máy ảnh** (góc trên bên phải hoặc màn hình chờ).
3. Tại mục **Cơ chế chụp ảnh**: Chọn **Máy ảnh Thật & Flash Studio (DSLR Bridge)**.
4. Bấm **Kiểm tra kết nối Bridge**: Hệ thống sẽ hiển thị trạng thái `Canon EOS R50 (Sẵn sàng chụp 24MP & Flash)`.
5. Bấm **Thử chụp có Flash**: Đèn flash sẽ chớp sáng và ảnh mẫu 24MP sẽ hiển thị ngay lập tức!

---

## ⚙️ Các Chế Độ Cấu Hình Trong `config.json`

File `config.json`:
```json
{
  "port": 4000,
  "mode": "digicamcontrol",
  "digicamcontrol": {
    "url": "http://127.0.0.1:5513",
    "timeoutMs": 12000,
    "photoSaveDir": "C:\\LalePhotos"
  },
  "hotfolder": {
    "enabled": false,
    "watchDir": "./captured_photos"
  },
  "mock": {
    "enabled": false
  }
}
```

- `"mode": "digicamcontrol"`: Kết nối tự động với digiCamControl qua HTTP API port 5513.
- `"mode": "hotfolder"`: Dùng cho Canon EOS Utility hoặc bất kỳ phần mềm tethering nào (tự động theo dõi thư mục ảnh mới).
- `"mode": "mock"`: Dùng để lập trình / kiểm thử offline khi không cắm máy ảnh thật.
