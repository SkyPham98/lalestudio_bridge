# ========================================================================
# 🌸 LALÉ PHOTO STUDIO - NATIVE WINDOWS CAMERA BRIDGE (AUTO-DISCOVERY)
# Chạy trực tiếp trên Windows 10/11 - KHÔNG CẦN CÀI ĐẶT NODE.JS!
# Tự động phát hiện IP của digiCamControl (192.168.1.x / 127.0.0.1)
# ========================================================================

param (
    [int]$Port = 4000,
    [string]$DccUrl = "",
    [string]$PhotoDir = "C:\LalePhotos"
)

# Đọc cấu hình từ config.json nếu có
$configPath = Join-Path $PSScriptRoot "config.json"
if (Test-Path $configPath) {
    try {
        $rawConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        if (-not $DccUrl -and $rawConfig.digicamcontrol.url) {
            $DccUrl = $rawConfig.digicamcontrol.url
        }
        if ($rawConfig.digicamcontrol.photoSaveDir) {
            $PhotoDir = $rawConfig.digicamcontrol.photoSaveDir
        }
    } catch {}
}

# Đảm bảo thư mục lưu ảnh tồn tại
if (-not (Test-Path -Path $PhotoDir)) {
    try {
        New-Item -ItemType Directory -Path $PhotoDir -Force | Out-Null
    } catch {
        $PhotoDir = Join-Path $PSScriptRoot "captured_photos"
        New-Item -ItemType Directory -Path $PhotoDir -Force | Out-Null
    }
}

# Các thư mục ảnh tiềm năng để theo dõi
$potentialPhotoDirs = [System.Collections.Generic.List[string]]::new()
$potentialPhotoDirs.Add($PhotoDir)
$defaultDccPicDir = Join-Path ([Environment]::GetFolderPath('MyPictures')) "digiCamControl"
if (Test-Path $defaultDccPicDir) { $potentialPhotoDirs.Add($defaultDccPicDir) }
$localCapturedDir = Join-Path $PSScriptRoot "captured_photos"
if (Test-Path $localCapturedDir) { $potentialPhotoDirs.Add($localCapturedDir) }

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " 🌸 LALE PHOTO STUDIO - NATIVE HARDWARE CAMERA BRIDGE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " [INFO] Cong Bridge Kiosk: http://127.0.0.1:$Port" -ForegroundColor Yellow
Write-Host " [INFO] Thu muc luu anh:   $PhotoDir" -ForegroundColor Yellow

# Hàm tự động dò tìm IP của digiCamControl
function Find-DigiCamControlUrl {
    param ([string]$ManualUrl)

    $urlsToTest = [System.Collections.Generic.List[string]]::new()
    if ($ManualUrl -and $ManualUrl.Trim().Length -gt 0) { 
        $urlsToTest.Add($ManualUrl.Trim().TrimEnd('/')) 
    }

    # 1. Thêm các IP mạng nội bộ của máy (ví dụ: 192.168.1.172, ...)
    try {
        $hostName = [System.Net.Dns]::GetHostName()
        $ips = [System.Net.Dns]::GetHostAddresses($hostName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
        foreach ($ip in $ips) {
            $ipStr = $ip.ToString()
            if ($ipStr -ne "127.0.0.1") {
                $urlsToTest.Add("http://${ipStr}:5513")
            }
        }
    } catch {}

    # 2. Thêm localhost & 127.0.0.1
    $urlsToTest.Add("http://127.0.0.1:5513")
    $urlsToTest.Add("http://localhost:5513")

    $uniqueUrls = $urlsToTest | Select-Object -Unique

    foreach ($testUrl in $uniqueUrls) {
        try {
            $check = Invoke-RestMethod -Uri "$testUrl/?CMD=Get_Current_Value&Param=cameraname" -TimeoutSec 1 -ErrorAction Stop
            if ($check -ne $null) {
                return @{
                    url = $testUrl
                    cameraName = $check.ToString().Trim()
                    connected = $true
                }
            }
        } catch {}
    }

    # Thử kiểm tra cổng TCP 5513 (phòng trường hợp web server mở nhưng chưa bật camera)
    foreach ($testUrl in $uniqueUrls) {
        try {
            $uri = [System.Uri]$testUrl
            $tcp = New-Object System.Net.Sockets.TcpClient
            $async = $tcp.BeginConnect($uri.Host, $uri.Port, $null, $null)
            $wait = $async.AsyncWaitHandle.WaitOne(400, $false)
            if ($wait -and $tcp.Connected) {
                $tcp.Close()
                return @{
                    url = $testUrl
                    cameraName = "Chưa kết nối máy ảnh"
                    connected = $false
                }
            }
            $tcp.Close()
        } catch {}
    }

    # Mặc định fallback
    if ($ManualUrl) { return @{ url = $ManualUrl; cameraName = "Chưa nhận diện"; connected = $false } }
    return @{ url = "http://127.0.0.1:5513"; cameraName = "Chưa nhận diện"; connected = $false }
}

# Dò tìm URL digiCamControl ban đầu
$activeDcc = Find-DigiCamControlUrl -ManualUrl $DccUrl
$DccUrl = $activeDcc.url

if ($activeDcc.connected) {
    Write-Host " [OK] DA TIM THAY DIGICAMCONTROL TAI: $DccUrl" -ForegroundColor Green
    Write-Host " [CAMERA] May anh ket noi: $($activeDcc.cameraName)" -ForegroundColor Green
} else {
    Write-Host " [THONG BAO] Dang su dung dia chi digiCamControl: $DccUrl" -ForegroundColor Cyan
    Write-Host " [LUU Y] Neu chua mo digiCamControl, hay mo app tren may tinh!" -ForegroundColor Yellow
}

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " [SAN SANG] Dang cho lenh chup tu Kiosk phong chup..." -ForegroundColor White

# Khởi tạo HTTP Listener trên cổng 4000
$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "[LOI] Khong the mo cong $Port. Co the mot chuong trinh khac dang chiem cong nay." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Exit
}

function Send-JsonResponse($response, $statusCode, $jsonObj) {
    $jsonString = $jsonObj | ConvertTo-Json -Depth 5 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonString)
    
    $response.StatusCode = $statusCode
    $response.ContentType = "application/json; charset=utf-8"
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization")
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}

function Handle-OptionsRequest($response) {
    $response.StatusCode = 204
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization")
    $response.OutputStream.Close()
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $rawUrl = $request.RawUrl
        $method = $request.HttpMethod

        # Xử lý CORS Preflight
        if ($method -eq "OPTIONS") {
            Handle-OptionsRequest -response $response
            continue
        }

        # 1. API STATUS: /api/status
        if ($rawUrl -match "^/api/status") {
            # Tự động kiểm tra lại URL digiCamControl
            $checkDcc = Find-DigiCamControlUrl -ManualUrl $DccUrl
            $DccUrl = $checkDcc.url

            $statusData = @{
                success = $true
                bridgeOnline = $true
                version = "2.1.0-AutoDiscovery"
                mode = "native-windows"
                camera = @{
                    connected = $checkDcc.connected
                    name = $checkDcc.cameraName
                    source = "digiCamControl ($DccUrl)"
                }
                dccUrl = $DccUrl
                watchDirectory = $PhotoDir
            }
            Send-JsonResponse -response $response -statusCode 200 -jsonObj $statusData
            continue
        }

        # 2. API CAPTURE: /api/capture
        if ($rawUrl -match "^/api/capture" -and $method -eq "POST") {
            Write-Host "`n[CHUP ANH] Nhan lenh tu Kiosk phong chup! Dang kich hoat co may anh & Flash..." -ForegroundColor Cyan

            # Đọc orderCode
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()

            $orderCode = "LALE"
            if ($body) {
                try {
                    $jsonBody = $body | ConvertFrom-Json
                    if ($jsonBody.orderCode) { $orderCode = $jsonBody.orderCode }
                } catch {}
            }

            $beforeCaptureTime = (Get-Date).AddSeconds(-1)
            $triggerSuccess = $false

            # Đảm bảo DccUrl chuẩn trước khi chụp
            $probe = Find-DigiCamControlUrl -ManualUrl $DccUrl
            $DccUrl = $probe.url

            Write-Host "[DCC] Dang goi lenh Shutter toi: $DccUrl/?CMD=Capture" -ForegroundColor White

            try {
                $triggerRes = Invoke-RestMethod -Uri "$DccUrl/?CMD=Capture" -TimeoutSec 6 -ErrorAction Stop
                $triggerSuccess = $true
                Write-Host "[OK] Da phat lenh Shutter! Man trap co hoc da nhay va Flash Studio da no." -ForegroundColor Green
            } catch {
                Write-Host "[CANH BAO] Khong the ket noi toi $DccUrl ($($_.Exception.Message))" -ForegroundColor Yellow
                # Thử lại 1 lần nữa với IP quét tự động
                $reProbe = Find-DigiCamControlUrl
                $DccUrl = $reProbe.url
                try {
                    $triggerRes = Invoke-RestMethod -Uri "$DccUrl/?CMD=Capture" -TimeoutSec 6 -ErrorAction Stop
                    $triggerSuccess = $true
                    Write-Host "[OK] Da phat lenh Shutter sau khi tu dong chuyen sang: $DccUrl" -ForegroundColor Green
                } catch {
                    Write-Host "[LOI] Thu lai van that bai voi $DccUrl" -ForegroundColor Red
                }
            }

            # Chờ đợi file ảnh mới xuất hiện trong các thư mục tiềm năng
            $foundFile = $null
            $timeoutSeconds = 8
            $waited = 0

            Write-Host "Dang cho may anh truyen file anh 24MP ve may tinh..." -NoNewline
            while ($waited -lt ($timeoutSeconds * 4)) {
                Start-Sleep -Milliseconds 250
                $waited++

                foreach ($dir in $potentialPhotoDirs) {
                    if (Test-Path $dir) {
                        $latest = Get-ChildItem -Path $dir -Include *.jpg,*.jpeg,*.png -File -Recurse -ErrorAction SilentlyContinue | 
                                  Where-Object { $_.LastWriteTime -ge $beforeCaptureTime } | 
                                  Sort-Object LastWriteTime -Descending | 
                                  Select-Object -First 1

                        if ($latest) {
                            Start-Sleep -Milliseconds 300
                            $foundFile = $latest.FullName
                            break
                        }
                    }
                }

                if ($foundFile) { break }
                Write-Host "." -NoNewline
            }
            Write-Host ""

            # Cách 1: Đọc file ảnh từ ổ đĩa nếu tìm thấy
            if ($foundFile -and (Test-Path $foundFile)) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($foundFile)
                    $base64 = [Convert]::ToBase64String($bytes)
                    $dataUrl = "data:image/jpeg;base64,$base64"
                    $sizeMb = [Math]::Round(($bytes.Length / 1MB), 2)
                    $fileName = [System.IO.Path]::GetFileName($foundFile)

                    Write-Host "[THANH CONG] Da nhan anh goc 24MP tu o dia: $fileName ($sizeMb MB)" -ForegroundColor Green

                    $result = @{
                        success = $true
                        source = "Canon EOS R50 Native (Disk File)"
                        filename = $fileName
                        imageData = $dataUrl
                        fileSizeBytes = $bytes.Length
                        fileSizeMb = "$sizeMb MB"
                        resolution = "6000x4000 (24.2 MP)"
                    }
                    Send-JsonResponse -response $response -statusCode 200 -jsonObj $result
                    continue
                } catch {
                    Write-Host "[LOI] Khong doc duoc file anh tu o dia: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            # Cách 2: Dự phòng tải ảnh trực tiếp từ Web Server của digiCamControl (/preview.jpg)
            Write-Host "[FALLBACK] Dang thu tai anh truc tiep tu digiCamControl Webserver ($DccUrl/preview.jpg)..." -ForegroundColor Cyan
            try {
                $wc = New-Object System.Net.WebClient
                $previewBytes = $wc.DownloadData("$DccUrl/preview.jpg")
                if ($previewBytes -and $previewBytes.Length -gt 1000) {
                    $base64 = [Convert]::ToBase64String($previewBytes)
                    $dataUrl = "data:image/jpeg;base64,$base64"
                    $sizeMb = [Math]::Round(($previewBytes.Length / 1MB), 2)
                    $fileName = "${orderCode}_$((Get-Date).Ticks)_original.jpg"

                    Write-Host "[THANH CONG] Da nhan anh goc qua Web Preview: $fileName ($sizeMb MB)" -ForegroundColor Green

                    $result = @{
                        success = $true
                        source = "Canon EOS R50 Native (Web Preview)"
                        filename = $fileName
                        imageData = $dataUrl
                        fileSizeBytes = $previewBytes.Length
                        fileSizeMb = "$sizeMb MB"
                        resolution = "Full-Res JPEG"
                    }
                    Send-JsonResponse -response $response -statusCode 200 -jsonObj $result
                    continue
                }
            } catch {
                Write-Host "[FALLBACK] Khong the lay anh tu preview.jpg: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # Fallback nếu cả 2 cách đều chưa có file
            Write-Host "[THONG BAO] Khong tim thay file anh moi, tra ve thong bao de Kiosk tu dong chup du phong bang Webcam." -ForegroundColor Yellow
            $errResult = @{
                success = $false
                message = "Khong nhan duoc file anh tu may anh trong 8 giay"
            }
            Send-JsonResponse -response $response -statusCode 500 -jsonObj $errResult
            continue
        }

        # 3. API LIVEVIEW START: /api/liveview/start
        if ($rawUrl -match "^/api/liveview/start") {
            try {
                Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveViewWnd_Show" -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
                Write-Host "[LIVEVIEW] Da gui lenh bat Live View toi digiCamControl ($DccUrl)" -ForegroundColor Green
                Send-JsonResponse -response $response -statusCode 200 -jsonObj @{ success = $true; message = "Live View started" }
            } catch {
                Send-JsonResponse -response $response -statusCode 500 -jsonObj @{ success = $false; error = $_.Exception.Message }
            }
            continue
        }

        # 4. API LIVEVIEW FRAME: /api/liveview
        if ($rawUrl -match "^/api/liveview") {
            try {
                $wc = New-Object System.Net.WebClient
                $lvBytes = $wc.DownloadData("$DccUrl/liveview.jpg")
                $response.StatusCode = 200
                $response.ContentType = "image/jpeg"
                $response.Headers.Add("Access-Control-Allow-Origin", "*")
                $response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
                $response.ContentLength64 = $lvBytes.Length
                $response.OutputStream.Write($lvBytes, 0, $lvBytes.Length)
                $response.OutputStream.Close()
            } catch {
                $response.StatusCode = 502
                $response.OutputStream.Close()
            }
            continue
        }

        # 5. API LIVEVIEW STREAM: /api/liveview/stream
        if ($rawUrl -match "^/api/liveview/stream") {
            try {
                $response.StatusCode = 302
                $response.Headers.Add("Location", "$DccUrl/mjpeg")
                $response.Headers.Add("Access-Control-Allow-Origin", "*")
                $response.OutputStream.Close()
            } catch {
                $response.StatusCode = 502
                $response.OutputStream.Close()
            }
            continue
        }

        # Route khác
        Send-JsonResponse -response $response -statusCode 404 -jsonObj @{ error = "Not found" }
    }
} finally {
    $listener.Stop()
}
