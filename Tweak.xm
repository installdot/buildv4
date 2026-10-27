// Tweak.xm — Race Toolkit (iOS, IL2CPP VTable & Metadata Hook)
//
// Features & Fixes:
// 1. Auto Racing (Full Bot): Tu dong danh lai, di chuyen, vao cua drift, thoat cua kich hoat CWW Boost & MiniBoost.
// 2. Guide Line & Arrows: Ve duong chi dan to ro rang tren mat duong + mui ten om cua tu xa.
// 3. Miniboost: Goi ForceCanTriggerOnce(Mini/Air/FallingGround) lien tuc, khong giu o muc 2 nua.
// 4. Auto End Drift: Goi ExitCurDriftState + ForceClearDriftParams ngay khi nha nut drift -> Khong con dinh drift.
// 5. Speed Boost: Chi bat dau kich hoat sau 5 giay tu khi xuat phat (GameGoState::ImpEnter).
// 6. Anti-Cheat Report: Khoa SdcVehicleVel o muc 300 km/h.
// 7. Top Overlay: Hien thi MinMapTime, LapTimeLimit & Can Finish (TRUE/FALSE).

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

static BOOL   gAutoRacing     = NO;  // Tu dong dua (Auto Racing Bot)
static BOOL   gGuideLine      = YES; // Bat duong chi dan ro net
static BOOL   gFullMiniBoost  = NO;
static BOOL   gAutoDriftEnd   = NO;
static float  gSpeedKmh       = 0.f;
static double gGoTime         = 0.0;
static BOOL   gHooksInstalled = NO;

// Race status & metrics
static float  gCurrentMatchTime  = 0.f;
static float  gMainCurveLength   = 0.f;
static int    gMapTotalLaps      = 2;
static float  gMinMapTimeSeconds = 0.f;
static float  gLapTimeLimit      = 0.f;
static BOOL   gCanFinish         = NO;
static int    gLastCheckPointId  = 0;

// Cached TraceLine Component pointer
static void  *gTraceLineComp     = NULL;

// Autopilot state variables (declared early for hook_GoImpEnter)
static int   s_BotClosestIdx     = -1;
static BOOL  s_BotDrifting       = NO;
static int   s_BotDriftDir       = 0;
static int   s_BotDriftExit      = 0;

enum {
    // ExtraVelocityTriggerMgr
    kOffExVelReserveMgr   = 144, // 0x90 mReserveSmallBoostMgr

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
};

static inline double nowSeconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

#pragma mark - IL2CPP Runtime API & Structures

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef void (*Il2CppMethodPointer)();

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
    const Il2CppAssembly **assemblies = il2cpp_domain_get_assemblies(domain, &count);
    if (!assemblies || count == 0) return NULL;
    for (size_t i = 0; i < count; i++) {
        const Il2CppImage *image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        Il2CppClass *k = il2cpp_class_from_name(image, namespaze ?: "", name);
        if (k) return k;
    }
    return NULL;
}

static void *rtGetMethodPointer(const char *namespaze, const char *className,
                                const char *methodName, int argsCount) {
    Il2CppClass *klass = rtFindClass(namespaze, className);
    if (!klass) return NULL;
    const MethodInfo *method = il2cpp_class_get_method_from_name(klass, methodName, argsCount);
    if (!method) return NULL;
    return *(void **)((char *)method + 0);
}

// Resolve a method pointer by exact RVA. Needed for overloaded names where
// arg-count alone is ambiguous (e.g. BeginSteering(float) vs BeginSteering(NssSteerDir)).
static void *rtGetMethodPointerByRva(const char *namespaze, const char *className, uint32_t rva) {
    Il2CppClass *klass = rtFindClass(namespaze, className);
    uintptr_t base = unityFrameworkBase();
    if (!klass || !base) return NULL;

    // Class::Init phải chạy trước thì klass->methods (0x98) mới được build.
    // Gọi get_method_from_name với 1 method bất kỳ để ép init.
    if (il2cpp_class_get_method_from_name) {
        il2cpp_class_get_method_from_name(klass, ".ctor", -1);
        il2cpp_class_get_method_from_name(klass, "Update", -1);
        il2cpp_class_get_method_from_name(klass, "ToggleDrifting", -1);
    }

    uint16_t n = *(uint16_t *)((char *)klass + 296);   // method_count
    void *methods = *(void **)((char *)klass + 152);   // methods
    if (n && methods) {
        for (uint16_t i = 0; i < n; i++) {
            void *m = *(void **)((char *)methods + i * 8);
            if (!m) continue;
            void *ptr = *(void **)((char *)m + 0);
            if (ptr && (uintptr_t)ptr - base == (uintptr_t)rva) return ptr;
        }
    }

    // Fallback: quét toàn bộ method của class bằng get_methods iterator
    // (dùng khi method_count == 0 vì chưa Init)
    return NULL;
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

#pragma mark - Original function pointers & Replacements

static void  (*orig_GameGo_ImpEnter)(void *, const void *) = NULL;

static void  (*orig_ExVelMgr_Update)(void *, float, const void *) = NULL;
static void  (*orig_Drift_Release)(void *, const void *) = NULL;
static void  (*orig_Drift_ExitCurDriftState)(void *, const void *) = NULL;
static void  (*orig_Drift_ForceClearDriftParams)(void *, const void *) = NULL;

static void  (*orig_PowerChain_Update)(void *, float, const void *) = NULL;
static void  (*orig_SdcVehicleVel_Update)(void *, float, const void *) = NULL;
static void  (*orig_CheckPointMgr_Init)(void *, void *, bool, bool, const void *) = NULL;
static void  (*orig_ActorCpReporter_Update)(void *, float, float, const void *) = NULL;

// Guide Line & TraceLine
static void  (*orig_TraceLineConfig_Init)(void *, int, const void *) = NULL;
static BOOL  (*orig_TraceLineComponent_GameModeForceOpen)(void *, const void *) = NULL;
static BOOL  (*orig_TraceLineComponent_EnableUpdate)(void *, const void *) = NULL;
static void  (*orig_TraceLineComponent_Update)(void *, float, const void *) = NULL;

// Native methods invoked directly
static void  (*ExtraVelocityTriggerMgr_ForceCanTriggerOnce)(void *, int, const void *) = NULL;
static void  (*ExtraVelocityFast_DoPerfectCWWBoost)(void *, const void *) = NULL;
static void *(*TraceLineComponent_GetTraceLinePoints)(void *, const void *) = NULL;

static void  (*NssPhyVehicleCab_ThrottleDown)(void *, float, const void *) = NULL;
static void  (*NssPhyVehicleCab_BeginSteeringAnalog)(void *, float, const void *) = NULL;
static BOOL  (*NssPhyVehicleCab_BeginDrifting)(void *, int, const void *) = NULL;
static BOOL  (*NssPhyVehicleCab_EndDrifting)(void *, int, const void *) = NULL;

// Drift state machine entry points. Cab::BeginDrifting chỉ push button vào queue,
// KHÔNG chuyển DriftStateMachine. Chỉ DriftCtrl::ToggleDrifting mới thật sự vào drift.
static void  (*NssVehicleDriftCtrl_ToggleDrifting_)(void *, float, const void *) = NULL;
static void  (*NssVehicleDriftCtrl_ReleaseDrifting_)(void *, const void *) = NULL;

static void  (*orig_MotionCtrl_Update)(void *, float, const void *) = NULL;

// 1. Race Start
static void hook_GoImpEnter(void *self, const void *method) {
    if (orig_GameGo_ImpEnter) orig_GameGo_ImpEnter(self, method);
    gGoTime = nowSeconds();
    gCurrentMatchTime = 0.f;
    gCanFinish = NO;
    s_BotClosestIdx = -1;
    s_BotDrifting = NO;
    rtLog("race started -> gGoTime=%.3f, MinMapTime=%.1fs, LapTimeLimit=%.1fs",
          gGoTime, gMinMapTimeSeconds, gLapTimeLimit);
}

// 2. Mini Boost: Gọi ForceCanTriggerOnce(Mini/Air/FallingGround) liên tục
static void hook_ExVelMgrUpdate(void *self, float dt, const void *method) {
    if (orig_ExVelMgr_Update) orig_ExVelMgr_Update(self, dt, method);
    if (!gFullMiniBoost || !self) return;

    if (ExtraVelocityTriggerMgr_ForceCanTriggerOnce) {
        ExtraVelocityTriggerMgr_ForceCanTriggerOnce(self, 2, nullptr);  // Mini
        ExtraVelocityTriggerMgr_ForceCanTriggerOnce(self, 3, nullptr);  // Air
        ExtraVelocityTriggerMgr_ForceCanTriggerOnce(self, 11, nullptr); // FallingGround
    }
}

// 3. Auto End Drift: Tránh dính drift
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

// 4. PowerChain Speed Boost (chỉ boost, autopilot tách riêng sang Cab::Update)
static void hook_PowerChainUpdate(void *self, float dt, const void *method) {
    if (orig_PowerChain_Update) orig_PowerChain_Update(self, dt, method);
    if (!self || gSpeedKmh <= 0.f) return;

    if (gGoTime <= 0.0 || (nowSeconds() - gGoTime) < 5.0) return;

    *(float *)((char *)self + kOffPowerExtraKMPH)    = gSpeedKmh;
    *(float *)((char *)self + kOffPowerExtraTorque)  = gSpeedKmh * 10.0f;
    *(float *)((char *)self + kOffPowerMPSScaleCoef) = 1.0f + (gSpeedKmh / 120.0f);
    *(float *)((char *)self + kOffPowerTorqueScale)  = 1.0f + (gSpeedKmh / 120.0f);
}

// ---------------------------------------------------------------------------
// AUTOPILOT — TRACE-LINE FOLLOWER
// ---------------------------------------------------------------------------
// FIX 1: UpdateDrivingData (0x7AF6EC8) là non-virtual, được gọi bằng BL trực tiếp
//        từ MotionCtrl::Update (0x7B107D8) => patch methodPointer KHÔNG có tác dụng.
//        Phải ghi vào NssSteeringData (tham số a2) mà MotionCtrl truyền vào.
// FIX 2: NssSteeringData layout (dump.cs 36143):
//          0x10 float mForward        <- throttle
//          0x14 int   mBrakingState   <- NssVehicleBrakeState (None=0)
//          0x18 bool  mIsHandbrake
//          0x19 bool  mIsTimeRel
//          0x1A bool  mIsFixWheel
//          0x1C float mSteeringLeft   <- steering: Left=+1.0, Right=-1.0
// FIX 3: NssPhyVehicleDrivingCtrl::UpdateDrivingData đọc steeringData->mForward
//        và steeringData->mSteeringLeft, KHÔNG đọc drivingCtrl+0x3C/0x40.

#define kSdForward      0x10   // float  mForward
#define kSdBrakingState 0x14   // int    mBrakingState
#define kSdHandbrake    0x18   // bool   mIsHandbrake
#define kSdSteering     0x1C   // float  mSteeringLeft

#define kDriveToDyn     0x10   // NssPhyVehicleDrivingCtrl.mVehicle (IDynamicVehicle)
#define kDriveToPhyCtrl 0x18   // NssPhyVehicleDrivingCtrl.mVehiclePhyCtrl
#define kPhyToSim       0x28   // NssPhyVehicleCtrl.mSimulateOutput

#define kDynCab         0x30
#define kDynVehicle     0x10
#define kDynDriftCtrl   0x60   // qua mDriftCtrl của MotionCtrlHelper; thực tế lấy từ dyn+0x38+0x60

#define kSimKmph        0x10
#define kSimPos         0x64
#define kSimRot         0x70

#define kTlpPos         0x10
#define kTlpDriftFlag   0x37

static void rtAutoDrive(void *drivingCtrl, void *sd) {
    if (!drivingCtrl) return;

    // --- Luôn đạp ga tiến, không bao giờ phanh ---
    if (sd) {
        *(float *)((char *)sd + kSdForward)      = 1.0f;
        *(int   *)((char *)sd + kSdBrakingState) = 0;     // None
        *(uint8_t *)((char *)sd + kSdHandbrake)  = 0;
    }

    if (!gAutoRacing || !gTraceLineComp || !TraceLineComponent_GetTraceLinePoints) return;
    if (!sd) return;

    void *listView = TraceLineComponent_GetTraceLinePoints(gTraceLineComp, nullptr);
    if (!listView) return;
    void *ctx = *(void **)((char *)listView + 0x10);
    int size  = *(int *)((char *)listView + 0x18);
    if (!ctx || size < 10) return;
    void **items = (void **)((char *)ctx + 0x20);

    void *dyn0 = *(void **)((char *)drivingCtrl + kDriveToDyn);   // IDynamicVehicle
    void *phyCtrl = *(void **)((char *)drivingCtrl + kDriveToPhyCtrl);
    if (!phyCtrl) phyCtrl = dyn0 ? *(void **)((char *)dyn0 + 0x40) : NULL;
    if (!phyCtrl) return;
    void *sim = *(void **)((char *)phyCtrl + kPhyToSim);
    if (!sim) return;

    float px = *(float *)((char *)sim + kSimPos);
    float pz = *(float *)((char *)sim + kSimPos + 8);

    // Heading từ quaternion chassis (hợp lệ cả khi xe đứng yên)
    float qx = *(float *)((char *)sim + kSimRot);
    float qy = *(float *)((char *)sim + kSimRot + 4);
    float qz = *(float *)((char *)sim + kSimRot + 8);
    float qw = *(float *)((char *)sim + kSimRot + 12);

    float fwdX = 2.0f * (qx * qz + qw * qy);
    float fwdZ = 1.0f - 2.0f * (qx * qx + qy * qy);
    float fl = sqrtf(fwdX * fwdX + fwdZ * fwdZ);
    if (fl < 1e-4f) return;
    fwdX /= fl; fwdZ /= fl;
    float heading = atan2f(fwdX, fwdZ);

    // Tìm điểm gần nhất. Lần đầu quét toàn map; sau đó chỉ tiến (chống quay đầu).
    if (s_BotClosestIdx < 0 || s_BotClosestIdx >= size) {
        float best = 1e30f; int bi = 0;
        for (int i = 0; i < size; i++) {
            void *pt = items[i]; if (!pt) continue;
            float dx = *(float *)((char *)pt + kTlpPos) - px;
            float dz = *(float *)((char *)pt + kTlpPos + 8) - pz;
            float d = dx * dx + dz * dz;
            if (d < best) { best = d; bi = i; }
        }
        s_BotClosestIdx = bi;
    } else {
        float best = 1e30f; int bi = s_BotClosestIdx;
        for (int step = -2; step <= 24; step++) {
            int idx = (s_BotClosestIdx + step + size) % size;
            void *pt = items[idx]; if (!pt) continue;
            float dx = *(float *)((char *)pt + kTlpPos) - px;
            float dz = *(float *)((char *)pt + kTlpPos + 8) - pz;
            float d = dx * dx + dz * dz;
            if (d < best) { best = d; bi = idx; }
        }
        // Nếu lệch quá xa (>25m) thì coi như mất dấu, quét lại toàn map
        if (best > 625.0f) {
            best = 1e30f;
            for (int i = 0; i < size; i++) {
                void *pt = items[i]; if (!pt) continue;
                float dx = *(float *)((char *)pt + kTlpPos) - px;
                float dz = *(float *)((char *)pt + kTlpPos + 8) - pz;
                float d = dx * dx + dz * dz;
                if (d < best) { best = d; bi = i; }
            }
        }
        s_BotClosestIdx = bi;
    }

    // Nhìn trước ngắn để bám sát vạch
    int look = 4;
    int tIdx = (s_BotClosestIdx + look) % size;
    void *tgt = items[tIdx];
    if (!tgt) return;

    float tx = *(float *)((char *)tgt + kTlpPos);
    float tz = *(float *)((char *)tgt + kTlpPos + 8);
    uint8_t wantDrift = *(uint8_t *)((char *)tgt + kTlpDriftFlag);

    float da = atan2f(tx - px, tz - pz) - heading;
    while (da >  (float)M_PI) da -= 2.0f * (float)M_PI;
    while (da < -(float)M_PI) da += 2.0f * (float)M_PI;

    // Left = +1.0, Right = -1.0  (theo _UpdateCabSteering: Left += 1.0, Right += -1.0)
    // da > 0  => mục tiêu lệch sang phải  => steering âm (rẽ phải)
    float steer = -da * 2.4f;
    if (steer >  1.0f) steer =  1.0f;
    if (steer < -1.0f) steer = -1.0f;

    *(float *)((char *)sd + kSdSteering) = steer;

    // --- Drift & CWW ---
    void *dyn = dyn0;
    void *cab = dyn ? *(void **)((char *)dyn + kDynCab) : NULL;
    void *veh = dyn ? *(void **)((char *)dyn + kDynVehicle) : NULL;
    void *dc  = NULL;
    if (dyn) {
        void *mc = *(void **)((char *)dyn + 0x38);
        if (mc) dc = *(void **)((char *)mc + 0x60);
    }

    float kmph = *(float *)((char *)sim + kSimKmph);

    // Vùng vàng drift: Drift flag HOẶC DriftingPercent > 0 HOẶC góc cua lớn
    float driftPct = *(float *)((char *)tgt + 0x60);   // TraceLinePoint.DriftingPercent
    BOOL inDriftZone = wantDrift || (driftPct > 0.01f) ||
                       (fabsf(da) > 0.30f && kmph > 65.0f);

    // LAZY RESOLVE: class methods chỉ tồn tại sau khi Class::Init chạy lần đầu
    static BOOL s_DriftResolved = NO;
    if (!s_DriftResolved) {
        if (!NssVehicleDriftCtrl_ToggleDrifting_)
            NssVehicleDriftCtrl_ToggleDrifting_ = (void (*)(void *, float, const void *))
                rtGetMethodPointerByRva("", "NssVehicleDriftCtrl", 0x7C6E368);
        if (!NssVehicleDriftCtrl_ReleaseDrifting_)
            NssVehicleDriftCtrl_ReleaseDrifting_ = (void (*)(void *, const void *))
                rtGetMethodPointerByRva("", "NssVehicleDriftCtrl", 0x7C6E51C);
        if (NssVehicleDriftCtrl_ToggleDrifting_ && NssVehicleDriftCtrl_ReleaseDrifting_) {
            s_DriftResolved = YES;
            rtLog("il2cpp: drift LAZY resolved toggle=%p release=%p",
                  NssVehicleDriftCtrl_ToggleDrifting_, NssVehicleDriftCtrl_ReleaseDrifting_);
        }
    }

    if (inDriftZone) {
        s_BotDriftExit = 0;
        if (!s_BotDrifting) {
            s_BotDrifting = YES;
            s_BotDriftDir = (da > 0.0f) ? 2 : 1;   // 2 = Right, 1 = Left
            // Push button để HUD hiển thị đúng + game ghi nhận input
            if (cab && NssPhyVehicleCab_BeginDrifting)
                NssPhyVehicleCab_BeginDrifting(cab, s_BotDriftDir, nullptr);
            // Steering PHẢI cùng dấu với hướng vào cua, nếu không ToggleDrifting
            // sẽ bị chặn bởi điều kiện (coreTopSpeed * steering) < 0
            float dsteer = (s_BotDriftDir == 1) ? 1.0f : -1.0f;
            if (dc && NssVehicleDriftCtrl_ToggleDrifting_)
                NssVehicleDriftCtrl_ToggleDrifting_(dc, dsteer, nullptr);
        }
    } else {
        if (s_BotDrifting) {
            // Cần 3 frame liên tiếp hết vùng vàng mới nhả, tránh nhấp nháy
            if (fabsf(da) < 0.13f && driftPct <= 0.01f && !wantDrift) {
                if (++s_BotDriftExit >= 3) {
                    if (cab && NssPhyVehicleCab_EndDrifting)
                        NssPhyVehicleCab_EndDrifting(cab, s_BotDriftDir, nullptr);
                    if (dc) {
                        if (NssVehicleDriftCtrl_ReleaseDrifting_)
                            NssVehicleDriftCtrl_ReleaseDrifting_(dc, nullptr);
                        if (orig_Drift_ExitCurDriftState)
                            orig_Drift_ExitCurDriftState(dc, nullptr);
                        if (orig_Drift_ForceClearDriftParams)
                            orig_Drift_ForceClearDriftParams(dc, nullptr);
                    }
                    s_BotDrifting  = NO;
                    s_BotDriftExit = 0;
                    if (ExtraVelocityFast_DoPerfectCWWBoost && veh)
                        ExtraVelocityFast_DoPerfectCWWBoost(veh, nullptr);
                }
            } else {
                s_BotDriftExit = 0;
            }
        }
    }
}

// Hook bọc MotionCtrl::Update (slot 96) — nơi gọi UpdateDrivingData bằng BL.
// Ghi đè NssSteeringData SAU khi game đã điền, TRƯỚC khi UpdateDrivingData chạy
// là không khả thi; nên ta ghi đè sau đó và áp lại vào frame kế tiếp.
static void hook_MotionCtrlUpdate(void *self, float dt, const void *method) {
    if (gAutoRacing && self) {
        // self = NssPhyVehicleMotionCtrl (kế thừa NssPhyVehicleMotionCtrlHelper)
        //   0x10 mSteeringData     (NssSteeringData*)
        //   0x20 mVehiclePhyCtrl   (NssPhyVehicleCtrl*)
        //   0x28 mDynamicVehicle   (IDynamicVehicle*)
        //   0x38 mDrivingCtrl      (NssPhyVehicleDrivingCtrl*)
        //   0x60 mDriftCtrl        (IVehicleDriftCtrl*)
        // UpdateDrivingData được gọi bằng BL ngay đầu Update -> phải ghi TRƯỚC orig.
        void *sd  = *(void **)((char *)self + 0x10);
        void *dvc = *(void **)((char *)self + 0x38);
        if (sd && dvc) rtAutoDrive(dvc, sd);
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, method);
}

// 5. Anti-Cheat Report: Khóa SdcVehicleVel ở mức 300 km/h
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

// 6. Guide Line & Racing Line: Đường chỉ dẫn to rõ + mũi tên ôm cua từ xa
static void hook_TraceLineConfig_Init(void *self, int mapID, const void *method) {
    if (orig_TraceLineConfig_Init) orig_TraceLineConfig_Init(self, mapID, method);
    if (!self || !gGuideLine) return;

    // Vạch đường chỉ dẫn:
    *(int *)  ((char *)self + 0x24) = 1000;   // VisibleMeshMaxDistance: hiển thị vạch xa tới 1000m
    *(float *)((char *)self + 0x3C) = 3.6f;   // LineWidth: to gấp đôi bình thường, cực kỳ rõ nét
    *(float *)((char *)self + 0x40) = 0.25f;  // LineUpOffset: nâng cao 25cm so với mặt đường, không bị lún

    // Mũi tên hướng dẫn góc ôm cua/drift:
    *(float *)((char *)self + 0x54) = 4.5f;   // DriftFXWidth: mũi tên to rõ ràng
    *(float *)((char *)self + 0x5C) = 600.0f; // DriftFXVisibleDistance: nhìn thấy mũi tên trước 600m
    rtLog("guideline: enhanced LineWidth=3.6, UpOffset=0.25, VisibleDist=1000m, DriftFXWidth=4.5");
}

static BOOL hook_TraceLineComponent_GameModeForceOpen(void *self, const void *method) {
    if (gGuideLine) return YES;
    return orig_TraceLineComponent_GameModeForceOpen ? orig_TraceLineComponent_GameModeForceOpen(self, method) : NO;
}

static BOOL hook_TraceLineComponent_EnableUpdate(void *self, const void *method) {
    if (gGuideLine) return YES;
    return orig_TraceLineComponent_EnableUpdate ? orig_TraceLineComponent_EnableUpdate(self, method) : NO;
}

static void hook_TraceLineComponent_Update(void *self, float dt, const void *method) {
    gTraceLineComp = self; // Lưu con trỏ TraceLineComponent cho Autopilot
    if (gGuideLine && self) {
        *(uint8_t *)((char *)self + 0xB0) = 1; // mIsEnable = true
        *(uint8_t *)((char *)self + 0xB1) = 1; // mIsClassicMode = true
        *(uint8_t *)((char *)self + 0xB2) = 1; // mIsLadderMode = true
    }
    if (orig_TraceLineComponent_Update) orig_TraceLineComponent_Update(self, dt, method);
}

// 7. CheckPointMgr & ActorCpReporter: Tính MinMapTime, LapTimeLimit & Can Finish
static void hook_CheckPointMgrInit(void *self, void *config, bool checkCrc, bool enableReset, const void *method) {
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, checkCrc, enableReset, method);
    if (config) {
        gMainCurveLength = *(float *)((char *)config + 0x4C);
        int laps = gMapTotalLaps > 0 ? gMapTotalLaps : 2;
        float lapDist = gMainCurveLength > 100.f ? gMainCurveLength : 2500.f;
        float totalDist = lapDist * (float)laps;

        // Vận tốc chuẩn an toàn 300 km/h (≈ 83.33 m/s)
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
        rtLog("install: SKIPPED (no_hooks flag present) - hooks disabled, menu only");
        return;
    }

    rtLog("install: installing IL2CPP metadata hooks (zero text-patching)");

    // 1. Race start marker (đếm 5s xuất phát)
    orig_GameGo_ImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "FreePracticeGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "ActionSpeedGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);

    // 2. Mini Boost: Gọi ForceCanTriggerOnce liên tục
    orig_ExVelMgr_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "ExtraVelocityTriggerMgr", "Update", 1, (void *)hook_ExVelMgrUpdate);

    // Resolve native functions for Autopilot & Boosts
    ExtraVelocityTriggerMgr_ForceCanTriggerOnce = (void (*)(void *, int, const void *))
        rtGetMethodPointer("", "ExtraVelocityTriggerMgr", "ForceCanTriggerOnce", 1);
    ExtraVelocityFast_DoPerfectCWWBoost = (void (*)(void *, const void *))
        rtGetMethodPointer("", "ExtraVelocityFast", "DoPerfectCWWBoost", 1);
    TraceLineComponent_GetTraceLinePoints = (void *(*)(void *, const void *))
        rtGetMethodPointer("", "TraceLineComponent", "GetTraceLinePoints", 0);

    NssPhyVehicleCab_ThrottleDown = (void (*)(void *, float, const void *))
        rtGetMethodPointer("", "NssPhyVehicleCab", "ThrottleDown", 1);
    NssPhyVehicleCab_BeginSteeringAnalog = (void (*)(void *, float, const void *))
        rtGetMethodPointerByRva("", "NssPhyVehicleCab", 0x7AEC854); // BeginSteering(float)
    NssPhyVehicleCab_BeginDrifting = (BOOL (*)(void *, int, const void *))
        rtGetMethodPointer("", "NssPhyVehicleCab", "BeginDrifting", 1);
    NssPhyVehicleCab_EndDrifting = (BOOL (*)(void *, int, const void *))
        rtGetMethodPointer("", "NssPhyVehicleCab", "EndDrifting", 1);

    NssVehicleDriftCtrl_ToggleDrifting_ = (void (*)(void *, float, const void *))
        rtGetMethodPointerByRva("", "NssVehicleDriftCtrl", 0x7C6E368);   // ToggleDrifting(float)
    NssVehicleDriftCtrl_ReleaseDrifting_ = (void (*)(void *, const void *))
        rtGetMethodPointerByRva("", "NssVehicleDriftCtrl", 0x7C6E51C);   // ReleaseDrifting()

    rtLog("il2cpp: drift toggle=%p release=%p", NssVehicleDriftCtrl_ToggleDrifting_,
          NssVehicleDriftCtrl_ReleaseDrifting_);

    rtLog("il2cpp: Autopilot resolved (CWW=%p, SteerAnalog=%p, Throttle=%p, Drift=%p, TL=%p)",
          ExtraVelocityFast_DoPerfectCWWBoost, NssPhyVehicleCab_BeginSteeringAnalog,
          NssPhyVehicleCab_ThrottleDown, NssPhyVehicleCab_BeginDrifting,
          TraceLineComponent_GetTraceLinePoints);

    // 3. Auto End Drift (ExitCurDriftState + ForceClearDriftParams)
    orig_Drift_Release = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ReleaseDrifting", 0, (void *)hook_DriftRelease);
    orig_Drift_ExitCurDriftState = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ExitCurDriftState", 0, (void *)hook_DriftExitCurState);
    orig_Drift_ForceClearDriftParams = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ForceClearDriftParams", 0, (void *)hook_DriftForceClear);

    // 4. Tốc độ trục truyền động vật lý (PowerChain)
    orig_PowerChain_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehiclePowerChain", "Update", 1, (void *)hook_PowerChainUpdate);

    // 4b. Autopilot: bọc MotionCtrl::Update (slot 96) — nơi gọi UpdateDrivingData bằng BL
    orig_MotionCtrl_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleMotionCtrl", "Update", 1, (void *)hook_MotionCtrlUpdate);

    // 5. Anti-Cheat Report: SdcVehicleVel khóa 300 km/h
    orig_SdcVehicleVel_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleVel", "Update", 1, (void *)hook_SdcVehicleVelUpdate);

    // 6. Guide Line & Racing Line
    orig_TraceLineConfig_Init = (void (*)(void *, int, const void *))
        rtHookMethod("", "TraceLineConfig", "Init", 1, (void *)hook_TraceLineConfig_Init);
    orig_TraceLineComponent_GameModeForceOpen = (BOOL (*)(void *, const void *))
        rtHookMethod("", "TraceLineComponent", "GameModeForceOpen", 0, (void *)hook_TraceLineComponent_GameModeForceOpen);
    orig_TraceLineComponent_EnableUpdate = (BOOL (*)(void *, const void *))
        rtHookMethod("", "TraceLineComponent", "EnableUpdate", 0, (void *)hook_TraceLineComponent_EnableUpdate);
    orig_TraceLineComponent_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "TraceLineComponent", "Update", 1, (void *)hook_TraceLineComponent_Update);

    // 7. CheckPointMgr & ActorCpReporter (Tính MinMapTime, LapTimeLimit và Can Finish)
    orig_CheckPointMgr_Init = (void (*)(void *, void *, bool, bool, const void *))
        rtHookMethod("", "CheckPointMgr", "Init", 3, (void *)hook_CheckPointMgrInit);
    orig_ActorCpReporter_Update = (void (*)(void *, float, float, const void *))
        rtHookMethod("", "ActorCpReporter", "Update", 2, (void *)hook_ActorCpReporterUpdate);

    rtLog("install: done (all hooks active)");
}

#pragma mark - UI

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

@interface RCRaceToolkitMenu : NSObject
@property (nonatomic, strong) RCPassThroughWindow *window;
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *speedLabel;

// Top HUD Overlay
@property (nonatomic, strong) UIView *topHud;
@property (nonatomic, strong) UILabel *topTimeLabel;
@property (nonatomic, strong) UILabel *topFinishLabel;
@property (nonatomic, strong) NSTimer *hudTimer;
@end

static RCRaceToolkitMenu *gMenu = nil;

@implementation RCRaceToolkitMenu

- (UISwitch *)switchAtY:(CGFloat)y title:(NSString *)title on:(BOOL)on action:(SEL)action {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 4, 205, 32)];
    l.text = title;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.panel addSubview:l];

    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(226, y, 51, 31)];
    s.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
    s.on = on;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:s];
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

    // === TOP HUD OVERLAY (MinMapTime, LapTimeLimit & Can Finish) ===
    CGFloat hudW = 340, hudH = 46;
    self.topHud = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - hudW) / 2, 8, hudW, hudH)];
    self.topHud.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.88];
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

    // Timer cập nhật HUD 10 lần mỗi giây
    self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                     target:self
                                                   selector:@selector(updateTopHud)
                                                   userInfo:nil
                                                    repeats:YES];

    // === FLOATING BUTTON (FAB) ===
    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(screen.size.width - 68, 96, 56, 56);
    self.fab.backgroundColor = [UIColor colorWithRed:0.10 green:0.45 blue:0.90 alpha:0.92];
    self.fab.layer.cornerRadius = 28;
    self.fab.layer.borderWidth = 1.5;
    self.fab.layer.borderColor = UIColor.whiteColor.CGColor;
    [self.fab setTitle:@"R" forState:UIControlStateNormal];
    self.fab.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)]];
    [self.host addSubview:self.fab];

    // === MENU PANEL ===
    CGFloat w = 310, h = 330;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2,
                                                        (screen.size.height - h) / 2, w, h)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.panel.hidden = YES;
    [self.host addSubview:self.panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 240, 26)];
    title.text = @"Race Toolkit (Auto Racer)";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.panel addSubview:title];

    [self switchAtY:40  title:@"Auto Racing (Bot)"    on:gAutoRacing    action:@selector(onAutoRacing:)];
    [self switchAtY:76  title:@"Guide Line & Arrows"  on:gGuideLine     action:@selector(onGuideLine:)];
    [self switchAtY:112 title:@"Inf Mini Boost"       on:gFullMiniBoost action:@selector(onMini:)];
    [self switchAtY:148 title:@"Auto End Drift"       on:gAutoDriftEnd  action:@selector(onAutoDrift:)];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 190, 268, 22)];
    self.speedLabel.textColor = UIColor.whiteColor;
    self.speedLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.speedLabel.text = [self speedText];
    [self.panel addSubview:self.speedLabel];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 216, 268, 32)];
    slider.minimumValue = 0.f;
    slider.maximumValue = 300.f;
    slider.value = gSpeedKmh;
    slider.tintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
    [slider addTarget:self action:@selector(onSpeedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:slider];

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(16, 256, 278, 62)];
    note.numberOfLines = 4;
    note.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    note.font = [UIFont systemFontOfSize:10.5];
    note.text = @"Auto Racing: Tự động lái theo TraceLine, ôm cua drift, thoát cua bắn CWW Boost & MiniBoost hoàn hảo.\nGuide Line: Đường dẫn & mũi tên cực nét.";
    [self.panel addSubview:note];
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

- (void)togglePanel {
    self.panel.hidden = (self.panel.hidden ? NO : YES);
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.hidden = NO;
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}

- (void)onAutoRacing:(UISwitch *)s { gAutoRacing = s.isOn;     rtLog("toggle AutoRacing=%d", s.isOn); }
- (void)onGuideLine:(UISwitch *)s  { gGuideLine = s.isOn;      rtLog("toggle GuideLine=%d", s.isOn); }
- (void)onMini:(UISwitch *)s       { gFullMiniBoost = s.isOn;  rtLog("toggle FullMiniBoost=%d", s.isOn); }
- (void)onAutoDrift:(UISwitch *)s  { gAutoDriftEnd = s.isOn;   rtLog("toggle AutoEndDrift=%d", s.isOn); }

- (void)onSpeedChanged:(UISlider *)s {
    gSpeedKmh = s.value;
    self.speedLabel.text = [self speedText];
    rtLog("speed slider = %.0f km/h", gSpeedKmh);
}

@end

#pragma mark - Bootstrap

static void buildMenuSafely(void) {
    if (gMenu) return;
    @try {
        gMenu = [RCRaceToolkitMenu new];
        [gMenu build];
        rtLog("UI: menu built");
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
