# ========================================================================
# 🌸 LALÉ PHOTO STUDIO - NATIVE WINDOWS CAMERA BRIDGE
# Chạy trực tiếp trên Windows 10/11 - KHÔNG CẦN CÀI ĐẶT NODE.JS HOẶC BẤT KỲ GÌ!
# Sử dụng trực tiếp .NET Framework có sẵn trong Windows để mở cổng HTTP 4000
# ========================================================================

param (
    [int]$Port = 4000,
    [string]$DccUrl = "http://127.0.0.1:5513",
    [string]$PhotoDir = "C:\LalePhotos"
)

# Đảm bảo thư mục lưu ảnh tồn tại
if (-not (Test-Path -Path $PhotoDir)) {
    try {
        New-Item -ItemType Directory -Path $PhotoDir -Force | Out-Null
        Write-Host "[OK] Da tao thu muc anh: $PhotoDir" -ForegroundColor Green
    } catch {
        $PhotoDir = Join-Path $PSScriptRoot "captured_photos"
        New-Item -ItemType Directory -Path $PhotoDir -Force | Out-Null
    }
}

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " 🌸 LALE PHOTO STUDIO - NATIVE HARDWARE CAMERA BRIDGE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " [INFO] Cong Bridge: http://127.0.0.1:$Port" -ForegroundColor Yellow
Write-Host " [INFO] digiCamControl Port: $DccUrl" -ForegroundColor Yellow
Write-Host " [INFO] Thu muc luu anh: $PhotoDir" -ForegroundColor Yellow
Write-Host " [INFO] KHONG CAN CAI NODEJS! Chay truc tiep bang Windows PowerShell." -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " Dang cho lenh chup tu man hinh Kiosk phong chup (Space / Remote)..." -ForegroundColor White

# Khởi tạo HTTP Listener
$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "[SAN SANG] Bridge dang lang nghe tren $prefix" -ForegroundColor Green
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

        # Xu ly CORS Preflight
        if ($method -eq "OPTIONS") {
            Handle-OptionsRequest -response $response
            continue
        }

        # 1. API STATUS: /api/status
        if ($rawUrl -match "^/api/status") {
            $cameraOnline = $false
            $cameraName = "Chua ket noi may anh"

            try {
                $dccCheck = Invoke-RestMethod -Uri "$DccUrl/?CMD=Get_Current_Value&Param=cameraname" -TimeoutSec 2 -ErrorAction Stop
                if ($dccCheck -and -not ($dccCheck -match "Error|No camera")) {
                    $cameraOnline = $true
                    $cameraName = $dccCheck.Trim()
                }
            } catch {
                # DCC chua mo
            }

            $statusData = @{
                success = $true
                bridgeOnline = $true
                version = "2.0.0-NativeWindows"
                mode = "native-powershell"
                camera = @{
                    connected = $cameraOnline
                    name = $cameraName
                    source = "digiCamControl (Port 5513)"
                }
                watchDirectory = $PhotoDir
            }
            Send-JsonResponse -response $response -statusCode 200 -jsonObj $statusData
            continue
        }

        # 2. API CAPTURE: /api/capture
        if ($rawUrl -match "^/api/capture" -and $method -eq "POST") {
            Write-Host "`n[CHUP ANH] Nhan lenh tu Kiosk phong chup! Dang kich hoat co may anh & Flash..." -ForegroundColor Cyan

            # Doc body (neu co)
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

            # Kich hoat shutter qua digiCamControl
            try {
                $triggerRes = Invoke-RestMethod -Uri "$DccUrl/?CMD=Capture" -TimeoutSec 5 -ErrorAction Stop
                $triggerSuccess = $true
                Write-Host "[OK] Da phat lenh Shutter! Man trap da nhay va Flash da no." -ForegroundColor Green
            } catch {
                Write-Host "[CANH BAO] Khong the ket noi digiCamControl tai $DccUrl ($($_.Exception.Message))" -ForegroundColor Yellow
            }

            # Cho doi file anh moi xuat hien trong thu muc
            $foundFile = $null
            $timeoutSeconds = 10
            $waited = 0

            Write-Host "Dang cho may anh truyen file anh 24MP ve may tinh..." -NoNewline
            while ($waited -lt ($timeoutSeconds * 4)) {
                Start-Sleep -Milliseconds 250
                $waited++

                if (Test-Path $PhotoDir) {
                    $latest = Get-ChildItem -Path $PhotoDir -Include *.jpg,*.jpeg,*.png -File -Recurse | 
                              Where-Object { $_.LastWriteTime -ge $beforeCaptureTime } | 
                              Sort-Object LastWriteTime -Descending | 
                              Select-Object -First 1

                    if ($latest) {
                        # Cho them 300ms de file duoc ghi xong hoan toan
                        Start-Sleep -Milliseconds 300
                        $foundFile = $latest.FullName
                        break
                    }
                }
                Write-Host "." -NoNewline
            }
            Write-Host ""

            # Doc file anh va chuyen sang base64
            if ($foundFile -and (Test-Path $foundFile)) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($foundFile)
                    $base64 = [Convert]::ToBase64String($bytes)
                    $dataUrl = "data:image/jpeg;base64,$base64"
                    $sizeMb = [Math]::Round(($bytes.Length / 1MB), 2)
                    $fileName = [System.IO.Path]::GetFileName($foundFile)

                    Write-Host "[THANH CONG] Da nhan anh goc 24MP: $fileName ($sizeMb MB)" -ForegroundColor Green

                    $result = @{
                        success = $true
                        source = "Canon EOS R50 Native"
                        filename = $fileName
                        imageData = $dataUrl
                        fileSizeBytes = $bytes.Length
                        fileSizeMb = "$sizeMb MB"
                        resolution = "6000x4000 (24.2 MP)"
                    }
                    Send-JsonResponse -response $response -statusCode 200 -jsonObj $result
                    continue
                } catch {
                    Write-Host "[LOI] Khong doc duoc file anh: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            # Fallback neu chua nhan duoc file anh (tranh treo Kiosk)
            Write-Host "[THONG BAO] Khong tim thay file anh moi, tra ve thong bao de Kiosk fallback sang Webcam." -ForegroundColor Yellow
            $errResult = @{
                success = $false
                message = "Khong nhan duoc file anh tu may anh trong 10 giay"
            }
            Send-JsonResponse -response $response -statusCode 500 -jsonObj $errResult
            continue
        }

        # Route khac
        Send-JsonResponse -response $response -statusCode 404 -jsonObj @{ error = "Not found" }
    }
} finally {
    $listener.Stop()
}
