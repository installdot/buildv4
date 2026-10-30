// Tweak.xm — Race Toolkit (iOS, IL2CPP VTable & Metadata Hook)
//
// Features & Fixes:
// 1. Shadow Auto: Tu dong dua theo quy dao tim duong dua (Trackline) + full ga, khong khoa UI control.
// 2. Miniboost: Goi ForceCanTriggerOnce(Mini/Air/FallingGround) lien tuc, khong giu o muc 2 nua.
// 3. Auto End Drift: Goi ExitCurDriftState + ForceClearDriftParams ngay khi nha nut drift -> Khong con dinh drift.
// 4. Speed Boost: Chi bat dau kich hoat sau 5 giay tu khi xuat phat (GameGoState::ImpEnter).
// 5. Anti-Cheat Report: Khoa SdcVehicleVel o muc 300 km/h.
// 6. Top Overlay: Hien thi MinMapTime, LapTimeLimit & Can Finish (TRUE/FALSE).

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
static BOOL   gAutoPlay       = NO; // Kích hoạt AI tự động đua khi mất mạng kể cả khi đang online
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

    // NssVehicle
    kOffVehicleMotion     = 0x20, // mDynamicVehicle
    kOffVehicleIsMain     = 0xF8, // mIsMainPlayer

    // IDynamicVehicle (DynamicVehicle)
    kOffDynVehicle        = 0x10, // mVehicle
    kOffDynESP            = 0x20, // mESP
    kOffDynACC            = 0x28, // mACC

    // NssPhyVehicleCtrl
    kOffPhySimOutput      = 0x28, // mSimulateOutput

    // NssPhyVehicleMotionCtrlHelper
    kOffMotionSteerData   = 0x10, // mSteeringData (NssSteeringData, by value)
    kOffMotionVehicle     = 0x18, // mVehicle
    kOffMotionPhyCtrl     = 0x20, // mVehiclePhyCtrl
    kOffMotionDynVehicle  = 0x28, // mDynamicVehicle
    kOffMotionDrivingCtrl = 0x38, // mDrivingCtrl

    // NssPhyVehicleDrivingCtrl
    kOffDrvDynVehicle     = 0x10, // mVehicle (IDynamicVehicle)
    kOffDrvPhyCtrl        = 0x18, // mVehiclePhyCtrl
    kOffDrvThrottle       = 0x3C, // mThrottle (float)
    kOffDrvSteering       = 0x40, // mSteering (float)

    // NssSteeringData — the per-frame input struct DrivingCtrl consumes
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

static void (*ExtraVelocityTriggerMgr_ForceCanTriggerOnce)(void *, int, const void *) = NULL;
static void (*orig_MotionCtrl_Update)(void *, float, const void *) = NULL;

// Shadow autopilot
static void (*orig_Shadow_EnableMatchInput)(void *, bool, const void *) = NULL;
static void (*orig_Shadow_EnableAutoSpeedUp)(void *, bool, const void *) = NULL;
static void (*orig_Shadow_IgnoreCollision)(void *, bool, const void *) = NULL;
static BOOL (*orig_Input_GetKey)(void *, int, const void *) = NULL;
static char  sShadowState[3] = {0, 0, 0};   // last applied [input, speedup, nocoll]

// Offline / Always-Connected bypass
static int (*orig_App_get_internetReachability)(const void *) = NULL;
static int (*orig_Net_OnReturnToLogin)(void *, void *, const void *) = NULL;

// 1. Race Start
static void hook_GoImpEnter(void *self, const void *method) {
    if (orig_GameGo_ImpEnter) orig_GameGo_ImpEnter(self, method);
    gGoTime = nowSeconds();
    gCurrentMatchTime = 0.f;
    gCanFinish = NO;
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

static inline BOOL rtPtrOk(const void *p) {
    uintptr_t v = (uintptr_t)p;
    if (v < 0x10000ULL) return NO;
    if (v & 7) return NO;
    return YES;
}

// Layer A + skill arbitration.
//
// Verified order in NssPhyVehicleMotionCtrl.Update (0x7B10770):
//   sub_7AF6EC8(mDrivingCtrl, mSteeringData, dt)   // UpdateDrivingData
//       -> _UpdatePhyDrivingParams -> set_Throttle / set_Steering
// mSteeringData sits at +0x10, mDrivingCtrl at +0x38. So the only place a write
// survives the tick is BEFORE the original Update runs; hooking
// _UpdatePhyDrivingParams is too late because AssistTurning and Handbrake
// overwrite mSteering afterwards.
//
//   NssSteeringData: +0x10 mForward, +0x14 mBrakingState(int),
//                    +0x18 mIsHandbrake, +0x1C mSteeringLeft
static void hook_MotionCtrlUpdate(void *self, float dt, const void *method) {
    if (gAutoPlay && rtPtrOk(self)) {
        void *steerData = *(void **)((char *)self + kOffMotionSteerData);
        void *dyn       = *(void **)((char *)self + kOffMotionDynVehicle);
        void *phyCtrl   = *(void **)((char *)self + kOffMotionPhyCtrl);
        void *vehicle   = rtPtrOk(dyn) ? *(void **)((char *)dyn + kOffDynVehicle) : NULL;

        if (rtPtrOk(steerData) && rtPtrOk(dyn) && rtPtrOk(phyCtrl)) {
            void *acc = *(void **)((char *)dyn + kOffDynACC);
            void *sim = *(void **)((char *)phyCtrl + kOffPhySimOutput);
            void *tp  = rtPtrOk(acc) ? *(void **)((char *)acc + kOffAccCurTrackPoint) : NULL;

            if (rtPtrOk(sim) && rtPtrOk(tp)) {
                float fwdX = *(float *)((char *)sim + kOffSimMovingDir);
                float fwdZ = *(float *)((char *)sim + kOffSimMovingDir + 8);
                float dirX = *(float *)((char *)tp + kOffTpDirection);
                float dirZ = *(float *)((char *)tp + kOffTpDirection + 8);
                float hDis = *(float *)((char *)acc + kOffAccHorizDis);

                // cross(fwd,dir) = |fwd||dir|sin(theta); normalise so the gain is
                // independent of the vector magnitudes the sim happens to report.
                float flen = sqrtf(fwdX * fwdX + fwdZ * fwdZ);
                float dlen = sqrtf(dirX * dirX + dirZ * dirZ);
                float cross = (fwdX * dirZ) - (fwdZ * dirX);
                if (flen > 1e-4f && dlen > 1e-4f) cross /= (flen * dlen);

                float steer = (cross * 2.4f) - (hDis * 0.045f);
                if (steer > 1.0f) steer = 1.0f;
                if (steer < -1.0f) steer = -1.0f;

                float userSteer = *(float *)((char *)steerData + kOffSteerWheel);
                BOOL playerSteering = fabsf(userSteer) >= 0.2f;

                if (!playerSteering) *(float *)((char *)steerData + kOffSteerWheel) = steer;
                // (no cache needed: mSteeringData is the single source of truth)

                int braking = *(int *)((char *)steerData + kOffSteerBraking);
                bool handbrake = *(bool *)((char *)steerData + kOffSteerHandbrake);
                if (braking == 0 && !handbrake)
                    *(float *)((char *)steerData + kOffSteerForward) = 1.0f;

                // ---- skill layer: held-key mask for GetKey ----
                // Hysteresis: latch drift on a real corner and only release when
                // the corner opens, otherwise the state machine toggles per frame
                // and the drift gauge never charges.
                int mask = 0;
                if (fabsf(steer) > 0.55f)      gAPDriftLatch = 1;
                else if (fabsf(steer) < 0.25f) gAPDriftLatch = 0;

                if (gAPDriftLatch && !handbrake) {
                    mask |= (1 << 8);                             // Drift
                    mask |= (steer > 0.f) ? (1 << 2) : (1 << 1);  // Right : Left
                } else if (!playerSteering) {
                    if (steer > 0.15f)      mask |= (1 << 2);
                    else if (steer < -0.15f) mask |= (1 << 1);
                }

                // Mini boost: two-tick tap on drift exit, same as a human release.
                if (!gAPDriftLatch && gAPBoostTicks == 0 && fabsf(cross) < 0.20f)
                    gAPBoostTicks = 2;
                if (gAPBoostTicks > 0) {
                    mask |= (1 << 5);                             // SmallBoost
                    gAPBoostTicks--;
                }

                gAPKeyMask = mask;
            }
        }
    } else {
        gAPKeyMask = 0;   // off: never leak a synthetic key into the game
        gAPDriftLatch = 0;
        gAPBoostTicks = 0;
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

#pragma mark - 8. Shadow autopilot

// ShadowTrusteeship drives the car through four side effects. Three of them are
// fine here, one has to be neutralised:
//
//   EnableMatchInput(false)  -> cuts the touch->steer/drift/nitro link  [BLOCK]
//   EnableAutoSpeedUp(true)  -> Throttle = 1.0 on the cab             [KEEP]
//   IgnoreCollision(true)    -> VhcActionIgnoreCollision, no wall ping [KEEP]
//   EnableVehiclePhy(false)  -> kinematic, replay overwrites motion    [KEEP]
//
// We keep the player's input alive by forcing enable = true at the source, and
// then generate the motion ourselves: this codebase has no replay blob
// (MoveTransInfo2/EventTransInfo), so the ReplayMoveAlgm keyframe sampling is
// replaced by live ITrackPoint sampling from IVehicleACC. The result is written
// to NssSteeringData, the same struct ReplayMoveProcess ultimately feeds.
static void hook_ShadowEnableMatchInput(void *self, bool enable, const void *method) {
    bool want = gAutoPlay ? true : enable;
    if (orig_Shadow_EnableMatchInput && want != (bool)sShadowState[0]) {
        orig_Shadow_EnableMatchInput(self, want, method);
        sShadowState[0] = want ? 1 : 0;
    } else if (!orig_Shadow_EnableMatchInput) {
        rtLog("shadow: EnableMatchInput unavailable, input path untouched");
    }
}

static void hook_ShadowEnableAutoSpeedUp(void *self, bool enable, const void *method) {
    if (orig_Shadow_EnableAutoSpeedUp) orig_Shadow_EnableAutoSpeedUp(self, enable, method);
}

static void hook_ShadowIgnoreCollision(void *self, bool enable, const void *method) {
    if (orig_Shadow_IgnoreCollision) orig_Shadow_IgnoreCollision(self, enable, method);
}

// ==== Auto Play core =====================================================
//
// The car is driven by two independent layers, both owned by the game:
//
//   [A] analog: NssSteeringData{mForward, mBrakingState, mIsHandbrake,
//       mSteeringLeft} -> NssPlayerVehicleDrivingCtrl._UpdatePhyDrivingParams
//       -> mThrottle / mSteering -> forces.                    (throttle + steer)
//   [B] discrete: InputModule.GetKey(InputKeyType) -> ECU/Cab -> drift state
//       machine, mini-boost trigger, nitro.                    (Drift / Boost)
//
// Layer A alone can steer and hold throttle but can never drift or boost, so a
// pure-A implementation feels dead. Layer B alone has no analog resolution.
// Auto Play therefore writes both: A for the racing line, B for the skills.
//
// InputKeyType (dump): Left=1 Right=2 PropOne=3 PropTwo=4 SmallBoost=5
//                      Brake=6 Reset=7 Drift=8 SidewaysDrift=9 ...
// Steering is recomputed once per motion tick and cached, because GetKey can be
// polled several times per frame by different consumers.

static int   gAPKeyMask    = 0;    // bit N set => key N is "held" this frame
static int   gAPDriftLatch = 0;    // 1 while drift is held
static int   gAPBoostTicks = 0;    // frames left to hold SmallBoost

static BOOL rtAPKey(int t) { return (gAPKeyMask >> t) & 1; }

// Layer B: pretend the thumb holds these keys. Everything downstream (drift
// state machine, CWW/WCW boost, nitro) runs the untouched game code path.
static BOOL hook_Input_GetKey(void *self, int keyType, const void *method) {
    if (gAutoPlay && keyType > 0 && keyType < 18 && rtAPKey(keyType))
        return TRUE;
    return orig_Input_GetKey ? orig_Input_GetKey(self, keyType, method) : FALSE;
}

// để game không bao giờ tự ngắt tính năng hoặc ép dừng trận đua khi rớt mạng.
static int hook_App_get_internetReachability(const void *method) {
    return 2; // Always ReachableViaLocalAreaNetwork (WiFi)
}

// Chặn văng về màn hình đăng nhập nếu rớt mạng trong lúc xe đang tự động đua dở
static int hook_Net_OnReturnToLogin(void *self, void *e, const void *method) {
    if (gGoTime > 0.0 && !gCanFinish) {
        rtLog("net: suppressed disconnect popup during active race");
        return 0; // Chặn xử lý văng về login
    }
    return orig_Net_OnReturnToLogin ? orig_Net_OnReturnToLogin(self, e, method) : 0;
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

    ExtraVelocityTriggerMgr_ForceCanTriggerOnce = (void (*)(void *, int, const void *))
        rtGetMethodPointer("", "ExtraVelocityTriggerMgr", "ForceCanTriggerOnce", 1);

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

    orig_MotionCtrl_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleMotionCtrl", "Update", 1, (void *)hook_MotionCtrlUpdate);


    // 5. Anti-Cheat Report: SdcVehicleVel khóa 300 km/h
    orig_SdcVehicleVel_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleVel", "Update", 1, (void *)hook_SdcVehicleVelUpdate);

    // 7. CheckPointMgr & ActorCpReporter (Tính MinMapTime, LapTimeLimit và Can Finish)
    orig_CheckPointMgr_Init = (void (*)(void *, void *, bool, bool, const void *))
        rtHookMethod("", "CheckPointMgr", "Init", 3, (void *)hook_CheckPointMgrInit);
    orig_ActorCpReporter_Update = (void (*)(void *, float, float, const void *))
        rtHookMethod("", "ActorCpReporter", "Update", 2, (void *)hook_ActorCpReporterUpdate);

    // 8. Shadow autopilot: keep input alive, feed the steering struct
    orig_Shadow_EnableMatchInput = (void (*)(void *, bool, const void *))
        rtHookMethod("", "ShadowTrusteeship", "EnableMatchInput", 1, (void *)hook_ShadowEnableMatchInput);
    orig_Shadow_EnableAutoSpeedUp = (void (*)(void *, bool, const void *))
        rtHookMethod("", "ShadowTrusteeship", "EnableAutoSpeedUp", 1, (void *)hook_ShadowEnableAutoSpeedUp);
    orig_Shadow_IgnoreCollision = (void (*)(void *, bool, const void *))
        rtHookMethod("", "ShadowTrusteeship", "IgnoreCollision", 1, (void *)hook_ShadowIgnoreCollision);

    // Auto Play is entirely served by two hooks: MotionCtrl.Update (analog steer
    // + throttle, written into mSteeringData before UpdateDrivingData consumes
    // it) and InputModule.GetKey (drift / mini-boost / scrub keys).
    // Auto Play layer B: synthesise the discrete input keys (Drift / SmallBoost /
    // Left / Right). InputModule.GetKey is the single funnel every consumer reads.
    orig_Input_GetKey = (BOOL (*)(void *, int, const void *))
        rtHookMethod("", "InputModule", "GetKey", 1, (void *)hook_Input_GetKey);

    rtLog("autoplay: motionCtrl=%p inputGetKey=%p", orig_MotionCtrl_Update, orig_Input_GetKey);
    // 9. Offline / Always-Connected bypass: Xe tự lái liên tục kể cả khi rớt mạng/mất WiFi
    orig_App_get_internetReachability = (int (*)(const void *))
        rtHookMethod("UnityEngine", "Application", "get_internetReachability", 0, (void *)hook_App_get_internetReachability);
    orig_Net_OnReturnToLogin = (int (*)(void *, void *, const void *))
        rtHookMethod("", "NetGeneralMgr", "OnReturnToLoginStateAfterDisconnect", 1, (void *)hook_Net_OnReturnToLogin);
    rtLog("offline bypass: appReachability=%p netDisconnect=%p",
          orig_App_get_internetReachability, orig_Net_OnReturnToLogin);

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
    CGFloat w = 310, h = 265;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2,
                                                        (screen.size.height - h) / 2, w, h)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.panel.hidden = YES;
    [self.host addSubview:self.panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 240, 26)];
    title.text = @"Race Toolkit";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.panel addSubview:title];

    [self switchAtY:40  title:@"Auto Play"        on:gAutoPlay  action:@selector(onAutoPlay:)];
    [self switchAtY:76  title:@"Inf Mini Boost"   on:gFullMiniBoost action:@selector(onMini:)];
    [self switchAtY:112 title:@"Auto End Drift"   on:gAutoDriftEnd  action:@selector(onAutoDrift:)];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 150, 268, 20)];
    self.speedLabel.textColor = UIColor.whiteColor;
    self.speedLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.speedLabel.text = [self speedText];
    [self.panel addSubview:self.speedLabel];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 172, 268, 32)];
    slider.minimumValue = 0.f;
    slider.maximumValue = 300.f;
    slider.value = gSpeedKmh;
    slider.tintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
    [slider addTarget:self action:@selector(onSpeedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:slider];

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(16, 212, 278, 42)];
    note.numberOfLines = 2;
    note.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    note.font = [UIFont systemFontOfSize:10.5];
    note.text = @"Auto Play: bam tim duong, giu ga, tu drift va mini boost.\nCham phim lai bat ky luc nao de gianh quyen dieu khien.";
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

- (void)onAutoPlay:(UISwitch *)s {
    gAutoPlay = s.isOn;
    sShadowState[0] = 0;   // force EnableMatchInput to be re-issued on the next call
    rtLog("auto play (offline ai)=%d", s.isOn);
}
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
