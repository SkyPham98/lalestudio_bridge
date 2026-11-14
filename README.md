# 🌸 LALÉ STUDIO - HARDWARE CAMERA BRIDGE (DUAL CAMERA: CANON & FUJIFILM)
> Cầu nối phần cứng điều khiển Máy ảnh **Canon EOS R50** (24.2 MP) và **FUJIFILM X-T4** (26.1 MP), kích nổ Màn trập cơ học & Đèn Flash Studio cho phòng chụp Kiosk (`/room/[roomId]`).

---

## 📸 Tổng Quan Hệ Thống

Hệ thống Lalé Camera Bridge hỗ trợ song song 2 dòng máy ảnh hàng đầu cho photobooth chuyên nghiệp:
1. **Canon EOS R50** (Cảm biến APS-C 24.2 Megapixel 6000 x 4000) qua digiCamControl & IPC Direct.
2. **FUJIFILM X-T4** (Cảm biến X-Trans CMOS 4 26.1 Megapixel 6240 x 4160) qua Fujifilm Camera Control SDK chính hãng (Windows 64-bit Native).

Cả hai dòng máy đều đáp ứng đầy đủ tiêu chuẩn Studio:
- **Live View mượt mà**: 1080p 60fps qua HDMI Capture Card (hoặc USB stream) để khách soi gương tạo dáng.
- **Tự động lấy nét (Autofocus Lock)**: Dual Pixel AF (Canon) hoặc Phase/Contrast AF (Fujifilm) khóa nét vào khuôn mặt/mắt khách trước khi chụp.
- **Màn trập cơ học nhảy thật**: Kéo cò cơ học bảo toàn dải tương phản (Dynamic Range) và màu sắc gốc.
- **Kích nổ Flash Studio đồng bộ 100%**: Qua chân Hotshoe đỉnh máy ảnh kết nối Cục phát Trigger không dây (Godox).
- **Tải ảnh gốc siêu nét tức thì**: Ảnh gốc nguyên bản (24.2MP hoặc 26.1MP) lưu thẳng về PC phòng chụp (`C:\LalePhotos`), đẩy lên hệ thống để khách in photostrip sắc nét.

---

## ⚙️ Cơ Chế Tự Động Nhận Diện Máy Ảnh ("mode": "auto")

Trong file `config.json`, chế độ mặc định được thiết lập là `"mode": "auto"`:
- **Khi phòng chụp dùng Canon EOS R50**: Bridge tự động kết nối qua digiCamControl (port 5513 / IPC Named Pipe). Vận hành 100% như cũ, không thay đổi bất kỳ thao tác nào!
- **Khi phòng chụp chuyển sang FUJIFILM X-T4**: Bridge tự động chuyển sang driver Fujifilm SDK (64-bit native), kết nối trực tiếp với camera qua cổng USB Tether.
- Nếu muốn cố định 1 dòng máy, bạn có thể chỉnh `"mode": "digicamcontrol"` hoặc `"mode": "fujifilm"`.

---

## 🛠 Hướng Dẫn Cài Đặt Chi Tiết Cho Từng Dòng Máy

---

### A. Đối Với Máy Ảnh FUJIFILM X-T4 (Windows 64-bit)

#### 1. Cài đặt trên thân máy ảnh FUJIFILM X-T4:
1. **Chế độ kết nối PC**:
   - Bấm nút `MENU/OK` -> biểu tượng Cờ lê (`SET UP`) -> `CONNECTION SETTING`.
   - Chọn `PC CONNECTION MODE` -> chọn **`USB TETHER SHOOTING AUTO`**.
2. **Chế độ lấy nét**:
   - Gạt cần lấy nét ở mặt trước máy sang vị trí **`S`** (Single AF) hoặc **`C`** (Continuous AF).
3. **Cài đặt thông số chụp studio (Manual Mode)**:
   - Xoay bánh xe chế độ hoặc vòng tốc độ/khẩu độ sang `M`:
     - *Khẩu độ (Aperture)*: f/8.0 – f/11 (để chụp nhóm khách nét đều từ trước ra sau).
     - *Tốc độ (Shutter Speed)*: 1/160s hoặc 1/180s (tốc độ ăn đèn flash chuẩn của X-T4).
     - *ISO*: 160 (ISO gốc của X-T4) hoặc 200.
4. **Xuất hình sạch Clean HDMI ra màn hình soi gương (Capture Card)**:
   - Menu Cài đặt Phim (`MOVIE SETTING`) -> `HDMI OUTPUT INFO DISPLAY` -> chọn **`OFF`** (tắt toàn bộ icon để màn hình Kiosk sạch đẹp như gương).
5. **Đèn Flash Studio**:
   - Gắn cục phát trigger **Godox X2T-F** hoặc **Godox XPro-F** (phiên bản dành riêng cho Fujifilm, chân đế chuẩn Fuji) lên khe Hotshoe trên đỉnh máy.

#### 2. Cấu trúc bộ SDK Fujifilm trên máy tính phòng chụp:
SDK đã được tích hợp sẵn đầy đủ trong thư mục `bin/fujifilm_win64/`:
- `XAPI.dll`, `FTLPTP.dll`, `FTLPTPIP.dll`: Thư viện lõi SDK 64-bit.
- `FF0014API.dll`: Thư viện điều khiển dòng máy FUJIFILM X-T4.
- `XSDK.DAT`: File cấu hình nhận diện thiết bị của hãng.
- `FujiBridge.cs`: Mã nguồn C# giao tiếp P/Invoke với XAPI.dll.
- `build_fuji_bridge.bat`: File biên dịch tự động ra `fuji_bridge.exe` bằng trình biên dịch `csc.exe` có sẵn trong Windows (không cần cài thêm bất cứ gì).

#### 3. Khởi chạy:
- Chạy Bridge chính: Nhấp đúp chuột vào `start_bridge.bat` hoặc `start_bridge_windows_native.bat`.
- *(Tùy chọn)* Nếu muốn chạy riêng Daemon kết nối liên tục với Fujifilm: Nhấp đúp vào `start_fuji_daemon.bat` (chạy trên port 5514).

---

### B. Đối Với Máy Ảnh Canon EOS R50 (Giữ Nguyên Như Cũ 100%)

#### 1. Cài đặt phần mềm digiCamControl:
1. Mở phần mềm **digiCamControl**:
   - Vào menu **File > Settings > Webserver**.
   - Tích chọn: **[x] Enable web server**.
   - Cổng mặc định: **5513**.
   - Tích chọn: **[x] Allow interaction via webserver**.
   - Thư mục lưu ảnh: `C:\LalePhotos`.

#### 2. Kết nối máy ảnh Canon EOS R50:
1. Cắm cáp USB Type-C từ Canon R50 vào cổng USB 3.0 của máy tính.
2. Menu máy ảnh Canon: Tab Cài đặt (cờ lê vàng) > **Choose USB connection app** > Chọn **Photo import/Remote control**.
3. Bánh xe chế độ: **M (Manual)**:
   - Khẩu độ: f/8.0 – f/11.
   - Tốc độ: 1/160s hoặc 1/200s.
   - ISO: 100 hoặc 200.
4. Gắn trigger **Godox X2T-C** hoặc **Godox XPro-C** (phiên bản Canon) lên khe Hotshoe.

---

## 🚀 Các File Khởi Động Nhanh (Windows)

| Tên File | Công Dụng |
| :--- | :--- |
| **`start_bridge.bat`** | Khởi chạy Bridge đa luồng (Node.js) hỗ trợ tự động cả Canon và Fujifilm. |
| **`start_bridge_windows_native.bat`** | Bản Native PowerShell chạy trực tiếp trên Windows mà **không cần cài Node.js**. |
| **`start_fuji_daemon.bat`** | Khởi chạy tiến trình nền Fujifilm SDK Daemon (port 5514) duy trì kết nối USB liên tục. |
| **`bin/fujifilm_win64/build_fuji_bridge.bat`** | Biên dịch `FujiBridge.cs` thành `fuji_bridge.exe` 64-bit độc lập. |

---

## 🌐 Danh Sách API Của Bridge (Port 4000)

| Endpoint | Method | Chức Năng |
| :--- | :--- | :--- |
| `/api/status` | `GET` | Kiểm tra trạng thái máy ảnh hiện tại, trả về camera name (`FUJIFILM X-T4` hoặc `Canon EOS R50`), trạng thái kết nối và driver đang hoạt động. |
| `/api/focus` | `ALL` | Kích hoạt lấy nét tự động (Dual Pixel AF cho Canon hoặc Contrast/Phase AF cho Fujifilm). |
| `/api/capture` | `POST` | Kích nổ màn trập cơ học, kích nổ đèn Flash Studio, tải file ảnh gốc (26.1MP hoặc 24.2MP) lưu vào ổ đĩa và trả về dữ liệu Base64 cho Kiosk. |
| `/api/liveview/stream` | `GET` | Luồng ảnh Liveview MJPEG từ cảm biến máy ảnh (chế độ USB Live View). |
