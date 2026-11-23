# ========================================================================
#  LALE PHOTO STUDIO - NATIVE WINDOWS CAMERA BRIDGE (AUTO-RECONNECT)
# Chay truc tiep tren Windows 10/11 - KHONG CAN CAI DAT NODE.JS!
# Tu dong phat hien IP cua digiCamControl, tu dong ket noi lai tu dau khi mat ket noi
# ========================================================================

param (
    [int]$Port = 4000,
    [string]$DccUrl = "",
    [string]$PhotoDir = "C:\LalePhotos"
)

# Doc cau hinh tu config.json neu co
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

# Dam bao thu muc luu anh ton tai
if (-not (Test-Path -Path $PhotoDir)) {
    try {
        New-Item -ItemType Directory -Path $PhotoDir -Force | Out-Null
    } catch {
        $PhotoDir = Join-Path $PSScriptRoot "captured_photos"
        New-Item -ItemType Directory -Path $PhotoDir -Force | Out-Null
    }
}

# Cac thu muc anh tiem nang de theo doi
$potentialPhotoDirs = [System.Collections.Generic.List[string]]::new()
$potentialPhotoDirs.Add($PhotoDir)
$defaultDccPicDir = Join-Path ([Environment]::GetFolderPath('MyPictures')) "digiCamControl"
if (Test-Path $defaultDccPicDir) { $potentialPhotoDirs.Add($defaultDccPicDir) }
$localCapturedDir = Join-Path $PSScriptRoot "captured_photos"
if (Test-Path $localCapturedDir) { $potentialPhotoDirs.Add($localCapturedDir) }

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "  LALE PHOTO STUDIO - NATIVE HARDWARE CAMERA BRIDGE (AUTO-RECONNECT)" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host " [INFO] Cong Bridge Kiosk: http://127.0.0.1:$Port" -ForegroundColor Yellow
Write-Host " [INFO] Thu muc luu anh:   $PhotoDir" -ForegroundColor Yellow

[System.Net.WebRequest]::DefaultWebProxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()

# Ham tim kiem tien ich CameraControlRemoteCmd.exe (IPC Direct)
function Get-DccRemoteCmdPath {
    # 1. Tim tu tien trinh CameraControl dang chay trong Windows
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

    # 2. Tim qua cac duong dan cai dat tieu chuan
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

    # 3. Tim qua Registry
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

# Khoi tao va tu dong bien dich FujiBridge cho Fujifilm neu can
$global:FujiBridgeExe = Join-Path $PSScriptRoot "bin\fujifilm_win64\fuji_bridge.exe"
$csSource = Join-Path $PSScriptRoot "bin\fujifilm_win64\FujiBridge.cs"

$needsCompile = (-not (Test-Path $global:FujiBridgeExe))
if (-not $needsCompile -and (Test-Path $csSource)) {
    if ((Get-Item $csSource).LastWriteTime -gt (Get-Item $global:FujiBridgeExe).LastWriteTime) {
        $needsCompile = $true
        Write-Host " [INFO] Phat hien FujiBridge.cs da duoc cap nhat moi, tien hanh bien dich lai..." -ForegroundColor Yellow
    }
}

if ($needsCompile -and (Test-Path $csSource)) {
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
    if (Test-Path $csc) {
        try {
            Write-Host " [INFO] Dang tu dong bien dich fuji_bridge.exe (64-bit)..." -ForegroundColor Cyan
            $proc = Start-Process -FilePath $csc -ArgumentList "/target:exe /platform:x64 /optimize+ /out:`"$global:FujiBridgeExe`" `"$csSource`"" -WorkingDirectory (Split-Path $global:FujiBridgeExe) -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0 -and (Test-Path $global:FujiBridgeExe)) {
                Write-Host " [OK] Da tao thanh cong: fuji_bridge.exe (FUJIFILM SDK)" -ForegroundColor Green
            } else {
                Write-Host " [CANH BAO] Bien dich fuji_bridge.exe that bai (ExitCode=$($proc.ExitCode))" -ForegroundColor Yellow
            }
        } catch {
            Write-Host " [CANH BAO] Khong the chay csc.exe: $($_.Message)" -ForegroundColor Yellow
        }
    }
}
if (Test-Path $global:FujiBridgeExe) {
    Write-Host " [OK] TIM THAY TIEN ICH FUJIFILM BRIDGE: $global:FujiBridgeExe" -ForegroundColor Green
}

# Ham kiem tra port co dang duoc listen khong (sieu toc, 100ms)
function Test-PortListening {
    param ([int]$Port, [int]$TimeoutMs = 150)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ready = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ready -and $client.Connected) {
            $client.EndConnect($iar)
            $client.Close()
            return $true
        }
        $client.Close()
    } catch {}
    return $false
}

# Cache driver may anh dang hoat dong de tranh tre (latency) khi chup
$global:ActiveCameraDriver = $null

# Ham kiem tra trang thai may anh Fujifilm (Daemon HTTP 5514 hoac fuji_bridge.exe CLI)
function Find-FujifilmCamera {
    if (Test-PortListening -Port 5514 -TimeoutMs 150) {
        try {
            $check = Invoke-RestMethod -Uri "http://127.0.0.1:5514/api/status" -TimeoutSec 1 -ErrorAction Stop
            if ($check -and ($check.connected -or $check.cameraConnected)) {
                return @{
                    connected = $true
                    cameraName = if ($check.cameraName) { $check.cameraName } else { "FUJIFILM X-T4" }
                    method = "daemon"
                    resolution = "6240x4160 (26.1 MP)"
                }
            }
        } catch {}
    }

    if ($global:FujiBridgeExe -and (Test-Path $global:FujiBridgeExe)) {
        try {
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $global:FujiBridgeExe
            $pinfo.Arguments = "status"
            $pinfo.WorkingDirectory = Split-Path $global:FujiBridgeExe
            $pinfo.RedirectStandardOutput = $true
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($pinfo)
            $p.WaitForExit(3000) | Out-Null
            $out = $p.StandardOutput.ReadToEnd().Trim()
            if ($out) {
                $json = $out | ConvertFrom-Json
                if ($json.connected) {
                    return @{
                        connected = $true
                        cameraName = if ($json.cameraName) { $json.cameraName } else { "FUJIFILM X-T4" }
                        method = "cli"
                        resolution = "6240x4160 (26.1 MP)"
                    }
                }
            }
        } catch {}
    }

    return @{ connected = $false; cameraName = $null; method = "none"; resolution = "Chua ket noi" }
}

# Ham lay driver may anh tich cuc (Canon hoac Fujifilm)
function Get-ActiveCameraInfo {
    param ([string]$ManualDccUrl)

    # Neu da xac dinh Fujifilm truoc do, uu tien kiem tra nhanh Fujifilm truoc (duoi 50ms)
    if ($global:ActiveCameraDriver -eq "fujifilm") {
        $fuji = Find-FujifilmCamera
        if ($fuji.connected) {
            return @{
                driver = "fujifilm"
                connected = $true
                cameraName = $fuji.cameraName
                source = "FUJIFILM Camera Control SDK (64-bit)"
                resolution = "6240x4160 (26.1 MP)"
                dcc = @{ connected = $false }
            }
        }
    }

    # Kiem tra DCC
    $dcc = Find-DigiCamControlUrl -ManualUrl $ManualDccUrl
    if ($dcc.connected) {
        $global:ActiveCameraDriver = "digicamcontrol"
        return @{
            driver = "digicamcontrol"
            connected = $true
            cameraName = $dcc.cameraName
            source = "digiCamControl ($($dcc.url))"
            resolution = "6000x4000 (24.2 MP)"
            dcc = $dcc
        }
    }

    # Kiem tra Fujifilm
    $fuji = Find-FujifilmCamera
    if ($fuji.connected) {
        $global:ActiveCameraDriver = "fujifilm"
        return @{
            driver = "fujifilm"
            connected = $true
            cameraName = $fuji.cameraName
            source = "FUJIFILM Camera Control SDK (64-bit)"
            resolution = "6240x4160 (26.1 MP)"
            dcc = $dcc
        }
    }

    $global:ActiveCameraDriver = $null
    return @{
        driver = if ($dcc.online) { "digicamcontrol" } else { "none" }
        connected = $false
        cameraName = if ($dcc.online) { $dcc.cameraName } else { "Chua nhan dien may anh (Ho tro Canon EOS & FUJIFILM X-T4)" }
        source = if ($dcc.online) { "digiCamControl ($($dcc.url))" } else { "None" }
        resolution = "Chua xac dinh"
        dcc = $dcc
    }
}

# Ham tu dong do tim IP hoac tien trinh cua digiCamControl
function Find-DigiCamControlUrl {
    param ([string]$ManualUrl)

    # Kiem tra nhanh xem co port 5513 tren 127.0.0.1 khong
    $port5513Open = Test-PortListening -Port 5513 -TimeoutMs 150
    if (-not $port5513Open) {
        # Neu port 5513 khong mo tren 127.0.0.1, kiem tra nhanh xem CameraControl.exe co dang chay khong
        $proc = Get-Process -Name "CameraControl" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $proc) {
            return @{ url = $null; cameraName = $null; connected = $false; online = $false; method = "none" }
        }
    }

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

    # 1. Thu HTTP Webserver (port 5513)
    foreach ($testUrl in $uniqueUrls) {
        try {
            $check = Invoke-RestMethod -Uri "$testUrl/?CMD=Get_Current_Value&Param=cameraname" -TimeoutSec 1 -ErrorAction Stop
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

    # 2. Neu HTTP khong phan hoi: KIEM TRA TIEN TRINH DIGICAMCONTROL DANG CHAY TREN WINDOWS
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
        cameraName = "Chua nhan dien may anh"
        connected = $false
        online = $false 
        method = "none"
    }
}

# Cau hinh session cua digiCamControl
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

# Lay frame LiveView an toan voi timeout ngan (tranh treo luong)
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

function Send-RawJson($response, $statusCode, [string]$rawJsonString) {
    try {
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($rawJsonString)
        
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

# Quan ly trang thai ket noi may anh tu dong
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

            # Danh thuc Live View & Focus
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

# Khoi tao kiem tra ban dau
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

# VONG LAP BAT TU (Never Exit): Tu dong khoi phuc neu listener gap su co bat ngo
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
                    break # Listener bi huy hoac dong, thoat de khoi dong lai
                }

                # Xu ly an toan tung request - khong bao gio de exception lam sap listener
                try {
                    # Kiem tra va tu dong ket noi lai camera neu can
                    Test-And-AutoReconnect

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
                        Test-And-AutoReconnect -Force
                        $camInfo = Get-ActiveCameraInfo -ManualDccUrl $DccUrl
                        if ($camInfo.dcc) { $DccUrl = $camInfo.dcc.url }

                        $statusData = @{
                            success = $true
                            bridgeOnline = $true
                            version = "2.3.0-DualCamera"
                            mode = "native-windows"
                            activeDriver = $camInfo.driver
                            camera = @{
                                connected = $camInfo.connected
                                name = $camInfo.cameraName
                                source = $camInfo.source
                                resolution = $camInfo.resolution
                            }
                            autoReconnect = @{
                                enabled = $true
                                isCameraConnected = $camInfo.connected
                            }
                            dccUrl = $DccUrl
                            watchDirectory = $PhotoDir
                        }
                        Send-JsonResponse -response $response -statusCode 200 -jsonObj $statusData
                        continue
                    }

                    # 1b. API FOCUS: /api/focus (Kich hoat lay net Canon R50 / FUJIFILM X-T4)
                    if ($rawUrl -match "^/api/focus") {
                        Write-Host "`n[LAY NET] Nhan lenh lay net tu Kiosk!..." -ForegroundColor Green
                        $camInfo = Get-ActiveCameraInfo -ManualDccUrl $DccUrl
                        $focused = $false

                        # FUJIFILM FOCUS
                        if ($camInfo.driver -eq "fujifilm") {
                            Write-Host "[FUJI FOCUS] Dang kich hoat autofocus FUJIFILM..." -ForegroundColor Cyan
                            $focusMsg = ""
                            try {
                                $fujiRes = Invoke-RestMethod -Uri "http://127.0.0.1:5514/api/focus" -TimeoutSec 3 -ErrorAction Stop
                                if ($fujiRes -and $fujiRes.success) {
                                    $focused = $true
                                    $focusMsg = $fujiRes.message
                                }
                            } catch {
                                Write-Host "[FUJI FOCUS] Daemon focus that bai: $($_.Exception.Message)" -ForegroundColor Yellow
                            }

                            if (-not $focused -and $global:FujiBridgeExe -and (Test-Path $global:FujiBridgeExe)) {
                                try {
                                    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                                    $pinfo.FileName = $global:FujiBridgeExe
                                    $pinfo.Arguments = "focus"
                                    $pinfo.WorkingDirectory = Split-Path $global:FujiBridgeExe
                                    $pinfo.RedirectStandardOutput = $true
                                    $pinfo.RedirectStandardError = $true
                                    $pinfo.UseShellExecute = $false
                                    $pinfo.CreateNoWindow = $true
                                    $p = [System.Diagnostics.Process]::Start($pinfo)
                                    $p.WaitForExit(5000) | Out-Null
                                    $errOut = $p.StandardError.ReadToEnd()
                                    $out = $p.StandardOutput.ReadToEnd()
                                    if ($errOut) { Write-Host "[FUJI FOCUS LOG] $errOut" -ForegroundColor DarkGray }
                                    if ($p.ExitCode -eq 0) {
                                        $focused = $true
                                        $focusMsg = "Da kich hoat autofocus FUJIFILM thanh cong"
                                    }
                                } catch {
                                    Write-Host "[FUJI FOCUS LOI] $($_.Message)" -ForegroundColor Red
                                }
                            }

                            $focusResult = @{
                                success = $focused
                                message = if ($focused) { if ($focusMsg) { $focusMsg } else { "Da kich hoat autofocus FUJIFILM" } } else { "Lay net Fujifilm that bai" }
                            }
                            Send-JsonResponse -response $response -statusCode 200 -jsonObj $focusResult
                            continue
                        }

                        # CANON EOS FOCUS (Existing)
                        Write-Host "[CANON] Dang kich hoat autofocus Dual Pixel AF cho Canon R50..." -ForegroundColor Green
                        if (-not $global:RemoteCmdExe) {
                            $global:RemoteCmdExe = Get-DccRemoteCmdPath
                        }
                        if ($global:RemoteCmdExe) {
                            try {
                                Start-Process -FilePath $global:RemoteCmdExe -ArgumentList "/c", "LiveView_Focus" -WindowStyle Hidden -ErrorAction SilentlyContinue
                                $focused = $true
                            } catch {}
                        }
                        if (-not $focused -and $DccUrl) {
                            try {
                                Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Focus" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
                                $focused = $true
                            } catch {}
                        }
                        $focusResult = @{
                            success = $true
                            message = "Da kich hoat lay net may anh Canon R50"
                        }
                        Send-JsonResponse -response $response -statusCode 200 -jsonObj $focusResult
                        continue
                    }

                    # 2. API CAPTURE: /api/capture
                    if ($rawUrl -match "^/api/capture" -and $method -eq "POST") {
                        Write-Host "`n[CHUP ANH] Nhan lenh tu Kiosk phong chup! Dang kich hoat co may anh & Flash..." -ForegroundColor Cyan

                        # Doc orderCode
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

                        # Kiem tra may anh hien tai (FUJIFILM hoac CANON)
                        $camInfo = Get-ActiveCameraInfo -ManualDccUrl $DccUrl

                        # A. XU LY CHUP ANH BANG FUJIFILM (26.1 MP)
                        if ($camInfo.driver -eq "fujifilm") {
                            Write-Host "========================================================================" -ForegroundColor Magenta
                            Write-Host "[FUJI BRIDGE STEP 1/4] Kich hoat chup anh FUJIFILM X-T4 (26.1 MP)..." -ForegroundColor Cyan
                            Write-Host "  -> Ma don: $orderCode | Thu muc luu: $PhotoDir" -ForegroundColor DarkGray
                            $fujiCaptured = $null
                            $fujiErrMsg = ""

                            # 1. Thu qua Daemon HTTP 5514 (neu port 5514 dang mo)
                            if (Test-PortListening -Port 5514 -TimeoutMs 150) {
                                try {
                                    Write-Host "[FUJI BRIDGE STEP 2/4] Goi Daemon HTTP (http://127.0.0.1:5514/api/capture)..." -ForegroundColor Cyan
                                    $postBody = @{ orderCode = $orderCode; photoSaveDir = $PhotoDir; autoFocus = $true } | ConvertTo-Json
                                    $fujiRes = Invoke-RestMethod -Uri "http://127.0.0.1:5514/api/capture" -Method POST -Body $postBody -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
                                    if ($fujiRes -and $fujiRes.success) {
                                        $fujiCaptured = $fujiRes
                                        Write-Host "[FUJI BRIDGE STEP 3/4] Daemon chup thanh cong! File: $($fujiRes.filename) ($($fujiRes.fileSizeMb))" -ForegroundColor Green
                                    } else {
                                        $fujiErrMsg = if ($fujiRes.error) { $fujiRes.error } else { "Daemon bao khong thanh cong" }
                                        Write-Host "[FUJI BRIDGE STEP 2 CANH BAO] Daemon phan hoi: $fujiErrMsg" -ForegroundColor Yellow
                                    }
                                } catch {
                                    $fujiErrMsg = $_.Exception.Message
                                    Write-Host "[FUJI BRIDGE STEP 2 THONG BAO] Khong the chup qua Daemon 5514 ($fujiErrMsg). Chuyen sang goi truc tiep CLI..." -ForegroundColor Yellow
                                }
                            } else {
                                Write-Host "[FUJI BRIDGE STEP 2] Daemon 5514 chua khoi chay, goi truc tiep CLI..." -ForegroundColor Yellow
                            }

                            # 2. Neu Daemon chua chay hoac loi, goi truc tiep qua CLI fuji_bridge.exe
                            $fujiRawJson = $null
                            if (-not $fujiCaptured -and $global:FujiBridgeExe -and (Test-Path $global:FujiBridgeExe)) {
                                # Giai phong bat ky tien trinh fuji_bridge nao dang chiem cong USB de tranh loi 0x1001 SEQUENCE
                                $dangling = Get-Process -Name "fuji_bridge" -ErrorAction SilentlyContinue
                                if ($dangling) {
                                    $dangling | Stop-Process -Force -ErrorAction SilentlyContinue
                                    Start-Sleep -Milliseconds 100
                                }

                                Write-Host "[FUJI BRIDGE STEP 2b] Khoi chay truc tiep CLI: $global:FujiBridgeExe capture..." -ForegroundColor Cyan
                                try {
                                    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                                    $pinfo.FileName = $global:FujiBridgeExe
                                    $pinfo.Arguments = "capture `"$PhotoDir`" `"$orderCode`""
                                    $pinfo.WorkingDirectory = Split-Path $global:FujiBridgeExe
                                    $pinfo.RedirectStandardOutput = $true
                                    $pinfo.RedirectStandardError = $true
                                    $pinfo.UseShellExecute = $false
                                    $pinfo.CreateNoWindow = $true
                                    $p = [System.Diagnostics.Process]::Start($pinfo)

                                    $stdErrTask = $p.StandardError.ReadToEndAsync()
                                    $stdOutTask = $p.StandardOutput.ReadToEndAsync()

                                    $p.WaitForExit(20000) | Out-Null

                                    $errOut = $stdErrTask.Result
                                    $out = $stdOutTask.Result

                                    if ($errOut) {
                                        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
                                        Write-Host "[FUJI SDK LOG CHI TIET TUNG BUOC]:" -ForegroundColor DarkCyan
                                        $errOut.Split("`n") | ForEach-Object {
                                            $tLine = $_.Trim()
                                            if ($tLine) {
                                                if ($tLine -like "*LOI*" -or $tLine -like "*ERROR*" -or $tLine -like "*FAIL*" -or $tLine -like "*TIMEOUT*") {
                                                    Write-Host "  $tLine" -ForegroundColor Red
                                                } elseif ($tLine -like "*CANH BAO*" -or $tLine -like "*WARN*") {
                                                    Write-Host "  $tLine" -ForegroundColor Yellow
                                                } elseif ($tLine -like "*THANH CONG*" -or $tLine -like "*PHAT HIEN*" -or $tLine -like "*SUCCESS*") {
                                                    Write-Host "  $tLine" -ForegroundColor Green
                                                } else {
                                                    Write-Host "  $tLine" -ForegroundColor Gray
                                                }
                                            }
                                        }
                                        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
                                    }

                                    if ($p.ExitCode -ne 0) {
                                        Write-Host "[FUJI BRIDGE] CLI ket thuc voi ExitCode = $($p.ExitCode)" -ForegroundColor Red
                                    }

                                    if ($out) {
                                        $trimmedOut = $out.Trim()
                                        if ($trimmedOut.StartsWith("{") -and $trimmedOut.Contains('"success":true')) {
                                            $fujiRawJson = $trimmedOut
                                        } else {
                                            try {
                                                $fujiCaptured = $trimmedOut | ConvertFrom-Json
                                            } catch {
                                                Write-Host "[FUJI BRIDGE] Khong the giai ma JSON tu CLI: $out" -ForegroundColor Red
                                            }
                                        }
                                    }
                                } catch {
                                    $fujiErrMsg = $_.Exception.Message
                                    Write-Host "[FUJI BRIDGE] Ngoai le khi goi CLI: $fujiErrMsg" -ForegroundColor Red
                                }
                            }

                            if ($fujiRawJson) {
                                Write-Host "[FUJI BRIDGE STEP 4/4] CHUP ANH FUJIFILM THANH CONG (STREAM RAW JSON SIEU TOC)!" -ForegroundColor Green
                                Write-Host "========================================================================" -ForegroundColor Magenta
                                Send-RawJson -response $response -statusCode 200 -rawJsonString $fujiRawJson
                                continue
                            } elseif ($fujiCaptured -and $fujiCaptured.success) {
                                Write-Host "[FUJI BRIDGE STEP 4/4] CHUP ANH FUJIFILM THANH CONG!" -ForegroundColor Green
                                Write-Host "  -> File anh goc: $($fujiCaptured.filePath)" -ForegroundColor Green
                                Write-Host "  -> Do phan giai: $($fujiCaptured.resolution) ($($fujiCaptured.fileSizeMb))" -ForegroundColor Green
                                Write-Host "========================================================================" -ForegroundColor Magenta
                                Send-JsonResponse -response $response -statusCode 200 -jsonObj $fujiCaptured
                                continue
                            } else {
                                $finalErr = if ($fujiCaptured.error) { $fujiCaptured.error } elseif ($fujiCaptured.message) { $fujiCaptured.message } elseif ($fujiErrMsg) { $fujiErrMsg } else { "Khong nhan duoc phan hoi tu camera Fujifilm." }
                                Write-Host "[FUJI BRIDGE THAT BAI] $finalErr" -ForegroundColor Red
                                Write-Host "========================================================================" -ForegroundColor Magenta
                                $errResult = @{
                                    success = $false
                                    message = "Loi chup anh FUJIFILM: $finalErr"
                                }
                                Send-JsonResponse -response $response -statusCode 500 -jsonObj $errResult
                                continue
                            }
                        }

                        # B. XU LY CHUP ANH BANG CANON / DIGICAMCONTROL (Giu nguyen 100%)
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
                                message = "May anh Canon chua ket noi hoac chua mo phan mem digiCamControl tren may tinh!"
                            }
                            Send-JsonResponse -response $response -statusCode 503 -jsonObj $errResult
                            continue
                        }

                        # 0. Lay ten anh gan nhat truoc khi chup de so sanh (lastcaptured)
                        $prevLastCaptured = ""
                        try {
                            $prevRes = Invoke-RestMethod -Uri "$DccUrl/?slc=get&param1=lastcaptured" -TimeoutSec 1 -ErrorAction SilentlyContinue
                            if ($prevRes) { $prevLastCaptured = $prevRes.ToString().Trim() }
                        } catch {}

                        # Them thu muc session dang hoat dong cua digiCamControl vao danh sach theo doi
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

                        # 1. Phat lenh chup: UU TIEN 1 qua CameraControlRemoteCmd.exe (Direct IPC - 100% dong bo nut bam GUI)
                        $remoteCmdExe = $global:RemoteCmdExe
                        if (-not $remoteCmdExe) { $remoteCmdExe = Get-DccRemoteCmdPath }

                        # [AF] TU DONG LAY NET (PRE-FOCUS) TRUOC KHI MO MAN TRAP
                        if ($liveViewSource -ne "usb") {
                            Write-Host "[LAY NET] [AF] Tu dong lay net (Pre-focus Dual Pixel AF) cho Canon R50..." -ForegroundColor Green
                            if ($remoteCmdExe) {
                                try {
                                    Start-Process -FilePath $remoteCmdExe -ArgumentList "/c", "LiveView_Focus" -WindowStyle Hidden -ErrorAction SilentlyContinue
                                } catch {}
                            } elseif ($DccUrl) {
                                try {
                                    Invoke-RestMethod -Uri "$DccUrl/?CMD=LiveView_Focus" -TimeoutSec 1 -ErrorAction SilentlyContinue | Out-Null
                                } catch {}
                            }
                            Start-Sleep -Milliseconds 250
                        }

                        if ($remoteCmdExe -and ($liveViewSource -ne "usb")) {
                            Write-Host "[DCC]  [IPC DIRECT] Dang kich hoat man trap va flash qua CLI: $remoteCmdExe" -ForegroundColor Cyan
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
                        }

                        # UU TIEN 2: Kich hoat qua HTTP Webserver neu chua kich hoat qua CLI
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
                                            Write-Host "[CANH BAO] [CANH BAO] digiCamControl dang TAT: 'Allow interaction via webserver'!" -ForegroundColor Red
                                            Write-Host "-> Vao digiCamControl -> File -> Settings -> Webserver: Tich chon 'Allow interaction via webserver'!" -ForegroundColor Yellow
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

                        # 2. Cho doi file anh moi xuat hien: Ket hop do tim thu muc + hoi truc tiep API lastcaptured
                        $foundFile = $null
                        $timeoutSeconds = 9
                        $waited = 0

                        Write-Host "Dang cho may anh truyen file anh 24MP ve may tinh..." -NoNewline
                        while ($waited -lt ($timeoutSeconds * 4)) {
                            Start-Sleep -Milliseconds 250
                            $waited++

                            # A. Kiem tra API lastcaptured cua digiCamControl
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

                            # B. Quet cac thu muc luu anh
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

                        # Cach 1: Doc file anh tu o dia neu tim thay
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

                                # Chi khoi phuc Live View neu nguoi dung dang dung che do USB
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

                        # Cach 2: Du phong tai anh truc tiep tu Web Server cua digiCamControl (/preview.jpg)
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

                        # That bai: Khong nhan duoc file anh sau khi bam co
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

                    # Route khac
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
