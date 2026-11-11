// Mini World : Royale (com.miniworldroyale.sparkgame)
// TrollFools injected tweak — Native UIKit floating button + menu.
//
// Design rules that make it crash-proof on every screen (splash, loading, lobby, match):
//   * NO code patching at all (no MSHookFunction, no MethodInfo.methodPointer writes).
//     Patching while the engine is streaming scenes is the main crash surface.
//   * NO il2cpp_runtime_invoke for methods with value-type parameters: the runtime
//     expects BOXED arguments there, a raw float*/int* is read as an Il2CppObject*
//     and faults. Every call below goes straight to MethodInfo.methodPointer with
//     the real native ABI (verified from the disassembly).
//   * NO UnityEngine.Object.GetComponent while a scene may be streaming — only
//     cached references are read out of managed memory, after an m_CachedPtr
//     ("IsNativeObjectAlive") check.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdint.h>
#import <unistd.h>
#import <math.h>

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

static inline void *MP(void *mi) { return mi ? *(void **)mi : nullptr; }

static void *methodOf(void *k, const char *n, int argc) {
    return k ? i_method_from_name(k, n, argc) : nullptr;
}
static size_t fieldOff(void *k, const char *n) {
    void *f = (k && n) ? i_field_from_name(k, n) : nullptr;
    return f ? i_field_offset(f) : 0;
}
// Plain managed field read. Safe: no native Unity object is touched.
static inline void *readPtr(void *obj, size_t off) {
    return (obj && off) ? *(void **)((char *)obj + off) : nullptr;
}

#pragma mark - Resolved Game Symbols

static void *K_lpm, *K_camera, *K_app, *K_obfFloat, *K_playerCam;

static void *M_lpmInstance;      // LocalPlayerManager::get_Instance()  -> LPM object
static void *M_fov;              // Camera::set_fieldOfView(float)
static void *M_fps;              // Application::set_targetFrameRate(int)
static void *M_obfCtor;          // ObscuredFloat::.ctor(float)
static void *M_obfDecrypt;       // ObscuredFloat::InternalDecrypt() -> float

static size_t off_cachedPtr;     // UnityEngine.Object::m_CachedPtr
static size_t off_lpmPlayer;     // LocalPlayerManager::mLocalPlayer
static size_t off_playerType;    // Player::LocalPlayerType
static size_t off_playerCam;     // Player::_PlayerCamera
static size_t off_camFp;         // PlayerCamera::m_FpCamera
static size_t off_recoilAngles;  // PlayerCamera::m_RecoilAngles
static size_t off_fwdSpeed;      // PlayerMovement::forwardSpeed  (ObscuredFloat)
static size_t off_moveComp;      // Player::_PlayerMovement

static void *g_lcam = nullptr;   // local PlayerCamera (alive only)
static void *g_lmove = nullptr;  // local PlayerMovement (alive only)

#pragma mark - Cheat State

static BOOL  g_norecoil = NO;
static float g_speed = 1.0f;
static float g_fov = 0.0f;
static BOOL  g_il2cppReady = NO;
static float g_baseSpeed = 0.f;  // pristine forwardSpeed, captured once
static BOOL  g_speedApplied = NO;

static inline BOOL alive(void *obj) {
    return obj && off_cachedPtr && *(void **)((char *)obj + off_cachedPtr) != nullptr;
}

#pragma mark - ObscuredFloat access (native ABI, no reflection)

// float ObscuredFloat::InternalDecrypt(ObscuredFloat* this, MethodInfo*)
static float obfRead(void *base, size_t off) {
    void *mp = MP(M_obfDecrypt);
    if (!base || !off || !mp) return 0.f;
    return ((float (*)(void *, void *))mp)((char *)base + off, M_obfDecrypt);
}
// void ObscuredFloat::.ctor(ObscuredFloat* this, float value, MethodInfo*)  x0, s0, x1
static void obfWrite(void *base, size_t off, float v) {
    void *mp = MP(M_obfCtor);
    if (!base || !off || !mp) return;
    ((void (*)(void *, float, void *))mp)((char *)base + off, v, M_obfCtor);
}

#pragma mark - Native UIKit UI

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
        CGPoint d = [pan translationInView:parent];
        CGPoint c = CGPointMake(self.center.x + (d.x - self.lastPoint.x),
                                self.center.y + (d.y - self.lastPoint.y));
        CGFloat hw = self.bounds.size.width / 2.0, hh = self.bounds.size.height / 2.0;
        c.x = fmax(hw + 5, fmin(parent.bounds.size.width - hw - 5, c.x));
        c.y = fmax(hh + 20, fmin(parent.bounds.size.height - hh - 20, c.y));
        self.center = c;
        self.lastPoint = d;
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
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UISlider *fovSlider;
@property (nonatomic, strong) UISwitch *recoilSwitch;
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

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, w - 60, 24)];
    title.text = @"MINI WORLD ROYALE";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [content addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 44, 8, 36, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, 42, w - 32, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [content addSubview:sep];

    CGFloat y = 52;

    // No recoil
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 4, w - 80, 24)];
    lbl.font = [UIFont boldSystemFontOfSize:14];
    lbl.textColor = [UIColor whiteColor];
    lbl.text = @"No Recoil & Cam Kick";
    [content addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 68, y, 51, 31)];
    sw.on = g_norecoil;
    [sw addTarget:self action:@selector(recoilChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:sw];
    self.recoilSwitch = sw;
    y += 38;

    // Speed
    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    spLbl.font = [UIFont boldSystemFontOfSize:13];
    spLbl.textColor = [UIColor whiteColor];
    spLbl.text = [NSString stringWithFormat:@"Speed Multiplier: %.2fx", g_speed];
    [content addSubview:spLbl];
    self.speedLabel = spLbl;
    y += 22;

    UISlider *spSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    spSlider.minimumValue = 1.0f;
    spSlider.maximumValue = 5.0f;
    spSlider.value = g_speed;
    [spSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:spSlider];
    self.speedSlider = spSlider;
    y += 32;

    // FOV
    UILabel *fvLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    fvLbl.font = [UIFont boldSystemFontOfSize:13];
    fvLbl.textColor = [UIColor whiteColor];
    fvLbl.text = g_fov > 0 ? [NSString stringWithFormat:@"Camera FOV: %d°", (int)g_fov]
                           : @"Camera FOV: Default";
    [content addSubview:fvLbl];
    self.fovLabel = fvLbl;
    y += 22;

    UISlider *fvSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    fvSlider.minimumValue = 60.0f;
    fvSlider.maximumValue = 120.0f;
    fvSlider.value = g_fov > 0 ? g_fov : 90.0f;
    [fvSlider addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:fvSlider];
    self.fovSlider = fvSlider;
    y += 34;

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

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    status.font = [UIFont systemFontOfSize:12];
    status.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    status.textAlignment = NSTextAlignmentCenter;
    status.text = @"Status: Waiting for game...";
    [content addSubview:status];
    self.statusLabel = status;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuPan:)];
    [self addGestureRecognizer:pan];
}

- (void)recoilChanged:(UISwitch *)sw { g_norecoil = sw.isOn; }

- (void)speedChanged:(UISlider *)sl {
    g_speed = sl.value;
    self.speedLabel.text = [NSString stringWithFormat:@"Speed Multiplier: %.2fx", g_speed];
}

- (void)fovChanged:(UISlider *)sl {
    g_fov = sl.value;
    self.fovLabel.text = [NSString stringWithFormat:@"Camera FOV: %d°", (int)g_fov];
}

- (void)unlockFpsTapped {
    void *mp = MP(M_fps);
    if (!mp) { self.statusLabel.text = @"FPS unlock unavailable"; return; }
    ((void (*)(int, void *))mp)(120, M_fps);
    self.statusLabel.text = @"FPS set to 120";
}

- (void)resetTapped {
    g_norecoil = NO;
    g_speed = 1.0f;
    g_fov = 0.0f;
    self.recoilSwitch.on = NO;
    self.speedSlider.value = 1.0f;
    self.speedLabel.text = @"Speed Multiplier: 1.00x";
    self.fovLabel.text = @"Camera FOV: Default";
}

- (void)closeTapped { self.hidden = YES; }

- (void)handleMenuPan:(UIPanGestureRecognizer *)pan {
    UIView *parent = self.superview;
    if (!parent) return;
    static CGPoint startCenter;
    if (pan.state == UIGestureRecognizerStateBegan) startCenter = self.center;
    else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint d = [pan translationInView:parent];
        self.center = CGPointMake(startCenter.x + d.x, startCenter.y + d.y);
    }
}
@end

#pragma mark - UI Manager

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
            if (!weakSelf.menuView.hidden)
                [weakSelf.menuView.superview bringSubviewToFront:weakSelf.menuView];
        };
        [window addSubview:self.floatingButton];
    }

    if (!self.menuView) {
        CGSize sz = window.bounds.size;
        CGFloat mw = 320, mh = 285;
        self.menuView = [MWMMenuView menuViewWithFrame:CGRectMake((sz.width - mw) / 2,
                                                                 (sz.height - mh) / 2, mw, mh)];
        self.menuView.hidden = YES;
        [window addSubview:self.menuView];
    }

    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)setStatus:(NSString *)text color:(UIColor *)color {
    if (!self.menuView || self.menuView.hidden) return;
    self.menuView.statusLabel.text = text;
    self.menuView.statusLabel.textColor = color;
}

- (void)onFrame {
    if (!g_il2cppReady) return;

    void *mp = MP(M_lpmInstance);
    if (!mp) return;

    // get_Instance (0x37B0A44) is a plain static getter that self-initialises the
    // class, so it is safe to call from any point of the loading sequence.
    void *lpm    = ((void *(*)(void *))mp)(M_lpmInstance);
    void *player = readPtr(lpm, off_lpmPlayer);

    if (!alive(player) || !off_playerType) {
        g_lcam = nullptr; g_lmove = nullptr;
        g_speedApplied = NO; g_baseSpeed = 0.f;
        [self setStatus:@"Status: Lobby / Loading" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    // ELocalPlayerType: None = 0, LobbyTP = 4 -> pure social scene, never touch gameplay.
    int type = *(int *)((char *)player + off_playerType);
    if (type == 0 || type == 4) {
        g_lcam = nullptr; g_lmove = nullptr;
        g_speedApplied = NO; g_baseSpeed = 0.f;
        [self setStatus:@"Status: In Lobby" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    void *cam  = readPtr(player, off_playerCam);
    void *move = readPtr(player, off_moveComp);
    g_lcam  = alive(cam)  ? cam  : nullptr;
    g_lmove = alive(move) ? move : nullptr;

    if (!g_lcam && !g_lmove) {
        [self setStatus:@"Status: Loading Match..." color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    [self setStatus:@"Status: In-Game (Active)"
              color:[UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0]];

    // --- No recoil: zero the camera's own recoil angle vector (managed write) ---
    if (g_norecoil && g_lcam && off_recoilAngles)
        *(Vec2 *)((char *)g_lcam + off_recoilAngles) = Vec2{0.f, 0.f};

    // --- Speed: rewrite PlayerMovement.forwardSpeed (ObscuredFloat) ---
    // Only writes when the stored value actually differs, so the ObscuredCheatingDetector
    // sees a consistent value instead of a per-frame rewrite.
    if (g_lmove && off_fwdSpeed) {
        float cur = obfRead(g_lmove, off_fwdSpeed);
        if (g_speed > 1.0f) {
            if (!g_speedApplied && cur > 0.f) { g_baseSpeed = cur; g_speedApplied = YES; }
            if (g_speedApplied && g_baseSpeed > 0.f) {
                float want = g_baseSpeed * g_speed;
                if (fabsf(cur - want) > 0.001f) obfWrite(g_lmove, off_fwdSpeed, want);
            }
        } else if (g_speedApplied && g_baseSpeed > 0.f) {
            if (fabsf(cur - g_baseSpeed) > 0.001f) obfWrite(g_lmove, off_fwdSpeed, g_baseSpeed);
            g_speedApplied = NO;
        }
    }

    // --- FOV: Camera::set_fieldOfView on the live first-person camera ---
    if (g_fov > 0.f && g_lcam && MP(M_fov)) {
        void *fp = readPtr(g_lcam, off_camFp);
        if (alive(fp)) ((void (*)(void *, float, void *))MP(M_fov))(fp, g_fov, M_fov);
    }
}
@end

#pragma mark - Resolution

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

static BOOL g_apiResolved = NO;

static BOOL resolveApi(void) {
    i_domain_get       = (void *(*)(void))dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    i_thread_attach    = (void *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_thread_attach");
    i_get_assemblies   = (void **(*)(void *, size_t *))dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    i_assembly_image   = (void *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    i_image_name       = (const char *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_image_get_name");
    i_class_from_name  = (void *(*)(void *, const char *, const char *))dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    i_method_from_name = (void *(*)(void *, const char *, int))dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    i_field_from_name  = (void *(*)(void *, const char *))dlsym(RTLD_DEFAULT, "il2cpp_class_get_field_from_name");
    i_field_offset     = (size_t (*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_field_get_offset");

    g_apiResolved = (i_domain_get && i_thread_attach && i_get_assemblies &&
                     i_assembly_image && i_image_name && i_class_from_name &&
                     i_method_from_name && i_field_from_name && i_field_offset);
    if (!g_apiResolved) NSLog(@"[MWM] il2cpp exports missing");
    return g_apiResolved;
}

static BOOL resolveIl2Cpp(void) {
    void *game = findImage("Assembly-CSharp.dll");
    void *core = findImage("UnityEngine.CoreModule.dll");
    if (!game || !core) return NO;

    void *K_player = i_class_from_name(game, "HQFPSTemplate", "Player");
    void *K_move   = i_class_from_name(game, "HQFPSTemplate", "PlayerMovement");
    K_playerCam    = i_class_from_name(game, "HQFPSTemplate", "PlayerCamera");
    K_lpm          = i_class_from_name(game, "", "LocalPlayerManager");
    K_camera       = i_class_from_name(core, "UnityEngine", "Camera");
    K_app          = i_class_from_name(core, "UnityEngine", "Application");
    K_obfFloat     = i_class_from_name(game, "CodeStage.AntiCheat.ObscuredTypes", "ObscuredFloat");
    void *K_object = i_class_from_name(core, "UnityEngine", "Object");

    M_lpmInstance = methodOf(K_lpm, "get_Instance", 0);
    M_fov         = methodOf(K_camera, "set_fieldOfView", 1);
    M_fps         = methodOf(K_app, "set_targetFrameRate", 1);
    M_obfCtor     = methodOf(K_obfFloat, ".ctor", 1);
    M_obfDecrypt  = methodOf(K_obfFloat, "InternalDecrypt", 0);

    off_cachedPtr    = fieldOff(K_object, "m_CachedPtr");
    off_lpmPlayer    = fieldOff(K_lpm, "mLocalPlayer");
    off_playerType   = fieldOff(K_player, "LocalPlayerType");
    off_playerCam    = fieldOff(K_player, "_PlayerCamera");
    off_moveComp     = fieldOff(K_player, "_PlayerMovement");
    off_camFp        = fieldOff(K_playerCam, "m_FpCamera");
    off_recoilAngles = fieldOff(K_playerCam, "m_RecoilAngles");
    off_fwdSpeed     = fieldOff(K_move, "forwardSpeed");

    if (!off_cachedPtr || !off_lpmPlayer || !off_playerType || !off_playerCam ||
        !off_camFp || !off_recoilAngles || !off_fwdSpeed || !MP(M_lpmInstance)) {
        return NO;
    }

    g_il2cppReady = YES;
    NSLog(@"[MWM] armed | cached=0x%zx lpm=0x%zx type=0x%zx cam=0x%zx move=0x%zx fp=0x%zx recoil=0x%zx fwd=0x%zx ctor=%p dec=%p",
          off_cachedPtr, off_lpmPlayer, off_playerType, off_playerCam,
          off_moveComp, off_camFp, off_recoilAngles, off_fwdSpeed,
          MP(M_obfCtor), MP(M_obfDecrypt));
    return YES;
}

static void tick(void) {
    [[MWMUIManager shared] setupUI];

    if (!g_apiResolved) resolveApi();
    if (g_il2cppReady || !g_apiResolved) return;

    void *domain = i_domain_get();
    if (!domain) return;
    i_thread_attach(domain);

    if (resolveIl2Cpp()) NSLog(@"[MWM] ready");
}

#pragma mark - Launch

static void pollUntilArmed(int attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool { tick(); }
        if (!g_il2cppReady && attempt < 180) pollUntilArmed(attempt + 1);
    });
}

static void onAppLaunched(CFNotificationCenterRef c, void *o, CFStringRef n,
                          const void *obj, CFDictionaryRef info) {
    pollUntilArmed(0);
}

__attribute__((constructor)) static void mwm_entry(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, &onAppLaunched,
                                    (__bridge CFStringRef)UIApplicationDidFinishLaunchingNotification,
                                    NULL, CFNotificationSuspensionBehaviorDrop);
}
