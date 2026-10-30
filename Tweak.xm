// Tweak.xm — Race Toolkit Pro (iOS, IL2CPP VTable & Metadata Hook)
//
// Features:
// 1. Modern Glassmorphic UI Menu with interactive Vehicle / Skin Dropdown.
// 2. Mod Xe / Skin Tự Động (Visual RAM): Tự động đổi xe trong Sảnh (Lobby/Garage) và ngay khi Vào Trận / Load Trận.
// 3. Auto Play (AI Tự Đua): Bám tim đường tức thì qua Quaternion chassis + nắn lái vật lý trực tiếp.
// 4. Slider Sức Mạnh Đổi Hướng (Steer Strength 0.5x - 3.0x): Nhân trực tiếp mô-men xoắn bẻ lái bánh xe.
// 5. Inf Mini Boost (ForceCanTriggerOnce liên tục).
// 6. Gia Tốc / Speed Boost (PowerChain extra KMPH + torque sau 5s xuất phát).
// 7. Anti-Cheat Report: Khóa SdcVehicleVel ở mức 300 km/h.
// 8. Auto End Drift (ExitCurDriftState + ForceClearDriftParams).
// 9. Top Overlay: MinMapTime, LapTimeLimit & Can Finish status.

#import <UIKit/UIKit.h>
#import <math.h>
#import <string.h>
#import <time.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <pthread.h>

#pragma mark - Minimal logger

static int gLogFd = -1;
static char gLogPath[1024];

static void rtLogOpen(void) {
    if (gLogFd >= 0) return;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
    NSString *p = [doc stringByAppendingPathComponent:@"racetoolkit.log"];
    [p getFileSystemRepresentation:gLogPath maxLength:sizeof(gLogPath)];
    gLogFd = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
}

static void rtLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void rtLog(const char *fmt, ...) {
    if (gLogFd < 0) rtLogOpen();
    if (gLogFd < 0) return;

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    char buf[2048];
    int n = snprintf(buf, sizeof(buf), "[%ld.%03ld] ", (long)ts.tv_sec, ts.tv_nsec / 1000000);
    if (n < 0 || n >= (int)sizeof(buf)) return;

    va_list ap;
    va_start(ap, fmt);
    int m = vsnprintf(buf + n, sizeof(buf) - (size_t)n, fmt, ap);
    va_end(ap);
    if (m < 0) return;

    size_t total = (size_t)n + (size_t)m;
    if (total + 1 < sizeof(buf)) {
        buf[total++] = '\n';
        buf[total] = '\0';
    }
    ssize_t w = write(gLogFd, buf, total);
    (void)w;
}

#pragma mark - Crash diagnostic (read-only signal reporter)

static int rtAppendHex(char *buf, int k, uintptr_t val) {
    static const char h[] = "0123456789abcdef";
    buf[k++] = '0'; buf[k++] = 'x';
    for (int sh = (int)(sizeof(uintptr_t) * 8 - 4); sh >= 0; sh -= 4) {
        buf[k++] = h[(val >> sh) & 0xF];
    }
    return k;
}

static void rtSignalHandler(int sig, siginfo_t *info, void *uap) {
    char msg[256];
    int len = 0;
    const char *hdr = "\n===== CRASH signal=";
    while (*hdr) msg[len++] = *hdr++;
    msg[len++] = '0' + (sig / 10);
    msg[len++] = '0' + (sig % 10);
    const char *fa = " faultAddr="; while (*fa) msg[len++] = *fa++;
    len = rtAppendHex(msg, len, (uintptr_t)(info ? info->si_addr : 0));
    const char *tail = " =====\n"; while (*tail) msg[len++] = *tail++;

    ssize_t w = write(gLogFd, msg, (size_t)len);
    (void)w;

    ucontext_t *uc = (ucontext_t *)uap;
    char loc[256];
    int k = 0;
    const char *p1 = "  PC="; while (*p1) loc[k++] = *p1++;
    k = rtAppendHex(loc, k, uc && uc->uc_mcontext ? (uintptr_t)uc->uc_mcontext->__ss.__pc : 0);
    const char *p2 = "  LR="; while (*p2) loc[k++] = *p2++;
    k = rtAppendHex(loc, k, uc && uc->uc_mcontext ? (uintptr_t)uc->uc_mcontext->__ss.__lr : 0);
    const char *p3 = "\n"; loc[k++] = *p3++;
    ssize_t w2 = write(gLogFd, loc, (size_t)k);
    (void)w2;

    fsync(gLogFd);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void rtInstallCrashHandler(void) {
    static char altStack[64 * 1024];
    stack_t ss;
    ss.ss_sp = altStack;
    ss.ss_size = sizeof(altStack);
    ss.ss_flags = 0;
    sigaltstack(&ss, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = rtSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
        sigaction(sigs[i], &sa, NULL);
    }
}

#pragma mark - Toolkit state & field offsets

static BOOL   gFullMiniBoost  = NO;
static BOOL   gAutoDriftEnd   = NO;
static BOOL   gAutoPlay       = NO;
static float  gSpeedKmh       = 0.f;
static float  gSteerStrength  = 1.0f; // Multiplier: 0.5x - 3.0x

// Visual Vehicle Mod state
static BOOL   gModEnabled     = NO;
static int    gModVehicleID   = 0;    // Vehicle ID
static int    gModSkinID      = 0;    // Skin ID
static int    gSelectedPreset = 0;    // Index in kVehicleCatalog

static double gGoTime         = 0.0;
static BOOL   gHooksInstalled = NO;
static void  *gCurrentVehicle = NULL;

// Race status & metrics
static float  gCurrentMatchTime  = 0.f;
static float  gMainCurveLength   = 0.f;
static int    gMapTotalLaps      = 2;
static float  gMinMapTimeSeconds = 0.f;
static float  gLapTimeLimit      = 0.f;
static BOOL   gCanFinish         = NO;
static int    gLastCheckPointId  = 0;

enum {
    // NssPhyVehiclePowerChain
    kOffPowerExtraKMPH    = 68,  // 0x44 mExtraKMPH (float)
    kOffPowerExtraTorque  = 72,  // 0x48 mExtraTorque (float)
    kOffPowerMPSScaleCoef = 56,  // 0x38 mMPSScaleCoef (float)
    kOffPowerTorqueScale  = 64,  // 0x40 mTorqueScaleCoef (float)

    // SdcVehicleVel (Security Data Collect)
    kOffSdcVelEndData     = 88,  // 0x58 mEndData
    kOffSdcVelProcData    = 96,  // 0x60 mProcessData

    // ActorCpReporter
    kOffActorCpLastCp     = 104, // 0x68 mLastCheckPoint
    kOffActorCpLaps       = 120, // 0x78 mMapTotalRoundNum

    // NssVehicle
    kOffVehicleID         = 0x10, // mVehicleID (int)
    kOffVehicleDyn        = 0x20, // mDynamicVehicle
    kOffVehicleIsMain     = 0xF8, // mIsMainPlayer (bool)

    // IDynamicVehicle (DynamicVehicle)
    kOffDynVehicle        = 0x10, // mVehicle
    kOffDynMotionCtrl     = 0x38, // mMotionCtrl
    kOffDynACC            = 0x28, // mACC

    // NssPhyVehicleCtrl
    kOffPhySimOutput      = 0x28, // mSimulateOutput

    // NssPhyVehicleMotionCtrlHelper
    kOffMotionSteerData   = 0x10, // mSteeringData
    kOffMotionVehicle     = 0x18, // mVehicle
    kOffMotionPhyCtrl     = 0x20, // mVehiclePhyCtrl
    kOffMotionDynVehicle  = 0x28, // mDynamicVehicle
    kOffMotionDrivingCtrl = 0x38, // mDrivingCtrl

    // NssPlayerVehicleDrivingCtrl
    kOffDrvThrottle       = 0x3C, // mThrottle (float)
    kOffDrvSteering       = 0x40, // mSteering (float)
    kOffDrvInputXPos      = 0x68, // mInputXPosition (float)
    kOffDrvDriftPress     = 0x75, // mDriftIsPress (bool)

    // NssSteeringData
    kOffSteerForward      = 0x10, // mForward (float)
    kOffSteerBraking      = 0x14, // mBrakingState (int)
    kOffSteerHandbrake    = 0x18, // mIsHandbrake (bool)
    kOffSteerWheel        = 0x1C, // mSteeringLeft (float)

    // NssPhyVehicleACC
    kOffAccCurTrackPoint  = 0x38, // mCurTrackPoint
    kOffAccHorizDis       = 0x5C, // mHorizontalDis (float)

    // NssTrackPoint
    kOffTpDirection       = 0x1C, // mDirection (Vector3)

    // NssVehicleSimOutput
    kOffSimMovingDir      = 0x44, // mMovingDirection (Vector3)
    kOffSimChassisRot     = 0x70, // mChassisRotation (Quaternion: x, y, z, w)
};

static inline double nowSeconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static inline BOOL rtPtrOk(const void *p) {
    uintptr_t v = (uintptr_t)p;
    if (v < 0x10000ULL) return NO;
    if (v & 7) return NO;
    return YES;
}

#pragma mark - IL2CPP Runtime API & Structures

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct {
    void *methodPtr;
    const MethodInfo *method;
} VirtualInvokeData;

static Il2CppDomain *(*il2cpp_domain_get)(void) = NULL;
static const Il2CppAssembly **(*il2cpp_domain_get_assemblies)(const Il2CppDomain *domain, size_t *size) = NULL;
static const Il2CppImage *(*il2cpp_assembly_get_image)(const Il2CppAssembly *assembly) = NULL;
static Il2CppClass *(*il2cpp_class_from_name)(const Il2CppImage *image, const char *namespaze, const char *name) = NULL;
static const MethodInfo *(*il2cpp_class_get_method_from_name)(Il2CppClass *klass, const char *name, int argsCount) = NULL;

static uintptr_t unityFrameworkBase(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static BOOL rtInitIl2CppApi(void) {
    if (il2cpp_domain_get) return YES;

    void *handle = RTLD_DEFAULT;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            handle = dlopen(name, RTLD_NOW | RTLD_NOLOAD);
            break;
        }
    }

    *(void **)&il2cpp_domain_get = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_domain_get");
    *(void **)&il2cpp_domain_get_assemblies = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    *(void **)&il2cpp_assembly_get_image = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_assembly_get_image");
    *(void **)&il2cpp_class_from_name = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_class_from_name");
    *(void **)&il2cpp_class_get_method_from_name = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_class_get_method_from_name");

    if (!il2cpp_domain_get || !il2cpp_class_from_name || !il2cpp_class_get_method_from_name) {
        return NO;
    }

    rtLog("il2cpp: API resolved (domain_get=%p, class_from_name=%p)",
          il2cpp_domain_get, il2cpp_class_from_name);
    return YES;
}

static Il2CppClass *rtFindClass(const char *namespaze, const char *name) {
    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies) return NULL;
    Il2CppDomain *domain = il2cpp_domain_get();
    if (!domain) return NULL;
    size_t count = 0;
    const Il2CppAssembly **assemblies = domain ? il2cpp_domain_get_assemblies(domain, &count) : NULL;
    if (!assemblies || count == 0) return NULL;
    for (size_t i = 0; i < count; i++) {
        const Il2CppImage *image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        Il2CppClass *k = il2cpp_class_from_name(image, namespaze ?: "", name);
        if (k) return k;
        if (strchr(name, '.')) {
            char nestedName[256];
            strncpy(nestedName, name, sizeof(nestedName) - 1);
            nestedName[sizeof(nestedName) - 1] = '\0';
            for (char *p = nestedName; *p; p++) {
                if (*p == '.') *p = '/';
            }
            k = il2cpp_class_from_name(image, namespaze ?: "", nestedName);
            if (k) return k;
        }
    }
    return NULL;
}

__attribute__((unused)) static void *rtGetMethodPointer(const char *namespaze, const char *className,
                                const char *methodName, int argsCount) {
    Il2CppClass *klass = rtFindClass(namespaze, className);
    if (!klass) return NULL;
    const MethodInfo *method = il2cpp_class_get_method_from_name(klass, methodName, argsCount);
    if (!method) return NULL;
    return *(void **)((char *)method + 0);
}

static void *rtHookMethod(const char *namespaze, const char *className,
                          const char *methodName, int argsCount,
                          void *replacement) {
    Il2CppClass *klass = rtFindClass(namespaze, className);
    if (!klass) {
        rtLog("il2cpp: class %s::%s NOT FOUND", namespaze ?: "", className);
        return NULL;
    }

    const MethodInfo *method = il2cpp_class_get_method_from_name(klass, methodName, argsCount);
    if (!method) {
        rtLog("il2cpp: %s::%s(args=%d) NOT FOUND", className, methodName, argsCount);
        return NULL;
    }

    void *orig = *(void **)((char *)method + 0);
    *(void **)((char *)method + 0) = replacement;

    uint16_t slot = *(uint16_t *)((char *)method + 88);
    uint16_t vtable_count = *(uint16_t *)((char *)klass + 306);

    uintptr_t base = unityFrameworkBase();
    uintptr_t rva = base && orig ? ((uintptr_t)orig - base) : 0;

    if (slot < vtable_count) {
        VirtualInvokeData *vtable = (VirtualInvokeData *)((char *)klass + 336);
        vtable[slot].methodPtr = replacement;
        rtLog("il2cpp: HOOK %-24s :: %-26s (slot %2u/%2u, rva=0x%lx) orig=%p -> rep=%p",
              className, methodName, (unsigned)slot, (unsigned)vtable_count, (unsigned long)rva, orig, replacement);
    } else {
        rtLog("il2cpp: HOOK %-24s :: %-26s (methodPointer only, rva=0x%lx) orig=%p -> rep=%p",
              className, methodName, (unsigned long)rva, orig, replacement);
    }

    return orig;
}

#pragma mark - Function Pointers

static void (*orig_GameGo_ImpEnter)(void *, const void *) = NULL;
static void (*orig_ExVelMgr_Update)(void *, float, const void *) = NULL;
static void (*orig_Drift_Release)(void *, const void *) = NULL;
static void (*orig_Drift_ExitCurDriftState)(void *, const void *) = NULL;
static void (*orig_Drift_ForceClearDriftParams)(void *, const void *) = NULL;
static void (*orig_PowerChain_Update)(void *, float, const void *) = NULL;
static void (*orig_SdcVehicleVel_Update)(void *, float, const void *) = NULL;
static void (*orig_CheckPointMgr_Init)(void *, void *, bool, bool, const void *) = NULL;
static void (*orig_ActorCpReporter_Update)(void *, float, float, const void *) = NULL;
static void (*ExtraVelocityTriggerMgr_ForceCanTriggerOnce)(void *, int, const void *) = NULL;
static void (*orig_MotionCtrl_Update)(void *, float, const void *) = NULL;
static void (*orig_PhyVehicleCtrl_DoSteering)(void *, float, const void *) = NULL;
static BOOL (*orig_Input_GetKey)(void *, int, const void *) = NULL;
static void (*orig_NssVehicle_PreInit)(void *, uint64_t, int, void *, const void *) = NULL;
static int  (*orig_NssVehicle_GetVehicleID)(void *, const void *) = NULL;
static uint64_t (*orig_ItemVehicle_GetModelID)(void *, const void *) = NULL;
static void (*orig_Previewer_ShowVehicle)(void *, void *, uint32_t, void *, void *, const void *) = NULL;

#pragma mark - Hook Implementations

// 1. Race Start Marker
static void hook_GoImpEnter(void *self, const void *method) {
    if (orig_GameGo_ImpEnter) orig_GameGo_ImpEnter(self, method);
    gGoTime = nowSeconds();
    gCurrentMatchTime = 0.f;
    gCanFinish = NO;
    rtLog("race started -> gGoTime=%.3f, MinMapTime=%.1fs, LapTimeLimit=%.1fs",
          gGoTime, gMinMapTimeSeconds, gLapTimeLimit);
}

// 2. Mini Boost: Giữ nguyên cơ chế gọi ForceCanTriggerOnce liên tục
static void hook_ExVelMgrUpdate(void *self, float dt, const void *method) {
    if (orig_ExVelMgr_Update) orig_ExVelMgr_Update(self, dt, method);
    if (!gFullMiniBoost || !self) return;

    if (ExtraVelocityTriggerMgr_ForceCanTriggerOnce) {
        ExtraVelocityTriggerMgr_ForceCanTriggerOnce(self, 2, nullptr);  // Mini
        ExtraVelocityTriggerMgr_ForceCanTriggerOnce(self, 3, nullptr);  // Air
        ExtraVelocityTriggerMgr_ForceCanTriggerOnce(self, 11, nullptr); // FallingGround
    }
}

// 3. Auto End Drift
static void hook_DriftExitCurState(void *self, const void *method) {
    if (orig_Drift_ExitCurDriftState) orig_Drift_ExitCurDriftState(self, method);
}

static void hook_DriftForceClear(void *self, const void *method) {
    if (orig_Drift_ForceClearDriftParams) orig_Drift_ForceClearDriftParams(self, method);
}

static void hook_DriftRelease(void *self, const void *method) {
    if (orig_Drift_Release) orig_Drift_Release(self, method);
    if (!gAutoDriftEnd || !self) return;

    if (orig_Drift_ExitCurDriftState) {
        orig_Drift_ExitCurDriftState(self, nullptr);
    }
    if (orig_Drift_ForceClearDriftParams) {
        orig_Drift_ForceClearDriftParams(self, nullptr);
    }
}

// 4. Gia Tốc / Speed Boost (+5s gate)
static void hook_PowerChainUpdate(void *self, float dt, const void *method) {
    if (orig_PowerChain_Update) orig_PowerChain_Update(self, dt, method);
    if (!self || gSpeedKmh <= 0.f) return;

    if (gGoTime <= 0.0 || (nowSeconds() - gGoTime) < 5.0) return;

    *(float *)((char *)self + kOffPowerExtraKMPH)    = gSpeedKmh;
    *(float *)((char *)self + kOffPowerExtraTorque)  = gSpeedKmh * 10.0f;
    *(float *)((char *)self + kOffPowerMPSScaleCoef) = 1.0f + (gSpeedKmh / 120.0f);
    *(float *)((char *)self + kOffPowerTorqueScale)  = 1.0f + (gSpeedKmh / 120.0f);
}

// 5. Anti-Cheat Report Speed: Khóa SdcVehicleVel ở mức 300 km/h
static void hook_SdcVehicleVelUpdate(void *self, float dt, const void *method) {
    if (orig_SdcVehicleVel_Update) orig_SdcVehicleVel_Update(self, dt, method);
    if (!self) return;

    void *endData = *(void **)((char *)self + kOffSdcVelEndData);
    if (endData) {
        *(int *)((char *)endData + 0x10) = 300; // CarSpeedMax = 300 km/h
        *(int *)((char *)endData + 0x14) = 0;   // CarSpeedOverBase = 0
    }
    void *procData = *(void **)((char *)self + kOffSdcVelProcData);
    if (procData) {
        *(int *)((char *)procData + 0x10) = 300; // ProcessVehicleMaxVel = 300 km/h
        *(int *)((char *)procData + 0x28) = 300; // ProcessVehicleMaxBaseVel = 300 km/h
    }
    *(float *)((char *)self + 0x94) = 300.0f; // mMaxVehicleKMPH = 300.0f
}

// 6. CheckPoint & Lap time
static void hook_CheckPointMgrInit(void *self, void *config, bool checkCrc, bool enableReset, const void *method) {
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, checkCrc, enableReset, method);
    if (config) {
        gMainCurveLength = *(float *)((char *)config + 0x4C);
        int laps = gMapTotalLaps > 0 ? gMapTotalLaps : 2;
        float lapDist = gMainCurveLength > 100.f ? gMainCurveLength : 2500.f;
        float totalDist = lapDist * (float)laps;

        gLapTimeLimit = lapDist / (300.0f / 3.6f);
        gMinMapTimeSeconds = totalDist / (300.0f / 3.6f);

        rtLog("map loaded: length=%.1fm, laps=%d -> LapLimit=%.2fs, MinMapTime=%.2fs",
              lapDist, laps, gLapTimeLimit, gMinMapTimeSeconds);
    }
}

static void hook_ActorCpReporterUpdate(void *self, float dt, float matchTime, const void *method) {
    if (orig_ActorCpReporter_Update) orig_ActorCpReporter_Update(self, dt, matchTime, method);
    if (!self) return;

    gCurrentMatchTime = matchTime;
    int laps = *(int *)((char *)self + kOffActorCpLaps);
    if (laps > 0) gMapTotalLaps = laps;
    gLastCheckPointId = *(int *)((char *)self + kOffActorCpLastCp);

    float curTime = gCurrentMatchTime > 0.f ? gCurrentMatchTime :
                    (gGoTime > 0.0 ? (float)(nowSeconds() - gGoTime) : 0.f);
    if (gMinMapTimeSeconds > 0.f && curTime >= gMinMapTimeSeconds) {
        gCanFinish = YES;
    } else {
        gCanFinish = NO;
    }
}

// ==== Auto Play state ====================================================
//
// Written from hook_MotionCtrlUpdate (once per motion tick) and read from
// hook_Input_GetKey (polled several times per frame), so both must exist
// before either hook.
//
// InputKeyType (dump): Left=1 Right=2 PropOne=3 PropTwo=4 SmallBoost=5
//                      Brake=6 Reset=7 Drift=8 SidewaysDrift=9 ...
static int gAPKeyMask    = 0;   // bit N set => key N is "held" this frame
static int gAPDriftLatch = 0;   // 1 while drift is held
static int gAPBoostTicks = 0;   // frames left to hold SmallBoost

static BOOL rtAPKey(int t) { return (gAPKeyMask >> t) & 1; }

// Layer B: pretend the thumb holds these keys. Everything downstream (drift
// state machine, CWW/WCW boost, nitro) runs the untouched game code path.
static BOOL hook_Input_GetKey(void *self, int keyType, const void *method) {
    if (gAutoPlay && keyType > 0 && keyType < 18 && rtAPKey(keyType))
        return TRUE;
    return orig_Input_GetKey ? orig_Input_GetKey(self, keyType, method) : FALSE;
}

// 7 + 10. Steering strength + Auto Play steering, both injected here.
//
// Decompile of NssPhyVehicleCtrl::DoSteering (0x7AF5BAC):
//     float v5 = *(float *)(self + 256) * a2;   // a2 = normalised steer
//     PHY_VehicleDoSteering(phyHandle, v5);
// So `torque` arrives already normalised to -1..1 and the game scales it by
// its own mSteerTorqueScale. Writing here bypasses the whole input chain
// (_UpdateInputXTimeRel ramp, AssistTurning overwrite, mSteering flush), which
// is why steering from mSteeringData never survived a tick.
static float rtAPComputeSteer(void *phyCtrl, void *vehicle) {
    void *dyn = rtPtrOk(vehicle) ? *(void **)((char *)vehicle + kOffVehicleDyn) : NULL;
    void *sim = *(void **)((char *)phyCtrl + kOffPhySimOutput);
    void *acc = rtPtrOk(dyn) ? *(void **)((char *)dyn + kOffDynACC) : NULL;
    void *tp  = rtPtrOk(acc) ? *(void **)((char *)acc + kOffAccCurTrackPoint) : NULL;
    if (!rtPtrOk(sim) || !rtPtrOk(tp)) return 0.f;

    // Nose direction from the chassis quaternion (valid even at standstill,
    // unlike mMovingDirection which is zero before the car rolls).
    float qx = *(float *)((char *)sim + kOffSimChassisRot);
    float qy = *(float *)((char *)sim + kOffSimChassisRot + 4);
    float qz = *(float *)((char *)sim + kOffSimChassisRot + 8);
    float qw = *(float *)((char *)sim + kOffSimChassisRot + 12);

    float fwdX = 2.0f * (qx * qz + qw * qy);
    float fwdZ = 1.0f - 2.0f * (qx * qx + qy * qy);

    // Guide line = centre-line tangent at the current track point.
    float dirX = *(float *)((char *)tp + kOffTpDirection);
    float dirZ = *(float *)((char *)tp + kOffTpDirection + 8);

    // Signed lateral offset from that guide line (mHorizontalDis).
    float hDis = *(float *)((char *)acc + kOffAccHorizDis);

    float flen = sqrtf(fwdX * fwdX + fwdZ * fwdZ);
    float dlen = sqrtf(dirX * dirX + dirZ * dirZ);
    float cross = (fwdX * dirZ) - (fwdZ * dirX);
    if (flen > 1e-4f && dlen > 1e-4f) cross /= (flen * dlen);

    // Pull toward the line proportional to how far off it we are, with a
    // hard cap so a big lateral error cannot demand full lock instantly.
    float pull = hDis * 0.045f;
    if (pull >  0.45f) pull =  0.45f;
    if (pull < -0.45f) pull = -0.45f;

    float steer = (cross * 2.6f) - pull;
    if (steer >  1.f) steer =  1.f;
    if (steer < -1.f) steer = -1.f;
    return steer;
}

static void hook_PhyVehicleCtrl_DoSteering(void *self, float torque, const void *method) {
    if (rtPtrOk(self)) {
        void *vehicle = *(void **)((char *)self + 0x10);   // NssPhyVehicleCtrl.mVehicle

        BOOL isPlayer = rtPtrOk(vehicle) ? *(bool *)((char *)vehicle + kOffVehicleIsMain) : NO;

        if (isPlayer && gAutoPlay) {
            float steer = rtAPComputeSteer(self, vehicle);

            // A real thumb input always wins over the AI.
            void *dyn = *(void **)((char *)vehicle + kOffVehicleDyn);
            void *mc  = rtPtrOk(dyn) ? *(void **)((char *)dyn + kOffDynMotionCtrl) : NULL;
            void *sd  = rtPtrOk(mc) ? *(void **)((char *)mc + kOffMotionSteerData) : NULL;
            if (rtPtrOk(sd) && fabsf(*(float *)((char *)sd + kOffSteerWheel)) >= 0.2f) {
                steer = *(float *)((char *)sd + kOffSteerWheel);
            }
            torque = steer;
        }

        if (gSteerStrength > 0.0f) torque *= gSteerStrength;
    }

    if (orig_PhyVehicleCtrl_DoSteering) orig_PhyVehicleCtrl_DoSteering(self, torque, method);
}

// 8. Tự động Mod Xe / Skin trong Sảnh (Lobby / Garage / Preview)
//
// VehiclePreviewParam (+0x28 SkinId / +0x2C VehicleId) is only the *preview*
// descriptor; the model actually resolves from InitVehicleParams inside the
// loader. Both are patched here so the rendered car matches.
static void hook_Previewer_ShowVehicle(void *self, void *vehiclePreviewParam, uint32_t downloadPriority, void *memberName, void *filePath, const void *method) {
    if (gModEnabled && gModVehicleID > 0 && rtPtrOk(vehiclePreviewParam)) {
        *(uint32_t *)((char *)vehiclePreviewParam + 0x2C) = (uint32_t)gModVehicleID; // VehicleId
        *(uint32_t *)((char *)vehiclePreviewParam + 0x28) = (uint32_t)gModSkinID;    // SkinId (0 = default)

        // DirectItemVehicle (+0x50) bypasses the id path entirely when set, so
        // clear it to force resolution through the patched ids.
        *(void **)((char *)vehiclePreviewParam + 0x50) = NULL;

        rtLog("ShowVehicle modded -> VehicleID=%d SkinID=%d", gModVehicleID, gModSkinID);
    }
    if (orig_Previewer_ShowVehicle) orig_Previewer_ShowVehicle(self, vehiclePreviewParam, downloadPriority, memberName, filePath, method);
}

// 9. Mod Xe khi Vào Trận
//
// PreInit only shows "methodPointer only" in the log and never fires during a
// match load, because IL2CPP calls the compiled address directly for internal
// callers. So the model id is instead forced from the two accessors the loader
// actually queries, plus the id field on the live entity every motion tick.
static void hook_NssVehicle_PreInit(void *self, uint64_t uid, int vehicleID, void *compConfig, const void *method) {
    if (gModEnabled && gModVehicleID > 0) {
        vehicleID = gModVehicleID;
        rtLog("PreInit modded vehicleID -> %d (uid=%llu)", gModVehicleID, (unsigned long long)uid);
    }
    if (orig_NssVehicle_PreInit) orig_NssVehicle_PreInit(self, uid, vehicleID, compConfig, method);

    // Belt and braces: the field is what every later getter reads.
    if (gModEnabled && gModVehicleID > 0 && rtPtrOk(self))
        *(int *)((char *)self + kOffVehicleID) = gModVehicleID;
}

static int hook_NssVehicle_GetVehicleID(void *self, const void *method) {
    if (gModEnabled && gModVehicleID > 0 && rtPtrOk(self)) {
        *(int *)((char *)self + kOffVehicleID) = gModVehicleID;
        return gModVehicleID;
    }
    return orig_NssVehicle_GetVehicleID ? orig_NssVehicle_GetVehicleID(self, method) : 0;
}

static uint64_t hook_ItemVehicle_GetModelID(void *self, const void *method) {
    if (gModEnabled && gModVehicleID > 0 && rtPtrOk(self)) {
        return (uint64_t)gModVehicleID;
    }
    return orig_ItemVehicle_GetModelID ? orig_ItemVehicle_GetModelID(self, method) : 0;
}

// 10. Auto Play: throttle + skill keys.
//
// Steering is NOT written here. DoSteering (0x7AF5BAC) receives the final
// normalised torque and is the only point downstream of _UpdateInputXTimeRel
// (which ramps mInputXPosition at ~1.0/s) and AssistTurning (which overwrites
// mSteering). This hook therefore only owns throttle and the discrete
// Drift / SmallBoost / Left / Right keys consumed by InputModule.GetKey.
static void hook_MotionCtrlUpdate(void *self, float dt, const void *method) {
    if (rtPtrOk(self)) {
        void *vehicle = *(void **)((char *)self + kOffMotionVehicle);
        if (rtPtrOk(vehicle)) {
            gCurrentVehicle = vehicle;
            if (gModEnabled && gModVehicleID > 0) {
                *(int *)((char *)vehicle + kOffVehicleID) = gModVehicleID;
            }
        }

        if (gAutoPlay) {
            void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
            void *dyn         = *(void **)((char *)self + kOffMotionDynVehicle);
            void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
            void *drivingCtrl = *(void **)((char *)self + kOffMotionDrivingCtrl);

            if (rtPtrOk(steerData) && rtPtrOk(dyn) && rtPtrOk(phyCtrl)) {
                void *acc = *(void **)((char *)dyn + kOffDynACC);
                void *sim = *(void **)((char *)phyCtrl + kOffPhySimOutput);
                void *tp  = rtPtrOk(acc) ? *(void **)((char *)acc + kOffAccCurTrackPoint) : NULL;

                int braking   = *(int *)((char *)steerData + kOffSteerBraking);
                bool handbrake = *(bool *)((char *)steerData + kOffSteerHandbrake);

                if (braking == 0 && !handbrake) {
                    *(float *)((char *)steerData + kOffSteerForward) = 1.0f;
                    if (rtPtrOk(drivingCtrl))
                        *(float *)((char *)drivingCtrl + kOffDrvThrottle) = 1.0f;
                }

                // Skill keys: latch drift through corners, tap mini boost on exit.
                if (rtPtrOk(sim) && rtPtrOk(tp)) {
                    float steer = rtAPComputeSteer(phyCtrl, vehicle);
                    int mask = 0;

                    if (fabsf(steer) > 0.55f)      gAPDriftLatch = 1;
                    else if (fabsf(steer) < 0.25f) gAPDriftLatch = 0;

                    if (gAPDriftLatch && !handbrake) {
                        mask |= (1 << 8);                              // Drift
                        mask |= (steer > 0.f) ? (1 << 2) : (1 << 1);   // Right : Left
                    } else {
                        if (steer >  0.15f) mask |= (1 << 2);
                        if (steer < -0.15f) mask |= (1 << 1);
                    }

                    if (!gAPDriftLatch && gAPBoostTicks == 0 && fabsf(steer) < 0.20f)
                        gAPBoostTicks = 2;
                    if (gAPBoostTicks > 0) {
                        mask |= (1 << 5);                              // SmallBoost
                        gAPBoostTicks--;
                    }

                    gAPKeyMask = mask;
                }
            }
        } else {
            gAPKeyMask = 0;
            gAPDriftLatch = 0;
            gAPBoostTicks = 0;
        }
    }

    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, method);
}

#pragma mark - Hook installation

static BOOL rtHooksDisabled(void) {
    char path[1200];
    const char *dir = strrchr(gLogPath, '/');
    if (!dir) return NO;
    size_t n = (size_t)(dir - gLogPath);
    if (n + 10 >= sizeof(path)) return NO;
    memcpy(path, gLogPath, n);
    memcpy(path + n, "/no_hooks", 10);
    int fd = open(path, O_RDONLY);
    if (fd >= 0) { close(fd); return YES; }
    return NO;
}

static void installHooks(void) {
    if (rtHooksDisabled()) {
        rtLog("install: SKIPPED (no_hooks flag present)");
        return;
    }

    rtLog("install: installing IL2CPP metadata hooks");

    // 1. Race start
    orig_GameGo_ImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "FreePracticeGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "ActionSpeedGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);

    // 2. Mini Boost
    orig_ExVelMgr_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "ExtraVelocityTriggerMgr", "Update", 1, (void *)hook_ExVelMgrUpdate);
    ExtraVelocityTriggerMgr_ForceCanTriggerOnce = (void (*)(void *, int, const void *))
        rtGetMethodPointer("", "ExtraVelocityTriggerMgr", "ForceCanTriggerOnce", 1);

    // 3. Auto End Drift
    orig_Drift_Release = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ReleaseDrifting", 0, (void *)hook_DriftRelease);
    orig_Drift_ExitCurDriftState = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ExitCurDriftState", 0, (void *)hook_DriftExitCurState);
    orig_Drift_ForceClearDriftParams = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ForceClearDriftParams", 0, (void *)hook_DriftForceClear);

    // 4. Gia Tốc / Speed Boost
    orig_PowerChain_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehiclePowerChain", "Update", 1, (void *)hook_PowerChainUpdate);

    // 5. Anti-Cheat Report
    orig_SdcVehicleVel_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleVel", "Update", 1, (void *)hook_SdcVehicleVelUpdate);

    // 6. CheckPoint & Lap time
    orig_CheckPointMgr_Init = (void (*)(void *, void *, bool, bool, const void *))
        rtHookMethod("", "CheckPointMgr", "Init", 3, (void *)hook_CheckPointMgrInit);
    orig_ActorCpReporter_Update = (void (*)(void *, float, float, const void *))
        rtHookMethod("", "ActorCpReporter", "Update", 2, (void *)hook_ActorCpReporterUpdate);

    // 7. MotionCtrl (Auto Play & RAM Vehicle ID)
    orig_MotionCtrl_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleMotionCtrl", "Update", 1, (void *)hook_MotionCtrlUpdate);

    // Auto Play layer B: synthesise the discrete input keys (Drift / SmallBoost /
    // Left / Right). InputModule.GetKey is the single funnel every consumer reads.
    orig_Input_GetKey = (BOOL (*)(void *, int, const void *))
        rtHookMethod("", "InputModule", "GetKey", 1, (void *)hook_Input_GetKey);

    // 8. Sức mạnh đổi hướng + Auto Play steering (DoSteering)
    orig_PhyVehicleCtrl_DoSteering = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleCtrl", "DoSteering", 1, (void *)hook_PhyVehicleCtrl_DoSteering);

    // 9. Mod Xe trong Sảnh / Lobby (Item3DPreviewSystem)
    orig_Previewer_ShowVehicle = (void (*)(void *, void *, uint32_t, void *, void *, const void *))
        rtHookMethod("", "Item3DPreviewSystem.CustomPlayerPreviewer", "ShowVehicle", 4, (void *)hook_Previewer_ShowVehicle);
    if (!orig_Previewer_ShowVehicle) {
        orig_Previewer_ShowVehicle = (void (*)(void *, void *, uint32_t, void *, void *, const void *))
            rtHookMethod("", "Item3DPreviewSystem.PlayerPreviewer", "ShowVehicle", 4, (void *)hook_Previewer_ShowVehicle);
    }

    // 10. Mod Xe khi Vào Trận / Load Trận (PreInit & ModelID)
    orig_NssVehicle_PreInit = (void (*)(void *, uint64_t, int, void *, const void *))
        rtHookMethod("", "NssVehicle", "PreInit", 3, (void *)hook_NssVehicle_PreInit);
    orig_NssVehicle_GetVehicleID = (int (*)(void *, const void *))
        rtHookMethod("", "NssVehicle", "GetVehicleID", 0, (void *)hook_NssVehicle_GetVehicleID);
    orig_ItemVehicle_GetModelID = (uint64_t (*)(void *, const void *))
        rtHookMethod("", "ItemVehicle", "GetVechicleModelID", 0, (void *)hook_ItemVehicle_GetModelID);

    rtLog("install: done (all hooks active)");
}

#pragma mark - Modern UI Implementation with Vehicle/Skin Dropdown

@interface RCPassThroughWindow : UIWindow
@end

@implementation RCPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if (hit == self) return nil;
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeFocused  { return NO; }
@end

// Vehicle & Skin Catalog Definition
typedef struct {
    int vehicleID;
    int skinID;
    const char *displayName;
} RCVehicleItem;

static const RCVehicleItem kVehicleCatalog[] = {
    { 0,     0,     "Mặc định (Không Mod)" },
    { 4,     0,     "[A] 雷诺 / Lôi Nặc (Renault)" },
    { 4,     10004, "[A-Skin] Lôi Nặc - Hoàng Kim (Gold)" },
    { 439,   0,     "[S] 冰魄 / Băng Phách (S-Ice Soul)" },
    { 439,   10439, "[S-Skin] Băng Phách - Thiên Sứ (Angel)" },
    { 511,   0,     "[T-Mecha] 序列未来 (Future Sequence)" },
    { 511,   10511, "[T-Skin] T-Future - Thiên Ngoại (Galaxy)" },
    { 539,   0,     "[A] 孙悟空 / Tôn Ngộ Không (Sun Wukong)" },
    { 539,   10539, "[A-Skin] Ngộ Không - Tề Thiên Đại Thánh" },
    { 552,   0,     "[A] 幻星 / Huyễn Tinh (Phantasm Star)" },
    { 567,   0,     "[B] 奶瓶 / Bình Sữa (Magic Bottle)" },
    { 579,   0,     "[A] 破晓 / Phá Hiểu (Daybreak)" },
    { 590,   0,     "[T-Mecha] 冥王哈迪斯 (Hades Mecha)" },
    { 590,   10590, "[T-Skin] Hades - Dạ Quỷ (Night Hades)" },
    { 400,   0,     "[S] 追光者 / Truy Quang (Light Chaser)" },
    { 410,   0,     "[S] 逐星者 / Trục Tinh (Star Chaser)" },
    { 450,   0,     "[S] 裁决者 / Tài Quyết (S-Judgement)" },
    { 480,   0,     "[S] 天行者 / Thiên Hành (S-Skywalker)" },
    { 500,   0,     "[T-Mecha] 源极之星EXA (Origin Star T1)" },
    { 520,   0,     "[A] 地狱天启 / Địa Ngục Thiên Khải" },
    { 530,   0,     "[A] 双生战神 / Song Sinh Chiến Thần" },
    { 540,   0,     "[A] 迈凯伦600LT / McLaren 600LT" },
    { 560,   0,     "[A] 劳斯莱斯曜影 / Rolls-Royce Dawn" },
    { 580,   0,     "[A] 兰博基尼 / Lamborghini RACING" },
    { 600,   0,     "[T-Mecha] 红喷奥特曼 / Ultraman Mecha" }
};
static const int kVehicleCatalogCount = sizeof(kVehicleCatalog) / sizeof(kVehicleCatalog[0]);

@interface RCRaceToolkitMenu : NSObject
@property (nonatomic, strong) RCPassThroughWindow *window;
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIScrollView *scrollView;

// Dropdown components
@property (nonatomic, strong) UIButton *dropdownBtn;
@property (nonatomic, strong) UIView *dropdownPopup;
@property (nonatomic, strong) UIScrollView *dropdownScroll;

// Labels
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *steerLabel;

// Top HUD Overlay
@property (nonatomic, strong) UIView *topHud;
@property (nonatomic, strong) UILabel *topTimeLabel;
@property (nonatomic, strong) UILabel *topFinishLabel;
@property (nonatomic, strong) NSTimer *hudTimer;
@end

static RCRaceToolkitMenu *gMenu = nil;

@implementation RCRaceToolkitMenu

- (UISwitch *)addSwitchAtY:(CGFloat)y title:(NSString *)title on:(BOOL)on action:(SEL)action {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 4, 190, 24)];
    l.text = title;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.scrollView addSubview:l];

    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(220, y, 51, 31)];
    s.onTintColor = [UIColor colorWithRed:0.18 green:0.85 blue:0.55 alpha:1.0];
    s.on = on;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:s];
    return s;
}

- (void)build {
    CGRect screen = UIScreen.mainScreen.bounds;

    self.window = [[RCPassThroughWindow alloc] initWithFrame:screen];

    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            if (sc.activationState != UISceneActivationStateForegroundActive) continue;
            self.window.windowScene = (UIWindowScene *)sc;
            break;
        }
    }
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.opaque = NO;
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.rootViewController.view.opaque = NO;
    self.window.hidden = NO;

    self.host = self.window.rootViewController.view;

    // === TOP HUD OVERLAY ===
    CGFloat hudW = 340, hudH = 46;
    self.topHud = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - hudW) / 2, 8, hudW, hudH)];
    self.topHud.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.92];
    self.topHud.layer.cornerRadius = 14;
    self.topHud.layer.borderWidth = 1.0;
    self.topHud.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.topHud.userInteractionEnabled = NO;

    self.topTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, hudW - 16, 18)];
    self.topTimeLabel.textColor = UIColor.whiteColor;
    self.topTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
    self.topTimeLabel.textAlignment = NSTextAlignmentCenter;
    self.topTimeLabel.text = @"MinMap: --:-- | LapMin: --:-- | Time: 00:00.0";
    [self.topHud addSubview:self.topTimeLabel];

    self.topFinishLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 24, hudW - 16, 18)];
    self.topFinishLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
    self.topFinishLabel.textAlignment = NSTextAlignmentCenter;
    self.topFinishLabel.textColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
    self.topFinishLabel.text = @"Can Finish: FALSE";
    [self.topHud addSubview:self.topFinishLabel];

    [self.host addSubview:self.topHud];

    self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                     target:self
                                                   selector:@selector(updateTopHud)
                                                   userInfo:nil
                                                    repeats:YES];

    // === FLOATING BUTTON (FAB) ===
    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(screen.size.width - 66, 96, 54, 54);
    self.fab.backgroundColor = [UIColor colorWithRed:0.08 green:0.48 blue:0.98 alpha:0.94];
    self.fab.layer.cornerRadius = 27;
    self.fab.layer.borderWidth = 1.5;
    self.fab.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    [self.fab setTitle:@"R" forState:UIControlStateNormal];
    self.fab.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)]];
    [self.host addSubview:self.fab];

    // === MODERN MENU PANEL ===
    CGFloat w = 310, h = 420;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2,
                                                        (screen.size.height - h) / 2, w, h)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.96];
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderWidth = 1.0;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    self.panel.hidden = YES;
    [self.host addSubview:self.panel];

    // Panel Header
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 44)];
    header.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    header.layer.cornerRadius = 18;
    [self.panel addSubview:header];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 200, 24)];
    title.text = @"Race Toolkit Pro";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    [header addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 40, 8, 28, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];

    // ScrollView
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 44, w, h - 44)];
    self.scrollView.contentSize = CGSizeMake(w, 460);
    self.scrollView.showsVerticalScrollIndicator = YES;
    [self.panel addSubview:self.scrollView];

    CGFloat curY = 10;

    // 1. Toggles
    [self addSwitchAtY:curY title:@"Auto Play (AI Tự Đua)" on:gAutoPlay action:@selector(onAutoPlay:)];
    curY += 36;

    [self addSwitchAtY:curY title:@"Inf Mini Boost" on:gFullMiniBoost action:@selector(onMini:)];
    curY += 36;

    [self addSwitchAtY:curY title:@"Auto End Drift" on:gAutoDriftEnd action:@selector(onAutoDrift:)];
    curY += 40;

    // 2. Slider 1: Speed Boost
    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, curY, 268, 18)];
    self.speedLabel.textColor = UIColor.whiteColor;
    self.speedLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    self.speedLabel.text = [self speedText];
    [self.scrollView addSubview:self.speedLabel];
    curY += 20;

    UISlider *speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, curY, 268, 28)];
    speedSlider.minimumValue = 0.f;
    speedSlider.maximumValue = 300.f;
    speedSlider.value = gSpeedKmh;
    speedSlider.tintColor = [UIColor colorWithRed:0.20 green:0.80 blue:0.55 alpha:1.0];
    [speedSlider addTarget:self action:@selector(onSpeedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:speedSlider];
    curY += 34;

    // 3. Slider 2: Sức mạnh đổi hướng
    self.steerLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, curY, 268, 18)];
    self.steerLabel.textColor = UIColor.whiteColor;
    self.steerLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    self.steerLabel.text = [self steerText];
    [self.scrollView addSubview:self.steerLabel];
    curY += 20;

    UISlider *steerSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, curY, 268, 28)];
    steerSlider.minimumValue = 0.5f;
    steerSlider.maximumValue = 3.0f;
    steerSlider.value = gSteerStrength;
    steerSlider.tintColor = [UIColor colorWithRed:0.10 green:0.65 blue:1.0 alpha:1.0];
    [steerSlider addTarget:self action:@selector(onSteerChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:steerSlider];
    curY += 38;

    // 4. Section: Mod Skin / Xe (Dropdown Selection)
    [self addSwitchAtY:curY title:@"Bật Mod Xe / Skin" on:gModEnabled action:@selector(onModEnabled:)];
    curY += 36;

    UILabel *dropdownLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, curY, 268, 18)];
    dropdownLabel.text = @"Chọn Xe & Skin:";
    dropdownLabel.textColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1.0];
    dropdownLabel.font = [UIFont boldSystemFontOfSize:12.5];
    [self.scrollView addSubview:dropdownLabel];
    curY += 20;

    // Interactive Dropdown Button
    self.dropdownBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dropdownBtn.frame = CGRectMake(16, curY, 268, 34);
    self.dropdownBtn.backgroundColor = [UIColor colorWithRed:0.14 green:0.16 blue:0.22 alpha:1.0];
    self.dropdownBtn.layer.cornerRadius = 8;
    self.dropdownBtn.layer.borderWidth = 1.0;
    self.dropdownBtn.layer.borderColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:0.5].CGColor;
    [self.dropdownBtn setTitle:[NSString stringWithUTF8String:kVehicleCatalog[0].displayName] forState:UIControlStateNormal];
    [self.dropdownBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.dropdownBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.dropdownBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.dropdownBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    [self.dropdownBtn addTarget:self action:@selector(toggleDropdown) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.dropdownBtn];
    curY += 40;

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(16, curY, 268, 36)];
    note.numberOfLines = 2;
    note.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    note.font = [UIFont systemFontOfSize:10.5];
    note.text = @"Tự động đổi xe ở Sảnh và ngay khi Vào Trận / Load Trận.\nBật Auto Play để AI bám tim đường & giữ ga liên tục.";
    [self.scrollView addSubview:note];
    curY += 44;

    self.scrollView.contentSize = CGSizeMake(w, curY + 10);

    // === DROPDOWN POPUP OVERLAY ===
    self.dropdownPopup = [[UIView alloc] initWithFrame:CGRectMake(16, 90, w - 32, 260)];
    self.dropdownPopup.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.18 alpha:0.98];
    self.dropdownPopup.layer.cornerRadius = 12;
    self.dropdownPopup.layer.borderWidth = 1.5;
    self.dropdownPopup.layer.borderColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:0.8].CGColor;
    self.dropdownPopup.hidden = YES;
    [self.panel addSubview:self.dropdownPopup];

    UILabel *popupTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 200, 20)];
    popupTitle.text = @"Danh sách Xe & Skin:";
    popupTitle.textColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1.0];
    popupTitle.font = [UIFont boldSystemFontOfSize:12.5];
    [self.dropdownPopup addSubview:popupTitle];

    UIButton *popupClose = [UIButton buttonWithType:UIButtonTypeCustom];
    popupClose.frame = CGRectMake(w - 32 - 32, 6, 26, 26);
    [popupClose setTitle:@"✕" forState:UIControlStateNormal];
    popupClose.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [popupClose setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [popupClose addTarget:self action:@selector(toggleDropdown) forControlEvents:UIControlEventTouchUpInside];
    [self.dropdownPopup addSubview:popupClose];

    self.dropdownScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 32, w - 32, 220)];
    self.dropdownScroll.showsVerticalScrollIndicator = YES;
    [self.dropdownPopup addSubview:self.dropdownScroll];

    CGFloat optY = 4;
    for (int i = 0; i < kVehicleCatalogCount; i++) {
        UIButton *opt = [UIButton buttonWithType:UIButtonTypeCustom];
        opt.frame = CGRectMake(8, optY, w - 32 - 16, 28);
        opt.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
        opt.layer.cornerRadius = 6;
        opt.tag = i;
        [opt setTitle:[NSString stringWithUTF8String:kVehicleCatalog[i].displayName] forState:UIControlStateNormal];
        [opt setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        opt.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        opt.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        opt.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
        [opt addTarget:self action:@selector(selectVehicleOption:) forControlEvents:UIControlEventTouchUpInside];
        [self.dropdownScroll addSubview:opt];
        optY += 32;
    }
    self.dropdownScroll.contentSize = CGSizeMake(w - 32, optY + 8);
}

- (void)updateTopHud {
    float curTime = gCurrentMatchTime;
    if (curTime <= 0.f && gGoTime > 0.0) {
        curTime = (float)(nowSeconds() - gGoTime);
    }

    int mapM = (int)(gMinMapTimeSeconds / 60.0f);
    float mapS = gMinMapTimeSeconds - (float)(mapM * 60);

    int lapM = (int)(gLapTimeLimit / 60.0f);
    float lapS = gLapTimeLimit - (float)(lapM * 60);

    int curM = (int)(curTime / 60.0f);
    float curS = curTime - (float)(curM * 60);

    self.topTimeLabel.text = [NSString stringWithFormat:@"MinMap: %02d:%04.1f | LapMin: %02d:%04.1f | Time: %02d:%04.1f",
                              mapM, mapS, lapM, lapS, curM, curS];

    if (gCanFinish) {
        self.topFinishLabel.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.45 alpha:1.0];
        self.topFinishLabel.text = @"Can Finish: TRUE (Safe to Finish)";
        self.topHud.layer.borderColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.45 alpha:0.6].CGColor;
    } else {
        float remaining = gMinMapTimeSeconds > curTime ? (gMinMapTimeSeconds - curTime) : 0.f;
        self.topFinishLabel.textColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
        if (remaining > 0.f) {
            self.topFinishLabel.text = [NSString stringWithFormat:@"Can Finish: FALSE (Wait %.1fs)", remaining];
        } else {
            self.topFinishLabel.text = @"Can Finish: FALSE (Time not reached)";
        }
        self.topHud.layer.borderColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:0.4].CGColor;
    }
}

- (NSString *)speedText {
    return [NSString stringWithFormat:@"Boost speed: %d km/h (+5s gate)", (int)gSpeedKmh];
}

- (NSString *)steerText {
    return [NSString stringWithFormat:@"Sức mạnh đổi hướng: %.1fx", gSteerStrength];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.hidden = NO;
    if (self.panel.hidden) {
        self.dropdownPopup.hidden = YES;
    }
}

- (void)toggleDropdown {
    self.dropdownPopup.hidden = !self.dropdownPopup.hidden;
    if (!self.dropdownPopup.hidden) {
        [self.panel bringSubviewToFront:self.dropdownPopup];
    }
}

- (void)selectVehicleOption:(UIButton *)btn {
    int idx = (int)btn.tag;
    if (idx >= 0 && idx < kVehicleCatalogCount) {
        gSelectedPreset = idx;
        gModVehicleID = kVehicleCatalog[idx].vehicleID;
        gModSkinID = kVehicleCatalog[idx].skinID;
        [self.dropdownBtn setTitle:[NSString stringWithUTF8String:kVehicleCatalog[idx].displayName] forState:UIControlStateNormal];
        self.dropdownPopup.hidden = YES;
        rtLog("selected vehicle: ID=%d, Skin=%d (%s)", gModVehicleID, gModSkinID, kVehicleCatalog[idx].displayName);

        // Apply immediately if already driving
        if (gModEnabled && rtPtrOk(gCurrentVehicle)) {
            *(int *)((char *)gCurrentVehicle + kOffVehicleID) = gModVehicleID;
        }
    }
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}

- (void)onAutoPlay:(UISwitch *)s {
    gAutoPlay = s.isOn;
    rtLog("toggle AutoPlay=%d", s.isOn);
}

- (void)onMini:(UISwitch *)s {
    gFullMiniBoost = s.isOn;
    rtLog("toggle FullMiniBoost=%d", s.isOn);
}

- (void)onAutoDrift:(UISwitch *)s {
    gAutoDriftEnd = s.isOn;
    rtLog("toggle AutoEndDrift=%d", s.isOn);
}

- (void)onModEnabled:(UISwitch *)s {
    gModEnabled = s.isOn;
    rtLog("toggle ModEnabled=%d (VehicleID=%d, SkinID=%d)", s.isOn, gModVehicleID, gModSkinID);
    if (gModEnabled && rtPtrOk(gCurrentVehicle) && gModVehicleID > 0) {
        *(int *)((char *)gCurrentVehicle + kOffVehicleID) = gModVehicleID;
    }
}

- (void)onSpeedChanged:(UISlider *)s {
    gSpeedKmh = s.value;
    self.speedLabel.text = [self speedText];
}

- (void)onSteerChanged:(UISlider *)s {
    gSteerStrength = s.value;
    self.steerLabel.text = [self steerText];
}

@end

#pragma mark - Bootstrap

static void buildMenuSafely(void) {
    if (gMenu) return;
    @try {
        gMenu = [RCRaceToolkitMenu new];
        [gMenu build];
        rtLog("UI: modern menu built");
    } @catch (NSException *e) {
        gMenu = nil;
        rtLog("UI: menu build FAILED: %s", e.reason.UTF8String ?: "?");
    }
}

static void startToolkit(void) {
    static int tries = 0;
    if (!rtInitIl2CppApi()) {
        if (++tries > 60) {
            rtLog("bootstrap: gave up waiting for IL2CPP API in UnityFramework");
            buildMenuSafely();
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }

    Il2CppDomain *domain = il2cpp_domain_get();
    size_t count = 0;
    const Il2CppAssembly **assemblies = domain ? il2cpp_domain_get_assemblies(domain, &count) : NULL;
    if (!assemblies || count == 0) {
        if (++tries > 60) {
            rtLog("bootstrap: gave up waiting for IL2CPP domain/assemblies");
            buildMenuSafely();
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }

    rtLog("bootstrap: IL2CPP ready (%zu assemblies) after %d polls", count, tries);
    if (!gHooksInstalled) {
        gHooksInstalled = YES;
        installHooks();
    }
    buildMenuSafely();
}

__attribute__((constructor)) static void RCInit(void) {
    rtLogOpen();
    rtInstallCrashHandler();
    rtLog("=== RaceToolkit session start ===\nlog: %s\npid=%d", gLogPath, getpid());
    rtLog("architecture: IL2CPP VTable & Metadata Hook (zero __TEXT patch)");
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "UnityFramework") || strstr(name, "zsmvn") || strstr(name, "Bypass"))) {
            rtLog("IMAGE base=%p slide=%lld path=%s", (void *)_dyld_get_image_header(i),
                  (long long)_dyld_get_image_vmaddr_slide(i), name);
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ startToolkit(); });
}
