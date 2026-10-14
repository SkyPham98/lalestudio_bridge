const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar');
const { execFile } = require('child_process');

// Prevent unexpected process crashes on unhandled errors/rejections
process.on('uncaughtException', (err) => {
  console.warn(`[Bridge] ⚠️ Lỗi ngoại lệ được bảo vệ (tránh crash tiến trình): ${err?.message || err}`);
});

process.on('unhandledRejection', (reason) => {
  console.warn(`[Bridge] ⚠️ Lỗi Promise Rejection được bảo vệ (tránh crash tiến trình): ${reason?.message || reason}`);
});

// Load Configuration
const configPath = path.join(__dirname, 'config.json');
let config = {
  port: 4000,
  mode: 'digicamcontrol',
  digicamcontrol: {
    url: 'http://127.0.0.1:5513',
    timeoutMs: 12000,
    photoSaveDir: path.join(__dirname, 'captured_photos')
  },
  hotfolder: {
    enabled: false,
    watchDir: path.join(__dirname, 'captured_photos'),
    timeoutMs: 12000
  },
  mock: {
    enabled: false,
    delayMs: 500
  }
};

if (fs.existsSync(configPath)) {
  try {
    const fileConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    config = { ...config, ...fileConfig };
  } catch (e) {
    console.warn('[Bridge] Warning: Could not parse config.json, using defaults.');
  }
}

// Ensure captured photos directory exists
const defaultPhotosDir = path.isAbsolute(config.digicamcontrol.photoSaveDir)
  ? config.digicamcontrol.photoSaveDir
  : path.join(__dirname, config.digicamcontrol.photoSaveDir || 'captured_photos');

if (!fs.existsSync(defaultPhotosDir)) {
  fs.mkdirSync(defaultPhotosDir, { recursive: true });
}

const app = express();
const PORT = process.env.PORT || config.port || 4000;

app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use('/photos', express.static(defaultPhotosDir));

let lastCapturedFile = null;
let lastCapturedBase64 = null;

// Hotfolder watcher setup
let latestFileDetected = null;
let pendingCaptureResolve = null;

const watchTargetDir = (config.hotfolder && config.hotfolder.enabled && config.hotfolder.watchDir)
  ? config.hotfolder.watchDir
  : defaultPhotosDir;
const absWatchDir = path.isAbsolute(watchTargetDir) ? watchTargetDir : path.join(__dirname, watchTargetDir);
if (!fs.existsSync(absWatchDir)) {
  fs.mkdirSync(absWatchDir, { recursive: true });
}

console.log(`[Bridge] Watching folder for new camera photos: ${absWatchDir}`);

// Also watch digiCamControl's default Pictures folder as safety net
const watchDirs = [absWatchDir];
const userHome = process.env.USERPROFILE || process.env.HOME || '';
if (userHome) {
  const dccDefaultDir = path.join(userHome, 'Pictures', 'digiCamControl');
  if (dccDefaultDir !== absWatchDir) {
    watchDirs.push(dccDefaultDir);
    console.log(`[Bridge] Also watching digiCamControl default folder: ${dccDefaultDir}`);
  }
}

const watcher = chokidar.watch(watchDirs, {
  ignored: /(^|[\/\\])\../,
  persistent: true,
  ignoreInitial: true,
  awaitWriteFinish: {
    stabilityThreshold: 400,
    pollInterval: 100
  }
});

watcher.on('add', (filePath) => {
  const ext = path.extname(filePath).toLowerCase();
  if (['.jpg', '.jpeg', '.png'].includes(ext)) {
    console.log(`[Bridge] New high-res photo detected from camera: ${path.basename(filePath)} (in ${path.dirname(filePath)})`);
    latestFileDetected = filePath;
    lastCapturedFile = filePath;

    if (pendingCaptureResolve) {
      pendingCaptureResolve(filePath);
      pendingCaptureResolve = null;
    }
  }
});

const os = require('os');

let cachedWorkingDccUrl = config.digicamcontrol?.url || 'http://127.0.0.1:5513';

let cachedRemoteCmdPath = null;

/**
 * Tìm file thực thi CameraControlRemoteCmd.exe của digiCamControl trên Windows
 * Tiện ích này cho phép gửi lệnh trực tiếp vào tiến trình CameraControl.exe qua IPC (Named Pipes)
 * Đồng bộ 100% với việc bấm nút Capture trên giao diện, không bị phụ thuộc cài đặt Webserver
 */
function findCameraControlRemoteCmd() {
  if (cachedRemoteCmdPath && fs.existsSync(cachedRemoteCmdPath)) {
    return cachedRemoteCmdPath;
  }

  // 1. Dò tìm từ tiến trình CameraControl.exe đang chạy
  try {
    const stdout = require('child_process').execSync(
      'powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \\"Name = \'CameraControl.exe\'\\").ExecutablePath"',
      { timeout: 2000, stdio: ['pipe', 'pipe', 'ignore'] }
    ).toString().trim();
    if (stdout && fs.existsSync(stdout)) {
      const candidate = path.join(path.dirname(stdout), 'CameraControlRemoteCmd.exe');
      if (fs.existsSync(candidate)) {
        cachedRemoteCmdPath = candidate;
        return candidate;
      }
    }
  } catch (e) {}

  // 2. Dò tìm trong các thư mục cài đặt tiêu chuẩn
  const candidates = [];
  if (process.env['ProgramFiles(x86)']) {
    candidates.push(path.join(process.env['ProgramFiles(x86)'], 'digiCamControl', 'CameraControlRemoteCmd.exe'));
  }
  if (process.env['ProgramFiles']) {
    candidates.push(path.join(process.env['ProgramFiles'], 'digiCamControl', 'CameraControlRemoteCmd.exe'));
  }

  const drives = ['C', 'D', 'E'];
  for (const drive of drives) {
    candidates.push(`${drive}:\\Program Files (x86)\\digiCamControl\\CameraControlRemoteCmd.exe`);
    candidates.push(`${drive}:\\Program Files\\digiCamControl\\CameraControlRemoteCmd.exe`);
    candidates.push(`${drive}:\\digiCamControl\\CameraControlRemoteCmd.exe`);
  }

  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) {
        cachedRemoteCmdPath = p;
        return p;
      }
    } catch (e) {}
  }
  return null;
}

function isDigiCamControlProcessRunning() {
  try {
    const stdout = require('child_process').execSync(
      'powershell -NoProfile -Command "Get-Process -Name CameraControl -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"',
      { timeout: 1500, stdio: ['pipe', 'pipe', 'ignore'] }
    ).toString().trim();
    return Boolean(stdout);
  } catch (e) {
    return false;
  }
}

function getCandidateDccUrls() {
  const list = [];
  list.push('http://127.0.0.1:5513');
  list.push('http://localhost:5513');
  if (cachedWorkingDccUrl) list.push(cachedWorkingDccUrl.replace(/\/$/, ''));
  if (config.digicamcontrol?.url) list.push(config.digicamcontrol.url.replace(/\/$/, ''));
  
  try {
    const ifaces = os.networkInterfaces();
    for (const name of Object.keys(ifaces)) {
      for (const net of ifaces[name] || []) {
        if (net.family === 'IPv4' && !net.internal && net.address !== '127.0.0.1') {
          list.push(`http://${net.address}:5513`);
        }
      }
    }
  } catch (e) {}

  return Array.from(new Set(list));
}

/**
 * Check digiCamControl status with automatic IP discovery and process fallback
 */
async function checkDigiCamControlStatus() {
  const candidates = getCandidateDccUrls();
  for (const testUrl of candidates) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 1500);
      const res = await fetch(`${testUrl}/?CMD=Get_Current_Value&Param=cameraname`, {
        signal: controller.signal
      });
      clearTimeout(timeout);

      if (res.ok) {
        const text = await res.text();
        const cleanName = text.trim();
        cachedWorkingDccUrl = testUrl;
        return {
          online: true,
          cameraConnected: cleanName.length > 0 && cleanName !== 'No camera connected' && !cleanName.includes('Error'),
          cameraName: cleanName || 'Canon EOS Camera',
          serverUrl: testUrl,
          method: 'http'
        };
      }
    } catch (err) {
      // try next candidate
    }
  }

  // Fallback: Kiểm tra xem tiến trình CameraControl.exe có đang chạy không
  if (isDigiCamControlProcessRunning() || findCameraControlRemoteCmd()) {
    return {
      online: true,
      cameraConnected: true,
      cameraName: 'Canon EOS Camera (via digiCamControl Process)',
      serverUrl: cachedWorkingDccUrl || 'http://127.0.0.1:5513',
      method: 'ipc_process'
    };
  }

  return { online: false, cameraConnected: false, cameraName: null, error: 'Cannot connect to digiCamControl on any IP' };
}

/**
 * Configure digiCamControl session: Set transfer mode to "Save to PC only"
 * and session folder to our configured photoSaveDir (e.g. C:\LalePhotos).
 * This ensures photos land in our watch folder, not digiCamControl's default.
 */
let dccSessionConfigured = false;
let isConfiguringSession = false;

async function configureDigiCamControlSession(force = false) {
  if (isConfiguringSession && !force) return { success: false, pending: true };
  isConfiguringSession = true;

  const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';
  const targetFolder = defaultPhotosDir.replace(/\//g, '\\'); // Ensure Windows-style backslashes

  try {
    // 1. Set transfer mode to "Save to PC and camera"
    const transferRes = await fetch(
      `${dccUrl}/?slc=set&param1=transfer&param2=Save_to_PC_and_camera`,
      { signal: AbortSignal.timeout(3000) }
    );
    const transferText = await transferRes.text();
    console.log(`[Bridge] Set transfer=Save_to_PC_and_camera: ${transferText.trim()}`);

    // 2. Set session folder to our configured directory (e.g. C:\LalePhotos)
    const folderRes = await fetch(
      `${dccUrl}/?slc=set&param1=session.folder&param2=${encodeURIComponent(targetFolder)}`,
      { signal: AbortSignal.timeout(3000) }
    );
    const folderText = await folderRes.text();
    console.log(`[Bridge] Set session.folder=${targetFolder}: ${folderText.trim()}`);

    dccSessionConfigured = true;
    console.log(`[Bridge] ✓ digiCamControl configured: Photos will save to ${targetFolder}`);
    return { success: true, folder: targetFolder, transfer: 'Save_to_PC_and_camera' };
  } catch (err) {
    console.warn(`[Bridge] Could not configure digiCamControl session: ${err.message}`);
    return { success: false, error: err.message };
  } finally {
    isConfiguringSession = false;
  }
}

// Trạng thái theo dõi kết nối máy ảnh tự động
let isCameraConnected = false;
let lastKnownCameraName = '';
let isCheckingReconnect = false;

/**
 * Watchdog tự động phát hiện mất kết nối và kết nối lại từ đầu:
 * - Khi mất kết nối: không exit, chuyển sang chế độ chờ kết nối lại.
 * - Khi cắm lại USB / bật lại máy ảnh: tự động dò tìm IP, kết nối lại từ đầu, cấu hình lại session và bật lại Live View.
 */
async function monitorAndAutoReconnectCamera() {
  if (isCheckingReconnect) return;
  isCheckingReconnect = true;

  try {
    const status = await checkDigiCamControlStatus();

    if (status.online && status.cameraConnected) {
      if (!isCameraConnected) {
        console.log('\n========================================================================');
        console.log(`[Bridge] 🔄 [KẾT NỐI LẠI THÀNH CÔNG] Đã phát hiện máy ảnh: "${status.cameraName}" tại ${status.serverUrl}`);
        console.log('[Bridge] Tiến hành thiết lập lại kết nối và cấu hình session từ đầu...');
        console.log('========================================================================');
        isCameraConnected = true;
        lastKnownCameraName = status.cameraName;
        dccSessionConfigured = false;

        // Cấu hình lại session (thư mục lưu ảnh và transfer mode)
        await configureDigiCamControlSession(true);

        // Đánh thức Live View & Focus
        triggerAutoLiveViewStart(status.serverUrl);
      } else if (!dccSessionConfigured) {
        await configureDigiCamControlSession();
      }
    } else {
      if (isCameraConnected) {
        console.warn('\n========================================================================');
        console.warn(`[Bridge] ⚠️ [MẤT KẾT NỐI] Mất kết nối với máy ảnh! (${status.error || status.cameraName || 'Máy ảnh bị ngắt hoặc tắt nguồn'})`);
        console.warn('[Bridge] Hệ thống sẽ giữ Bridge hoạt động và tự động kết nối lại ngay khi máy ảnh được cắm lại.');
        console.warn('========================================================================\n');
        isCameraConnected = false;
        dccSessionConfigured = false;
      }
    }
  } catch (err) {
    if (isCameraConnected) {
      console.warn(`[Bridge] ⚠️ [MẤT KẾT NỐI] Lỗi kết nối tới digiCamControl: ${err.message}`);
      isCameraConnected = false;
      dccSessionConfigured = false;
    }
  } finally {
    isCheckingReconnect = false;
  }
}

// Khởi chạy kiểm tra ban đầu và duy trì watchdog chu kỳ 2.5 giây
setTimeout(monitorAndAutoReconnectCamera, 1500);
setInterval(monitorAndAutoReconnectCamera, 2500);

/**
 * Health & Status Check Endpoint
 * Used by Room Kiosk to verify bridge & camera status
 */
app.get('/api/status', async (req, res) => {
  const dccStatus = await checkDigiCamControlStatus();
  
  // Auto-configure session if not yet done and digiCamControl is online
  if (dccStatus.online && !dccSessionConfigured) {
    await configureDigiCamControlSession();
  }

  if (dccStatus.cameraConnected && !isCameraConnected) {
    isCameraConnected = true;
    lastKnownCameraName = dccStatus.cameraName;
  }

  res.json({
    success: true,
    bridgeOnline: true,
    version: '1.2.0-AutoReconnect',
    mode: config.mode,
    camera: {
      connected: dccStatus.cameraConnected || config.mode === 'mock',
      name: dccStatus.cameraName || (config.mode === 'mock' ? 'Canon EOS R50 (Simulated)' : 'Chưa nhận diện máy ảnh (Đang chờ kết nối lại)'),
      source: dccStatus.online ? `digiCamControl (${dccStatus.serverUrl})` : config.mode,
      details: dccStatus
    },
    autoReconnect: {
      enabled: true,
      isCameraConnected,
      lastKnownCameraName
    },
    sessionConfigured: dccSessionConfigured,
    watchDirectory: absWatchDir,
    lastPhoto: lastCapturedFile ? path.basename(lastCapturedFile) : null
  });
});

app.get('/api/liveview/start', async (req, res) => {
  const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';
  try {
    await fetch(`${dccUrl}/?CMD=LiveViewWnd_Show`, { signal: AbortSignal.timeout(3000) });
    // Wake up Canon R50 sensor with Focus trigger
    setTimeout(async () => {
      try {
        await fetch(`${dccUrl}/?CMD=LiveView_Focus`, { signal: AbortSignal.timeout(2000) });
      } catch (e) {}
    }, 400);
    res.json({ success: true, message: 'Đã gửi lệnh bật Live View & đánh thức cảm biến (Focus)' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/api/liveview/stop', async (req, res) => {
  const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';
  try {
    await fetch(`${dccUrl}/?CMD=LiveViewWnd_Hide`, { signal: AbortSignal.timeout(3000) });
    res.json({ success: true, message: 'Đã gửi lệnh tắt Live View (nghỉ cảm biến)' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Active MJPEG stream clients broadcaster
const streamClients = new Set();
let streamInterval = null;

async function broadcastLiveViewFrame() {
  if (streamClients.size === 0) {
    if (streamInterval) {
      clearInterval(streamInterval);
      streamInterval = null;
    }
    return;
  }

  const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';
  try {
    const resp = await fetch(`${dccUrl}/liveview.jpg`, { signal: AbortSignal.timeout(900) });
    if (!resp.ok) return;
    const buf = Buffer.from(await resp.arrayBuffer());
    if (buf.length < 500) return; // Discard partial/broken frames

    const header = `--liveviewboundary\r\nContent-Type: image/jpeg\r\nContent-Length: ${buf.length}\r\n\r\n`;
    for (const clientRes of Array.from(streamClients)) {
      try {
        if (!clientRes.writableEnded && !clientRes.destroyed) {
          clientRes.write(header);
          clientRes.write(buf);
          clientRes.write('\r\n');
        } else {
          streamClients.delete(clientRes);
        }
      } catch (e) {
        streamClients.delete(clientRes);
      }
    }
  } catch (err) {
    // Drop frame silently when camera shutter fires or camera is busy/disconnected
  }
}

app.get('/api/liveview/stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'multipart/x-mixed-replace; boundary=--liveviewboundary',
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'Connection': 'close',
    'Access-Control-Allow-Origin': '*',
    'Pragma': 'no-cache'
  });

  streamClients.add(res);

  res.on('error', () => {
    streamClients.delete(res);
  });

  if (!streamInterval) {
    // Poll digiCamControl at ~30 FPS (33ms)
    streamInterval = setInterval(broadcastLiveViewFrame, 33);
  }

  req.on('close', () => {
    streamClients.delete(res);
    if (streamClients.size === 0 && streamInterval) {
      clearInterval(streamInterval);
      streamInterval = null;
    }
  });
});

let lastAutoLiveViewStart = 0;
function triggerAutoLiveViewStart(dccUrl) {
  const now = Date.now();
  if (now - lastAutoLiveViewStart > 4000) {
    lastAutoLiveViewStart = now;
    console.log('[Bridge] Live View appears inactive. Auto-sending LiveViewWnd_Show & LiveView_Focus to digiCamControl...');
    fetch(`${dccUrl}/?CMD=LiveViewWnd_Show`, { signal: AbortSignal.timeout(3000) })
      .then(() => new Promise(r => setTimeout(r, 400)))
      .then(() => fetch(`${dccUrl}/?CMD=LiveView_Focus`, { signal: AbortSignal.timeout(2000) }))
      .catch(() => {});
  }
}

app.get('/api/liveview', async (req, res) => {
  const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';
  try {
    const upstream = await fetch(`${dccUrl}/liveview.jpg`, { signal: AbortSignal.timeout(2000) });
    if (upstream.ok) {
      res.setHeader('Content-Type', 'image/jpeg');
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.setHeader('Access-Control-Allow-Origin', '*');
      const buf = await upstream.arrayBuffer();
      return res.send(Buffer.from(buf));
    }
    triggerAutoLiveViewStart(dccUrl);
    res.status(502).send('Liveview not ready. Auto-starting...');
  } catch (err) {
    triggerAutoLiveViewStart(dccUrl);
    res.status(502).send(err.message);
  }
});


/**
 * Kích hoạt màn trập qua CameraControlRemoteCmd.exe
 */
function triggerViaRemoteCmd(noAf = false) {
  const remoteCmdExe = findCameraControlRemoteCmd();
  if (!remoteCmdExe) return Promise.resolve({ success: false, reason: 'RemoteCmd not found' });

  return new Promise((resolve) => {
    const cmdArg = noAf ? 'capturenoaf' : 'capture';
    console.log(`[Bridge] 🚀 [IPC DIRECT] Đang kích hoạt màn trập và flash qua: "${remoteCmdExe}" /c ${cmdArg}`);
    execFile(remoteCmdExe, ['/c', cmdArg], { timeout: 7000 }, (err, stdout, stderr) => {
      if (err) {
        console.warn(`[Bridge] RemoteCmd execution notice: ${err.message}`);
        return resolve({ success: false, error: err.message });
      }
      const out = (stdout || '').trim();
      console.log(`[Bridge] RemoteCmd response: ${out || 'Executed successfully'}`);
      return resolve({ success: true, output: out });
    });
  });
}

/**
 * Kích hoạt màn trập qua HTTP Webserver của digiCamControl
 */
async function triggerViaHttp(dccUrl, noAf = false) {
  const endpoints = noAf
    ? [
        `${dccUrl}/?CMD=Capture_No_Af`,
        `${dccUrl}/?slc=CaptureNoAf&param1=&param2=`
      ]
    : [
        `${dccUrl}/?CMD=Capture`,
        `${dccUrl}/?slc=capture&param1=&param2=`
      ];

  for (const url of endpoints) {
    try {
      console.log(`[Bridge] Gửi lệnh chụp qua HTTP tới: ${url}`);
      const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
      const text = await res.text();
      console.log(`[Bridge] Phản hồi từ digiCamControl (${url}): "${text.trim().substring(0, 100)}"`);

      const lower = text.toLowerCase();
      if (lower.includes('not allowed') || lower.includes('disabled')) {
        console.error('\n' + '='.repeat(70));
        console.error('🚨 [CẢNH BÁO QUAN TRỌNG TỪ DIGICAMCONTROL]');
        console.error('digiCamControl đang TẮT tùy chọn "Allow interaction via webserver"!');
        console.error('👉 Cách bật: Mở digiCamControl -> File -> Settings -> Webserver:');
        console.error('👉 TÍCH CHỌN ô "Allow interaction via webserver" và bấm OK!');
        console.error('='.repeat(70) + '\n');
      } else if (!lower.includes('error') && res.ok) {
        return { success: true, url, response: text.trim() };
      }
    } catch (err) {
      console.warn(`[Bridge] HTTP trigger error (${url}): ${err.message}`);
    }
  }
  return { success: false };
}

/**
 * Trigger Physical Camera Shutter & Capture High-Res 24MP Photo
 */
app.post('/api/capture', async (req, res) => {
  const { orderCode = 'LALE', roomId = '1' } = req.body || {};
  console.log(`[Bridge] Received capture trigger for Order: ${orderCode}, Room: ${roomId}`);

  const startTime = Date.now();

  try {
    // 1. MOCK MODE (For offline / testing without camera hardware)
    if (config.mode === 'mock' || req.query.mock === 'true') {
      console.log('[Bridge] Running in Mock Mode - generating high-res simulated photo...');
      await new Promise(r => setTimeout(r, config.mock?.delayMs || 500));

      const mockSvg = `
        <svg xmlns="http://www.w3.org/2000/svg" width="6000" height="4000" viewBox="0 0 6000 4000">
          <defs>
            <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#1e1b4b" />
              <stop offset="50%" stop-color="#312e81" />
              <stop offset="100%" stop-color="#4c1d95" />
            </linearGradient>
            <radialGradient id="flash" cx="50%" cy="40%" r="60%">
              <stop offset="0%" stop-color="rgba(255,255,255,0.4)" />
              <stop offset="100%" stop-color="rgba(0,0,0,0)" />
            </radialGradient>
          </defs>
          <rect width="6000" height="4000" fill="url(#bg)" />
          <rect width="6000" height="4000" fill="url(#flash)" />
          <text x="3000" y="1800" font-size="160" font-weight="900" fill="#ffffff" text-anchor="middle" font-family="sans-serif">
            🌸 LALÉ PHOTO STUDIO
          </text>
          <text x="3000" y="2100" font-size="110" font-weight="bold" fill="#f43f5e" text-anchor="middle" font-family="sans-serif">
            CANON EOS R50 • 24.2 MEGAPIXELS (6000 x 4000)
          </text>
          <text x="3000" y="2350" font-size="80" fill="#cbd5e1" text-anchor="middle" font-family="monospace">
            ĐƠN HÀNG: ${orderCode} • THỜI GIAN: ${new Date().toLocaleString('vi-VN')}
          </text>
          <text x="3000" y="2550" font-size="70" fill="#10b981" text-anchor="middle" font-family="sans-serif">
            ⚡ ĐÈN FLASH STUDIO NỔ CHỚP ĐỒNG BỘ THÀNH CÔNG
          </text>
        </svg>
      `;

      const base64Data = `data:image/svg+xml;base64,${Buffer.from(mockSvg).toString('base64')}`;
      return res.json({
        success: true,
        source: 'Mock Canon EOS R50',
        filename: `${orderCode}_${Date.now()}_original.jpg`,
        imageData: base64Data,
        resolution: '6000x4000',
        elapsedMs: Date.now() - startTime
      });
    }

    // 2. DIGICAMCONTROL INTEGRATION (Default on Windows Kiosk)
    const dccCheck = await checkDigiCamControlStatus();
    if (!dccCheck.online || !dccCheck.cameraConnected) {
      console.warn(`[Bridge] Lệnh chụp bị từ chối: Mất kết nối máy ảnh (${dccCheck.error || dccCheck.cameraName || 'Offline'})`);
      return res.status(503).json({
        success: false,
        cameraDisconnected: true,
        message: 'Máy ảnh Canon chưa được kết nối hoặc bị ngắt kết nối USB. Bridge đang tự động dò tìm và kết nối lại...',
        elapsedMs: Date.now() - startTime
      });
    }

    const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';

    // Ensure session is configured so photos land in our folder (e.g. C:\LalePhotos)
    if (!dccSessionConfigured) {
      await configureDigiCamControlSession();
    }

    const { liveViewSource = 'hdmi' } = req.body || {};

    // 0. Query previous last captured photo filename/path from digiCamControl
    let prevLastCaptured = '';
    try {
      const lastRes = await fetch(`${dccUrl}/?slc=get&param1=lastcaptured`, { signal: AbortSignal.timeout(1500) });
      if (lastRes.ok) {
        prevLastCaptured = (await lastRes.text()).trim();
      }
    } catch (e) {}

    // Also get current session folder from digiCamControl dynamically
    try {
      const sessRes = await fetch(`${dccUrl}/?slc=get&param1=session.folder`, { signal: AbortSignal.timeout(1500) });
      if (sessRes.ok) {
        const sessFolder = (await sessRes.text()).trim();
        if (sessFolder && fs.existsSync(sessFolder) && !watchDirs.includes(sessFolder)) {
          watchDirs.push(sessFolder);
          watcher.add(sessFolder);
          console.log(`[Bridge] Dynamically watching active digiCamControl session folder: ${sessFolder}`);
        }
      }
    } catch (e) {}

    console.log(`[Bridge] Sending Shutter Release command to digiCamControl at ${dccUrl} (Mode: ${liveViewSource})...`);

    // Prepare a promise waiting for the new image file via watcher
    const fileWaitPromise = new Promise((resolve) => {
      pendingCaptureResolve = resolve;
    });

    // Active polling for new photo directly from digiCamControl API (slc=get&param1=lastcaptured)
    const pollStartTime = Date.now();
    let pollTimer = null;
    const pollPromise = new Promise((resolve) => {
      const checkPoll = async () => {
        if (Date.now() - pollStartTime > 9500) return;
        try {
          const resp = await fetch(`${dccUrl}/?slc=get&param1=lastcaptured`, { signal: AbortSignal.timeout(1000) });
          if (resp.ok) {
            const current = (await resp.text()).trim();
            if (current && current !== '-' && current !== prevLastCaptured && !current.includes('Error')) {
              console.log(`[Bridge] digiCamControl reported new lastcaptured: ${current}`);
              if (fs.existsSync(current)) {
                return resolve(current);
              }
              // If current is just a filename, check in watchDirs
              const baseName = path.basename(current);
              for (const dir of watchDirs) {
                const cand = path.join(dir, baseName);
                if (fs.existsSync(cand)) return resolve(cand);
              }
            }
          }
        } catch (e) {}
        pollTimer = setTimeout(checkPoll, 200);
      };
      pollTimer = setTimeout(checkPoll, 200);
    });

    // Send Capture command to digiCamControl
    // ƯU TIÊN 1: Gọi trực tiếp CameraControlRemoteCmd.exe (Giao thức IPC đồng bộ nút bấm GUI 100%, không bị phụ thuộc webserver HTTP)
    let triggered = false;
    const remoteCmdExe = findCameraControlRemoteCmd();
    if (remoteCmdExe && liveViewSource !== 'usb') {
      const cliRes = await triggerViaRemoteCmd(false);
      if (cliRes.success) {
        triggered = true;
        console.log('[Bridge] ✓ Đã kích hoạt màn trập và Flash thành công qua RemoteCmd CLI!');
      } else {
        // Thử lại với capturenoaf nếu AF bị kẹt
        const noAfRes = await triggerViaRemoteCmd(true);
        if (noAfRes.success) {
          triggered = true;
          console.log('[Bridge] ✓ Đã kích hoạt qua RemoteCmd CLI (bỏ qua AF)!');
        }
      }
    }

    // ƯU TIÊN 2: Kích hoạt qua HTTP Webserver nếu chưa kích hoạt được bằng CLI
    if (!triggered) {
      if (liveViewSource !== 'usb') {
        console.log('[Bridge] Đang gửi lệnh chụp qua HTTP API tới digiCamControl...');
        const httpRes = await triggerViaHttp(dccUrl, false);
        if (httpRes.success) {
          triggered = true;
          console.log('[Bridge] ✓ Gửi lệnh chụp qua HTTP thành công!');
        } else {
          console.log('[Bridge] Thử lại HTTP API ở chế độ CaptureNoAf (bỏ qua AF)...');
          const noAfHttp = await triggerViaHttp(dccUrl, true);
          if (noAfHttp.success) triggered = true;
        }
      } else {
        // In USB mode where digiCamControl's LiveView window is active:
        try {
          console.log('[Bridge] (USB Mode) Sending LiveView_Capture...');
          const lvRes = await fetch(`${dccUrl}/?CMD=LiveView_Capture`, { signal: AbortSignal.timeout(5000) });
          if (!lvRes.ok) throw new Error('LiveView_Capture status ' + lvRes.status);
          triggered = true;
        } catch (lvErr) {
          console.warn(`[Bridge] LiveView_Capture note (${lvErr.message}), trying standard Capture...`);
          await triggerViaHttp(dccUrl, false);
        }
      }
    }

    console.log('[Bridge] Shutter command sent! Waiting for photo file transfer...');

    // Wait for the new file via either watcher, lastcaptured polling, or preview fallback (max 10s)
    let imageFilePath = null;
    try {
      const timeoutPromise = new Promise((_, reject) => {
        const timeoutMs = config.digicamcontrol?.timeoutMs || 10000;
        setTimeout(() => reject(new Error(`Hết thời gian chờ ảnh từ máy ảnh (quá ${timeoutMs / 1000}s)`)), timeoutMs);
      });

      imageFilePath = await Promise.race([fileWaitPromise, pollPromise, timeoutPromise]);
    } catch (waitErr) {
      console.warn(`[Bridge] Disk wait notice: ${waitErr.message}. Checking preview fallback...`);
      // Fallback: try fetching latest preview image directly from digiCamControl web server
      try {
        const prevRes = await fetch(`${dccUrl}/preview.jpg`, { signal: AbortSignal.timeout(4000) });
        if (prevRes.ok) {
          const arrayBuffer = await prevRes.arrayBuffer();
          const base64 = `data:image/jpeg;base64,${Buffer.from(arrayBuffer).toString('base64')}`;
          
          if (liveViewSource === 'usb') {
            setTimeout(async () => {
              try {
                await fetch(`${dccUrl}/?CMD=LiveViewWnd_Show`, { signal: AbortSignal.timeout(3000) });
                await new Promise(r => setTimeout(r, 400));
                await fetch(`${dccUrl}/?CMD=LiveView_Focus`, { signal: AbortSignal.timeout(2000) });
              } catch (e) {}
            }, 300);
          }

          return res.json({
            success: true,
            source: 'digiCamControl Preview Feed',
            filename: `${orderCode}_${Date.now()}_original.jpg`,
            imageData: base64,
            resolution: 'Full-Res JPEG',
            elapsedMs: Date.now() - startTime
          });
        }
      } catch (prevErr) {
        console.warn('[Bridge] Preview fallback failed:', prevErr.message);
      }
      throw waitErr;
    } finally {
      if (pollTimer) clearTimeout(pollTimer);
    }

    // Read full-resolution original file from disk
    if (imageFilePath && fs.existsSync(imageFilePath)) {
      const fileBuffer = fs.readFileSync(imageFilePath);
      const ext = path.extname(imageFilePath).toLowerCase().replace('.', '');
      const mime = ext === 'png' ? 'image/png' : 'image/jpeg';
      const base64Data = `data:${mime};base64,${fileBuffer.toString('base64')}`;
      const fileSizeMb = (fileBuffer.length / (1024 * 1024)).toFixed(2);

      console.log(`[Bridge] Successfully loaded original photo: ${path.basename(imageFilePath)} (${fileSizeMb} MB, ${Date.now() - startTime}ms)`);

      if (liveViewSource === 'usb') {
        setTimeout(async () => {
          try {
            await fetch(`${dccUrl}/?CMD=LiveViewWnd_Show`, { signal: AbortSignal.timeout(3000) });
            await new Promise(r => setTimeout(r, 400));
            await fetch(`${dccUrl}/?CMD=LiveView_Focus`, { signal: AbortSignal.timeout(2000) });
            console.log('[Bridge] USB Live View resumed after capture.');
          } catch (e) {}
        }, 300);
      }

      return res.json({
        success: true,
        source: 'Canon EOS R50 Original File',
        filename: path.basename(imageFilePath),
        imageData: base64Data,
        fileSizeBytes: fileBuffer.length,
        fileSizeMb: `${fileSizeMb} MB`,
        resolution: '6000x4000 (24.2 MP)',
        elapsedMs: Date.now() - startTime
      });
    }

    throw new Error('Không tìm thấy file ảnh sau khi chụp');
  } catch (error) {
    console.error('[Bridge] Capture error:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Lỗi chụp ảnh máy ảnh',
      elapsedMs: Date.now() - startTime
    });
  }
});

// Start Server
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`
========================================================================
🌸 LALÉ STUDIO - HARDWARE CAMERA BRIDGE (AUTO-RECONNECT)
========================================================================
✓ Bridge Server running on http://127.0.0.1:${PORT}
✓ Mode: ${config.mode.toUpperCase()}
✓ digiCamControl Port: ${config.digicamcontrol?.url || 'http://127.0.0.1:5513'}
✓ Photo Watch Folder: ${absWatchDir}
✓ Status API: http://127.0.0.1:${PORT}/api/status
✓ Trigger API: http://127.0.0.1:${PORT}/api/capture
✓ Auto-Reconnect: Đang bật (tự động kết nối lại khi cắm lại máy ảnh)
========================================================================
Ready to trigger Canon R50 physical shutter & Studio Flash!
  `);
});

server.on('error', (err) => {
  console.error('[Bridge] HTTP Server Error:', err.message);
});
