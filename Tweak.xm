// Tweak.xm — Race Toolkit (iOS, IL2CPP VTable & Metadata Hook)
//
// Features & Fixes:
// 1. ShadowTrusted: autopilot that follows the track centre line, holds full
//    throttle and leaves all touch controls to the player.
// 2. Miniboost: zeroes the game's own post-drift mini-boost delay.
// 3. Auto End Drift: exits the drift state when the drift key is released.
// 4. Speed Boost: only after 5s from race start (GameGoState::ImpEnter).
// 5. Anti-Cheat Report: clamps SdcVehicleVel to 300 km/h.
// 6. Top Overlay: MinMapTime, LapTimeLimit and Can Finish.

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

static BOOL   gShadowTrusted  = NO;
static void  *gPlayerVehicle = NULL;   // cached from VehicleInputCtrl
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

// Resolve by exact RVA; needed where overloads make arg-count ambiguous.
__attribute__((unused)) static void *rtGetMethodPointerByRva(const char *className, uint32_t rva) {
    Il2CppClass *klass = rtFindClass("", className);
    uintptr_t base = unityFrameworkBase();
    if (!klass || !base) return NULL;
    if (il2cpp_class_get_method_from_name) {
        il2cpp_class_get_method_from_name(klass, ".ctor", -1);
        il2cpp_class_get_method_from_name(klass, "Update", -1);
    }
    uint16_t n = *(uint16_t *)((char *)klass + 296);
    void *methods = *(void **)((char *)klass + 152);
    if (!n || !methods) return NULL;
    for (uint16_t i = 0; i < n; i++) {
        void *m = *(void **)((char *)methods + i * 8);
        if (!m) continue;
        void *ptr = *(void **)((char *)m + 0);
        if (ptr && (uintptr_t)ptr - base == (uintptr_t)rva) return ptr;
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

#pragma mark - Original function pointers & Replacements

static void  (*orig_GameGo_ImpEnter)(void *, const void *) = NULL;

static void  (*orig_AutoSmallBoostHelper_Update)(void *, float, const void *) = NULL;
static void  (*orig_PowerChain_Update)(void *, float, const void *) = NULL;
static void  (*orig_SdcVehicleVel_Update)(void *, float, const void *) = NULL;
static void  (*orig_CheckPointMgr_Init)(void *, void *, bool, bool, const void *) = NULL;
static void  (*orig_ActorCpReporter_Update)(void *, float, float, const void *) = NULL;

static void (*orig_MotionCtrl_Update)(void *, float, const void *) = NULL;
static void (*orig_VehicleInputCtrl_Update)(void *, float, const void *) = NULL;
static void (*orig_Shadow_EnableMatchInput)(void *, bool, const void *) = NULL;
static bool (*orig_DriveAssist_IsEnable)(void *, const void *) = NULL;
static void (*orig_DriveAssist_CopyConfig)(void *, void *, void *, void *, const void *) = NULL;
static void (*orig_DAVirtualCollision_Update)(void *, float, const void *) = NULL;
static void (*orig_DrivingCtrl_UpdateDrivingData)(void *, void *, float, const void *) = NULL;

static inline BOOL rtPtrOk(const void *p) {
    uintptr_t v = (uintptr_t)p;
    if (v < 0x10000ULL) return NO;
    if (v & 7) return NO;
    return YES;
}

// VehicleInputCtrl exists only for the local player; cache its vehicle.
static void hook_VehicleInputCtrlUpdate(void *self, float dt, const void *method) {
    if (orig_VehicleInputCtrl_Update) orig_VehicleInputCtrl_Update(self, dt, method);
    void *vehicle = self ? *(void **)((char *)self + 0x58) : NULL;   // VehicleInputCtrl.mVehicle
    // Set unconditionally: a stricter gate here is exactly what made both features inert.
    if (rtPtrOk(vehicle)) gPlayerVehicle = vehicle;
}

// 1. Race Start
static void hook_GoImpEnter(void *self, const void *method) {
    if (orig_GameGo_ImpEnter) orig_GameGo_ImpEnter(self, method);
    gGoTime = nowSeconds();
    gCurrentMatchTime = 0.f;
    gCanFinish = NO;
    rtLog("race started -> gGoTime=%.3f, MinMapTime=%.1fs, LapTimeLimit=%.1fs",
          gGoTime, gMinMapTimeSeconds, gLapTimeLimit);
}

// 2. Mini Boost: shorten the game's own post-drift auto-boost delay to zero so
// the existing AutoSmallBoostHelper state machine fires on the first normal
// frame. The stay timer is left alone: forcing it would break the state
// accounting and spam the trigger every tick.
static void hook_AutoSmallBoostHelperUpdate(void *self, float dt, const void *method) {
    if (gFullMiniBoost && rtPtrOk(self)) {
        *(float *)((char *)self + 0x28) = 0.0f;  // mAutoMiniBoostDelayTime
    }
    if (orig_AutoSmallBoostHelper_Update) orig_AutoSmallBoostHelper_Update(self, dt, method);
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

// Player identity comes from the input controller, which only the local player owns.
__attribute__((unused)) static BOOL rtIsPlayerVehicle(void *vehicle) {
    if (!rtPtrOk(vehicle)) return NO;
    if (gPlayerVehicle && vehicle == gPlayerVehicle) return YES;
    return *(bool *)((char *)vehicle + 0xF8); // NssVehicle.mIsMainPlayer
}

// 5. ShadowTrusted & Max Drive Assist (Tuyet doi KHONG khoa UI control cua nguoi choi)
static void hook_Shadow_EnableMatchInput(void *self, bool enable, const void *method) {
    if (gShadowTrusted) {
        enable = true; // Luon mo khoa UI control / touch input
    }
    if (orig_Shadow_EnableMatchInput) orig_Shadow_EnableMatchInput(self, enable, method);
}

static bool hook_DriveAssist_IsEnable(void *self, const void *method) {
    if (gShadowTrusted) return true; // Luon kich hoat Drive Assist cho moi map va mode
    return orig_DriveAssist_IsEnable ? orig_DriveAssist_IsEnable(self, method) : false;
}

static void hook_DriveAssist_CopyConfig(void *self, void *cfg, void *detectConfig, void *collConfig, const void *method) {
    if (orig_DriveAssist_CopyConfig) orig_DriveAssist_CopyConfig(self, cfg, detectConfig, collConfig, method);
    if (!gShadowTrusted) return;

    if (detectConfig) {
        *(float *)((char *)detectConfig + 0x10) = 0.55f; // mLinvelPredictTime: du doan vua phai
        *(int *)((char *)detectConfig + 0x14)   = 1;     // mPredictType: Swept AABB
    }
    if (collConfig) {
        *(float *)((char *)collConfig + 0x10) = 8.0f;  // mSlerpSpeed: keo huong nhe nhang
        *(float *)((char *)collConfig + 0x14) = 1.8f;  // mDriftAccCoef: tang toc drift hop ly
        *(float *)((char *)collConfig + 0x18) = 0.0f;  // mDriftMaxAngSpeedKMPHThreshold
        *(float *)((char *)collConfig + 0x1C) = 1.3f;  // mDriftMaxAngelSpeedCoef
        *(float *)((char *)collConfig + 0x20) = 1.0f;  // mDriftSlidingMaxAngSpeedCoef: GIU DRIFT TU NHIEN, khong clamp 0.01
        *(float *)((char *)collConfig + 0x24) = 0.12f; // mSteerAngleThreshold: chi ho tro khi chệch huong lon
        *(float *)((char *)collConfig + 0x28) = 4.0f;  // mSteerAngleSpeed: tro luc vua phai, khong cuop tay lai
    }
}

static void hook_DAVirtualCollision_Update(void *self, float dt, const void *method) {
    if (gShadowTrusted && self) {
        void *collConfig = *(void **)((char *)self + 0x20); // mConfig
        if (collConfig) {
            *(float *)((char *)collConfig + 0x10) = 8.0f;
            *(float *)((char *)collConfig + 0x14) = 1.8f;
            *(float *)((char *)collConfig + 0x18) = 0.0f;
            *(float *)((char *)collConfig + 0x1C) = 1.3f;
            *(float *)((char *)collConfig + 0x20) = 1.0f;
            *(float *)((char *)collConfig + 0x24) = 0.12f;
            *(float *)((char *)collConfig + 0x28) = 4.0f;
        }
        void *envInfo = *(void **)((char *)self + 0x18); // mDAEnvInfo
        if (envInfo) {
            void *detectConfig = *(void **)((char *)envInfo + 0x70); // mConfig
            if (detectConfig) {
                *(float *)((char *)detectConfig + 0x10) = 0.55f;
                *(int *)((char *)detectConfig + 0x14)   = 1;
            }
        }
    }
    if (orig_DAVirtualCollision_Update) orig_DAVirtualCollision_Update(self, dt, method);
}

// Autopilot injects into NssSteeringData, the game's own per-frame input struct
// consumed by NssPhyVehicleDrivingCtrl._UpdatePhyDrivingParams. Writing
// mThrottle/mSteering on the ctrl is useless: _UpdatePhyDrivingParams derives
// them from this struct on the same tick.
// Hooked on NssPlayerVehicleDrivingCtrl (Slot 25) because the base virtual is
// overridden there, and only the local player uses that subclass.
//   NssSteeringData: +0x10 mForward (float), +0x14 mBrakingState (int),
//                    +0x18 mIsHandbrake (bool), +0x1C mSteeringLeft (float)
static void hook_DrivingCtrl_UpdatePhyDrivingParams(void *self, void *steerData, float dt, const void *method) {
    if (rtPtrOk(self) && rtPtrOk(steerData)) {
        // NssPhyVehicleDrivingCtrl.mVehicle(0x10) is IDynamicVehicle;
        // DynamicVehicle.mVehicle(0x10) is the owning IVehicle/NssVehicle.
        void *dyn = *(void **)((char *)self + 0x10);
        void *vehicle = rtPtrOk(dyn) ? *(void **)((char *)dyn + 0x10) : NULL;

        if (gShadowTrusted && rtIsPlayerVehicle(vehicle)) {
            void *phyCtrl = *(void **)((char *)self + 0x18);                    // NssPhyVehicleCtrl
            void *acc = rtPtrOk(dyn) ? *(void **)((char *)dyn + 0x28) : NULL;   // IVehicleACC
            void *simOutput = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + 0x28) : NULL;
            void *curTp = rtPtrOk(acc) ? *(void **)((char *)acc + 0x38) : NULL;  // ITrackPoint

            if (rtPtrOk(simOutput) && rtPtrOk(curTp)) {
                float fwdX = *(float *)((char *)simOutput + 0x44);  // mMovingDirection.x
                float fwdZ = *(float *)((char *)simOutput + 0x4C);  // mMovingDirection.z
                float dirX = *(float *)((char *)curTp + 0x1C);      // NssTrackPoint.mDirection.x
                float dirZ = *(float *)((char *)curTp + 0x24);      // NssTrackPoint.mDirection.z
                float hDist = *(float *)((char *)acc + 0x5C);       // mHorizontalDis

                // 2D cross(fwd, dir): sign encodes which side the track bends to.
                float cross = (fwdX * dirZ) - (fwdZ * dirX);
                float steer = (cross * 2.2f) - (hDist * 0.10f);
                if (steer > 1.0f) steer = 1.0f;
                if (steer < -1.0f) steer = -1.0f;

                // Player override: real thumb input (|mSteeringLeft| > 0.2) always wins.
                float userSteer = *(float *)((char *)steerData + 0x1C);
                if (fabsf(userSteer) < 0.2f) {
                    *(float *)((char *)steerData + 0x1C) = steer;
                }

                // Full throttle unless the player is braking or on the handbrake.
                int braking = *(int *)((char *)steerData + 0x14);
                bool handbrake = *(bool *)((char *)steerData + 0x18);
                if (braking == 0 && !handbrake) {
                    *(float *)((char *)steerData + 0x10) = 1.0f;
                }
            }
        }
    }

    if (orig_DrivingCtrl_UpdateDrivingData) orig_DrivingCtrl_UpdateDrivingData(self, steerData, dt, method);
}

// Auto End Drift: leave the drift state machine on the tick the player releases
// the drift key. Edge-triggered, so it never fights an ongoing drift.
static void hook_MotionCtrlUpdate(void *self, float dt, const void *method) {
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, method);
    if (!gAutoDriftEnd || !rtPtrOk(self)) return;

    void *vehicle = *(void **)((char *)self + 0x18);
    if (!rtIsPlayerVehicle(vehicle)) return;

    void *drivingCtrl = *(void **)((char *)self + 0x38);
    if (!rtPtrOk(drivingCtrl)) return;

    bool pressed = *(bool *)((char *)drivingCtrl + 0x75);  // NssPlayerVehicleDrivingCtrl.mDriftIsPress
    static bool sWasPressed = false;
    if (sWasPressed && !pressed) {
        void (*exitDrift)(void *, const void *) = (void (*)(void *, const void *))
            rtGetMethodPointerByRva("NssPhyVehicleMotionCtrl", 0x7B10C64);
        if (exitDrift) exitDrift(self, nullptr);
    }
    sWasPressed = pressed;
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

    // 2. Mini Boost: AutoSmallBoostHelper tự động kích hoạt
    orig_AutoSmallBoostHelper_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "AutoSmallBoostHelper", "Update", 1, (void *)hook_AutoSmallBoostHelperUpdate);
    rtHookMethod("", "VehicleInputCtrl", "Update", 1, (void *)hook_VehicleInputCtrlUpdate);
    // 4. Tốc độ trục truyền động vật lý (PowerChain)
    orig_PowerChain_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehiclePowerChain", "Update", 1, (void *)hook_PowerChainUpdate);

    orig_MotionCtrl_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleMotionCtrl", "Update", 1, (void *)hook_MotionCtrlUpdate);
    // Autopilot input injection: private virtual _UpdatePhyDrivingParams on the
    // player-only subclass. argsCount 2 -> (NssSteeringData, float).
    orig_DrivingCtrl_UpdateDrivingData = (void (*)(void *, void *, float, const void *))
        rtHookMethod("", "NssPlayerVehicleDrivingCtrl", "_UpdatePhyDrivingParams", 2, (void *)hook_DrivingCtrl_UpdatePhyDrivingParams);
    orig_Shadow_EnableMatchInput = (void (*)(void *, bool, const void *))
        rtHookMethod("", "ShadowTrusteeship", "EnableMatchInput", 1, (void *)hook_Shadow_EnableMatchInput);
    orig_DriveAssist_IsEnable = (bool (*)(void *, const void *))
        rtHookMethod("", "VehicleDriveAssistComp", "IsEnable", 0, (void *)hook_DriveAssist_IsEnable);
    orig_DriveAssist_CopyConfig = (void (*)(void *, void *, void *, void *, const void *))
        rtHookMethod("", "VehicleDriveAssistComp", "CopyDataBinConfigToMono", 3, (void *)hook_DriveAssist_CopyConfig);
    orig_DAVirtualCollision_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "VehicleDAVirtualCollision", "Update", 1, (void *)hook_DAVirtualCollision_Update);
    rtLog("il2cpp: shadowInput=%p daEnable=%p daCfg=%p daColl=%p drvData=%p",
          orig_Shadow_EnableMatchInput, orig_DriveAssist_IsEnable, orig_DriveAssist_CopyConfig,
          orig_DAVirtualCollision_Update, orig_DrivingCtrl_UpdateDrivingData);

    // 5. Anti-Cheat Report: SdcVehicleVel khóa 300 km/h
    orig_SdcVehicleVel_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleVel", "Update", 1, (void *)hook_SdcVehicleVelUpdate);

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

    [self switchAtY:40  title:@"Shadow / Max Assist" on:gShadowTrusted action:@selector(onShadowTrusted:)];
    [self switchAtY:76  title:@"Inf Mini Boost"       on:gFullMiniBoost  action:@selector(onMini:)];
    [self switchAtY:112 title:@"Auto End Drift"       on:gAutoDriftEnd   action:@selector(onAutoDrift:)];

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
    note.text = @"Shadow/Assist: Tu nan goc bam cua & chong va cham tuong toi da ma khong khoa phim dieu khien.";
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

- (void)onShadowTrusted:(UISwitch *)s { gShadowTrusted = s.isOn; rtLog("shadow trusted=%d", s.isOn); }
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
