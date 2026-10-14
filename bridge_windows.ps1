# ========================================================================
# 🌸 LALÉ PHOTO STUDIO - NATIVE WINDOWS CAMERA BRIDGE (AUTO-RECONNECT)
# Chạy trực tiếp trên Windows 10/11 - KHÔNG CẦN CÀI ĐẶT NODE.JS!
# Tự động phát hiện IP của digiCamControl, tự động kết nối lại từ đầu khi mất kết nối
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
Write-Host " 🌸 LALE PHOTO STUDIO - NATIVE HARDWARE CAMERA BRIDGE (AUTO-RECONNECT)" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " [INFO] Cong Bridge Kiosk: http://127.0.0.1:$Port" -ForegroundColor Yellow
Write-Host " [INFO] Thu muc luu anh:   $PhotoDir" -ForegroundColor Yellow

[System.Net.WebRequest]::DefaultWebProxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()

# Hàm tìm kiếm tiện ích CameraControlRemoteCmd.exe (IPC Direct)
function Get-DccRemoteCmdPath {
    # 1. Tìm từ tiến trình CameraControl đang chạy trong Windows
    try {
        $cimProc = Get-CimInstance Win32_Process -Filter "Name = 'CameraControl.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cimProc -and $cimProc.ExecutablePath) {
            $dir = [System.IO.Path]::GetDirectoryName($cimProc.ExecutablePath)
            $exe = Join-Path $dir "CameraControlRemoteCmd.exe"
            if (Test-Path $exe) { return $exe }
        }
    } catch {}

    try {
        $proc = Get-Process -Name "CameraControl" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path) {
            $dir = [System.IO.Path]::GetDirectoryName($proc.Path)
            $exe = Join-Path $dir "CameraControlRemoteCmd.exe"
            if (Test-Path $exe) { return $exe }
        }
    } catch {}

    # 2. Tìm qua các đường dẫn cài đặt tiêu chuẩn
    $candidates = @(
        "C:\Program Files (x86)\digiCamControl\CameraControlRemoteCmd.exe",
        "C:\Program Files\digiCamControl\CameraControlRemoteCmd.exe",
        "D:\Program Files (x86)\digiCamControl\CameraControlRemoteCmd.exe",
        "D:\Program Files\digiCamControl\CameraControlRemoteCmd.exe",
        "C:\digiCamControl\CameraControlRemoteCmd.exe",
        "D:\digiCamControl\CameraControlRemoteCmd.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) { return $cand }
    }

    # 3. Tìm qua Registry
    try {
        $regPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\CameraControl.exe" -ErrorAction SilentlyContinue)."(default)"
        if ($regPath) {
            $dir = [System.IO.Path]::GetDirectoryName($regPath)
            $exe = Join-Path $dir "CameraControlRemoteCmd.exe"
            if (Test-Path $exe) { return $exe }
        }
    } catch {}

    return $null
}

$global:RemoteCmdExe = Get-DccRemoteCmdPath
if ($global:RemoteCmdExe) {
    Write-Host " [OK] TIM THAY TIEN ICH CHUP TRUC TIEP: $global:RemoteCmdExe" -ForegroundColor Green
} else {
    Write-Host " [CHU Y] Chua phat hien CameraControlRemoteCmd.exe. Se tu dong do tim khi digiCamControl khoi chay." -ForegroundColor Yellow
}

# Hàm tự động dò tìm IP hoặc tiến trình của digiCamControl
function Find-DigiCamControlUrl {
    param ([string]$ManualUrl)

    $urlsToTest = [System.Collections.Generic.List[string]]::new()
    $urlsToTest.Add("http://127.0.0.1:5513")
    $urlsToTest.Add("http://localhost:5513")
    if ($ManualUrl -and $ManualUrl.Trim().Length -gt 0) { 
        $urlsToTest.Add($ManualUrl.Trim().TrimEnd('/')) 
    }

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

    $uniqueUrls = $urlsToTest | Select-Object -Unique

    # 1. Thử HTTP Webserver (port 5513)
    foreach ($testUrl in $uniqueUrls) {
        try {
            $check = Invoke-RestMethod -Uri "$testUrl/?CMD=Get_Current_Value&Param=cameraname" -TimeoutSec 2 -ErrorAction Stop
            if ($check -ne $null) {
                $camStr = $check.ToString().Trim()
                $isConnected = ($camStr.Length -gt 0) -and ($camStr -ne "No camera connected") -and (-not $camStr.Contains("Error"))
                return @{
                    url = $testUrl
                    cameraName = if ($camStr) { $camStr } else { "Canon EOS Camera" }
                    connected = $isConnected
                    online = $true
                    method = "http"
                }
            }
        } catch {}
    }

    # 2. Nếu HTTP không phản hồi: KIỂM TRA TIẾN TRÌNH DIGICAMCONTROL ĐANG CHẠY TRÊN WINDOWS
    $proc = Get-Process -Name "CameraControl" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        if (-not $global:RemoteCmdExe) {
            $global:RemoteCmdExe = Get-DccRemoteCmdPath
        }

        $camName = "Canon EOS Camera"
        if ($global:RemoteCmdExe) {
            try {
                $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                $pinfo.FileName = $global:RemoteCmdExe
                $pinfo.Arguments = "/c get camera"
                $pinfo.RedirectStandardOutput = $true
                $pinfo.UseShellExecute = $false
                $pinfo.CreateNoWindow = $true
                $p = [System.Diagnostics.Process]::Start($pinfo)
                $p.WaitForExit(1500) | Out-Null
                $cliOut = $p.StandardOutput.ReadToEnd().Trim()
                if ($cliOut -and (-not $cliOut.Contains("Error")) -and (-not $cliOut.Contains("null"))) {
                    $camName = $cliOut
                }
            } catch {}
        }

        return @{
            url = "http://127.0.0.1:5513"
            cameraName = $camName
            connected = $true
            online = $true
            method = "ipc_process"
        }
    }

    return @{ 
        url = "http://127.0.0.1:5513"
        cameraName = "Chưa nhận diện máy ảnh"
        connected = $false
        online = $false 
        method = "none"
    }
}

# Cấu hình session của digiCamControl
function Configure-DccSession {
    param (
        [string]$TargetUrl,
        [string]$TargetDir
    )
    try {
        $folder = $TargetDir.Replace("/", "\")
        # 1. Set transfer = Save to PC and camera
        $setTransfer = Invoke-RestMethod -Uri "$TargetUrl/?slc=set&param1=transfer&param2=Save_to_PC_and_camera" -TimeoutSec 3 -ErrorAction SilentlyContinue
        Write-Host " [CONFIG] Transfer mode: Save_to_PC_and_camera ($setTransfer)" -ForegroundColor Cyan
        # 2. Set session folder
        $encodedFolder = [System.Uri]::EscapeDataString($folder)
        $setFolder = Invoke-RestMethod -Uri "$TargetUrl/?slc=set&param1=session.folder&param2=$encodedFolder" -TimeoutSec 3 -ErrorAction SilentlyContinue
        Write-Host " [CONFIG] Session folder: $folder ($setFolder)" -ForegroundColor Cyan
        Write-Host " [OK] Anh chup se luu thang vao: $folder" -ForegroundColor Green
        return $true
    } catch {
        Write-Host " [CANH BAO] Khong the cau hinh session folder: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Lấy frame LiveView an toàn với timeout ngắn (tránh treo luồng)
function Get-LiveViewBytes {
    param ([string]$TargetUrl)
    try {
        $req = [System.Net.HttpWebRequest]::Create("$TargetUrl/liveview.jpg")
        $req.Timeout = 1500
        $req.ReadWriteTimeout = 1500
        $req.Method = "GET"
        $resp = $req.GetResponse()
        try {
            $stream = $resp.GetResponseStream()
            $ms = New-Object System.IO.MemoryStream
            $stream.CopyTo($ms)
            return $ms.ToArray()
        } finally {
            $resp.Close()
        }
    } catch {
        return $null
    }
}

function Send-JsonResponse($response, $statusCode, $jsonObj) {
    try {
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
    } catch {
        try { $response.OutputStream.Close() } catch {}
    }
}

function Handle-OptionsRequest($response) {
    try {
        $response.StatusCode = 204
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization")
        $response.OutputStream.Close()
    } catch {
        try { $response.OutputStream.Close() } catch {}
    }
}

# Quản lý trạng thái kết nối máy ảnh tự động
$script:isCameraConnected = $false
$script:sessionConfigured = $false
$script:lastHealthCheckSec = 0
$lastLiveViewRevive = 0

function Test-And-AutoReconnect {
    param ([switch]$Force)
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $Force -and ($nowSec - $script:lastHealthCheckSec) -lt 3) {
        return
    }
    $script:lastHealthCheckSec = $nowSec

    $check = Find-DigiCamControlUrl -ManualUrl $DccUrl
    $DccUrl = $check.url

    if ($check.connected) {
        if (-not $script:isCameraConnected) {
            Write-Host ""
            Write-Host "========================================================================" -ForegroundColor Green
            Write-Host " [KET NOI LAI] Phat hien may anh: $($check.cameraName) tai $($check.url)!" -ForegroundColor Green
            Write-Host " [INFO] Dang thiet lap lai cau hinh tu dau (Save_to_PC_and_camera & C:\LalePhotos)..." -ForegroundColor Cyan
            Write-Host "========================================================================" -ForegroundColor Green
            $script:isCameraConnected = $true
            $cfg = Configure-DccSession -TargetUrl $check.url -TargetDir $PhotoDir
            $script:sessionConfigured = $cfg

            # Đánh thức Live View & Focus
            try {
                Invoke-RestMethod -Uri "$($check.url)/?CMD=LiveViewWnd_Show" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                Start-Sleep -Milliseconds 400
                Invoke-RestMethod -Uri "$($check.url)/?CMD=LiveView_Focus" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        } elseif (-not $script:sessionConfigured) {
            $cfg = Configure-DccSession -TargetUrl $check.url -TargetDir $PhotoDir
            $script:sessionConfigured = $cfg
        }
    } else {
        if ($script:isCameraConnected) {
            Write-Host ""
            Write-Host "========================================================================" -ForegroundColor Yellow
            Write-Host " [CANH BAO] Mat ket noi voi may anh Canon EOS R50!" -ForegroundColor Yellow
            Write-Host " [INFO] Bridge van duy tri hoat dong va tu dong doi ket noi lai tu dau..." -ForegroundColor Cyan
            Write-Host "========================================================================" -ForegroundColor Yellow
            Write-Host ""
            $script:isCameraConnected = $false
            $script:sessionConfigured = $false
        }
    }
}

# Khởi tạo kiểm tra ban đầu
$initialDcc = Find-DigiCamControlUrl -ManualUrl $DccUrl
$DccUrl = $initialDcc.url
if ($initialDcc.connected) {
    Write-Host " [OK] DA TIM THAY DIGICAMCONTROL TAI: $DccUrl" -ForegroundColor Green
    Write-Host " [CAMERA] May anh ket noi: $($initialDcc.cameraName)" -ForegroundColor Green
    $script:isCameraConnected = $true
    $script:sessionConfigured = Configure-DccSession -TargetUrl $DccUrl -TargetDir $PhotoDir
} else {
    Write-Host " [THONG BAO] Dang su dung dia chi digiCamControl: $DccUrl" -ForegroundColor Cyan
    Write-Host " [LUU Y] Bridge se tu dong phat hien va ket noi ngay khi bat may anh / digiCamControl!" -ForegroundColor Yellow
}

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " [SAN SANG] Dang cho lenh chup tu Kiosk phong chup..." -ForegroundColor White

# VÒNG LẶP BẤT TỬ (Never Exit): Tự động khôi phục nếu listener gặp sự cố bất ngờ
while ($true) {
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://127.0.0.1:$Port/"
    $listener.Prefixes.Add($prefix)

    $started = $false
    for ($i = 1; $i -le 5; $i++) {
        try {
            $listener.Start()
            $started = $true
            break
        } catch {
            Write-Host "[CANH BAO] Cong $Port chua san sang (lan $i/5): $($_.Exception.Message). Thu lai sau 2 giay..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }

    if ($started) {
        try {
            while ($listener.IsListening) {
                try {
                    $context = $listener.GetContext()
                } catch {
                    break # Listener bị hủy hoặc đóng, thoát để khởi động lại
                }

                # Xử lý an toàn từng request - không bao giờ để exception làm sập listener
                try {
                    # Kiểm tra và tự động kết nối lại camera nếu cần
                    Test-And-AutoReconnect

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
                        Test-And-AutoReconnect -Force
                        $checkDcc = Find-DigiCamControlUrl -ManualUrl $DccUrl
                        $DccUrl = $checkDcc.url

                        $statusData = @{
                            success = $true
                            bridgeOnline = $true
                            version = "2.2.0-AutoReconnect"
                            mode = "native-windows"
                            camera = @{
                                connected = $checkDcc.connected
                                name = if ($checkDcc.cameraName) { $checkDcc.cameraName } else { "Chưa nhận diện máy ảnh (Đang chờ kết nối lại)" }
                                source = "digiCamControl ($DccUrl)"
                            }
                            autoReconnect = @{
                                enabled = $true
                                isCameraConnected = $script:isCameraConnected
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
                        $liveViewSource = "hdmi"
                        if ($body) {
                            try {
                                $jsonBody = $body | ConvertFrom-Json
                                if ($jsonBody.orderCode) { $orderCode = $jsonBody.orderCode }
                                if ($jsonBody.liveViewSource) { $liveViewSource = $jsonBody.liveViewSource }
                            } catch {}
                        }

                        # Kiểm tra xem máy ảnh / digiCamControl có đang sẵn sàng không
                        $probe = Find-DigiCamControlUrl -ManualUrl $DccUrl
                        $DccUrl = $probe.url

                        if (-not $global:RemoteCmdExe) {
                            $global:RemoteCmdExe = Get-DccRemoteCmdPath
                        }
                        $isDccRunning = (Get-Process -Name "CameraControl" -ErrorAction SilentlyContinue) -ne $null
                        $canShoot = $probe.connected -or ($global:RemoteCmdExe -ne $null) -or $isDccRunning

                        if (-not $canShoot) {
                            Write-Host "[CANH BAO] Khong the chup: digiCamControl chua mo hoac May anh Canon bi ngat ket noi!" -ForegroundColor Yellow
                            $errResult = @{
                                success = $false
                                cameraDisconnected = $true
                                message = "Máy ảnh Canon chưa kết nối hoặc chưa mở phần mềm digiCamControl trên máy tính!"
                            }
                            Send-JsonResponse -response $response -statusCode 503 -jsonObj $errResult
                            continue
                        }

                        # 0. Lấy tên ảnh gần nhất trước khi chụp để so sánh (lastcaptured)
                        $prevLastCaptured = ""
                        try {
                            $prevRes = Invoke-RestMethod -Uri "$DccUrl/?slc=get&param1=lastcaptured" -TimeoutSec 1 -ErrorAction SilentlyContinue
                            if ($prevRes) { $prevLastCaptured = $prevRes.ToString().Trim() }
                        } catch {}

                        # Thêm thư mục session đang hoạt động của digiCamControl vào danh sách theo dõi
                        try {
                            $sessFolderRes = Invoke-RestMethod -Uri "$DccUrl/?slc=get&param1=session.folder" -TimeoutSec 1 -ErrorAction SilentlyContinue
                            if ($sessFolderRes) {
                                $sessFolder = $sessFolderRes.ToString().Trim()
                                if ($sessFolder -and (Test-Path $sessFolder) -and (-not $potentialPhotoDirs.Contains($sessFolder))) {
                                    $potentialPhotoDirs.Add($sessFolder)
                                    Write-Host "[DCC] Da them thu muc session vao danh sach theo doi: $sessFolder" -ForegroundColor Cyan
                                }
                            }
                        } catch {}

                        $beforeCaptureTime = (Get-Date).AddSeconds(-1)
                        $triggerSuccess = $false

                        Write-Host "[DCC] Dang goi lenh Shutter toi: $DccUrl (Che do: $liveViewSource)" -ForegroundColor White

                        # 1. Phát lệnh chụp: ƯU TIÊN 1 qua CameraControlRemoteCmd.exe (Direct IPC - 100% đồng bộ nút bấm GUI)
                        $remoteCmdExe = $global:RemoteCmdExe
                        if (-not $remoteCmdExe) { $remoteCmdExe = Get-DccRemoteCmdPath }

                        if ($remoteCmdExe -and ($liveViewSource -ne "usb")) {
                            Write-Host "[DCC] 🚀 [IPC DIRECT] Dang kich hoat man trap va flash qua CLI: $remoteCmdExe" -ForegroundColor Cyan
                            try {
                                $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                                $pinfo.FileName = $remoteCmdExe
                                $pinfo.Arguments = "/c capture"
                                $pinfo.RedirectStandardOutput = $true
                                $pinfo.RedirectStandardError = $true
                                $pinfo.UseShellExecute = $false
                                $pinfo.CreateNoWindow = $true
                                $p = [System.Diagnostics.Process]::Start($pinfo)
                                $p.WaitForExit(6000) | Out-Null
                                $cliOut = $p.StandardOutput.ReadToEnd().Trim()
                                Write-Host "[OK] Da kich hoat man trap va flash qua CLI: $cliOut" -ForegroundColor Green
                                $triggerSuccess = $true
                            } catch {
                                Write-Host "[CANH BAO] RemoteCmd loi: $($_.Exception.Message)" -ForegroundColor Yellow
                        }

                        # ƯU TIÊN 2: Kích hoạt qua HTTP Webserver nếu chưa kích hoạt qua CLI
                        if (-not $triggerSuccess) {
                            if ($liveViewSource -ne "usb") {
                                $captureUrls = @(
                                    "$DccUrl/?CMD=Capture",
                                    "$DccUrl/?slc=capture&param1=&param2=",
                                    "$DccUrl/?CMD=Capture_No_Af",
                                    "$DccUrl/?slc=CaptureNoAf&param1=&param2="
                                )
                                foreach ($capUrl in $captureUrls) {
                                    try {
                                        Write-Host "[DCC] Dang gui lenh chup qua HTTP toi: $capUrl" -ForegroundColor White
                                        $triggerRes = Invoke-RestMethod -Uri $capUrl -TimeoutSec 5 -ErrorAction Stop
                                        $resStr = if ($triggerRes) { $triggerRes.ToString() } else { "" }
                                        Write-Host "[DCC] Phan hoi: $resStr" -ForegroundColor Gray
                                        if ($resStr.ToLower().Contains("not allowed") -or $resStr.ToLower().Contains("disabled")) {
                                            Write-Host "========================================================================" -ForegroundColor Red
                                            Write-Host "🚨 [CANH BAO] digiCamControl dang TAT: 'Allow interaction via webserver'!" -ForegroundColor Red
                                            Write-Host "👉 Vao digiCamControl -> File -> Settings -> Webserver: Tich chon 'Allow interaction via webserver'!" -ForegroundColor Yellow
                                            Write-Host "========================================================================" -ForegroundColor Red
                                        } elseif (-not $resStr.ToLower().Contains("error")) {
                                            $triggerSuccess = $true
                                            Write-Host "[OK] Da phat lenh chup qua HTTP thanh cong! Flash da no." -ForegroundColor Green
                                            break
                                        }
                                    } catch {
                                        Write-Host "[CANH BAO] Gui $capUrl gap loi: $($_.Exception.Message)" -ForegroundColor Yellow
                                    }
                                }
                            } else {
                                # USB Live View mode
                                try {
                                    $triggerRes = Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Capture" -TimeoutSec 5 -ErrorAction Stop
                                    $triggerSuccess = $true
                                    Write-Host "[OK] Da phat lenh LiveView_Capture thanh cong! Flash da no." -ForegroundColor Green
                                } catch {
                                    try {
                                        $triggerRes = Invoke-RestMethod -Uri "$DccUrl/?CMD=Capture" -TimeoutSec 6 -ErrorAction Stop
                                        $triggerSuccess = $true
                                    } catch {}
                                }
                            }
                        }

                        # 2. Chờ đợi file ảnh mới xuất hiện: Kết hợp dò tìm thư mục + hỏi trực tiếp API lastcaptured
                        $foundFile = $null
                        $timeoutSeconds = 9
                        $waited = 0

                        Write-Host "Dang cho may anh truyen file anh 24MP ve may tinh..." -NoNewline
                        while ($waited -lt ($timeoutSeconds * 4)) {
                            Start-Sleep -Milliseconds 250
                            $waited++

                            # A. Kiểm tra API lastcaptured của digiCamControl
                            try {
                                $currCapturedRes = Invoke-RestMethod -Uri "$DccUrl/?slc=get&param1=lastcaptured" -TimeoutSec 1 -ErrorAction SilentlyContinue
                                if ($currCapturedRes) {
                                    $currCaptured = $currCapturedRes.ToString().Trim()
                                    if ($currCaptured -and $currCaptured -ne "-" -and $currCaptured -ne $prevLastCaptured -and (-not $currCaptured.Contains("Error"))) {
                                        Write-Host "`n[DCC] Phat hien anh moi qua API lastcaptured: $currCaptured" -ForegroundColor Green
                                        if (Test-Path $currCaptured) {
                                            $foundFile = $currCaptured
                                            break
                                        }
                                        $baseName = [System.IO.Path]::GetFileName($currCaptured)
                                        foreach ($dir in $potentialPhotoDirs) {
                                            $testPath = Join-Path $dir $baseName
                                            if (Test-Path $testPath) {
                                                $foundFile = $testPath
                                                break
                                            }
                                        }
                                        if ($foundFile) { break }
                                    }
                                }
                            } catch {}

                            # B. Quét các thư mục lưu ảnh
                            foreach ($dir in $potentialPhotoDirs) {
                                if (Test-Path $dir) {
                                    $latest = Get-ChildItem -Path $dir -Include *.jpg,*.jpeg,*.png -File -Recurse -ErrorAction SilentlyContinue | 
                                              Where-Object { $_.LastWriteTime -ge $beforeCaptureTime } | 
                                              Sort-Object LastWriteTime -Descending | 
                                              Select-Object -First 1

                                    if ($latest) {
                                        Start-Sleep -Milliseconds 200
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

                                # Chỉ khôi phục Live View nếu người dùng đang dùng chế độ USB
                                if ($liveViewSource -eq "usb") {
                                    try {
                                        Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveViewWnd_Show" -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
                                        Start-Sleep -Milliseconds 300
                                        Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Focus" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                                        try {
                                            $wshell = New-Object -ComObject WScript.Shell
                                            $wshell.AppActivate("Chrome") | Out-Null
                                            $wshell.AppActivate("Edge") | Out-Null
                                        } catch {}
                                    } catch {}
                                }
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

                                if ($liveViewSource -eq "usb") {
                                    try {
                                        Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveViewWnd_Show" -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
                                        Start-Sleep -Milliseconds 300
                                        Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Focus" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                                        try {
                                            $wshell = New-Object -ComObject WScript.Shell
                                            $wshell.AppActivate("Chrome") | Out-Null
                                            $wshell.AppActivate("Edge") | Out-Null
                                        } catch {}
                                    } catch {}
                                }
                                continue
                            }
                        } catch {
                            Write-Host "[FALLBACK] Khong the lay anh tu preview.jpg: $($_.Exception.Message)" -ForegroundColor Yellow
                        }

                        # Thất bại: Không nhận được file ảnh sau khi bấm cò
                        Write-Host "[LOI] Khong tim thay file anh moi tu may anh trong C:\LalePhotos." -ForegroundColor Red
                        $errResult = @{
                            success = $false
                            message = "Khong tim thay file anh moi tu may anh Canon trong C:\LalePhotos. Vui long kiem tra the nho/digiCamControl."
                        }
                        Send-JsonResponse -response $response -statusCode 500 -jsonObj $errResult
                        continue
                    }

                    # 3. API LIVEVIEW START: /api/liveview/start
                    if ($rawUrl -match "^/api/liveview/start") {
                        try {
                            Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveViewWnd_Show" -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
                            Start-Sleep -Milliseconds 400
                            Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Focus" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                            Write-Host "[LIVEVIEW] Da gui lenh bat Live View & danh thuc cam bien (Focus) toi digiCamControl ($DccUrl)" -ForegroundColor Green
                            Send-JsonResponse -response $response -statusCode 200 -jsonObj @{ success = $true; message = "Live View started" }
                        } catch {
                            Send-JsonResponse -response $response -statusCode 500 -jsonObj @{ success = $false; error = $_.Exception.Message }
                        }
                        continue
                    }

                    # 3.1 API LIVEVIEW STOP: /api/liveview/stop
                    if ($rawUrl -match "^/api/liveview/stop") {
                        try {
                            Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveViewWnd_Hide" -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
                            Write-Host "[LIVEVIEW] Da gui lenh tat Live View de may anh nghi ngoi ($DccUrl)" -ForegroundColor Yellow
                            Send-JsonResponse -response $response -statusCode 200 -jsonObj @{ success = $true; message = "Live View stopped" }
                        } catch {
                            Send-JsonResponse -response $response -statusCode 500 -jsonObj @{ success = $false; error = $_.Exception.Message }
                        }
                        continue
                    }

                    # 4. API LIVEVIEW FRAME: /api/liveview
                    if ($rawUrl -match "^/api/liveview(\?|$)") {
                        $lvBytes = Get-LiveViewBytes -TargetUrl $DccUrl
                        if ($lvBytes -and $lvBytes.Length -gt 500) {
                            try {
                                $response.StatusCode = 200
                                $response.ContentType = "image/jpeg"
                                $response.Headers.Add("Access-Control-Allow-Origin", "*")
                                $response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
                                $response.ContentLength64 = $lvBytes.Length
                                $response.OutputStream.Write($lvBytes, 0, $lvBytes.Length)
                                $response.OutputStream.Close()
                            } catch {
                                try { $response.OutputStream.Close() } catch {}
                            }
                        } else {
                            $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                            if (($nowSec - $lastLiveViewRevive) -gt 4) {
                                $lastLiveViewRevive = $nowSec
                                try {
                                    Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveViewWnd_Show" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                                    Start-Sleep -Milliseconds 400
                                    Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Focus" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                                } catch {}
                            }
                            try {
                                $response.StatusCode = 502
                                $response.OutputStream.Close()
                            } catch {}
                        }
                        continue
                    }

                    # 5. API LIVEVIEW STREAM: /api/liveview/stream
                    if ($rawUrl -match "^/api/liveview/stream") {
                        $lvBytes = Get-LiveViewBytes -TargetUrl $DccUrl
                        if ($lvBytes -and $lvBytes.Length -gt 500) {
                            try {
                                $response.StatusCode = 200
                                $response.ContentType = "image/jpeg"
                                $response.Headers.Add("Access-Control-Allow-Origin", "*")
                                $response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
                                $response.ContentLength64 = $lvBytes.Length
                                $response.OutputStream.Write($lvBytes, 0, $lvBytes.Length)
                                $response.OutputStream.Close()
                            } catch {
                                try { $response.OutputStream.Close() } catch {}
                            }
                        } else {
                            try {
                                $response.StatusCode = 502
                                $response.OutputStream.Close()
                            } catch {}
                        }
                        continue
                    }

                    # Route khác
                    Send-JsonResponse -response $response -statusCode 404 -jsonObj @{ error = "Not found" }

                } catch {
                    Write-Host "[CANH BAO] Loi xu ly request: $($_.Exception.Message)" -ForegroundColor Yellow
                    try {
                        $context.Response.StatusCode = 500
                        $context.Response.OutputStream.Close()
                    } catch {}
                }
            }
        } catch {
            Write-Host "[CANH BAO] Su co HTTP Listener: $($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            try { $listener.Stop() } catch {}
        }
    }

    Write-Host "[INFO] Khoi dong lai listener sau 2 giay..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
}
