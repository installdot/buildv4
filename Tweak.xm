// Tweak.xm — Race Toolkit (iOS, IL2CPP VTable & Metadata Hook)
//
// Zero-Crash Architecture:
// - Does NOT touch __TEXT (no vm_protect, no code-patching, no AMFI violation, no SIGBUS).
// - Replaces methodPointer in MethodInfo and slot in Il2CppClass::vtable (__DATA, natively RW).
// - Resolves runtime exports from UnityFramework (il2cpp_domain_get, il2cpp_class_from_name, etc.).
// - Fully compatible with jailed / rootless / TrollStore / modern iOS environments.

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

#define RT_TRACE(rate, fmt, ...) do {                           \
    static unsigned _rc_##__LINE__ = 0;                         \
    if ((_rc_##__LINE__++ % (rate)) == 0) {                     \
        rtLog(fmt, ##__VA_ARGS__);                              \
    }                                                           \
} while (0)

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

static BOOL   gFullNitro     = NO;
static BOOL   gFullMiniBoost = NO;
static BOOL   gAutoDriftEnd  = NO;
static float  gSpeedKmh      = 0.f;
static double gGoTime        = 0.0;
static BOOL   gHooksInstalled = NO;

static const float    kSpeedDelaySeconds = 5.0f;
static const uint32_t kNitroMaxPower     = 1000;
static const int      kTypeMini          = 2;

// Il2cpp field offsets verified against dump.cs:
enum {
    kOffNitroCurPower   = 208,  // 0xD0 SingleNitrogenCollect::mCurPower (uint)
    kOffTopMps          = 264,  // 0x108 NssPhyVehicleECUBase::mNormalTopMPS (float)
    kOffEvtVdAngleMax   = 116,  // 0x74 EvtMini::mDriftingMaxAbsVDAngle (float)
    kOffEvtDriftingTime = 124,  // 0x7C EvtMini::mDriftingTime (float)
    kOffEvtInCanTrigger = 133,  // 0x85 EvtMini::mInCanTriggerTime (bool)
    kOffEvtMiniVdMax    = 136,  // 0x88 EvtMini::mMiniBoostDriftingMaxAbsVDAngle (float)
    kOffEvtInChecking   = 140,  // 0x8C EvtMini::mIsInCheckingCanTrigger (bool)
    kOffEvtCheckTime    = 144,  // 0x90 EvtMini::mNewCheckMiniBoostTime (float)
    kOffEvtLastDrift    = 160,  // 0xA0 EvtMini::mLastIsDrifting (bool)
};

static inline double nowSeconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static inline BOOL speedWindowOpen(void) {
    if (gSpeedKmh <= 0.f) return NO;
    if (gGoTime > 0.0) {
        return (nowSeconds() - gGoTime) >= (double)kSpeedDelaySeconds;
    }
    return YES;
}

// NssVehicle::mIsMainPlayer @ 0xF8
static inline BOOL vehicleIsMainPlayer(void *vehicle) {
    if (!vehicle) return NO;
    return *(uint8_t *)((char *)vehicle + 0xF8) != 0;
}

// ExtraVelocityTriggerBase::mVehicle @ 0x18
static inline BOOL evtIsMainPlayer(void *evt) {
    if (!evt) return NO;
    return vehicleIsMainPlayer(*(void **)((char *)evt + 0x18));
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

// Function pointers resolved from UnityFramework
static Il2CppDomain *(*il2cpp_domain_get)(void) = NULL;
static const Il2CppAssembly **(*il2cpp_domain_get_assemblies)(const Il2CppDomain *domain, size_t *size) = NULL;
static const Il2CppImage *(*il2cpp_assembly_get_image)(const Il2CppAssembly *assembly) = NULL;
static Il2CppClass *(*il2cpp_class_from_name)(const Il2CppImage *image, const char *namespaze, const char *name) = NULL;
static const MethodInfo *(*il2cpp_class_get_method_from_name)(Il2CppClass *klass, const char *name, int argsCount) = NULL;
static const char *(*il2cpp_image_get_name)(const Il2CppImage *image) = NULL;

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
    *(void **)&il2cpp_image_get_name = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_image_get_name");

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

// Hooks a method via Il2CppClass vtable + MethodInfo.
// Zero code patching. Zero memory protection change. 100% safe on iOS.
static void *rtHookMethod(const char *namespaze, const char *className,
                          const char *methodName, int argsCount,
                          void *replacement) {
    Il2CppClass *klass = rtFindClass(namespaze, className);
    if (!klass) {
        rtLog("il2cpp: class %s::%s NOT FOUND", namespaze ?: "", className);
        return NULL;
    }

    // il2cpp_class_get_method_from_name automatically calls Class::Init(klass)
    const MethodInfo *method = il2cpp_class_get_method_from_name(klass, methodName, argsCount);
    if (!method) {
        rtLog("il2cpp: %s::%s(args=%d) NOT FOUND", className, methodName, argsCount);
        return NULL;
    }

    // Offset 0 of MethodInfo is methodPointer
    void *orig = *(void **)((char *)method + 0);

    // Replace in MethodInfo (for direct reflection / runtime_invoke)
    *(void **)((char *)method + 0) = replacement;

    // Offset 88 is slot (uint16_t)
    uint16_t slot = *(uint16_t *)((char *)method + 88);
    // Offset 306 is vtable_count (uint16_t)
    uint16_t vtable_count = *(uint16_t *)((char *)klass + 306);

    uintptr_t base = unityFrameworkBase();
    uintptr_t rva = base && orig ? ((uintptr_t)orig - base) : 0;

    // Offset 336 (0x150) is vtable array of VirtualInvokeData
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
static void  (*orig_Nitro_Update)(void *, float, const void *) = NULL;
static float (*orig_Nitro_GetProgress)(void *, const void *) = NULL;
static void  (*orig_EvtMini_Update)(void *, float, const void *) = NULL;
static BOOL  (*orig_EvtMini_CanTrigger)(void *, const void *) = NULL;
static int   (*orig_EvtMini_Trigger)(void *, const void *) = NULL;
static BOOL  (*orig_EvtN2O_CanTrigger)(void *, const void *) = NULL;
static int   (*orig_EvtN2O_Trigger)(void *, const void *) = NULL;
static BOOL  (*orig_IsCanTriggerExVel)(void *, int, const void *) = NULL;
static void  (*orig_Drift_Release)(void *, const void *) = NULL;
static void  (*orig_Drift_ForceEnd)(void *, const void *) = NULL;
static void  (*orig_ECU_SetNormalTopMPS)(void *, float, const void *) = NULL;

static void hook_GoImpEnter(void *self, const void *method) {
    RT_TRACE(4, "hook GameGoState::ImpEnter self=%p", self);
    if (orig_GameGo_ImpEnter) orig_GameGo_ImpEnter(self, method);
    gGoTime = nowSeconds();
    rtLog("race started -> speed gate armed (%.1fs delay)", kSpeedDelaySeconds);
}

static void hook_NitroUpdate(void *self, float dt, const void *method) {
    RT_TRACE(3, "hook Nitro::Update self=%p dt=%.3f", self, dt);
    if (orig_Nitro_Update) orig_Nitro_Update(self, dt, method);
    if (!gFullNitro || !self) return;
    void *veh = *(void **)((char *)self + 0x60);
    if (!vehicleIsMainPlayer(veh)) return;
    *(uint32_t *)((char *)self + kOffNitroCurPower) = kNitroMaxPower;
}

static float hook_NitroGetProgress(void *self, const void *method) {
    RT_TRACE(3, "hook Nitro::get_ProgressBarPowerValue self=%p", self);
    if (gFullNitro && self &&
        vehicleIsMainPlayer(*(void **)((char *)self + 0x60))) return 1.0f;
    return orig_Nitro_GetProgress ? orig_Nitro_GetProgress(self, method) : 0.0f;
}

static inline void armMiniWindow(void *self) {
    *(float *)   ((char *)self + kOffEvtVdAngleMax)   = 999.0f;
    *(float *)   ((char *)self + kOffEvtMiniVdMax)    = 999.0f;
    *(float *)   ((char *)self + kOffEvtDriftingTime) = 999.0f;
    *(float *)   ((char *)self + kOffEvtCheckTime)    = 0.0f;
    *(uint8_t *) ((char *)self + kOffEvtInCanTrigger) = 1;
    *(uint8_t *) ((char *)self + kOffEvtInChecking)   = 1;
    *(uint8_t *) ((char *)self + kOffEvtLastDrift)    = 1;
}

static void hook_EvtMiniUpdate(void *self, float dt, const void *method) {
    RT_TRACE(3, "hook EvtMini::Update self=%p", self);
    if (orig_EvtMini_Update) orig_EvtMini_Update(self, dt, method);
    if (!gFullMiniBoost || !self) return;
    if (!evtIsMainPlayer(self)) return;
    armMiniWindow(self);
}

static BOOL hook_EvtMiniCanTrigger(void *self, const void *method) {
    RT_TRACE(5, "hook EvtMini::IsCanTrigger self=%p", self);
    if (gFullMiniBoost && evtIsMainPlayer(self)) {
        armMiniWindow(self);
        return YES;
    }
    return orig_EvtMini_CanTrigger ? orig_EvtMini_CanTrigger(self, method) : NO;
}

static int hook_EvtMiniTrigger(void *self, const void *method) {
    RT_TRACE(5, "hook EvtMini::Trigger self=%p", self);
    return orig_EvtMini_Trigger ? orig_EvtMini_Trigger(self, method) : -1;
}

static BOOL hook_EvtN2OCanTrigger(void *self, const void *method) {
    RT_TRACE(5, "hook EvtN2O::IsCanTrigger self=%p", self);
    if (gFullNitro && evtIsMainPlayer(self)) return YES;
    return orig_EvtN2O_CanTrigger ? orig_EvtN2O_CanTrigger(self, method) : NO;
}

static int hook_EvtN2OTrigger(void *self, const void *method) {
    RT_TRACE(5, "hook EvtN2O::Trigger self=%p", self);
    return orig_EvtN2O_Trigger ? orig_EvtN2O_Trigger(self, method) : -1;
}

static BOOL hook_IsCanTriggerExVel(void *self, int type, const void *method) {
    RT_TRACE(6, "hook IsCanTriggerExtraVelocity self=%p type=%d", self, type);
    if (gFullMiniBoost && type == kTypeMini && self &&
        vehicleIsMainPlayer(*(void **)((char *)self + 0x68))) return YES;
    return orig_IsCanTriggerExVel ? orig_IsCanTriggerExVel(self, type, method) : NO;
}

static void hook_DriftForceEnd(void *self, const void *method) {
    RT_TRACE(4, "hook DriftCtrl::ForceEndDrifting self=%p", self);
    if (orig_Drift_ForceEnd) orig_Drift_ForceEnd(self, method);
}

static void hook_DriftRelease(void *self, const void *method) {
    RT_TRACE(4, "hook DriftCtrl::ReleaseDrifting self=%p", self);
    if (orig_Drift_Release) orig_Drift_Release(self, method);
    if (!gAutoDriftEnd || !self) return;

    void *dyn = *(void **)((char *)self + 0x10);   // NssVehicleDriftCtrl.mVehicle : IDynamicVehicle
    if (!dyn) return;
    void *veh = *(void **)((char *)dyn + 0x10);    // DynamicVehicle.mVehicle : IVehicle
    if (!vehicleIsMainPlayer(veh)) return;

    if (orig_Drift_ForceEnd) orig_Drift_ForceEnd(self, nullptr);
}

static void hook_SetNormalTopMPS(void *self, float topMps, const void *method) {
    RT_TRACE(3, "hook ECU::SetNormalTopMPS self=%p mps=%.3f", self, topMps);
    if (orig_ECU_SetNormalTopMPS) orig_ECU_SetNormalTopMPS(self, topMps, method);

    if (!self || !speedWindowOpen()) return;
    void *veh = *(void **)((char *)self + 0x18);   // NssPhyVehicleECUBase.mVehicle
    if (!vehicleIsMainPlayer(veh)) return;
    *(float *)((char *)self + kOffTopMps) += gSpeedKmh / 3.6f;
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

    // 1. Full Nitro
    orig_Nitro_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SingleNitrogenCollect", "Update", 1, (void *)hook_NitroUpdate);
    orig_Nitro_GetProgress = (float (*)(void *, const void *))
        rtHookMethod("", "SingleNitrogenCollect", "get_ProgressBarPowerValue", 0, (void *)hook_NitroGetProgress);
    orig_EvtN2O_CanTrigger = (BOOL (*)(void *, const void *))
        rtHookMethod("", "EvtN2O", "IsCanTrigger", 0, (void *)hook_EvtN2OCanTrigger);
    orig_EvtN2O_Trigger = (int (*)(void *, const void *))
        rtHookMethod("", "EvtN2O", "Trigger", 0, (void *)hook_EvtN2OTrigger);

    // 2. Full Mini Boost
    orig_EvtMini_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "EvtMini", "Update", 1, (void *)hook_EvtMiniUpdate);
    orig_EvtMini_CanTrigger = (BOOL (*)(void *, const void *))
        rtHookMethod("", "EvtMini", "IsCanTrigger", 0, (void *)hook_EvtMiniCanTrigger);
    orig_EvtMini_Trigger = (int (*)(void *, const void *))
        rtHookMethod("", "EvtMini", "Trigger", 0, (void *)hook_EvtMiniTrigger);
    orig_IsCanTriggerExVel = (BOOL (*)(void *, int, const void *))
        rtHookMethod("", "ExtraVelocityTriggerMgr", "IsCanTriggerExtraVelocity", 1, (void *)hook_IsCanTriggerExVel);

    // 3. Auto End Drift
    orig_Drift_Release = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ReleaseDrifting", 0, (void *)hook_DriftRelease);
    orig_Drift_ForceEnd = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ForceEndDrifting", 0, (void *)hook_DriftForceEnd);

    // 4. Speed Slider (ECU)
    orig_ECU_SetNormalTopMPS = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleECU", "SetNormalTopMPS", 1, (void *)hook_SetNormalTopMPS);
    rtHookMethod("", "NssPhyVehicleECUBase", "SetNormalTopMPS", 1, (void *)hook_SetNormalTopMPS);

    // 5. Race start marker
    orig_GameGo_ImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "FreePracticeGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "ActionSpeedGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);

    rtLog("install: done (IL2CPP metadata hooks active)");
}

#pragma mark - UI

// Window that only takes touches landing on our own controls.
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
    self.window.hidden = NO;   // never makeKeyAndVisible: keep the game key

    self.host = self.window.rootViewController.view;

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

    CGFloat w = 300, h = 300;
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

    [self switchAtY:44  title:@"Full Nitro"      on:gFullNitro     action:@selector(onNitro:)];
    [self switchAtY:84  title:@"Full Mini Boost" on:gFullMiniBoost action:@selector(onMini:)];
    [self switchAtY:124 title:@"Auto End Drift"  on:gAutoDriftEnd  action:@selector(onAutoDrift:)];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 168, 268, 22)];
    self.speedLabel.textColor = UIColor.whiteColor;
    self.speedLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.speedLabel.text = [self speedText];
    [self.panel addSubview:self.speedLabel];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 196, 268, 32)];
    slider.minimumValue = 0.f;
    slider.maximumValue = 200.f;
    slider.value = gSpeedKmh;
    slider.tintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
    [slider addTarget:self action:@selector(onSpeedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:slider];

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(16, 236, 268, 50)];
    note.numberOfLines = 3;
    note.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    note.font = [UIFont systemFontOfSize:11];
    note.text = @"Speed applies only after race start + 5s.\nAuto End Drift ends the drift when the drift key is released.";
    [self.panel addSubview:note];
}

- (NSString *)speedText {
    return [NSString stringWithFormat:@"Boost speed: %d km/h (+5s)", (int)gSpeedKmh];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.hidden = NO;
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}

- (void)onNitro:(UISwitch *)s     { gFullNitro = s.isOn;     rtLog("toggle FullNitro=%d", s.isOn); }
- (void)onMini:(UISwitch *)s      { gFullMiniBoost = s.isOn; rtLog("toggle FullMiniBoost=%d", s.isOn); }
- (void)onAutoDrift:(UISwitch *)s { gAutoDriftEnd = s.isOn;  rtLog("toggle AutoEndDrift=%d", s.isOn); }

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
