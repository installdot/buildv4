// Mini World : Royale (com.miniworldroyale.sparkgame)
// TrollFools injected tweak with Native UIKit Floating Button & Menu Overlay.
// NO Unity IMGUI, NO GameObject injection, NO OnGUI hooks -> Completely Crash-Proof.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdarg.h>
#import <stdint.h>
#import <unistd.h>
#import <math.h>

#pragma mark - Hooking Engine Detection

typedef void (*mshook_t)(void *symbol, void *hook, void **old);
static mshook_t g_mshook = nullptr;

#pragma mark - il2cpp ABI

typedef struct { float x, y; } Vec2;

static void *(*i_domain_get)(void);
static void *(*i_thread_attach)(void *);
static void **(*i_get_assemblies)(void *, size_t *);
static void *(*i_assembly_image)(void *);
static const char *(*i_image_name)(void *);
static void *(*i_class_from_name)(void *, const char *, const char *);
static void *(*i_method_from_name)(void *, const char *, int);
static void *(*i_field_from_name)(void *, const char *);
static size_t (*i_field_offset)(void *);
static void *(*i_runtime_invoke)(void *, void *, void **, void **);

static inline void *MP(void *mi) { return mi ? *(void **)mi : nullptr; }

static void *callN(void *mi, void *obj, int argc, ...) {
    if (!mi) return nullptr;
    void *p[4] = {nullptr};
    va_list ap; va_start(ap, argc);
    for (int k = 0; k < argc && k < 4; k++) p[k] = va_arg(ap, void *);
    va_end(ap);
    void *exc = nullptr;
    void *r = i_runtime_invoke(mi, obj, argc ? p : nullptr, &exc);
    return exc ? nullptr : r;
}
#define call0(mi, obj)      callN(mi, obj, 0)
#define call1(mi, obj, a)   callN(mi, obj, 1, (void *)(a))

static void *methodOf(void *k, const char *n, int argc) {
    return k ? i_method_from_name(k, n, argc) : nullptr;
}

#pragma mark - Resolved Game Symbols

static void *K_playerCam, *K_dmgPlayer, *K_lpm, *K_propComp, *K_camera, *K_app;
static void *M_getCamera, *M_getDamageable, *M_getPropComp, *M_lpmInstance, *M_lpmLocal;
static void *M_fpCamera, *M_forceAdd, *M_canDamage, *M_speedRate, *M_fov, *M_fps;

static void *O_forceAdd = nullptr;
static void *O_canDamage = nullptr;
static void *O_speedRate = nullptr;

static size_t off_recoilAngles = 0;

static void *g_lcam = nullptr;
static void *g_ldmg = nullptr;
static void *g_lprop = nullptr;

#pragma mark - Cheat State

static BOOL  g_god = NO;
static BOOL  g_norecoil = NO;
static float g_speed = 1.0f;
static float g_fov = 0.0f;          // 0 = game default
static BOOL  g_il2cppReady = NO;

#pragma mark - Native Hooks

static void hk_forceAdd(void *self, Vec2 v, void *mi) {
    if (g_norecoil && self && self == g_lcam) return;
    ((void (*)(void *, Vec2, void *))O_forceAdd)(self, v, mi);
}

static bool hk_canDamage(void *self, uint64_t lo, uint64_t hi, void *mi) {
    if (g_god && self && self == g_ldmg) return false;
    return ((bool (*)(void *, uint64_t, uint64_t, void *))O_canDamage)(self, lo, hi, mi);
}

static float hk_speedRate(void *self, bool withNoFov, void *mi) {
    float r = ((float (*)(void *, bool, void *))O_speedRate)(self, withNoFov, mi);
    if (!g_speed || g_speed == 1.0f || !self || self != g_lprop) return r;
    return r * g_speed;
}

#pragma mark - Native UIKit UI Components

@interface MWMFloatingButton : UIButton
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, copy) void (^tapHandler)(void);
@end

@implementation MWMFloatingButton
+ (instancetype)floatingButton {
    MWMFloatingButton *btn = [MWMFloatingButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(20, 100, 50, 50);
    btn.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.85];
    btn.layer.cornerRadius = 25;
    btn.layer.borderWidth = 2.0;
    btn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:0.9].CGColor;
    btn.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:0.6].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    btn.layer.shadowOpacity = 0.8;
    btn.layer.shadowRadius = 8;

    [btn setTitle:@"M" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    [btn addTarget:btn action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

    return btn;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *parent = self.superview;
    if (!parent) return;

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.lastPoint = [pan translationInView:parent];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [pan translationInView:parent];
        CGPoint newCenter = CGPointMake(self.center.x + (delta.x - self.lastPoint.x),
                                        self.center.y + (delta.y - self.lastPoint.y));

        // Clamp to screen edges
        CGFloat halfW = self.bounds.size.width / 2.0;
        CGFloat halfH = self.bounds.size.height / 2.0;
        newCenter.x = fmax(halfW + 5, fmin(parent.bounds.size.width - halfW - 5, newCenter.x));
        newCenter.y = fmax(halfH + 20, fmin(parent.bounds.size.height - halfH - 20, newCenter.y));

        self.center = newCenter;
        self.lastPoint = delta;
    }
}

- (void)tapped {
    if (self.tapHandler) self.tapHandler();
}
@end

@interface MWMMenuView : UIView
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *fovLabel;
@end

@implementation MWMMenuView
+ (instancetype)menuViewWithFrame:(CGRect)frame {
    MWMMenuView *menu = [[MWMMenuView alloc] initWithFrame:frame];
    [menu setupUI];
    return menu;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = 16;
    self.layer.masksToBounds = YES;

    // Dark Blur Background
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = self.bounds;
    blurView.layer.cornerRadius = 16;
    blurView.layer.masksToBounds = YES;
    blurView.layer.borderWidth = 1.2;
    blurView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:0.4].CGColor;
    [self addSubview:blurView];

    UIView *content = blurView.contentView;
    CGFloat w = self.bounds.size.width;

    // Header Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, w - 60, 24)];
    title.text = @"MINI WORLD ROYALE";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [content addSubview:title];

    // Close Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 44, 8, 36, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    // Separator
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, 42, w - 32, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [content addSubview:sep];

    CGFloat y = 52;
    CGFloat rowH = 38;

    // Toggle: GOD MODE
    [self addToggleRowIn:content y:y title:@"God Mode (Invincible)" initial:g_god tag:1];
    y += rowH;

    // Toggle: NO RECOIL
    [self addToggleRowIn:content y:y title:@"No Recoil & Cam Kick" initial:g_norecoil tag:2];
    y += rowH;

    // Slider: SPEED
    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    spLbl.font = [UIFont boldSystemFontOfSize:13];
    spLbl.textColor = [UIColor whiteColor];
    spLbl.text = [NSString stringWithFormat:@"Speed Multiplier: %.1fx", g_speed];
    self.speedLabel = spLbl;
    [content addSubview:spLbl];
    y += 22;

    UISlider *spSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    spSlider.minimumValue = 1.0f;
    spSlider.maximumValue = 5.0f;
    spSlider.value = g_speed;
    [spSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:spSlider];
    y += 32;

    // Slider: FOV
    UILabel *fvLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    fvLbl.font = [UIFont boldSystemFontOfSize:13];
    fvLbl.textColor = [UIColor whiteColor];
    fvLbl.text = [NSString stringWithFormat:@"Camera FOV: %d°", (int)(g_fov > 0 ? g_fov : 90)];
    self.fovLabel = fvLbl;
    [content addSubview:fvLbl];
    y += 22;

    UISlider *fvSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    fvSlider.minimumValue = 60.0f;
    fvSlider.maximumValue = 120.0f;
    fvSlider.value = g_fov > 0 ? g_fov : 90.0f;
    [fvSlider addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:fvSlider];
    y += 34;

    // Button: 120 FPS
    UIButton *fpsBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    fpsBtn.frame = CGRectMake(16, y, (w - 40) / 2, 32);
    fpsBtn.backgroundColor = [UIColor colorWithRed:0.12 green:0.22 blue:0.32 alpha:0.8];
    fpsBtn.layer.cornerRadius = 8;
    fpsBtn.layer.borderWidth = 1.0;
    fpsBtn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:0.4].CGColor;
    [fpsBtn setTitle:@"Unlock 120 FPS" forState:UIControlStateNormal];
    [fpsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    fpsBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [fpsBtn addTarget:self action:@selector(unlockFpsTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:fpsBtn];

    // Button: Reset All
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetBtn.frame = CGRectMake(16 + (w - 40) / 2 + 8, y, (w - 40) / 2, 32);
    resetBtn.backgroundColor = [UIColor colorWithRed:0.25 green:0.10 blue:0.10 alpha:0.8];
    resetBtn.layer.cornerRadius = 8;
    resetBtn.layer.borderWidth = 1.0;
    resetBtn.layer.borderColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.4].CGColor;
    [resetBtn setTitle:@"Reset Normal" forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:resetBtn];
    y += 40;

    // Status Label
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    status.font = [UIFont systemFontOfSize:12];
    status.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    status.textAlignment = NSTextAlignmentCenter;
    status.text = @"Status: Waiting for game...";
    self.statusLabel = status;
    [content addSubview:status];

    // Enable dragging on header
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuPan:)];
    [self addGestureRecognizer:pan];
}

- (void)addToggleRowIn:(UIView *)content y:(CGFloat)y title:(NSString *)title initial:(BOOL)on tag:(NSInteger)tag {
    CGFloat w = self.bounds.size.width;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 4, w - 80, 24)];
    lbl.font = [UIFont boldSystemFontOfSize:14];
    lbl.textColor = [UIColor whiteColor];
    lbl.text = title;
    [content addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 68, y, 51, 31)];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:sw];
}

- (void)switchChanged:(UISwitch *)sw {
    if (sw.tag == 1) g_god = sw.isOn;
    if (sw.tag == 2) g_norecoil = sw.isOn;
}

- (void)speedChanged:(UISlider *)sl {
    g_speed = sl.value;
    self.speedLabel.text = [NSString stringWithFormat:@"Speed Multiplier: %.1fx", g_speed];
}

- (void)fovChanged:(UISlider *)sl {
    g_fov = sl.value;
    self.fovLabel.text = [NSString stringWithFormat:@"Camera FOV: %d°", (int)g_fov];
}

- (void)unlockFpsTapped {
    if (M_fps) {
        int target = 120;
        call1(M_fps, nullptr, &target);
        self.statusLabel.text = @"FPS set to 120";
    }
}

- (void)resetTapped {
    g_god = NO;
    g_norecoil = NO;
    g_speed = 1.0f;
    g_fov = 0.0f;
    self.speedLabel.text = @"Speed Multiplier: 1.0x";
    self.fovLabel.text = @"Camera FOV: Default";
    for (UIView *v in [self subviews]) {
        for (UIView *sub in [v subviews]) {
            if ([sub isKindOfClass:[UISwitch class]]) [(UISwitch *)sub setOn:NO animated:YES];
            if ([sub isKindOfClass:[UISlider class]]) [(UISlider *)sub setValue:1.0f animated:YES];
        }
    }
}

- (void)closeTapped {
    self.hidden = YES;
}

- (void)handleMenuPan:(UIPanGestureRecognizer *)pan {
    UIView *parent = self.superview;
    if (!parent) return;
    static CGPoint startCenter;
    if (pan.state == UIGestureRecognizerStateBegan) {
        startCenter = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [pan translationInView:parent];
        self.center = CGPointMake(startCenter.x + delta.x, startCenter.y + delta.y);
    }
}
@end

#pragma mark - UI Manager Singleton

@interface MWMUIManager : NSObject
@property (nonatomic, strong) MWMFloatingButton *floatingButton;
@property (nonatomic, strong) MWMMenuView *menuView;
@property (nonatomic, strong) CADisplayLink *displayLink;
+ (instancetype)shared;
- (void)setupUI;
@end

@implementation MWMUIManager
+ (instancetype)shared {
    static MWMUIManager *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[MWMUIManager alloc] init]; });
    return inst;
}

- (void)setupUI {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        // Fallback for scene-based iOS 13+
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
    }
    if (!window) return;

    if (!self.floatingButton) {
        self.floatingButton = [MWMFloatingButton floatingButton];
        __weak MWMUIManager *weakSelf = self;
        self.floatingButton.tapHandler = ^{
            weakSelf.menuView.hidden = !weakSelf.menuView.hidden;
            if (!weakSelf.menuView.hidden) {
                [weakSelf.menuView.superview bringSubviewToFront:weakSelf.menuView];
            }
        };
        [window addSubview:self.floatingButton];
    }

    if (!self.menuView) {
        CGSize sz = window.bounds.size;
        CGFloat mw = 320, mh = 310;
        self.menuView = [MWMMenuView menuViewWithFrame:CGRectMake((sz.width - mw) / 2, (sz.height - mh) / 2, mw, mh)];
        self.menuView.hidden = YES;
        [window addSubview:self.menuView];
    }

    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)onFrame {
    if (!g_il2cppReady) return;

    // Per-frame player refresh
    if (M_lpmInstance && M_lpmLocal) {
        void *lpm = call0(M_lpmInstance, nullptr);
        void *pl  = lpm ? call0(M_lpmLocal, lpm) : nullptr;
        g_lcam  = (pl && M_getCamera)     ? call0(M_getCamera, pl)     : nullptr;
        g_ldmg  = (pl && M_getDamageable) ? call0(M_getDamageable, pl) : nullptr;
        g_lprop = (pl && M_getPropComp)   ? call0(M_getPropComp, pl)   : nullptr;
    }

    // Update status indicator
    if (self.menuView && !self.menuView.hidden) {
        if (g_lprop || g_lcam) {
            self.menuView.statusLabel.text = @"Status: In-Game (Player Active)";
            self.menuView.statusLabel.textColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0];
        } else {
            self.menuView.statusLabel.text = @"Status: In Lobby / Waiting for Match";
            self.menuView.statusLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        }
    }

    // Recoil zeroing (per frame on local camera)
    if (g_norecoil && g_lcam && off_recoilAngles) {
        *(Vec2 *)((char *)g_lcam + off_recoilAngles) = Vec2{0.f, 0.f};
    }

    // FOV setting
    if (g_fov > 0.f && g_lcam && M_fpCamera && M_fov) {
        void *cam = call0(M_fpCamera, g_lcam);
        if (cam) call1(M_fov, cam, &g_fov);
    }
}
@end

#pragma mark - Safe IL2CPP Resolution

static void *findImage(const char *name) {
    size_t n = 0;
    void **asms = i_get_assemblies(i_domain_get(), &n);
    if (!asms) return nullptr;
    for (size_t k = 0; k < n; k++) {
        void *img = i_assembly_image(asms[k]);
        const char *in = img ? i_image_name(img) : (const char *)0;
        if (in && !strcmp(in, name)) return img;
    }
    return nullptr;
}

static void resolveIl2Cpp(void) {
    void *game = findImage("Assembly-CSharp.dll");
    void *core = findImage("UnityEngine.CoreModule.dll");
    if (!game || !core) return;

    void *K_player = i_class_from_name(game, "HQFPSTemplate", "Player");
    K_playerCam    = i_class_from_name(game, "HQFPSTemplate", "PlayerCamera");
    K_dmgPlayer    = i_class_from_name(game, "", "DamageablePlayer");
    K_lpm          = i_class_from_name(game, "", "LocalPlayerManager");
    K_propComp     = i_class_from_name(game, "", "PlayerPropertyComp");
    K_camera       = i_class_from_name(core, "UnityEngine", "Camera");
    K_app          = i_class_from_name(core, "UnityEngine", "Application");

    M_getCamera     = methodOf(K_player, "get_Camera", 0);
    M_getDamageable = methodOf(K_player, "get_DamageablePlayer", 0);
    M_getPropComp   = methodOf(K_player, "get_PropertyComp", 0);
    M_lpmInstance   = methodOf(K_lpm, "get_Instance", 0);
    M_lpmLocal      = methodOf(K_lpm, "get_LocalPlayer", 0);
    M_fpCamera      = methodOf(K_playerCam, "GetFPCamera", 0);
    M_forceAdd      = methodOf(K_playerCam, "AddForceAngle", 1);
    M_canDamage     = methodOf(K_dmgPlayer, "CheckCanDamage", 1);
    M_speedRate     = methodOf(K_propComp, "GetSpeedRate", 1);
    M_fov           = methodOf(K_camera, "set_fieldOfView", 1);
    M_fps           = methodOf(K_app, "set_targetFrameRate", 1);

    void *f = K_playerCam ? i_field_from_name(K_playerCam, "m_RecoilAngles") : nullptr;
    off_recoilAngles = f ? i_field_offset(f) : 0;

    // Install hooks only if MSHookFunction is provided by the injector/runtime
    if (g_mshook) {
        if (MP(M_canDamage)) g_mshook(MP(M_canDamage), (void *)hk_canDamage, &O_canDamage);
        if (MP(M_forceAdd))  g_mshook(MP(M_forceAdd),  (void *)hk_forceAdd,  &O_forceAdd);
        if (MP(M_speedRate)) g_mshook(MP(M_speedRate), (void *)hk_speedRate, &O_speedRate);
    }

    g_il2cppReady = YES;
    NSLog(@"[MWM] IL2CPP ready! hooks=(%p,%p,%p) recoilOff=0x%zx",
          MP(M_canDamage), MP(M_forceAdd), MP(M_speedRate), off_recoilAngles);
}

static void initTweak(void) {
    // 1. Resolve il2cpp API exports dynamically
    i_domain_get       = (void *(*)(void))dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    i_thread_attach    = (void *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_thread_attach");
    i_get_assemblies   = (void **(*)(void *, size_t *))dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    i_assembly_image   = (void *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    i_image_name       = (const char *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_image_get_name");
    i_class_from_name  = (void *(*)(void *, const char *, const char *))dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    i_method_from_name = (void *(*)(void *, const char *, int))dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    i_field_from_name  = (void *(*)(void *, const char *))dlsym(RTLD_DEFAULT, "il2cpp_class_get_field_from_name");
    i_field_offset     = (size_t (*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_field_get_offset");
    i_runtime_invoke   = (void *(*)(void *, void *, void **, void **))dlsym(RTLD_DEFAULT, "il2cpp_runtime_invoke");

    g_mshook = (mshook_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (!g_mshook) g_mshook = (mshook_t)dlsym(RTLD_DEFAULT, "MSHookFunctionUnsafe");

    // 2. Setup native UIKit UI
    [[MWMUIManager shared] setupUI];

    // 3. Attach thread and resolve IL2CPP classes
    if (i_domain_get) {
        void *domain = i_domain_get();
        if (domain && i_thread_attach) {
            i_thread_attach(domain);
            resolveIl2Cpp();
        }
    }
}

#pragma mark - Safe Launch Trigger

static void onAppLaunched(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    // Delay 3.5s after launch to ensure Unity and window are 100% active
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        initTweak();
    });
}

__attribute__((constructor)) static void mwm_entry(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
                                    NULL,
                                    &onAppLaunched,
                                    (__bridge CFStringRef)UIApplicationDidFinishLaunchingNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDrop);
}
