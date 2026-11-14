using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Net;
using System.Runtime.InteropServices;

namespace Lalestudio.FujifilmBridge
{
    #region Data Structures & Enums

    [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Ansi)]
    public struct XSDK_DeviceInformation
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strVendor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strManufacturer;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strProduct;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strFirmware;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strDeviceType;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strSerialNo;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strFramework;
        public byte bDeviceId;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string strDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string strYNo;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Ansi)]
    public struct XSDK_ImageInformation
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string strInternalName;
        public int lFormat;
        public int lDataSize;
        public int lImagePixHeight;
        public int lImagePixWidth;
        public int lImageBitDepth;
        public int lPreviewSize;
        public IntPtr hImage;
    }

    #endregion

    #region Fujifilm SDK Wrapper Class

    public class FujiSdkNative : IDisposable
    {
        public const int XSDK_COMPLETE = 0;
        public const int XSDK_DSC_IF_USB = 1;
        public const int XSDK_DSC_MODE_TETHER = 1;

        public const int XSDK_PRIORITY_CAMERA = 0;
        public const int XSDK_PRIORITY_PC = 1;

        public const int XSDK_RELEASE_S1ON = 0x0200;
        public const int XSDK_RELEASE_N_S1OFF = 0x0004;
        public const int XSDK_RELEASE_S2 = 0x0300;
        public const int XSDK_RELEASE_S2_S1OFF = 0x0304;

        public const int XSDK_RELEASE_EX_S1_ON = 0x00010000;
        public const int XSDK_RELEASE_EX_S1_OFF = 0x00000001;
        public const int XSDK_RELEASE_EX_S2_ON = 0x00020000;
        public const int XSDK_RELEASE_EX_S2_OFF = 0x00000002;
        public const int XSDK_RELEASE_EX_S2_ON_S2_OFF_S1_OFF = 0x00020003;

        public const int XSDK_IMAGEFORMAT_NONE = 5;
        public const int XSDK_IMAGEFORMAT_RAW = 1;
        public const int XSDK_IMAGEFORMAT_JPEG = 7;
        public const int XSDK_IMAGEFORMAT_HEIF = 0x0012;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern IntPtr LoadLibrary(string lpLibFileName);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
        private static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FreeLibrary(IntPtr hModule);

        private delegate int XSDK_Init_Fn(IntPtr hLib);
        private delegate int XSDK_Exit_Fn();
        private delegate int XSDK_Detect_Fn(int lInterface, string pInterface, string pDeviceName, ref int plCount);
        private delegate int XSDK_OpenEx_Fn(string pDevice, ref IntPtr phCamera, ref int plCameraMode, IntPtr pOption);
        private delegate int XSDK_Close_Fn(IntPtr hCamera);
        private delegate int XSDK_GetDeviceInfo_Fn(IntPtr hCamera, ref XSDK_DeviceInformation pDevInfo);
        private delegate int XSDK_GetErrorNumber_Fn(IntPtr hCamera, ref int plAPICode, ref int plERRCode);
        private delegate int XSDK_SetPriorityMode_Fn(IntPtr hCamera, int lPriorityMode);
        private delegate int XSDK_GetPriorityMode_Fn(IntPtr hCamera, ref int plPriorityMode);
        private delegate int XSDK_Release_Fn(IntPtr hCamera, int lReleaseMode, ref int plShotOpt, ref int plAfStatus);
        private delegate int XSDK_ReleaseEx_Fn(IntPtr hCamera, int lReleaseMode, ref int plShotOpt, ref int plAfStatus);
        private delegate int XSDK_ReadImageInfo_Fn(IntPtr hCamera, ref XSDK_ImageInformation pImgInfo);
        private delegate int XSDK_ReadImage_Fn(IntPtr hCamera, IntPtr pData, uint lDataSize);
        private delegate int XSDK_DeleteImage_Fn(IntPtr hCamera);

        private IntPtr _hModule = IntPtr.Zero;
        private XSDK_Init_Fn _initFn;
        private XSDK_Exit_Fn _exitFn;
        private XSDK_Detect_Fn _detectFn;
        private XSDK_OpenEx_Fn _openExFn;
        private XSDK_Close_Fn _closeFn;
        private XSDK_GetDeviceInfo_Fn _getDeviceInfoFn;
        private XSDK_GetErrorNumber_Fn _getErrorNumberFn;
        private XSDK_SetPriorityMode_Fn _setPriorityModeFn;
        private XSDK_GetPriorityMode_Fn _getPriorityModeFn;
        private XSDK_Release_Fn _releaseFn;
        private XSDK_ReleaseEx_Fn _releaseExFn;
        private XSDK_ReadImageInfo_Fn _readImageInfoFn;
        private XSDK_ReadImage_Fn _readImageFn;
        private XSDK_DeleteImage_Fn _deleteImageFn;

        private IntPtr _hCamera = IntPtr.Zero;
        private bool _isSdkInitialized = false;

        public bool IsLoaded { get { return _hModule != IntPtr.Zero; } }
        public bool IsConnected { get { return _hCamera != IntPtr.Zero; } }
        public string LastError { get; private set; }

        public FujiSdkNative(string dllDirectory = null)
        {
            string baseDir = string.IsNullOrEmpty(dllDirectory)
                ? AppDomain.CurrentDomain.BaseDirectory
                : dllDirectory;

            string dllPath = Path.Combine(baseDir, "XAPI.dll");
            if (!File.Exists(dllPath))
            {
                // Fallback to current directory
                dllPath = "XAPI.dll";
            }

            _hModule = LoadLibrary(dllPath);
            if (_hModule == IntPtr.Zero)
            {
                int err = Marshal.GetLastWin32Error();
                LastError = string.Format("Cannot load XAPI.dll from {0} (Win32 Error: {1})", dllPath, err);
                return;
            }

            _initFn = GetDelegate<XSDK_Init_Fn>("XSDK_Init");
            _exitFn = GetDelegate<XSDK_Exit_Fn>("XSDK_Exit");
            _detectFn = GetDelegate<XSDK_Detect_Fn>("XSDK_Detect");
            _openExFn = GetDelegate<XSDK_OpenEx_Fn>("XSDK_OpenEx");
            _closeFn = GetDelegate<XSDK_Close_Fn>("XSDK_Close");
            _getDeviceInfoFn = GetDelegate<XSDK_GetDeviceInfo_Fn>("XSDK_GetDeviceInfo");
            _getErrorNumberFn = GetDelegate<XSDK_GetErrorNumber_Fn>("XSDK_GetErrorNumber");
            _setPriorityModeFn = GetDelegate<XSDK_SetPriorityMode_Fn>("XSDK_SetPriorityMode");
            _getPriorityModeFn = GetDelegate<XSDK_GetPriorityMode_Fn>("XSDK_GetPriorityMode");
            _releaseFn = GetDelegate<XSDK_Release_Fn>("XSDK_Release");
            _releaseExFn = GetDelegate<XSDK_ReleaseEx_Fn>("XSDK_ReleaseEx");
            _readImageInfoFn = GetDelegate<XSDK_ReadImageInfo_Fn>("XSDK_ReadImageInfo");
            _readImageFn = GetDelegate<XSDK_ReadImage_Fn>("XSDK_ReadImage");
            _deleteImageFn = GetDelegate<XSDK_DeleteImage_Fn>("XSDK_DeleteImage");
        }

        private T GetDelegate<T>(string procName) where T : class
        {
            IntPtr p = GetProcAddress(_hModule, procName);
            if (p == IntPtr.Zero) return null;
            return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
        }

        public bool InitializeSdk()
        {
            if (!IsLoaded) return false;
            if (_isSdkInitialized) return true;

            if (_initFn != null)
            {
                int ret = _initFn(IntPtr.Zero);
                if (ret == XSDK_COMPLETE)
                {
                    _isSdkInitialized = true;
                    return true;
                }
                LastError = string.Format("XSDK_Init failed with code {0}", ret);
                return false;
            }
            return false;
        }

        public bool ConnectCamera(out XSDK_DeviceInformation devInfo)
        {
            devInfo = new XSDK_DeviceInformation();

            if (!InitializeSdk()) return false;

            if (_detectFn == null || _openExFn == null)
            {
                LastError = "Required SDK functions not found";
                return false;
            }

            int count = 0;
            int detRet = _detectFn(XSDK_DSC_IF_USB, null, null, ref count);
            if (detRet != XSDK_COMPLETE || count <= 0)
            {
                LastError = string.Format("No Fujifilm camera detected on USB (Count: {0}, Ret: {1})", count, detRet);
                return false;
            }

            int mode = 0;
            int openRet = _openExFn("ENUM:0", ref _hCamera, ref mode, IntPtr.Zero);
            if (openRet != XSDK_COMPLETE || _hCamera == IntPtr.Zero)
            {
                LastError = string.Format("XSDK_OpenEx failed with code {0}", openRet);
                _hCamera = IntPtr.Zero;
                return false;
            }

            if (_getDeviceInfoFn != null)
            {
                int infoRet = _getDeviceInfoFn(_hCamera, ref devInfo);
                if (infoRet != XSDK_COMPLETE)
                {
                    LastError = string.Format("XSDK_GetDeviceInfo failed with code {0}", infoRet);
                }
            }

            return true;
        }

        public void DisconnectCamera()
        {
            if (_hCamera != IntPtr.Zero && _closeFn != null)
            {
                try { _closeFn(_hCamera); } catch { }
                _hCamera = IntPtr.Zero;
                Thread.Sleep(300);
            }
        }

        public bool TriggerFocus()
        {
            if (_hCamera == IntPtr.Zero)
            {
                XSDK_DeviceInformation dummy;
                if (!ConnectCamera(out dummy)) return false;
            }

            int shotOpt = 1;
            int status = 0;
            int ret = -1;

            if (_releaseFn != null)
            {
                ret = _releaseFn(_hCamera, XSDK_RELEASE_S1ON, ref shotOpt, ref status);
                Thread.Sleep(280);
                _releaseFn(_hCamera, XSDK_RELEASE_N_S1OFF, ref shotOpt, ref status);
            }
            else if (_releaseExFn != null)
            {
                ret = _releaseExFn(_hCamera, XSDK_RELEASE_EX_S1_ON, ref shotOpt, ref status);
                Thread.Sleep(280);
                _releaseExFn(_hCamera, XSDK_RELEASE_EX_S1_OFF, ref shotOpt, ref status);
            }

            return ret == XSDK_COMPLETE;
        }

        public byte[] CapturePhoto(bool autoFocus, out string resolution, int timeoutSeconds = 12)
        {
            resolution = "6240x4160 (26.1 MP)";

            if (_hCamera == IntPtr.Zero)
            {
                XSDK_DeviceInformation dummy;
                if (!ConnectCamera(out dummy))
                {
                    throw new Exception("Cannot connect to Fujifilm camera: " + LastError);
                }
            }

            int shotOpt = 1;
            int status = 0;

            // Optional Pre-focus
            if (autoFocus)
            {
                try
                {
                    if (_releaseFn != null)
                    {
                        _releaseFn(_hCamera, XSDK_RELEASE_S1ON, ref shotOpt, ref status);
                        Thread.Sleep(250);
                    }
                }
                catch { }
            }

            // Trigger shutter & strobe flash
            int releaseRet = -1;
            if (_releaseExFn != null)
            {
                releaseRet = _releaseExFn(_hCamera, XSDK_RELEASE_EX_S2_ON_S2_OFF_S1_OFF, ref shotOpt, ref status);
            }
            if (releaseRet != XSDK_COMPLETE && _releaseFn != null)
            {
                releaseRet = _releaseFn(_hCamera, XSDK_RELEASE_S2_S1OFF, ref shotOpt, ref status);
            }

            if (releaseRet != XSDK_COMPLETE)
            {
                throw new Exception(string.Format("Fujifilm shutter release failed (Code: {0}, Status: {1})", releaseRet, status));
            }

            // Poll for newly captured image
            DateTime startWait = DateTime.Now;
            XSDK_ImageInformation imgInfo = new XSDK_ImageInformation();

            while ((DateTime.Now - startWait).TotalSeconds < timeoutSeconds)
            {
                Thread.Sleep(150);

                if (_readImageInfoFn != null)
                {
                    imgInfo = new XSDK_ImageInformation();
                    imgInfo.lFormat = XSDK_IMAGEFORMAT_NONE;
                    int readInfoRet = _readImageInfoFn(_hCamera, ref imgInfo);

                    if (readInfoRet == XSDK_COMPLETE && imgInfo.lDataSize > 1000 && (imgInfo.lFormat & 0xFF) != XSDK_IMAGEFORMAT_NONE)
                    {
                        byte[] buffer = new byte[imgInfo.lDataSize];
                        GCHandle handle = GCHandle.Alloc(buffer, GCHandleType.Pinned);
                        try
                        {
                            IntPtr ptr = handle.AddrOfPinnedObject();
                            int readRet = _readImageFn(_hCamera, ptr, (uint)imgInfo.lDataSize);

                            if (_deleteImageFn != null)
                            {
                                _deleteImageFn(_hCamera);
                            }

                            if (readRet == XSDK_COMPLETE)
                            {
                                if (imgInfo.lImagePixWidth > 0 && imgInfo.lImagePixHeight > 0)
                                {
                                    resolution = string.Format("{0}x{1} (26.1 MP)", imgInfo.lImagePixWidth, imgInfo.lImagePixHeight);
                                }
                                return buffer;
                            }
                        }
                        finally
                        {
                            handle.Free();
                        }
                    }
                }
            }

            throw new TimeoutException("Hết thời gian chờ ảnh từ máy ảnh Fujifilm (quá " + timeoutSeconds + "s)");
        }

        public void Dispose()
        {
            DisconnectCamera();

            if (_isSdkInitialized && _exitFn != null)
            {
                try { _exitFn(); } catch { }
                _isSdkInitialized = false;
            }

            if (_hModule != IntPtr.Zero)
            {
                try { FreeLibrary(_hModule); } catch { }
                _hModule = IntPtr.Zero;
            }
        }
    }

    #endregion

    #region Console & HTTP Daemon Entry Point

    class Program
    {
        static void Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;

            if (args.Length == 0)
            {
                PrintHelp();
                return;
            }

            string command = args[0].ToLowerInvariant();

            // 1. DAEMON MODE: Persistent HTTP API Server (Default Port: 5514)
            if (command == "daemon" || command == "server")
            {
                int port = 5514;
                if (args.Length > 1) int.TryParse(args[1], out port);
                RunHttpDaemon(port);
                return;
            }

            // 2. ONE-SHOT CLI MODES
            using (FujiSdkNative sdk = new FujiSdkNative())
            {
                if (!sdk.IsLoaded)
                {
                    OutputJson(false, "Cannot load XAPI.dll: " + sdk.LastError);
                    return;
                }

                switch (command)
                {
                    case "status":
                        HandleStatus(sdk);
                        break;

                    case "focus":
                        HandleFocus(sdk);
                        break;

                    case "capture":
                        string saveDir = args.Length > 1 ? args[1] : @"C:\LalePhotos";
                        string orderCode = args.Length > 2 ? args[2] : "LALE";
                        bool noAf = args.Length > 3 && args[3] == "--no-af";
                        HandleCapture(sdk, saveDir, orderCode, !noAf);
                        break;

                    default:
                        PrintHelp();
                        break;
                }
            }
        }

        static void HandleStatus(FujiSdkNative sdk)
        {
            XSDK_DeviceInformation devInfo;
            bool connected = sdk.ConnectCamera(out devInfo);

            if (connected)
            {
                string model = string.IsNullOrEmpty(devInfo.strProduct) ? "FUJIFILM X-T4" : devInfo.strProduct.Trim();
                string fw = string.IsNullOrEmpty(devInfo.strFirmware) ? "" : devInfo.strFirmware.Trim();
                string serial = string.IsNullOrEmpty(devInfo.strSerialNo) ? "" : devInfo.strSerialNo.Trim();

                Console.WriteLine("{{\"success\":true,\"connected\":true,\"cameraName\":\"{0}\",\"model\":\"{0}\",\"firmware\":\"{1}\",\"serial\":\"{2}\"}}",
                    EscapeJson(model), EscapeJson(fw), EscapeJson(serial));
            }
            else
            {
                Console.WriteLine("{{\"success\":false,\"connected\":false,\"cameraName\":null,\"error\":\"{0}\"}}",
                    EscapeJson(sdk.LastError ?? "Chưa phát hiện máy ảnh Fujifilm cắm qua USB"));
            }
        }

        static void HandleFocus(FujiSdkNative sdk)
        {
            XSDK_DeviceInformation devInfo;
            if (!sdk.ConnectCamera(out devInfo))
            {
                OutputJson(false, "Không thể kết nối máy ảnh Fujifilm: " + sdk.LastError);
                return;
            }

            bool focused = sdk.TriggerFocus();
            if (focused)
            {
                Console.WriteLine("{\"success\":true,\"message\":\"Đã kích hoạt lấy nét tự động (FUJIFILM AF)\"}");
            }
            else
            {
                OutputJson(false, "Lỗi kích hoạt lấy nét tự động: " + sdk.LastError);
            }
        }

        static void HandleCapture(FujiSdkNative sdk, string saveDir, string orderCode, bool autoFocus)
        {
            if (!Directory.Exists(saveDir))
            {
                try { Directory.CreateDirectory(saveDir); } catch { }
            }

            XSDK_DeviceInformation devInfo;
            if (!sdk.ConnectCamera(out devInfo))
            {
                OutputJson(false, "Không thể kết nối máy ảnh Fujifilm: " + sdk.LastError);
                return;
            }

            string model = string.IsNullOrEmpty(devInfo.strProduct) ? "FUJIFILM X-T4" : devInfo.strProduct.Trim();

            long startTime = Environment.TickCount;
            string resolution;
            byte[] photoBytes = sdk.CapturePhoto(autoFocus, out resolution);

            string filename = string.Format("{0}_{1}_original.jpg", orderCode, DateTime.Now.Ticks);
            string fullPath = Path.Combine(saveDir, filename);

            File.WriteAllBytes(fullPath, photoBytes);

            string base64 = "data:image/jpeg;base64," + Convert.ToBase64String(photoBytes);
            double sizeMb = Math.Round((double)photoBytes.Length / (1024 * 1024), 2);
            long elapsedMs = Environment.TickCount - startTime;

            Console.WriteLine("{{\"success\":true,\"source\":\"{0} Original File\",\"cameraName\":\"{0}\",\"filename\":\"{1}\",\"filePath\":\"{2}\",\"fileSizeBytes\":{3},\"fileSizeMb\":\"{4} MB\",\"resolution\":\"{5}\",\"elapsedMs\":{6},\"imageData\":\"{7}\"}}",
                EscapeJson(model),
                EscapeJson(filename),
                EscapeJson(fullPath.Replace("\\", "\\\\")),
                photoBytes.Length,
                sizeMb,
                EscapeJson(resolution),
                elapsedMs,
                base64);
        }

        static void RunHttpDaemon(int port)
        {
            HttpListener listener = new HttpListener();
            string prefix = string.Format("http://127.0.0.1:{0}/", port);
            listener.Prefixes.Add(prefix);

            try
            {
                listener.Start();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("[FujiBridge Daemon] Error starting HTTP listener on port " + port + ": " + ex.Message);
                return;
            }

            Console.WriteLine("========================================================================");
            Console.WriteLine(" 🌸 LALE STUDIO - FUJIFILM CAMERA BRIDGE DAEMON (NATIVE 64-BIT)");
            Console.WriteLine(" Port: " + prefix);
            Console.WriteLine(" Sẵn sàng kích nổ màn trập cơ học FUJIFILM X-T4 & Flash Studio!");
            Console.WriteLine("========================================================================");

            using (FujiSdkNative sdk = new FujiSdkNative())
            {
                if (!sdk.IsLoaded)
                {
                    Console.Error.WriteLine("[FujiBridge Daemon] ⚠️ Cannot load XAPI.dll: " + sdk.LastError);
                }

                XSDK_DeviceInformation devInfo = new XSDK_DeviceInformation();
                bool connected = sdk.ConnectCamera(out devInfo);
                if (connected)
                {
                    Console.WriteLine("[FujiBridge Daemon] ✓ Đã kết nối với máy ảnh: " + (devInfo.strProduct ?? "FUJIFILM"));
                }
                else
                {
                    Console.WriteLine("[FujiBridge Daemon] Đang chờ kết nối máy ảnh Fujifilm qua USB...");
                }

                while (listener.IsListening)
                {
                    HttpListenerContext ctx = null;
                    try
                    {
                        ctx = listener.GetContext();
                    }
                    catch { break; }

                    ThreadPool.QueueUserWorkItem((state) =>
                    {
                        var context = (HttpListenerContext)state;
                        try
                        {
                            HandleDaemonRequest(context, sdk);
                        }
                        catch (Exception ex)
                        {
                            try
                            {
                                SendJson(context.Response, 500, string.Format("{{\"success\":false,\"error\":\"{0}\"}}", EscapeJson(ex.Message)));
                            }
                            catch { }
                        }
                    }, ctx);
                }
            }
        }

        static void HandleDaemonRequest(HttpListenerContext ctx, FujiSdkNative sdk)
        {
            HttpListenerRequest req = ctx.Request;
            HttpListenerResponse res = ctx.Response;
            string rawUrl = req.RawUrl.ToLowerInvariant();

            // Handle CORS OPTIONS
            if (req.HttpMethod == "OPTIONS")
            {
                res.StatusCode = 204;
                res.Headers.Add("Access-Control-Allow-Origin", "*");
                res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
                res.Headers.Add("Access-Control-Allow-Headers", "Content-Type");
                res.Close();
                return;
            }

            // 1. GET /api/status or /status
            if (rawUrl.StartsWith("/api/status") || rawUrl == "/status")
            {
                lock (sdk)
                {
                    XSDK_DeviceInformation devInfo;
                    bool connected = sdk.IsConnected;
                    if (!connected)
                    {
                        connected = sdk.ConnectCamera(out devInfo);
                    }
                    else
                    {
                        devInfo = new XSDK_DeviceInformation();
                        devInfo.strProduct = "FUJIFILM X-T4";
                    }

                    string model = (connected && !string.IsNullOrEmpty(devInfo.strProduct)) ? devInfo.strProduct.Trim() : "FUJIFILM X-T4";
                    string json = string.Format("{{\"success\":true,\"bridgeOnline\":true,\"connected\":{0},\"cameraConnected\":{0},\"cameraName\":\"{1}\",\"model\":\"{1}\"}}",
                        connected ? "true" : "false",
                        EscapeJson(model));
                    SendJson(res, 200, json);
                }
                return;
            }

            // 2. ALL /api/focus or /focus
            if (rawUrl.StartsWith("/api/focus") || rawUrl == "/focus")
            {
                lock (sdk)
                {
                    bool ok = sdk.TriggerFocus();
                    string json = string.Format("{{\"success\":{0},\"message\":\"{1}\"}}",
                        ok ? "true" : "false",
                        ok ? "Đã kích hoạt lấy nét tự động Fujifilm" : EscapeJson(sdk.LastError ?? "Lấy nét thất bại"));
                    SendJson(res, ok ? 200 : 500, json);
                }
                return;
            }

            // 3. POST /api/capture or /capture
            if (rawUrl.StartsWith("/api/capture") || rawUrl == "/capture")
            {
                string orderCode = "LALE";
                string saveDir = @"C:\LalePhotos";
                bool autoFocus = true;

                if (req.HasEntityBody)
                {
                    using (StreamReader reader = new StreamReader(req.InputStream, req.ContentEncoding))
                    {
                        string body = reader.ReadToEnd();
                        if (!string.IsNullOrEmpty(body))
                        {
                            orderCode = ExtractJsonString(body, "orderCode") ?? orderCode;
                            saveDir = ExtractJsonString(body, "photoSaveDir") ?? saveDir;
                            string afStr = ExtractJsonString(body, "autoFocus");
                            if (afStr == "false") autoFocus = false;
                        }
                    }
                }

                lock (sdk)
                {
                    if (!Directory.Exists(saveDir))
                    {
                        try { Directory.CreateDirectory(saveDir); } catch { }
                    }

                    long startTime = Environment.TickCount;
                    string resolution;
                    byte[] photoBytes = sdk.CapturePhoto(autoFocus, out resolution);

                    string filename = string.Format("{0}_{1}_original.jpg", orderCode, DateTime.Now.Ticks);
                    string fullPath = Path.Combine(saveDir, filename);

                    File.WriteAllBytes(fullPath, photoBytes);

                    string base64 = "data:image/jpeg;base64," + Convert.ToBase64String(photoBytes);
                    double sizeMb = Math.Round((double)photoBytes.Length / (1024 * 1024), 2);
                    long elapsedMs = Environment.TickCount - startTime;

                    string json = string.Format("{{\"success\":true,\"source\":\"FUJIFILM X-T4 Original File\",\"cameraName\":\"FUJIFILM X-T4\",\"filename\":\"{0}\",\"filePath\":\"{1}\",\"fileSizeBytes\":{2},\"fileSizeMb\":\"{3} MB\",\"resolution\":\"{4}\",\"elapsedMs\":{5},\"imageData\":\"{6}\"}}",
                        EscapeJson(filename),
                        EscapeJson(fullPath.Replace("\\", "\\\\")),
                        photoBytes.Length,
                        sizeMb,
                        EscapeJson(resolution),
                        elapsedMs,
                        base64);

                    SendJson(res, 200, json);
                }
                return;
            }

            SendJson(res, 404, "{\"error\":\"Not Found\"}");
        }

        static void SendJson(HttpListenerResponse res, int statusCode, string json)
        {
            try
            {
                byte[] buf = Encoding.UTF8.GetBytes(json);
                res.StatusCode = statusCode;
                res.ContentType = "application/json; charset=utf-8";
                res.Headers.Add("Access-Control-Allow-Origin", "*");
                res.ContentLength64 = buf.Length;
                res.OutputStream.Write(buf, 0, buf.Length);
                res.OutputStream.Close();
            }
            catch { }
        }

        static string ExtractJsonString(string json, string key)
        {
            string pattern = "\"" + key + "\"\\s*:\\s*\"?([^\"\\,\\}\\s]+)";
            var match = System.Text.RegularExpressions.Regex.Match(json, pattern);
            if (match.Success) return match.Groups[1].Value;
            return null;
        }

        static void OutputJson(bool success, string message)
        {
            Console.WriteLine("{{\"success\":{0},\"message\":\"{1}\"}}",
                success ? "true" : "false",
                EscapeJson(message));
        }

        static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "").Replace("\n", " ");
        }

        static void PrintHelp()
        {
            Console.WriteLine("Lale Studio - Fujifilm Camera Control Bridge (Windows 64-bit)");
            Console.WriteLine("Usage:");
            Console.WriteLine("  fuji_bridge.exe status");
            Console.WriteLine("  fuji_bridge.exe focus");
            Console.WriteLine("  fuji_bridge.exe capture [saveDir] [orderCode] [--no-af]");
            Console.WriteLine("  fuji_bridge.exe daemon [port (default 5514)]");
        }
    }

    #endregion
}
