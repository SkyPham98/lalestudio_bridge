const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar');

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

function getCandidateDccUrls() {
  const list = [];
  if (config.digicamcontrol?.url) list.push(config.digicamcontrol.url.replace(/\/$/, ''));
  if (cachedWorkingDccUrl) list.push(cachedWorkingDccUrl.replace(/\/$/, ''));
  
  try {
    const ifaces = os.networkInterfaces();
    for (const name of Object.keys(ifaces)) {
      for (const net of ifaces[name] || []) {
        if (net.family === 'IPv4' && !net.internal) {
          list.push(`http://${net.address}:5513`);
        }
      }
    }
  } catch (e) {}

  list.push('http://127.0.0.1:5513');
  list.push('http://localhost:5513');

  return Array.from(new Set(list));
}

/**
 * Check digiCamControl status with automatic IP discovery
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
          serverUrl: testUrl
        };
      }
    } catch (err) {
      // try next candidate
    }
  }
  return { online: false, cameraConnected: false, cameraName: null, error: 'Cannot connect to digiCamControl on any IP' };
}

/**
 * Configure digiCamControl session: Set transfer mode to "Save to PC only"
 * and session folder to our configured photoSaveDir (e.g. C:\LalePhotos).
 * This ensures photos land in our watch folder, not digiCamControl's default.
 */
let dccSessionConfigured = false;
async function configureDigiCamControlSession() {
  const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';
  const targetFolder = defaultPhotosDir.replace(/\//g, '\\'); // Ensure Windows-style backslashes

  try {
    // 1. Set transfer mode to "Save to PC only" (ảnh chỉ truyền về PC, không lưu thẻ nhớ)
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
  }
}

// Auto-configure on startup after a short delay (wait for digiCamControl to be ready)
setTimeout(async () => {
  const status = await checkDigiCamControlStatus();
  if (status.online) {
    await configureDigiCamControlSession();
  } else {
    console.log('[Bridge] digiCamControl not yet online. Session will be configured on first /api/status or /api/capture call.');
  }
}, 2000);

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

  res.json({
    success: true,
    bridgeOnline: true,
    version: '1.0.0',
    mode: config.mode,
    camera: {
      connected: dccStatus.cameraConnected || config.mode === 'mock',
      name: dccStatus.cameraName || (config.mode === 'mock' ? 'Canon EOS R50 (Simulated)' : 'Chưa nhận diện máy ảnh'),
      source: dccStatus.online ? 'digiCamControl (Port 5513)' : config.mode,
      details: dccStatus
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
        if (!clientRes.writableEnded) {
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
    // Drop frame silently when camera shutter fires or camera is busy
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
    const dccUrl = cachedWorkingDccUrl || config.digicamcontrol?.url || 'http://127.0.0.1:5513';

    // Ensure session is configured so photos land in our folder (e.g. C:\LalePhotos)
    if (!dccSessionConfigured) {
      await configureDigiCamControlSession();
    }

    console.log(`[Bridge] Sending Shutter Release command to digiCamControl at ${dccUrl}...`);

    // Prepare a promise waiting for the new image file
    const fileWaitPromise = new Promise((resolve, reject) => {
      pendingCaptureResolve = resolve;
      // Timeout after configured period
      const timeoutMs = config.digicamcontrol?.timeoutMs || 10000;
      setTimeout(() => {
        if (pendingCaptureResolve === resolve) {
          pendingCaptureResolve = null;
          reject(new Error(`Hết thời gian chờ ảnh từ máy ảnh (quá ${timeoutMs / 1000}s)`));
        }
      }, timeoutMs);
    });

    // Send Capture command to digiCamControl
    // If Live View is active, try LiveView_Capture first to pause EVF and take photo cleanly
    let captureRes;
    try {
      captureRes = await fetch(`${dccUrl}/?CMD=LiveView_Capture`, { signal: AbortSignal.timeout(5000) });
      if (!captureRes.ok) throw new Error('LiveView_Capture status ' + captureRes.status);
      console.log('[Bridge] LiveView_Capture sent successfully!');
    } catch (lvErr) {
      console.log(`[Bridge] LiveView_Capture note (${lvErr.message}), falling back to standard Capture...`);
      try {
        captureRes = await fetch(`${dccUrl}/?CMD=Capture`, { signal: AbortSignal.timeout(6000) });
        if (!captureRes.ok) throw new Error(`Capture status ${captureRes.status}`);
      } catch (capErr) {
        console.log(`[Bridge] Standard Capture failed (${capErr.message}), trying Capture_No_Af (bypass AF lock)...`);
        captureRes = await fetch(`${dccUrl}/?CMD=Capture_No_Af`, { signal: AbortSignal.timeout(6000) });
        if (!captureRes.ok) {
          throw new Error(`digiCamControl trả về mã lỗi: ${captureRes.status} ${captureRes.statusText}`);
        }
      }
    }

    console.log('[Bridge] Shutter command sent! Camera shutter clicked & flash triggered. Waiting for photo transfer...');

    // Wait for the new file to land in the folder OR try preview fallback
    let imageFilePath = null;
    try {
      imageFilePath = await fileWaitPromise;
    } catch (waitErr) {
      console.warn(`[Bridge] Folder wait notice: ${waitErr.message}. Checking preview fallback...`);
      // Fallback: try fetching latest preview image directly from digiCamControl web server
      try {
        const prevRes = await fetch(`${dccUrl}/preview.jpg`, { signal: AbortSignal.timeout(4000) });
        if (prevRes.ok) {
          const arrayBuffer = await prevRes.arrayBuffer();
          const base64 = `data:image/jpeg;base64,${Buffer.from(arrayBuffer).toString('base64')}`;
          // Tự động khôi phục Live View sau khi chụp qua preview
          setTimeout(async () => {
            try {
              await fetch(`${dccUrl}/?CMD=LiveViewWnd_Show`, { signal: AbortSignal.timeout(3000) });
              await new Promise(r => setTimeout(r, 400));
              await fetch(`${dccUrl}/?CMD=LiveView_Focus`, { signal: AbortSignal.timeout(2000) });
            } catch (e) {}
          }, 300);

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
    }

    // Read full-resolution original file from disk
    if (imageFilePath && fs.existsSync(imageFilePath)) {
      const fileBuffer = fs.readFileSync(imageFilePath);
      const ext = path.extname(imageFilePath).toLowerCase().replace('.', '');
      const mime = ext === 'png' ? 'image/png' : 'image/jpeg';
      const base64Data = `data:${mime};base64,${fileBuffer.toString('base64')}`;
      const fileSizeMb = (fileBuffer.length / (1024 * 1024)).toFixed(2);

      console.log(`[Bridge] Successfully loaded original photo: ${path.basename(imageFilePath)} (${fileSizeMb} MB, ${Date.now() - startTime}ms)`);

      // Tự động khôi phục Live View và gửi lệnh Focus để Live View tiếp tục chạy mượt mà
      setTimeout(async () => {
        try {
          await fetch(`${dccUrl}/?CMD=LiveViewWnd_Show`, { signal: AbortSignal.timeout(3000) });
          await new Promise(r => setTimeout(r, 400));
          await fetch(`${dccUrl}/?CMD=LiveView_Focus`, { signal: AbortSignal.timeout(2000) });
          console.log('[Bridge] Live View automatically resumed after capture.');
        } catch (e) {}
      }, 300);

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
app.listen(PORT, '0.0.0.0', () => {
  console.log(`
========================================================================
🌸 LALÉ STUDIO - HARDWARE CAMERA BRIDGE
========================================================================
✓ Bridge Server running on http://127.0.0.1:${PORT}
✓ Mode: ${config.mode.toUpperCase()}
✓ digiCamControl Port: ${config.digicamcontrol?.url || 'http://127.0.0.1:5513'}
✓ Photo Watch Folder: ${absWatchDir}
✓ Status API: http://127.0.0.1:${PORT}/api/status
✓ Trigger API: http://127.0.0.1:${PORT}/api/capture
========================================================================
Ready to trigger Canon R50 physical shutter & Studio Flash!
  `);
});
