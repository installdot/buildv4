// Tweak.xm — Race Toolkit v2 (iOS, IL2CPP VTable & Metadata Hook)
//
// Features:
// 1. Drift không mất tốc: hook DriftingSlideVelDamping (RVA 0x7C713DC) — chặn ma sát
//    drift native PHY_VehicleApplyExtraDriftFriction. Không đổi top speed.
// 2. Gia tốc: ghi mExtraKMPH (0x44) + mExtraTorque (0x48) trên PowerChain — chỉ là
//    extra velocity có sẵn của xe, bộ đếm km/h (ReadVehicleKMPH) KHÔNG thay đổi.
//    Bật sau 5s từ khi xuất phát.
// 3. No2 kéo dài: ForceDelayEndExtraVelocity(N2O) liên tục trong PowerChain::Update —
//    đẩy thời điểm kết thúc N2O ra sau mỗi frame.
// 4. Miniboost: ForceCanTriggerOnce(Mini/Air/FallingGround) liên tục.
// 5. Auto End Drift: ExitCurDriftState + ForceClearDriftParams khi thả nút drift.

#import <UIKit/UIKit.h>
#import <math.h>
#import <string.h>
#import <time.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>

#pragma mark - Logger

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
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    char buf[2048];
    int n = snprintf(buf, sizeof(buf), "[%ld.%03ld] ", (long)ts.tv_sec, ts.tv_nsec / 1000000);
    va_list ap; va_start(ap, fmt);
    int m = vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
    va_end(ap);
    if (m < 0) return;
    size_t total = (size_t)n + (size_t)m;
    if (total + 1 < sizeof(buf)) { buf[total++] = '\n'; buf[total] = '\0'; }
    write(gLogFd, buf, total);
}

#pragma mark - Crash reporter

static void rtSignalHandler(int sig, siginfo_t *info, void *uap) {
    char msg[300];
    int len = snprintf(msg, sizeof(msg), "\n===== CRASH signal=%d faultAddr=%p PC=%p =====\n",
                       sig, info ? info->si_addr : 0,
                       uap ? (void *)((ucontext_t *)uap)->uc_mcontext->__ss.__pc : 0);
    write(gLogFd, msg, len);
    fsync(gLogFd);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void rtInstallCrashHandler(void) {
    static char altStack[64 * 1024];
    stack_t ss = { .ss_sp = altStack, .ss_size = sizeof(altStack), .ss_flags = 0 };
    sigaltstack(&ss, NULL);
    struct sigaction sa; memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = rtSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };
    for (size_t i = 0; i < 6; i++) sigaction(sigs[i], &sa, NULL);
}

#pragma mark - State

static BOOL gDriftNoSlow    = YES;  // drift khong mat toc
static BOOL gSpeedBoost     = NO;   // gia toc an (mExtraKMPH)
static float gSpeedKmh      = 0.f;  // 0..120
static BOOL gProlongN2O     = YES;  // keo dai no2
static BOOL gFullMiniBoost  = NO;
static BOOL gAutoDriftEnd   = YES;
static double gGoTime       = 0.0;
static double gNextN2OProlong = 0.0;
static BOOL gHooksInstalled = NO;

static inline double nowSeconds(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

#pragma mark - IL2CPP API

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct { void *methodPtr; const MethodInfo *method; } VirtualInvokeData;

static Il2CppDomain *(*il2cpp_domain_get)(void) = NULL;
static const Il2CppAssembly **(*il2cpp_domain_get_assemblies)(const Il2CppDomain *, size_t *) = NULL;
static const Il2CppImage *(*il2cpp_assembly_get_image)(const Il2CppAssembly *) = NULL;
static Il2CppClass *(*il2cpp_class_from_name)(const Il2CppImage *, const char *, const char *) = NULL;
static const MethodInfo *(*il2cpp_class_get_method_from_name)(Il2CppClass *, const char *, int) = NULL;

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
        if (name && strstr(name, "UnityFramework")) { handle = dlopen(name, RTLD_NOW | RTLD_NOLOAD); break; }
    }
    *(void **)&il2cpp_domain_get = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_domain_get");
    *(void **)&il2cpp_domain_get_assemblies = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    *(void **)&il2cpp_assembly_get_image = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_assembly_get_image");
    *(void **)&il2cpp_class_from_name = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_class_from_name");
    *(void **)&il2cpp_class_get_method_from_name = dlsym(handle ?: RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    if (!il2cpp_domain_get || !il2cpp_class_from_name || !il2cpp_class_get_method_from_name) return NO;
    rtLog("il2cpp: API resolved");
    return YES;
}

static Il2CppClass *rtFindClass(const char *ns, const char *name) {
    if (!il2cpp_domain_get) return NULL;
    Il2CppDomain *domain = il2cpp_domain_get();
    if (!domain) return NULL;
    size_t count = 0;
    const Il2CppAssembly **assemblies = il2cpp_domain_get_assemblies(domain, &count);
    if (!assemblies || !count) return NULL;
    for (size_t i = 0; i < count; i++) {
        const Il2CppImage *image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        Il2CppClass *k = il2cpp_class_from_name(image, ns ?: "", name);
        if (k) return k;
    }
    return NULL;
}

static void *rtHookMethod(const char *ns, const char *className, const char *methodName,
                          int argsCount, void *replacement) {
    Il2CppClass *klass = rtFindClass(ns, className);
    if (!klass) { rtLog("il2cpp: class %s NOT FOUND", className); return NULL; }
    const MethodInfo *method = il2cpp_class_get_method_from_name(klass, methodName, argsCount);
    if (!method) { rtLog("il2cpp: %s::%s(%d) NOT FOUND", className, methodName, argsCount); return NULL; }

    void *orig = *(void **)((char *)method + 0);
    *(void **)((char *)method + 0) = replacement;

    uint16_t slot = *(uint16_t *)((char *)method + 88);
    uint16_t vcount = *(uint16_t *)((char *)klass + 306);
    uintptr_t base = unityFrameworkBase();
    uintptr_t rva = base && orig ? (uintptr_t)orig - base : 0;

    if (slot < vcount) {
        VirtualInvokeData *vt = (VirtualInvokeData *)((char *)klass + 336);
        vt[slot].methodPtr = replacement;
    }
    rtLog("il2cpp: HOOK %s::%s (slot %u rva=0x%lx) orig=%p -> rep=%p",
          className, methodName, slot, (unsigned long)rva, orig, replacement);
    return orig;
}

static void *rtMethodPtr(const char *ns, const char *className, const char *methodName, int argsCount) {
    Il2CppClass *k = rtFindClass(ns, className);
    if (!k) return NULL;
    const MethodInfo *m = il2cpp_class_get_method_from_name(k, methodName, argsCount);
    return m ? *(void **)m : NULL;
}

#pragma mark - Originals

static void  (*orig_GameGo_ImpEnter)(void *, const void *) = NULL;
static void  (*orig_PowerChain_Update)(void *, float, const void *) = NULL;
static void  (*orig_DriftSlideVelDamping)(void *, float, float, int, float, const void *) = NULL;
static void  (*orig_Drift_Release)(void *, const void *) = NULL;
static void  (*orig_Drift_Exit)(void *, const void *) = NULL;
static void  (*orig_Drift_ForceClear)(void *, const void *) = NULL;
static void  (*orig_ExVelMgr_Update)(void *, float, const void *) = NULL;

static void  (*ExtraVelMgr_ForceOnce)(void *, int) = NULL;
static int   (*ExtraVelFast_ForceDelayEnd)(void *, int) = NULL;

#pragma mark - Hooks

// 1. Race start
static void hook_GoImpEnter(void *self, const void *method) {
    if (orig_GameGo_ImpEnter) orig_GameGo_ImpEnter(self, method);
    gGoTime = nowSeconds();
    gNextN2OProlong = 0.0;
    rtLog("race started, boost gate 5s");
}

// 2. Gia tốc AN (mExtraKMPH = extra velocity field riêng của xe — KHÔNG đụng top speed
//    nên bộ đếm km/h (ReadVehicleKMPH đọc SimOutput) KHÔNG đổi. Xe vẫn nhanh hơn vì
//    PowerChain cộng mExtraKMPH vào vận tốc cuối mỗi frame.
static void hook_PowerChainUpdate(void *self, float dt, const void *method) {
    if (orig_PowerChain_Update) orig_PowerChain_Update(self, dt, method);
    if (!self) return;

    if (gSpeedBoost && gSpeedKmh > 0.f && gGoTime > 0.0 && (nowSeconds() - gGoTime) >= 5.0) {
        // mExtraKMPH (0x44): cộng vận tốc phụ; mExtraTorque (0x48): lực đẩy phụ.
        // Đây là 2 trường extra-velocity chuẩn của PowerChain — server telemetry
        // (SdcExtraVelocity) đã có channel cho chúng, không tạo giá trị lạ.
        *(float *)((char *)self + 0x44) = gSpeedKmh;
        *(float *)((char *)self + 0x48) = gSpeedKmh * 0.35f;
    }

    // 3. No2 kéo dài: ForceDelayEndExtraVelocity(N2O=1) mỗi 0.4s — đẩy thời điểm kết thúc.
    if (gProlongN2O && ExtraVelFast_ForceDelayEnd && gGoTime > 0.0 && nowSeconds() >= gNextN2OProlong) {
        void *veh = *(void **)((char *)self + 0x10);  // mVehicle (DynamicVehicle) at 0x10
        if (veh) {
            ExtraVelFast_ForceDelayEnd(veh, 1);  // N2O
            ExtraVelFast_ForceDelayEnd(veh, 14); // SuperN2O
        }
        gNextN2OProlong = nowSeconds() + 0.4;
    }
}

// 4. DRIFT KHÔNG MẤT TỐC: chặn ma sát drift native. DriftingSlideVelDamping là hàm duy nhất
//    tính (slerpCoef, extraMPS) rồi gọi PHY_VehicleApplyExtraDriftFriction. Không gọi orig
//    = không mất tốc khi drift. Không đổi top speed, không đổi km/h hiển thị.
static void hook_DriftSlideVelDamping(void *self, float curMPS, float dampingCoef,
                                       int driftStateType, float deltaTime, const void *method) {
    if (gDriftNoSlow) return;  // bỏ toàn bộ ma sát — orig KHÔNG chạy
    if (orig_DriftSlideVelDamping)
        orig_DriftSlideVelDamping(self, curMPS, dampingCoef, driftStateType, deltaTime, method);
}

// 5. Mini boost
static void hook_ExVelMgrUpdate(void *self, float dt, const void *method) {
    if (orig_ExVelMgr_Update) orig_ExVelMgr_Update(self, dt, method);
    if (!gFullMiniBoost || !self) return;
    if (ExtraVelMgr_ForceOnce) {
        ExtraVelMgr_ForceOnce(self, 2);   // Mini
        ExtraVelMgr_ForceOnce(self, 3);   // Air
        ExtraVelMgr_ForceOnce(self, 11);  // FallingGround
    }
}

// 6. Auto End Drift — hook riêng cho từng hàm, tránh recursion
static void hook_DriftRelease(void *self, const void *method) {
    if (orig_Drift_Release) orig_Drift_Release(self, method);
    if (!gAutoDriftEnd || !self) return;
    if (orig_Drift_Exit)       orig_Drift_Exit(self, nullptr);
    if (orig_Drift_ForceClear) orig_Drift_ForceClear(self, nullptr);
}
static void hook_DriftExit(void *self, const void *method) {
    if (orig_Drift_Exit) orig_Drift_Exit(self, method);
}
static void hook_DriftClear(void *self, const void *method) {
    if (orig_Drift_ForceClear) orig_Drift_ForceClear(self, method);
}

#pragma mark - Install

static BOOL rtHooksDisabled(void) {
    char path[1200];
    const char *dir = strrchr(gLogPath, '/');
    if (!dir) return NO;
    size_t n = (size_t)(dir - gLogPath);
    if (n + 10 >= sizeof(path)) return NO;
    memcpy(path, gLogPath, n); memcpy(path + n, "/no_hooks", 10);
    int fd = open(path, O_RDONLY);
    if (fd >= 0) { close(fd); return YES; }
    return NO;
}

static void installHooks(void) {
    if (rtHooksDisabled()) { rtLog("install: SKIPPED (no_hooks)"); return; }
    rtLog("install: v2 hooks");

    // Race start (5s gate)
    orig_GameGo_ImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "FreePracticeGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "ActionSpeedGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);

    // PowerChain: gia tốc an + N2O prolong
    orig_PowerChain_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehiclePowerChain", "Update", 1, (void *)hook_PowerChainUpdate);

    // DRIFT NO-SLOW: hook DriftingSlideVelDamping (rva 0x7C713DC)
    orig_DriftSlideVelDamping = (void (*)(void *, float, float, int, float, const void *))
        rtHookMethod("", "NssVehicleDriftHelper", "DriftingSlideVelDamping", 4, (void *)hook_DriftSlideVelDamping);

    // Mini boost
    orig_ExVelMgr_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "ExtraVelocityTriggerMgr", "Update", 1, (void *)hook_ExVelMgrUpdate);
    ExtraVelMgr_ForceOnce = (void (*)(void *, int))
        rtMethodPtr("", "ExtraVelocityTriggerMgr", "ForceCanTriggerOnce", 1);

    // N2O prolong helper
    ExtraVelFast_ForceDelayEnd = (int (*)(void *, int))
        rtMethodPtr("", "ExtraVelocityFast", "ForceDelayEndExtraVelocity", 2);

    // Auto end drift
    orig_Drift_Release = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ReleaseDrifting", 0, (void *)hook_DriftRelease);
    orig_Drift_Exit = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ExitCurDriftState", 0, (void *)hook_DriftExit);
    orig_Drift_ForceClear = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ForceClearDriftParams", 0, (void *)hook_DriftClear);

    rtLog("install: done");
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
@end

@interface RCMenu : NSObject
@property (nonatomic, strong) RCPassThroughWindow *window;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *speedLabel;
@end

static RCMenu *gMenu = nil;

@implementation RCMenu

- (UISwitch *)switchAtY:(CGFloat)y title:(NSString *)t on:(BOOL)on action:(SEL)a {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 4, 205, 32)];
    l.text = t; l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.panel addSubview:l];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(226, y, 51, 31)];
    sw.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
    sw.on = on;
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:sw];
    return sw;
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

    UIView *host = self.window.rootViewController.view;

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
    [host addSubview:self.fab];

    CGFloat w = 310, h = 300;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2,
                                                        (screen.size.height - h) / 2, w, h)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.panel.hidden = YES;
    [host addSubview:self.panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 260, 26)];
    title.text = @"Race Toolkit";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.panel addSubview:title];

    [self switchAtY:42  title:@"Drift Khong Mat Toc" on:gDriftNoSlow  action:@selector(onDriftNoSlow:)];
    [self switchAtY:78  title:@"Gia Toc An"          on:gSpeedBoost   action:@selector(onSpeed:)];
    [self switchAtY:114 title:@"No2 Keo Dai"         on:gProlongN2O   action:@selector(onN2O:)];
    [self switchAtY:150 title:@"Inf Mini Boost"      on:gFullMiniBoost action:@selector(onMini:)];
    [self switchAtY:186 title:@"Auto End Drift"      on:gAutoDriftEnd  action:@selector(onAutoDrift:)];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 222, 268, 22)];
    self.speedLabel.textColor = UIColor.whiteColor;
    self.speedLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.speedLabel.text = [self speedText];
    [self.panel addSubview:self.speedLabel];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 248, 268, 32)];
    slider.minimumValue = 0.f; slider.maximumValue = 120.f;
    slider.value = gSpeedKmh;
    slider.tintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
    [slider addTarget:self action:@selector(onSpeedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:slider];
}

- (NSString *)speedText {
    return [NSString stringWithFormat:@"Extra km/h (hidden): %d — 5s gate", (int)gSpeedKmh];
}
- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    self.window.hidden = NO;
}
- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}
- (void)onDriftNoSlow:(UISwitch *)s { gDriftNoSlow   = s.isOn; rtLog("driftNoSlow=%d",s.isOn); }
- (void)onSpeed:(UISwitch *)s       { gSpeedBoost    = s.isOn; rtLog("speedBoost=%d",s.isOn); }
- (void)onN2O:(UISwitch *)s         { gProlongN2O    = s.isOn; rtLog("prolongN2O=%d",s.isOn); }
- (void)onMini:(UISwitch *)s        { gFullMiniBoost = s.isOn; rtLog("mini=%d",s.isOn); }
- (void)onAutoDrift:(UISwitch *)s   { gAutoDriftEnd  = s.isOn; rtLog("autoDrift=%d",s.isOn); }
- (void)onSpeedChanged:(UISlider *)s {
    gSpeedKmh = s.value;
    self.speedLabel.text = [self speedText];
    rtLog("speed=%d",(int)gSpeedKmh);
}
@end

#pragma mark - Bootstrap

static void buildMenuSafely(void) {
    if (gMenu) return;
    @try {
        gMenu = [RCMenu new];
        [gMenu build];
        rtLog("UI: menu built");
    } @catch (NSException *e) {
        gMenu = nil;
        rtLog("UI: build FAILED: %s", e.reason.UTF8String ?: "?");
    }
}

static void startToolkit(void) {
    static int tries = 0;
    if (!rtInitIl2CppApi()) {
        if (++tries > 60) { rtLog("bootstrap: gave up il2cpp api"); buildMenuSafely(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }
    Il2CppDomain *domain = il2cpp_domain_get();
    size_t count = 0;
    const Il2CppAssembly **asms = domain ? il2cpp_domain_get_assemblies(domain, &count) : NULL;
    if (!asms || !count) {
        if (++tries > 60) { rtLog("bootstrap: gave up domain"); buildMenuSafely(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }
    rtLog("bootstrap: IL2CPP ready (%zu assemblies)", count);
    if (!gHooksInstalled) { gHooksInstalled = YES; installHooks(); }
    buildMenuSafely();
}

__attribute__((constructor)) static void RCInit(void) {
    rtLogOpen();
    rtInstallCrashHandler();
    rtLog("=== RaceToolkit v2 session start === log=%s pid=%d", gLogPath, getpid());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ startToolkit(); });
}
