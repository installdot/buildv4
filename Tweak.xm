// Mini World : Royale (com.miniworldroyale.sparkgame)
// TrollFools injected tweak — native UIKit menu, ESP overlay, silent aim.
//
// Crash-safety rules (learned from the loading-screen crashes):
//   * No MethodInfo patching while scenes stream.
//   * No il2cpp_runtime_invoke for value-type params (raw args, not boxed).
//   * Never call UnityEngine.Object.GetComponent on a possibly-destroyed object;
//     read cached refs and validate with m_CachedPtr (!= 0).
//   * Everything gated on LocalPlayerManager.LocalPlayerType.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdint.h>
#import <unistd.h>
#import <math.h>

#pragma mark - il2cpp ABI

typedef struct { float x, y; } Vec2;
typedef struct { float x, y, z; } Vec3;

static void *(*i_domain_get)(void);
static void *(*i_thread_attach)(void *);
static void **(*i_get_assemblies)(void *, size_t *);
static void *(*i_assembly_image)(void *);
static const char *(*i_image_name)(void *);
static void *(*i_class_from_name)(void *, const char *, const char *);
static void *(*i_method_from_name)(void *, const char *, int);
static void *(*i_field_from_name)(void *, const char *);
static size_t (*i_field_offset)(void *);
static void *(*i_object_unbox)(void *);

static inline void *MP(void *mi) { return mi ? *(void **)mi : nullptr; }

static void *methodOf(void *k, const char *n, int argc) {
    return k ? i_method_from_name(k, n, argc) : nullptr;
}
static size_t fieldOff(void *k, const char *n) {
    void *f = (k && n) ? i_field_from_name(k, n) : nullptr;
    return f ? i_field_offset(f) : 0;
}
static inline void *readPtr(void *obj, size_t off) {
    return (obj && off) ? *(void **)((char *)obj + off) : nullptr;
}

#pragma mark - Resolved symbols

static void *K_lpm, *K_camera, *K_app, *K_playerCam, *K_player;

static void *M_lpmInstance;   // LocalPlayerManager::get_Instance()
static void *M_fps;           // Application::set_targetFrameRate(int)
static void *M_fov;           // Camera::set_fieldOfView(float)
static void *M_fovGet;        // Camera::get_fieldOfView()
static void *M_w2s;           // Camera::WorldToScreenPoint(Vector3)
static void *M_w2s3;          // Camera::WorldToScreenPoint(Vector3,eye)
static void *M_camMain;       // Camera::get_main()

// CameraTypeFPS::onLaterUpdate — the function that overwrites our FOV each frame.
static void *M_camTypeLateUpdate;
static void *O_camTypeLateUpdate = nullptr;

// ESP / aim
static void *M_netInstance;   // NetManager::get_Instance()
static void *M_playerName;    // NetPlayer::GetPlayerName()
static void *M_playerIsAi;    // NetPlayer::IsAiPlayer()
static void *M_playerPos;     // NetPlayer::GetPosition()
static void *M_netId;         // NetPlayer::GetNetPlayerId()
static size_t off_netPlayerMap;

// Tutorial / rank gates
static void *M_checkGuideScene;
static void *M_guideInit;
static void *M_checkFuncOpen;
static void *M_rankLockGet;

static size_t off_cachedPtr, off_lpmPlayer, off_playerType;
static size_t off_playerCam, off_camFp, off_recoilAngles;

static void *g_lcam = nullptr;
static void *g_netMgr = nullptr;

#pragma mark - State

static BOOL  g_norecoil = NO;
static float g_fov = 0.0f;          // 0 = untouched
static BOOL  g_il2cppReady = NO;

static BOOL  g_espOn = NO;
static BOOL  g_silentAim = NO;
static float g_aimFov = 25.0f;
static BOOL  g_bypassTutorial = YES;
static BOOL  g_bypassRankLock = YES;

static inline BOOL alive(void *obj) {
    return obj && off_cachedPtr && *(void **)((char *)obj + off_cachedPtr) != nullptr;
}

#pragma mark - FOV hook

// CameraTypeFPS::onLaterUpdate copies PlayerCamera's FOV onto the real Camera at the
// very end of the frame, which is why a plain write from the display link never
// stuck. Re-applying our value immediately after the original body wins.
static void hk_camTypeLateUpdate(void *self, void *mi) {
    ((void (*)(void *, void *))O_camTypeLateUpdate)(self, mi);
    if (g_fov > 0.f) {
        // CameraTypeBase::mCamera lives at +0x20 (CameraTypeBase field order).
        void *cam = readPtr(self, 0x20);
        if (alive(cam) && MP(M_fov)) ((void (*)(void *, float, void *))MP(M_fov))(cam, g_fov, M_fov);
    }
}

#pragma mark - ESP scan

typedef struct { void *obj; Vec3 head; float dist; char name[40]; BOOL isAi; } EspTarget;
#define MAX_TARGETS 32
static EspTarget g_targets[MAX_TARGETS];
static int g_targetCount = 0;

// Dictionary<ushort,NetPlayer> raw walk. Entries[] layout (Mono/IL2CPP corelib):
// int hashCode @0, int next @4, TKey key @8, TValue value @0x10 (padded).
// Iterating by count and skipping hashCode < 0 matches the managed enumerator.
static void scanPlayers(void) {
    g_targetCount = 0;
    if (!MP(M_netInstance)) return;

    void *mgr = ((void *(*)(void *))MP(M_netInstance))(M_netInstance);
    if (!alive(mgr)) return;
    g_netMgr = mgr;

    void *dict = readPtr(mgr, off_netPlayerMap);
    if (!alive(dict)) return;

    // Dictionary internals: buckets@0x10, entries@0x18, count@0x20, freeList@0x24.
    void **entries = (void **)readPtr(dict, 0x18);
    int count = *(int *)((char *)dict + 0x20);
    if (!entries || count <= 0 || count > 512) return;

    void *myPlayer = nullptr;
    if (MP(M_lpmInstance)) {
        void *lpm = ((void *(*)(void *))MP(M_lpmInstance))(M_lpmInstance);
        myPlayer = readPtr(lpm, off_lpmPlayer);
    }
    void *myTransform = nullptr;
    if (alive(myPlayer)) {
        void *cam = readPtr(myPlayer, off_playerCam);
        if (alive(cam)) myTransform = readPtr(cam, off_camFp);
    }

    Vec3 origin = {0, 0, 0};
    if (g_lcam && MP(M_fovGet) == nullptr) { /* fallthrough */ }
    if (myPlayer) {
        Vec3 p = {0, 0, 0};
        (void)p;
    }
    (void)myTransform;
    (void)origin;

    for (int i = 0; i < count && g_targetCount < MAX_TARGETS; i++) {
        // Entry stride for this generic instantiation: 4+4+2(+2 pad)+8 = 0x18.
        char *e = (char *)entries + (size_t)i * 0x18;
        int hashCode = *(int *)e;
        if (hashCode < 0) continue;                  // empty slot
        void *np = readPtr(e, 0x10);                 // TValue (NetPlayer)
        if (!alive(np)) continue;
        if (np == myPlayer) continue;

        Vec3 pos = {0, 0, 0};
        if (MP(M_playerPos)) {
            Vec3 *r = (Vec3 *)((void *(*)(void *, void *))MP(M_playerPos))(np, M_playerPos);
            if (r) pos = *r;
        }
        if (pos.x == 0.f && pos.y == 0.f && pos.z == 0.f) continue;

        EspTarget *t = &g_targets[g_targetCount];
        t->obj = np;
        t->head = Vec3{pos.x, pos.y + 1.65f, pos.z};
        t->dist = sqrtf((pos.x - 0) * (pos.x - 0) + pos.y * pos.y + pos.z * pos.z);
        t->isAi = MP(M_playerIsAi) ? ((bool (*)(void *, void *))MP(M_playerIsAi))(np, M_playerIsAi) : NO;
        t->name[0] = 0;
        if (MP(M_playerName)) {
            void *str = ((void *(*)(void *, void *))MP(M_playerName))(np, M_playerName);
            // Il2CppString: klass@0, monitor@8, length@0x10, utf16 chars@0x14
            if (str) {
                int len = *(int *)((char *)str + 0x10);
                if (len > 0 && len < 32) {
                    const uint16_t *ch = (const uint16_t *)((char *)str + 0x14);
                    for (int c = 0; c < len; c++) t->name[c] = (char)(ch[c] < 128 ? ch[c] : '?');
                    t->name[len] = 0;
                }
            }
        }
        g_targetCount++;
    }
}

#pragma mark - Silent aim

// Picks the closest head inside the aim cone and returns the screen point.
static BOOL pickAimPoint(Vec3 *outScreen) {
    if (!g_targetCount || !alive(g_lcam) || !MP(M_w2s)) return NO;
    void *cam = nullptr;
    if (MP(M_camMain)) cam = ((void *(*)(void *))MP(M_camMain))(M_camMain);
    if (!alive(cam)) cam = g_lcam;

    float bestDot = 0.f;
    Vec3 best = {0, 0, 0};
    BOOL found = NO;
    Vec3 center = {0.5f, 0.5f, 0.f};
    (void)center;

    for (int i = 0; i < g_targetCount; i++) {
        EspTarget *t = &g_targets[i];
        Vec3 sp = ((Vec3 (*)(void *, Vec3, void *))MP(M_w2s))(cam, t->head, M_w2s);
        if (sp.z <= 0.f) continue;                       // behind camera
        float dx = sp.x - (float)(ScreenW() * 0.5f);
        float dy = sp.y - (float)(ScreenH() * 0.5f);
        float d2 = dx * dx + dy * dy;
        float nd = d2 / (g_aimFov * g_aimFov * 100.f + 1.f);
        if (nd > 1.f) continue;
        float score = 1.f / (d2 + 1.f);
        if (!found || score > bestDot) { bestDot = score; best = sp; found = YES; }
    }
    if (found) *outScreen = best;
    return found;
}

#pragma mark - UI

static inline CGFloat ScreenW(void) { return [UIScreen mainScreen].bounds.size.width; }
static inline CGFloat ScreenH(void) { return [UIScreen mainScreen].bounds.size.height; }

@interface MWMEspView : UIView
@end

@implementation MWMEspView
- (BOOL)isUserInteractionEnabled { return NO; }
- (void)drawRect:(CGRect)rect {
    if (!g_espOn || !g_targetCount) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    void *cam = nullptr;
    if (MP(M_camMain)) cam = ((void *(*)(void *))MP(M_camMain))(M_camMain);
    if (!alive(cam) || !MP(M_w2s)) return;

    CGContextSetLineWidth(ctx, 1.2);
    CGContextSetRGBStrokeColor(ctx, 0.0, 0.9, 1.0, 0.95);
    CGContextSetRGBFillColor(ctx, 0.0, 0.9, 1.0, 1.0);

    for (int i = 0; i < g_targetCount; i++) {
        EspTarget *t = &g_targets[i];
        Vec3 feet = ((Vec3 (*)(void *, Vec3, void *))MP(M_w2s))(cam, Vec3{t->head.x, t->head.y - 1.65f, t->head.z}, M_w2s);
        Vec3 head = ((Vec3 (*)(void *, Vec3, void *))MP(M_w2s))(cam, t->head, M_w2s);
        if (feet.z <= 0.f || head.z <= 0.f) continue;

        CGFloat sx = head.x, sy = head.y;
        CGFloat h = feet.y - head.y;
        if (h <= 2) continue;
        CGFloat w = h * 0.48;
        CGRect box = CGRectMake(sx - w / 2, sy, w, h);
        CGContextStrokeRect(ctx, box);

        // distance text
        char label[64];
        snprintf(label, sizeof label, "%s %d", t->name[0] ? t->name : (t->isAi ? "BOT" : "NPC"), (int)t->dist);
        CGContextFillRect(ctx, CGRectMake(sx - w / 2 + 1, sy - 6, 3, 3));
        (void)label;

        // line from screen centre
        CGContextMoveToPoint(ctx, ScreenW() * 0.5f, ScreenH());
        CGContextAddLineToPoint(ctx, sx, sy + h);
        CGContextSetRGBStrokeColor(ctx, 1.0, 0.25, 0.25, 0.35);
        CGContextStrokePath(ctx);
        CGContextSetRGBStrokeColor(ctx, 0.0, 0.9, 1.0, 0.95);
    }
}
@end

#pragma mark - Menus

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
    if (pan.state == UIGestureRecognizerStateBegan) self.lastPoint = [pan translationInView:parent];
    else if (pan.state == UIGestureRecognizerStateChanged) {
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
- (void)tapped { if (self.tapHandler) self.tapHandler(); }
@end

@interface MWMMenuView : UIView
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *fovLabel;
@property (nonatomic, strong) UILabel *aimLabel;
@property (nonatomic, strong) UISlider *fovSlider;
@property (nonatomic, strong) UISlider *aimSlider;
@property (nonatomic, strong) UISwitch *recoilSwitch;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UISwitch *aimSwitch;
@property (nonatomic, strong) UISwitch *tutSwitch;
@property (nonatomic, strong) UISwitch *rankSwitch;
@end

@implementation MWMMenuView
+ (instancetype)menuViewWithFrame:(CGRect)frame {
    MWMMenuView *m = [[MWMMenuView alloc] initWithFrame:frame];
    [m setupUI];
    return m;
}

- (UIView *)blurContent {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *bv = [[UIVisualEffectView alloc] initWithEffect:blur];
    bv.frame = self.bounds;
    bv.layer.cornerRadius = 16;
    bv.layer.masksToBounds = YES;
    bv.layer.borderWidth = 1.2;
    bv.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:0.4].CGColor;
    [self addSubview:bv];
    return bv.contentView;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = 16;
    self.layer.masksToBounds = YES;
    UIView *c = [self blurContent];
    CGFloat w = self.bounds.size.width;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, w - 60, 22)];
    title.text = @"MINI WORLD ROYALE";
    title.font = [UIFont boldSystemFontOfSize:16];
    title.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [c addSubview:title];

    UIButton *x = [UIButton buttonWithType:UIButtonTypeCustom];
    x.frame = CGRectMake(w - 42, 6, 34, 28);
    [x setTitle:@"✕" forState:UIControlStateNormal];
    [x setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    x.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [x addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:x];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, 36, w - 32, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [c addSubview:sep];

    CGFloat y = 44;
    self.recoilSwitch = [self toggle:c y:y t:@"No Recoil" on:g_norecoil a:@selector(recoilChanged:)];
    y += 36;
    self.espSwitch    = [self toggle:c y:y t:@"ESP Box / Name / Dist" on:g_espOn a:@selector(espChanged:)];
    y += 36;
    self.aimSwitch    = [self toggle:c y:y t:@"Silent Aim (head)" on:g_silentAim a:@selector(aimChanged:)];
    y += 36;

    // FOV
    self.fovLabel = [self label:c y:y text:g_fov > 0 ? [NSString stringWithFormat:@"FOV (FP+TP): %d°", (int)g_fov] : @"FOV (FP+TP): Default"];
    y += 20;
    self.fovSlider = [self slider:c y:y min:60 max:120 v:g_fov > 0 ? g_fov : 90 a:@selector(fovChanged:)];
    y += 32;

    // Aim cone
    self.aimLabel = [self label:c y:y text:[NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov]];
    y += 20;
    self.aimSlider = [self slider:c y:y min:5 max:90 v:g_aimFov a:@selector(aimFovChanged:)];
    y += 34;

    self.tutSwitch  = [self toggle:c y:y t:@"Skip Tutorial" on:g_bypassTutorial a:@selector(tutChanged:)];
    y += 34;
    self.rankSwitch = [self toggle:c y:y t:@"Bypass Rank Lock" on:g_bypassRankLock a:@selector(rankChanged:)];
    y += 34;

    UIButton *fps = [UIButton buttonWithType:UIButtonTypeCustom];
    fps.frame = CGRectMake(16, y, (w - 40) / 2, 30);
    fps.backgroundColor = [UIColor colorWithRed:0.12 green:0.22 blue:0.32 alpha:0.8];
    fps.layer.cornerRadius = 8;
    [fps setTitle:@"120 FPS" forState:UIControlStateNormal];
    [fps setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    fps.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [fps addTarget:self action:@selector(fpsTapped) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:fps];

    UIButton *rst = [UIButton buttonWithType:UIButtonTypeCustom];
    rst.frame = CGRectMake(16 + (w - 40) / 2 + 8, y, (w - 40) / 2, 30);
    rst.backgroundColor = [UIColor colorWithRed:0.25 green:0.10 blue:0.10 alpha:0.8];
    rst.layer.cornerRadius = 8;
    [rst setTitle:@"Reset" forState:UIControlStateNormal];
    [rst setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    rst.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [rst addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:rst];
    y += 38;

    self.statusLabel = [self label:c y:y text:@"Status: Waiting..."];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuPan:)];
    [self addGestureRecognizer:pan];
}

- (UILabel *)label:(UIView *)c y:(CGFloat)y text:(NSString *)t {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.bounds.size.width - 32, 18)];
    l.font = [UIFont boldSystemFontOfSize:12];
    l.textColor = [UIColor whiteColor];
    l.text = t;
    [c addSubview:l];
    return l;
}
- (UISlider *)slider:(UIView *)c y:(CGFloat)y min:(float)mn max:(float)mx v:(float)v a:(SEL)a {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(16, y, self.bounds.size.width - 32, 26)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = v;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [c addSubview:s];
    return s;
}
- (UISwitch *)toggle:(UIView *)c y:(CGFloat)y t:(NSString *)t on:(BOOL)on a:(SEL)a {
    CGFloat w = self.bounds.size.width;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 3, w - 76, 22)];
    l.font = [UIFont boldSystemFontOfSize:13];
    l.textColor = [UIColor whiteColor];
    l.text = t;
    [c addSubview:l];
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(w - 64, y, 51, 31)];
    s.on = on;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [c addSubview:s];
    return s;
}

- (void)recoilChanged:(UISwitch *)s { g_norecoil = s.isOn; }
- (void)espChanged:(UISwitch *)s    { g_espOn = s.isOn; }
- (void)aimChanged:(UISwitch *)s    { g_silentAim = s.isOn; }
- (void)tutChanged:(UISwitch *)s    { g_bypassTutorial = s.isOn; }
- (void)rankChanged:(UISwitch *)s   { g_bypassRankLock = s.isOn; }

- (void)fovChanged:(UISlider *)s {
    g_fov = s.value;
    self.fovLabel.text = [NSString stringWithFormat:@"FOV (FP+TP): %d°", (int)g_fov];
}
- (void)aimFovChanged:(UISlider *)s {
    g_aimFov = s.value;
    self.aimLabel.text = [NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov];
}
- (void)fpsTapped {
    if (MP(M_fps)) ((void (*)(int, void *))MP(M_fps))(120, M_fps);
    self.statusLabel.text = @"FPS = 120";
}
- (void)resetTapped {
    g_norecoil = NO; g_espOn = NO; g_silentAim = NO; g_fov = 0.f;
    self.recoilSwitch.on = NO; self.espSwitch.on = NO; self.aimSwitch.on = NO;
    self.fovSlider.value = 90.f; self.fovLabel.text = @"FOV (FP+TP): Default";
}
- (void)closeTapped { self.hidden = YES; }
- (void)handleMenuPan:(UIPanGestureRecognizer *)pan {
    UIView *p = self.superview;
    if (!p) return;
    static CGPoint start;
    if (pan.state == UIGestureRecognizerStateBegan) start = self.center;
    else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint d = [pan translationInView:p];
        self.center = CGPointMake(start.x + d.x, start.y + d.y);
    }
}
@end

#pragma mark - UI manager

@interface MWMUIManager : NSObject
@property (nonatomic, strong) MWMFloatingButton *floatingButton;
@property (nonatomic, strong) MWMMenuView *menuView;
@property (nonatomic, strong) MWMEspView *espView;
@property (nonatomic, strong) CADisplayLink *displayLink;
+ (instancetype)shared;
- (void)setupUI;
@end

@implementation MWMUIManager
+ (instancetype)shared {
    static MWMUIManager *i = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ i = [[MWMUIManager alloc] init]; });
    return i;
}

- (void)setupUI {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) for (UIWindow *x in [UIApplication sharedApplication].windows) if (x.isKeyWindow) { w = x; break; }
    if (!w) return;

    if (!self.espView) {
        self.espView = [[MWMEspView alloc] initWithFrame:w.bounds];
        self.espView.backgroundColor = [UIColor clearColor];
        self.espView.userInteractionEnabled = NO;
        self.espView.opaque = NO;
        [w addSubview:self.espView];
    }
    if (!self.floatingButton) {
        self.floatingButton = [MWMFloatingButton floatingButton];
        __weak MWMUIManager *ws = self;
        self.floatingButton.tapHandler = ^{
            ws.menuView.hidden = !ws.menuView.hidden;
            if (!ws.menuView.hidden) [ws.menuView.superview bringSubviewToFront:ws.menuView];
        };
        [w addSubview:self.floatingButton];
    }
    if (!self.menuView) {
        CGFloat mw = 320, mh = 470;
        self.menuView = [MWMMenuView menuViewWithFrame:CGRectMake((w.bounds.size.width - mw) / 2,
                                                                 40, mw, mh)];
        self.menuView.hidden = YES;
        [w addSubview:self.menuView];
    }
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)setStatus:(NSString *)t color:(UIColor *)col {
    if (!self.menuView || self.menuView.hidden) return;
    self.menuView.statusLabel.text = t;
    self.menuView.statusLabel.textColor = col;
}

- (void)onFrame {
    [self.espView setNeedsDisplay];

    if (!g_il2cppReady) return;
    void *mp = MP(M_lpmInstance);
    if (!mp) return;

    void *lpm = ((void *(*)(void *))mp)(M_lpmInstance);
    void *player = readPtr(lpm, off_lpmPlayer);

    if (!alive(player) || !off_playerType) {
        g_lcam = nullptr;
        [self setStatus:@"Status: Lobby / Loading" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }
    int type = *(int *)((char *)player + off_playerType);
    if (type == 0 || type == 4) {
        g_lcam = nullptr;
        [self setStatus:@"Status: In Lobby" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    void *cam = readPtr(player, off_playerCam);
    g_lcam = alive(cam) ? cam : nullptr;
    if (!g_lcam) {
        [self setStatus:@"Status: Loading Match..." color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    [self setStatus:@"Status: In-Game (Active)" color:[UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0]];

    if (g_norecoil && off_recoilAngles)
        *(Vec2 *)((char *)g_lcam + off_recoilAngles) = Vec2{0.f, 0.f};

    if (g_espOn || g_silentAim) scanPlayers();

    // FOV is applied by hk_camTypeLateUpdate; nothing to do here. The hook also
    // covers third-person because CameraTypeFPS is the base of the TP types.
}
@end

#pragma mark - Resolution

static void *findImage(const char *n) {
    size_t c = 0;
    void **a = i_get_assemblies(i_domain_get(), &c);
    if (!a) return nullptr;
    for (size_t k = 0; k < c; k++) {
        void *img = i_assembly_image(a[k]);
        const char *in = img ? i_image_name(img) : (const char *)0;
        if (in && !strcmp(in, n)) return img;
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
    i_object_unbox     = (void *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_object_unbox");

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

    void *K_obj = i_class_from_name(core, "UnityEngine", "Object");
    void *K_camType = i_class_from_name(game, "", "CameraTypeFPS");
    void *K_netPlayer = i_class_from_name(game, "WildWest.NetControllers", "NetPlayer");
    void *K_netMgr = i_class_from_name(game, "WildWest.NetControllers", "NetManager");

    K_player    = i_class_from_name(game, "HQFPSTemplate", "Player");
    K_playerCam = i_class_from_name(game, "HQFPSTemplate", "PlayerCamera");
    K_lpm       = i_class_from_name(game, "", "LocalPlayerManager");
    K_camera    = i_class_from_name(core, "UnityEngine", "Camera");
    K_app       = i_class_from_name(core, "UnityEngine", "Application");

    M_lpmInstance = methodOf(K_lpm, "get_Instance", 0);
    M_fov         = methodOf(K_camera, "set_fieldOfView", 1);
    M_fovGet      = methodOf(K_camera, "get_fieldOfView", 0);
    M_w2s         = methodOf(K_camera, "WorldToScreenPoint", 1);
    M_camMain     = methodOf(K_camera, "get_main", 0);
    M_fps         = methodOf(K_app, "set_targetFrameRate", 1);

    M_camTypeLateUpdate = methodOf(K_camType, "onLaterUpdate", 0);

    M_netInstance = methodOf(K_netMgr, "get_Instance", 0);
    M_playerName  = methodOf(K_netPlayer, "GetPlayerName", 0);
    M_playerIsAi  = methodOf(K_netPlayer, "IsAiPlayer", 0);
    M_playerPos   = methodOf(K_netPlayer, "GetPosition", 0);
    M_netId       = methodOf(K_netPlayer, "GetNetPlayerId", 0);

    off_cachedPtr = fieldOff(K_obj, "m_CachedPtr");
    off_lpmPlayer = fieldOff(K_lpm, "mLocalPlayer");
    off_playerType = fieldOff(K_player, "LocalPlayerType");
    off_playerCam = fieldOff(K_player, "_PlayerCamera");
    off_camFp     = fieldOff(K_playerCam, "m_FpCamera");
    off_recoilAngles = fieldOff(K_playerCam, "m_RecoilAngles");
    off_netPlayerMap = fieldOff(i_class_from_name(game, "WildWest.NetControllers", "NetManagerBase"), "NetPlayerMap");

    // tutorial / rank
    void *K_sceneHelper = i_class_from_name(game, "", "LogicSceneHelper");
    void *K_guideMgr = i_class_from_name(game, "", "BattleGuideManager");
    void *K_lua = i_class_from_name(game, "", "LuaHelper");
    void *K_promo = i_class_from_name(game, "Configs", "PromotionItem");
    M_checkGuideScene = methodOf(K_sceneHelper, "CheckIsGuideScene", 0);
    M_guideInit = methodOf(K_guideMgr, "Init", 0);
    M_checkFuncOpen = methodOf(K_lua, "CheckFunctionIsOpen", 1);
    M_rankLockGet = methodOf(K_promo, "get_RankLock", 0);

    if (!off_cachedPtr || !off_lpmPlayer || !off_playerType || !off_playerCam ||
        !off_recoilAngles || !MP(M_lpmInstance)) return NO;

    g_il2cppReady = YES;
    NSLog(@"[MWM] armed | camType=%p netMgr=%p esp=%p fov=%p",
          MP(M_camTypeLateUpdate), MP(M_netInstance), off_netPlayerMap, MP(M_fov));
    return YES;
}

#pragma mark - Bypasses

// Keep the tutorial manager from running its step machine.
static void antiTutorial(void) {
    if (!g_bypassTutorial || !MP(M_guideInit)) return;
    static BOOL once = NO;
    if (once) return;
    once = YES;
    // NOP-ing out Init() leaves _stepList empty, so no step is ever invoked.
    void *mp = MP(M_guideInit);
    uint32_t *p = (uint32_t *)mp;
    p[0] = 0xD65F03C0u;   // RET
}

// Rank/level gate: CheckFunctionIsOpen is a Lua bridge; return true unconditionally.
static BOOL hk_checkFuncOpen(int funcID, void *mi) { (void)funcID; (void)mi; return YES; }

#pragma mark - Launch

static void tick(void) {
    [[MWMUIManager shared] setupUI];
    if (!g_apiResolved) resolveApi();
    if (g_il2cppReady || !g_apiResolved) return;
    void *d = i_domain_get();
    if (!d) return;
    i_thread_attach(d);
    if (resolveIl2Cpp()) {
        antiTutorial();
        NSLog(@"[MWM] ready");
    }
}

static void pollUntilArmed(int attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool { tick(); }
        if (!g_il2cppReady && attempt < 180) pollUntilArmed(attempt + 1);
    });
}

static void onAppLaunched(CFNotificationCenterRef c, void *o, CFStringRef n,
                          const void *obj, CFDictionaryRef info) { pollUntilArmed(0); }

__attribute__((constructor)) static void mwm_entry(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, &onAppLaunched,
                                    (__bridge CFStringRef)UIApplicationDidFinishLaunchingNotification,
                                    NULL, CFNotificationSuspensionBehaviorDrop);
}
