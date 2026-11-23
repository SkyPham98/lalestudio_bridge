using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Net;
using System.Runtime.InteropServices;
using System.Collections.Generic;

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

        // Priority Mode (theo XAPI.H chinh thuc: CAMERA = 1, PC = 2)
        public const int XSDK_PRIORITY_CAMERA = 1;
        public const int XSDK_PRIORITY_PC = 2;

        // Release Modes
        public const int XSDK_RELEASE_SHOOT = 0x0100;
        public const int XSDK_RELEASE_S1ON = 0x0200;
        public const int XSDK_RELEASE_N_S1OFF = 0x0004;
        public const int XSDK_RELEASE_S2 = 0x0300;
        public const int XSDK_RELEASE_S2_S1OFF = 0x0304;
        public const int XSDK_RELEASE_SHOOT_S1OFF = 0x0104;

        // Release Modes Ex
        public const int XSDK_RELEASE_EX_S1_ON = 0x00010000;
        public const int XSDK_RELEASE_EX_S1_OFF = 0x00000001;
        public const int XSDK_RELEASE_EX_S2_ON = 0x00020000;
        public const int XSDK_RELEASE_EX_S2_OFF = 0x00000002;
        public const int XSDK_RELEASE_EX_S2_ON_S2_OFF_S1_OFF = 0x00020003;
        public const int XSDK_RELEASE_EX_S1_ON_S2_ON_S2_OFF_S1_OFF = 0x00030003;

        // Image Formats
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
        private delegate int XSDK_GetErrorDetails_Fn(IntPtr hCamera, ref int plERRCode);
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
        private XSDK_GetErrorDetails_Fn _getErrorDetailsFn;
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

        public static void Log(string msg)
        {
            string line = string.Format("[{0:HH:mm:ss.fff}] {1}", DateTime.Now, msg);
            Console.Error.WriteLine(line);
        }

        public static string DecodeErrorCode(int errCode)
        {
            switch (errCode)
            {
                case 0x0000: return "NOERR (Khong co loi)";
                case 0x1001: return "SEQUENCE (Sai thu tu ham goi SDK - Camera chua san sang nhan lenh nay)";
                case 0x1002: return "PARAM (Tham so dau vao khong hop le)";
                case 0x1003: return "INVALID_CAMERA (Handle may anh khong hop le hoac da bi dong)";
                case 0x1004: return "LOADLIB (Loi nap thu vien con cua dong may anh)";
                case 0x1005: return "UNSUPPORTED (Lenh khong duoc ho tro boi dong may nay)";
                case 0x1006: return "BUSY (May anh dang ban ghi the nho hoac xu ly tac vu khac)";
                case 0x1007: return "AF_TIMEOUT (Lay net that bai / Khong bat duoc net - Hay bat den studio hoac chuyen sang Manual Focus)";
                case 0x1008: return "SHOOT_ERROR (May anh tu choi bam chup! Kiem tra: 1. Can gat MOVIE/STILL duoi dia toc do phai o STILL; 2. The nho SD bi khoa/chua cam va SHOOT WITHOUT CARD dang OFF; 3. Vong xoay Drive phai o nac S; 4. AF-S PRIORITY SELECTION nen chon RELEASE)";
                case 0x1009: return "FRAME_FULL (Bo dem chup cua may anh da day)";
                case 0x1010: return "STANDBY (May anh dang o che do ngu tiet kiem pin Standby/Sleep)";
                case 0x1011: return "NODRIVER (Chua cai driver hoac may tinh khong nhan driver Fujifilm)";
                case 0x1012: return "NO_MODEL_MODULE (Thieu module dll cua model may trong thu muc)";
                case 0x1013: return "RECOGNIZE_FAIL (Khong nhan dien duoc may anh)";
                case 0x1014: return "CONNECT_FAIL (Ket noi that bai)";
                case 0x1015: return "INVALID_USBMODE (CHE DO USB SAI! Vao Menu may anh -> CONNECTION SETTING -> CONNECTION MODE -> Chon 'USB TETHER SHOOTING AUTO' hoac 'FIXED')";
                case 0x1016: return "FORCEMODE_BUSY (May anh dang ban)";
                case 0x1017: return "RUNNING_OTHER_FUNCTION (May anh dang ban chuc nang khac)";
                case 0x2001: return "COMMUNICATION (Loi giao tiep cap USB - Cap long hoac nhieu tin hieu)";
                case 0x2002: return "TIMEOUT (Qua thoi gian cho phan hoi tu may anh)";
                case 0x2003: return "COMBINATION (Thiet lap thong so may anh khong tuong thich)";
                case 0x2004: return "WRITEERROR (Loi ghi du lieu)";
                case 0x2005: return "CARDFULL (The nho trong may anh Fujifilm da day!)";
                case 0x3001: return "HARDWARE (Loi phan cung may anh hoac ong kinh)";
                case 0x9001: return "INTERNAL (Loi noi bo SDK)";
                case 0x9002: return "MEMFULL (Het bo nho RAM may tinh)";
                default: return string.Format("Ma loi SDK: 0x{0:X4}", errCode);
            }
        }

        public static string DecodeErrorDetails(int details)
        {
            var list = new List<string>();
            if ((details & 0x0001) != 0) list.Add("S1_PRESSED");
            if ((details & 0x0002) != 0) list.Add("AEL_ACTIVE");
            if ((details & 0x0004) != 0) list.Add("AFL_ACTIVE");
            if ((details & 0x0010) != 0) list.Add("AFON_ACTIVE");
            if ((details & 0x0020) != 0) list.Add("SHOOTING_IN_PROGRESS");
            if ((details & 0x0080) != 0) list.Add("RECORDING");
            if ((details & 0x0100) != 0) list.Add("LIVEVIEW_ACTIVE");
            if ((details & 0x0200) != 0) list.Add("UNTRANSFERRED_IMAGE_PENDING");
            if (list.Count == 0) return "NORMAL";
            return string.Join(" | ", list.ToArray());
        }

        public FujiSdkNative(string dllDirectory = null)
        {
            string baseDir = string.IsNullOrEmpty(dllDirectory)
                ? AppDomain.CurrentDomain.BaseDirectory
                : dllDirectory;

            string dllPath = Path.Combine(baseDir, "XAPI.dll");
            if (!File.Exists(dllPath))
            {
                dllPath = "XAPI.dll";
            }

            Log("[SDK LOAD] Dang nap thu vien: " + dllPath);
            _hModule = LoadLibrary(dllPath);
            if (_hModule == IntPtr.Zero)
            {
                int err = Marshal.GetLastWin32Error();
                LastError = string.Format("Khong the nap XAPI.dll tu {0} (Win32 Error: {1})", dllPath, err);
                Log("[SDK LOAD LOI] " + LastError);
                return;
            }

            _initFn = GetDelegate<XSDK_Init_Fn>("XSDK_Init");
            _exitFn = GetDelegate<XSDK_Exit_Fn>("XSDK_Exit");
            _detectFn = GetDelegate<XSDK_Detect_Fn>("XSDK_Detect");
            _openExFn = GetDelegate<XSDK_OpenEx_Fn>("XSDK_OpenEx");
            _closeFn = GetDelegate<XSDK_Close_Fn>("XSDK_Close");
            _getDeviceInfoFn = GetDelegate<XSDK_GetDeviceInfo_Fn>("XSDK_GetDeviceInfo");
            _getErrorNumberFn = GetDelegate<XSDK_GetErrorNumber_Fn>("XSDK_GetErrorNumber");
            _getErrorDetailsFn = GetDelegate<XSDK_GetErrorDetails_Fn>("XSDK_GetErrorDetails");
            _setPriorityModeFn = GetDelegate<XSDK_SetPriorityMode_Fn>("XSDK_SetPriorityMode");
            _getPriorityModeFn = GetDelegate<XSDK_GetPriorityMode_Fn>("XSDK_GetPriorityMode");
            _releaseFn = GetDelegate<XSDK_Release_Fn>("XSDK_Release");
            _releaseExFn = GetDelegate<XSDK_ReleaseEx_Fn>("XSDK_ReleaseEx");
            _readImageInfoFn = GetDelegate<XSDK_ReadImageInfo_Fn>("XSDK_ReadImageInfo");
            _readImageFn = GetDelegate<XSDK_ReadImage_Fn>("XSDK_ReadImage");
            _deleteImageFn = GetDelegate<XSDK_DeleteImage_Fn>("XSDK_DeleteImage");

            Log("[SDK LOAD THANH CONG] Da lien ket day du cac ham API tu XAPI.dll (64-bit)");
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
                Log("[SDK INIT] Dang khoi tao he thong SDK (XSDK_Init)...");
                int ret = _initFn(IntPtr.Zero);
                if (ret == XSDK_COMPLETE)
                {
                    _isSdkInitialized = true;
                    Log("[SDK INIT THANH CONG] XSDK_Init hoan tat (Ret=0)");
                    return true;
                }
                LastError = string.Format("XSDK_Init that bai voi ma loi {0}", ret);
                Log("[SDK INIT LOI] " + LastError);
                return false;
            }
            return false;
        }

        public bool ConnectCamera(out XSDK_DeviceInformation devInfo)
        {
            devInfo = new XSDK_DeviceInformation();

            Log("[CONNECT] Bat dau ket noi may anh Fujifilm...");
            if (!InitializeSdk())
            {
                Log("[CONNECT LOI] InitializeSdk that bai: " + LastError);
                return false;
            }

            if (_detectFn == null || _openExFn == null)
            {
                LastError = "Khong tim thay ham XSDK_Detect hoac XSDK_OpenEx trong XAPI.dll";
                Log("[CONNECT LOI] " + LastError);
                return false;
            }

            int count = 0;
            int detRet = _detectFn(XSDK_DSC_IF_USB, null, null, ref count);
            Log(string.Format("[CONNECT] Do tim may anh qua cong USB (XSDK_Detect): Ret={0}, So may tim thay={1}", detRet, count));

            if (detRet != XSDK_COMPLETE || count <= 0)
            {
                LastError = string.Format("Khong tim thay may anh Fujifilm nao qua USB (Count={0}, Ret={1}). Vui long kiem tra: Menu may anh -> CONNECTION SETTING -> CONNECTION MODE -> chon 'USB TETHER SHOOTING AUTO'.", count, detRet);
                Log("[CONNECT CANH BAO] " + LastError);
                return false;
            }

            int mode = 0;
            int openRet = _openExFn("ENUM:0", ref _hCamera, ref mode, IntPtr.Zero);
            Log(string.Format("[CONNECT] Mo phien giao tiep camera (XSDK_OpenEx 'ENUM:0'): Ret={0}, Handle=0x{1:X}, Mode={2}",
                openRet, _hCamera.ToInt64(), mode));

            if (openRet != XSDK_COMPLETE || _hCamera == IntPtr.Zero)
            {
                int apiCode = 0, errCode = 0;
                if (_getErrorNumberFn != null) _getErrorNumberFn(IntPtr.Zero, ref apiCode, ref errCode);
                LastError = string.Format("XSDK_OpenEx that bai (Ret={0}, ErrCode=0x{1:X} - {2})", openRet, errCode, DecodeErrorCode(errCode));
                Log("[CONNECT LOI] " + LastError);
                _hCamera = IntPtr.Zero;
                return false;
            }

            if (_getDeviceInfoFn != null)
            {
                int infoRet = _getDeviceInfoFn(_hCamera, ref devInfo);
                Log(string.Format("[CONNECT] Thong tin may anh: Model='{0}', Serial='{1}', Firmware='{2}', Ret={3}",
                    devInfo.strProduct, devInfo.strSerialNo, devInfo.strFirmware, infoRet));
            }

            // Thiet lap quyen dieu khien PC (XSDK_PRIORITY_PC = 2)
            if (_setPriorityModeFn != null)
            {
                EnsurePriorityMode(XSDK_PRIORITY_PC);
            }

            Log("[CONNECT THANH CONG] May anh Fujifilm da ket noi va san sang hoat dong!");
            return true;
        }

        private bool EnsurePriorityMode(int targetMode)
        {
            if (_setPriorityModeFn == null || _hCamera == IntPtr.Zero) return false;

            // Kiem tra priority hien tai neu co the
            if (_getPriorityModeFn != null)
            {
                int curPrio = 0;
                if (_getPriorityModeFn(_hCamera, ref curPrio) == XSDK_COMPLETE && curPrio == targetMode)
                {
                    Log(string.Format("[PRIORITY] Camera da o che do PC (PriorityMode=0x{0:X})", curPrio));
                    return true;
                }
            }

            int lastRet = _setPriorityModeFn(_hCamera, targetMode);
            if (lastRet == XSDK_COMPLETE)
            {
                Log("[PRIORITY] Thiet lap thanh cong quyen dieu khien PC (Ret=0)");
                return true;
            }

            // Neu chua thanh cong, thu them 1 lan nua sau 10ms (khong loop blocking)
            Thread.Sleep(10);
            lastRet = _setPriorityModeFn(_hCamera, targetMode);
            if (lastRet == XSDK_COMPLETE)
            {
                Log("[PRIORITY] Thiet lap thanh cong quyen dieu khien PC lan 2 (Ret=0)");
                return true;
            }

            int apiCode = 0, lastErr = 0;
            if (_getErrorNumberFn != null) _getErrorNumberFn(_hCamera, ref apiCode, ref lastErr);
            Log(string.Format("[PRIORITY] Ghi chu: SetPriorityMode Ret={0}, ErrCode=0x{1:X} (Bo qua de ban man trap ngay lap tuc)",
                lastRet, lastErr));
            return false;
        }

        public void DisconnectCamera()
        {
            if (_hCamera != IntPtr.Zero && _closeFn != null)
            {
                Log(string.Format("[DISCONNECT] Dong phien may anh Fujifilm Handle=0x{0:X}...", _hCamera.ToInt64()));
                try { _closeFn(_hCamera); } catch { }
                _hCamera = IntPtr.Zero;
                Thread.Sleep(300);
            }
        }

        public bool TriggerFocus()
        {
            Log("[FOCUS] Nhan yeu cau lay net tu dong (Autofocus)...");
            if (_hCamera == IntPtr.Zero)
            {
                XSDK_DeviceInformation dummy;
                if (!ConnectCamera(out dummy))
                {
                    Log("[FOCUS LOI] Khong the ket noi may anh: " + LastError);
                    return false;
                }
            }

            // Dam bao quyen PC
            if (_setPriorityModeFn != null)
            {
                _setPriorityModeFn(_hCamera, XSDK_PRIORITY_PC);
            }

            int shotOpt = 1;
            int status = 0;
            int ret = -1;

            if (_releaseFn != null)
            {
                Log("[FOCUS] Gui lenh S1ON (an nua co lay net)...");
                ret = _releaseFn(_hCamera, XSDK_RELEASE_S1ON, ref shotOpt, ref status);
                Log(string.Format("[FOCUS] Ket qua S1ON: Ret={0}, ShotOpt={1}, Status={2} (1=AF OK, 0=AF Fail)", ret, shotOpt, status));
                Thread.Sleep(280);
                _releaseFn(_hCamera, XSDK_RELEASE_N_S1OFF, ref shotOpt, ref status);
                Log("[FOCUS] Nha S1OFF hoan tat.");
            }
            else if (_releaseExFn != null)
            {
                Log("[FOCUS] Gui lenh ReleaseEx S1_ON...");
                ret = _releaseExFn(_hCamera, XSDK_RELEASE_EX_S1_ON, ref shotOpt, ref status);
                Log(string.Format("[FOCUS] Ket qua S1_ON: Ret={0}, ShotOpt={1}, Status={2}", ret, shotOpt, status));
                Thread.Sleep(280);
                _releaseExFn(_hCamera, XSDK_RELEASE_EX_S1_OFF, ref shotOpt, ref status);
            }

            if (ret != XSDK_COMPLETE)
            {
                int apiCode = 0, errCode = 0;
                if (_getErrorNumberFn != null) _getErrorNumberFn(_hCamera, ref apiCode, ref errCode);
                LastError = string.Format("Loi lay net: Ret={0}, ErrCode=0x{1:X} ({2})", ret, errCode, DecodeErrorCode(errCode));
                Log("[FOCUS LOI] " + LastError);
                return false;
            }

            Log("[FOCUS THANH CONG] Da hoan tat lay net tu dong.");
            return true;
        }

        public byte[] CapturePhoto(bool autoFocus, out string resolution, int timeoutSeconds = 15)
        {
            resolution = "6240x4160 (26.1 MP)";

            Log("========================================================================");
            Log("[FUJI CAPTURE STEP 1/6] Kiem tra ket noi may anh...");
            if (_hCamera == IntPtr.Zero)
            {
                Log("[FUJI CAPTURE STEP 1/6] Camera chua mo phien, dang tien hanh ket noi...");
                XSDK_DeviceInformation dummy;
                if (!ConnectCamera(out dummy))
                {
                    string err = "Khong the ket noi may anh Fujifilm: " + LastError;
                    Log("[FUJI CAPTURE LOI] " + err);
                    throw new Exception(err);
                }
            }

            // Kiem tra trang thai chi tiet truoc khi chup (xem co anh cu ton dong khong)
            if (_getErrorDetailsFn != null)
            {
                int details = 0;
                _getErrorDetailsFn(_hCamera, ref details);
                Log(string.Format("[FUJI CAPTURE STEP 1/6] Trang thai chi tiet truoc khi chup: 0x{0:X} ({1})", details, DecodeErrorDetails(details)));
            }

            // Dam bao may anh o quyen dieu khien PC (Kiem tra tuc thi 0ms)
            if (_setPriorityModeFn != null)
            {
                EnsurePriorityMode(XSDK_PRIORITY_PC);
                Log("[FUJI CAPTURE STEP 2/6] Kiem tra quyen PC hoan tat");
            }

            int shotOpt = 1;
            int status = 0;

            // Buoc 3: Lay net truoc (Autofocus S1) neu duoc yeu cau
            if (autoFocus && _releaseFn != null)
            {
                Log("[FUJI CAPTURE STEP 3/6] Kich hoat lay net S1ON (Pre-focus)...");
                try
                {
                    int s1Ret = _releaseFn(_hCamera, XSDK_RELEASE_S1ON, ref shotOpt, ref status);
                    string afNote = (status == 1 || status == 5) ? "[OK: Da khoa net]" : (status == 4 ? "[OK: Tieu cu co dinh]" : (status == 2 ? "[Chua kiem tra]" : "[Trang thai: " + status + "]"));
                    Log(string.Format("[FUJI CAPTURE STEP 3/6] Ket qua S1ON: Ret={0}, ShotOpt={1}, AfStatus={2} {3}", s1Ret, shotOpt, status, afNote));
                    if (s1Ret != XSDK_COMPLETE)
                    {
                        // Neu S1ON khong thanh cong (VD dang o Manual Focus), huy nua co de tranh treo
                        int cancelOpt = 1, cancelStatus = 0;
                        _releaseFn(_hCamera, XSDK_RELEASE_N_S1OFF, ref cancelOpt, ref cancelStatus);
                    }
                    Thread.Sleep(20);
                }
                catch (Exception exAf)
                {
                    Log("[FUJI CAPTURE CANH BAO] Ngoai le khi lay net S1ON: " + exAf.Message);
                }
            }

            // Buoc 4: Kich no man trap co hoc & Flash studio (S2 Shutter Release)
            Log("[FUJI CAPTURE STEP 4/6] [SHOOT] GUI LENH KICH NO MAN TRAP VA DEN FLASH STUDIO (S2_S1OFF)...");
            int releaseRet = -1;

            // Cach 1: XSDK_Release (S2_S1OFF - Chuan tieu chuan cua Fujifilm SDK)
            if (_releaseFn != null)
            {
                for (int tryS2 = 1; tryS2 <= 3; tryS2++)
                {
                    releaseRet = _releaseFn(_hCamera, XSDK_RELEASE_S2_S1OFF, ref shotOpt, ref status);
                    if (releaseRet == XSDK_COMPLETE) break;

                    int apiCode = 0, errCode = 0;
                    if (_getErrorNumberFn != null) _getErrorNumberFn(_hCamera, ref apiCode, ref errCode);
                    if (errCode == 0x1006 || errCode == 0x1016) // BUSY
                    {
                        Log(string.Format("[FUJI CAPTURE STEP 4/6] Camera dang ban (BUSY 0x{0:X}) o lan {1}, doi 100ms...", errCode, tryS2));
                        Thread.Sleep(100);
                        continue;
                    }
                    break;
                }
                Log(string.Format("[FUJI CAPTURE STEP 4/6] Ket qua XSDK_Release (S2_S1OFF): Ret={0}, ShotOpt={1}, AfStatus={2}",
                    releaseRet, shotOpt, status));
            }

            // Cach 2: Neu cach 1 that bai, thu XSDK_ReleaseEx (XSDK_RELEASE_EX_S2_ON_S2_OFF_S1_OFF)
            if (releaseRet != XSDK_COMPLETE && _releaseExFn != null)
            {
                Thread.Sleep(120);
                Log("[FUJI CAPTURE STEP 4b] Cach 1 that bai, thu ReleaseEx (XSDK_RELEASE_EX_S2_ON_S2_OFF_S1_OFF)...");
                releaseRet = _releaseExFn(_hCamera, XSDK_RELEASE_EX_S2_ON_S2_OFF_S1_OFF, ref shotOpt, ref status);
                Log(string.Format("[FUJI CAPTURE STEP 4b] Ket qua XSDK_ReleaseEx: Ret={0}, ShotOpt={1}, AfStatus={2}",
                    releaseRet, shotOpt, status));
            }

            // Cach 2b: Thu ReleaseEx chu trinh tron goi (S1_ON_S2_ON_S2_OFF_S1_OFF)
            if (releaseRet != XSDK_COMPLETE && _releaseExFn != null)
            {
                Thread.Sleep(120);
                Log("[FUJI CAPTURE STEP 4c] Thu ReleaseEx tron goi (S1_ON_S2_ON_S2_OFF_S1_OFF)...");
                releaseRet = _releaseExFn(_hCamera, XSDK_RELEASE_EX_S1_ON_S2_ON_S2_OFF_S1_OFF, ref shotOpt, ref status);
                Log(string.Format("[FUJI CAPTURE STEP 4c] Ket qua ReleaseEx Full: Ret={0}, ShotOpt={1}, AfStatus={2}",
                    releaseRet, shotOpt, status));
            }

            // Cach 3: Neu van that bai, thu XSDK_RELEASE_SHOOT_S1OFF
            if (releaseRet != XSDK_COMPLETE && _releaseFn != null)
            {
                Thread.Sleep(120);
                Log("[FUJI CAPTURE STEP 4d] Thu phuong thuc XSDK_RELEASE_SHOOT_S1OFF...");
                releaseRet = _releaseFn(_hCamera, XSDK_RELEASE_SHOOT_S1OFF, ref shotOpt, ref status);
                Log(string.Format("[FUJI CAPTURE STEP 4d] Ket qua XSDK_RELEASE_SHOOT_S1OFF: Ret={0}, ShotOpt={1}, AfStatus={2}",
                    releaseRet, shotOpt, status));
            }

            if (releaseRet != XSDK_COMPLETE)
            {
                int apiCode = 0;
                int errCode = 0;
                if (_getErrorNumberFn != null)
                {
                    _getErrorNumberFn(_hCamera, ref apiCode, ref errCode);
                }
                string errDesc = DecodeErrorCode(errCode);
                int details = 0;
                if (_getErrorDetailsFn != null) _getErrorDetailsFn(_hCamera, ref details);

                string fullErrMsg = string.Format("Loi kich no man trap Fujifilm: Release Ret={0}, AfStatus={1}, APICode=0x{2:X}, ErrCode=0x{3:X} ({4}), Details=0x{5:X} ({6})",
                    releaseRet, status, apiCode, errCode, errDesc, details, DecodeErrorDetails(details));
                Log("[FUJI CAPTURE LOI NGHIEM TRONG] " + fullErrMsg);
                throw new Exception(fullErrMsg);
            }

            Log("[FUJI CAPTURE STEP 4/6] [OK] Man trap da kich no thanh cong! Dang chuyen sang buoc nhan file anh...");

            // Buoc 5: Lang nghe va keo file anh goc tu bo dem may anh
            Log("[FUJI CAPTURE STEP 5/6] Dang lang nghe bo dem anh (polling XSDK_ReadImageInfo)...");
            DateTime startWait = DateTime.Now;
            XSDK_ImageInformation imgInfo = new XSDK_ImageInformation();
            int pollCount = 0;

            while ((DateTime.Now - startWait).TotalSeconds < timeoutSeconds)
            {
                pollCount++;

                if (_readImageInfoFn != null)
                {
                    imgInfo = new XSDK_ImageInformation();
                    imgInfo.lFormat = XSDK_IMAGEFORMAT_NONE;
                    int readInfoRet = _readImageInfoFn(_hCamera, ref imgInfo);

                    if (pollCount == 1 || pollCount % 15 == 0 || readInfoRet == XSDK_COMPLETE)
                    {
                        Log(string.Format("[FUJI CAPTURE STEP 5/6] Dang doi anh... (lan {0}, {1:0.0}s, Ret={2}, Format=0x{3:X}, Size={4} bytes)",
                            pollCount, (DateTime.Now - startWait).TotalSeconds, readInfoRet, imgInfo.lFormat, imgInfo.lDataSize));
                    }

                    if (readInfoRet == XSDK_COMPLETE && imgInfo.lDataSize > 1000 && (imgInfo.lFormat & 0xFF) != XSDK_IMAGEFORMAT_NONE)
                    {
                        double sizeMb = Math.Round((double)imgInfo.lDataSize / (1024 * 1024), 2);
                        Log(string.Format("[FUJI CAPTURE STEP 6/6] [OK] DA PHAT HIEN ANH GOC! Format=0x{0:X}, Size={1} bytes ({2} MB), Kich thuoc pixel={3}x{4}",
                            imgInfo.lFormat, imgInfo.lDataSize, sizeMb, imgInfo.lImagePixWidth, imgInfo.lImagePixHeight));

                        byte[] buffer = new byte[imgInfo.lDataSize];
                        GCHandle handle = GCHandle.Alloc(buffer, GCHandleType.Pinned);
                        try
                        {
                            IntPtr ptr = handle.AddrOfPinnedObject();
                            Log(string.Format("[FUJI CAPTURE STEP 6/6] Dang doc {0} bytes du lieu anh qua cap USB (XSDK_ReadImage)...", imgInfo.lDataSize));
                            int readRet = _readImageFn(_hCamera, ptr, (uint)imgInfo.lDataSize);
                            Log(string.Format("[FUJI CAPTURE STEP 6/6] Ket qua XSDK_ReadImage: Ret={0} (0 = Thanh cong)", readRet));

                            if (_deleteImageFn != null)
                            {
                                try { _deleteImageFn(_hCamera); } catch { }
                            }

                            if (readRet == XSDK_COMPLETE)
                            {
                                if (imgInfo.lImagePixWidth > 0 && imgInfo.lImagePixHeight > 0)
                                {
                                    resolution = string.Format("{0}x{1} (26.1 MP)", imgInfo.lImagePixWidth, imgInfo.lImagePixHeight);
                                }
                                Log("[FUJI CAPTURE THANH CONG] Da nhan tron ven du lieu anh goc tu may anh Fujifilm!");
                                Log("========================================================================");
                                return buffer;
                            }
                            else
                            {
                                Log("[FUJI CAPTURE LOI] XSDK_ReadImage tra ve ma loi: " + readRet);
                            }
                        }
                        finally
                        {
                            handle.Free();
                        }
                    }
                }

                Thread.Sleep(30);
            }

            int toApiCode = 0, toErrCode = 0;
            if (_getErrorNumberFn != null) _getErrorNumberFn(_hCamera, ref toApiCode, ref toErrCode);
            int toDetails = 0;
            if (_getErrorDetailsFn != null) _getErrorDetailsFn(_hCamera, ref toDetails);

            string timeoutMsg = string.Format("Het thoi gian cho anh tu may anh Fujifilm (qua {0}s). ErrCode=0x{1:X} ({2}), Details=0x{3:X} ({4}). GOI Y XU LY: Hay kiem tra Menu may anh -> 'SAVE IMAGE' / 'PC SHOOT' phai chon 'PC+SD' hoac 'PC ONLY' (khong duoc chon 'CARD ONLY').",
                timeoutSeconds, toErrCode, DecodeErrorCode(toErrCode), toDetails, DecodeErrorDetails(toDetails));
            Log("[FUJI CAPTURE TIMEOUT] " + timeoutMsg);
            Log("========================================================================");
            throw new TimeoutException(timeoutMsg);
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
                    FujiSdkNative.Log("[MAIN ERROR] Khong the nap XAPI.dll: " + sdk.LastError);
                    OutputJson(false, "Cannot load XAPI.dll: " + sdk.LastError);
                    Environment.ExitCode = 1;
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
                    EscapeJson(sdk.LastError ?? "Chua phat hien may anh Fujifilm cam qua USB"));
                Environment.ExitCode = 1;
            }
        }

        static void HandleFocus(FujiSdkNative sdk)
        {
            XSDK_DeviceInformation devInfo;
            if (!sdk.ConnectCamera(out devInfo))
            {
                OutputJson(false, "Khong the ket noi may anh Fujifilm: " + sdk.LastError);
                Environment.ExitCode = 1;
                return;
            }

            bool focused = sdk.TriggerFocus();
            if (focused)
            {
                Console.WriteLine("{\"success\":true,\"message\":\"Da kich hoat lay net tu dong (FUJIFILM AF)\"}");
            }
            else
            {
                OutputJson(false, "Loi kich hoat lay net tu dong: " + sdk.LastError);
                Environment.ExitCode = 1;
            }
        }

        static void HandleCapture(FujiSdkNative sdk, string saveDir, string orderCode, bool autoFocus)
        {
            FujiSdkNative.Log(string.Format("[CLI CAPTURE] Bat dau chup anh: Don='{0}', Thu muc='{1}', AF={2}", orderCode, saveDir, autoFocus));

            if (!Directory.Exists(saveDir))
            {
                try { Directory.CreateDirectory(saveDir); } catch { }
            }

            XSDK_DeviceInformation devInfo;
            if (!sdk.ConnectCamera(out devInfo))
            {
                string err = "Khong the ket noi may anh Fujifilm: " + sdk.LastError;
                FujiSdkNative.Log("[CLI CAPTURE LOI] " + err);
                OutputJson(false, err);
                Environment.ExitCode = 1;
                return;
            }

            string model = string.IsNullOrEmpty(devInfo.strProduct) ? "FUJIFILM X-T4" : devInfo.strProduct.Trim();

            long startTime = Environment.TickCount;
            string resolution;
            try
            {
                byte[] photoBytes = sdk.CapturePhoto(autoFocus, out resolution);

                string filename = string.Format("{0}_{1}_original.jpg", orderCode, DateTime.Now.Ticks);
                string fullPath = Path.Combine(saveDir, filename);

                File.WriteAllBytes(fullPath, photoBytes);
                FujiSdkNative.Log(string.Format("[CLI CAPTURE] Da luu file anh thanh cong: {0}", fullPath));

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
            catch (Exception ex)
            {
                FujiSdkNative.Log("[CLI CAPTURE EXCEPTION] " + ex.Message);
                OutputJson(false, ex.Message);
                Environment.ExitCode = 1;
            }
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
                FujiSdkNative.Log("[FujiBridge Daemon] Loi khoi dong HTTP listener port " + port + ": " + ex.Message);
                return;
            }

            Console.WriteLine("========================================================================");
            Console.WriteLine("  LALE STUDIO - FUJIFILM CAMERA BRIDGE DAEMON (NATIVE 64-BIT)");
            Console.WriteLine("  Port: " + prefix);
            Console.WriteLine("  San sang kich no man trap co hoc FUJIFILM X-T4 & Flash Studio!");
            Console.WriteLine("========================================================================");

            using (FujiSdkNative sdk = new FujiSdkNative())
            {
                if (!sdk.IsLoaded)
                {
                    FujiSdkNative.Log("[FujiBridge Daemon] [WARN] Khong the nap XAPI.dll: " + sdk.LastError);
                }

                XSDK_DeviceInformation devInfo = new XSDK_DeviceInformation();
                bool connected = sdk.ConnectCamera(out devInfo);
                if (connected)
                {
                    Console.WriteLine("[FujiBridge Daemon] [OK] Da ket noi voi may anh: " + (devInfo.strProduct ?? "FUJIFILM"));
                }
                else
                {
                    Console.WriteLine("[FujiBridge Daemon] Dang cho ket noi may anh Fujifilm qua USB...");
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
                                FujiSdkNative.Log("[DAEMON EXCEPTION] " + ex.Message);
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
                        ok ? "Da kich hoat lay net tu dong Fujifilm" : EscapeJson(sdk.LastError ?? "Lay net that bai"));
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

                FujiSdkNative.Log(string.Format("[DAEMON CAPTURE] Nhan yeu cau: Don='{0}', Thu muc='{1}', AF={2}", orderCode, saveDir, autoFocus));

                lock (sdk)
                {
                    if (!Directory.Exists(saveDir))
                    {
                        try { Directory.CreateDirectory(saveDir); } catch { }
                    }

                    long startTime = Environment.TickCount;
                    string resolution;
                    try
                    {
                        byte[] photoBytes = sdk.CapturePhoto(autoFocus, out resolution);

                        string filename = string.Format("{0}_{1}_original.jpg", orderCode, DateTime.Now.Ticks);
                        string fullPath = Path.Combine(saveDir, filename);

                        File.WriteAllBytes(fullPath, photoBytes);
                        FujiSdkNative.Log(string.Format("[DAEMON CAPTURE] Da luu file anh thanh cong: {0}", fullPath));

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
                    catch (Exception ex)
                    {
                        FujiSdkNative.Log("[DAEMON CAPTURE LOI] " + ex.Message);
                        SendJson(res, 500, string.Format("{{\"success\":false,\"error\":\"{0}\"}}", EscapeJson(ex.Message)));
                    }
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
