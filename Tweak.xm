// Mini World : Royale (com.miniworldroyale.sparkgame)
// TrollFools injected tweak — native UIKit menu, ESP overlay, silent aim.
//
// Features:
//   * No Recoil
//   * FOV Slider (FPP & TPP support)
//   * ESP: 2D Box + Snapline + Name + Distance + Bot/Player indicator
//   * Silent Aim: Redirects bullet trajectory to enemy head inside FOV
//   * Bypass Tutorial (blocks guide scene & battle guide manager init)
//   * Bypass Rank Lock by level (forces CheckFunctionIsOpen & CheckFuncUnlock to true)

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdint.h>
#import <unistd.h>
#import <math.h>

#pragma mark - Geometry & Screen Helpers

typedef struct { float x, y; } Vec2;
typedef struct { float x, y, z; } Vec3;

static inline CGFloat ScreenW(void) { return [UIScreen mainScreen].bounds.size.width; }
static inline CGFloat ScreenH(void) { return [UIScreen mainScreen].bounds.size.height; }

#pragma mark - il2cpp ABI

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
static inline void *readPtr(void *obj, size_t off) {
    return (obj && off) ? *(void **)((char *)obj + off) : nullptr;
}

#pragma mark - Resolved Symbols

static void *K_lpm, *K_camera, *K_playerCam, *K_player;
static void *K_weaponProc;

static void *M_lpmInstance;       // LocalPlayerManager::get_Instance()
static void *M_fov;               // Camera::set_fieldOfView(float)
static void *M_w2s;               // Camera::WorldToScreenPoint(Vector3)
static void *M_camMain;           // Camera::get_main()
static void *M_setFpCameraFov;    // PlayerCamera::SetFPCameraFieldOfView(float, float)

// ESP / Aim symbols
static void *M_netInstance;       // NetManager::get_Instance()
static void *M_playerName;        // NetPlayer::GetPlayerName()
static void *M_playerIsAi;        // NetPlayer::IsAiPlayer()
static void *M_playerPos;         // NetPlayer::GetPosition()
static size_t off_netPlayerMap;

// Weapon silent aim symbol
static void *M_fireDir;           // WeaponProcessBase::computerFireDirection(ref ModelShotData)
static void *O_computerFireDirection = nullptr;

// Bypass symbols
static void *M_guideInit;         // BattleGuideManager::Init()
static void *M_checkGuideScene;   // LogicSceneHelper::CheckIsGuideScene()
static void *M_isNewbieGame;      // LogicSceneHelper::IsNewbieGame()
static void *M_checkFuncOpen;     // LuaHelper::CheckFunctionIsOpen(int)
static void *M_checkFuncUnlock;   // LuaHelper::CheckFuncUnlock(int, Action)

static size_t off_cachedPtr, off_lpmPlayer, off_playerType;
static size_t off_playerCam, off_recoilAngles;

static void *g_lcam = nullptr;

#pragma mark - State

static BOOL  g_norecoil = NO;
static float g_fov = 0.0f;          // 0 = Default
static BOOL  g_il2cppReady = NO;

static BOOL  g_espOn = NO;
static BOOL  g_silentAim = NO;
static float g_aimFov = 35.0f;
static BOOL  g_bypassTutorial = YES;
static BOOL  g_bypassRankLock = YES;

static inline BOOL alive(void *obj) {
    return obj && off_cachedPtr && *(void **)((char *)obj + off_cachedPtr) != nullptr;
}

#pragma mark - WorldToScreen

static BOOL worldToScreen(void *cam, Vec3 world, CGPoint *outPt) {
    if (!cam || !outPt || !MP(M_w2s)) return NO;
    Vec3 p = ((Vec3 (*)(void *, Vec3, void *))MP(M_w2s))(cam, world, M_w2s);
    if (p.z <= 0.0f) return NO; // Behind camera
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale <= 0.0f) scale = 1.0f;
    outPt->x = (CGFloat)p.x / scale;
    outPt->y = ScreenH() - ((CGFloat)p.y / scale);
    return YES;
}

#pragma mark - ESP Target Scan

typedef struct {
    void *obj;
    Vec3 head;
    float dist;
    char name[32];
    BOOL isAi;
} EspTarget;

#define MAX_TARGETS 32
static EspTarget g_targets[MAX_TARGETS];
static int g_targetCount = 0;

static void scanPlayers(void) {
    g_targetCount = 0;
    if (!MP(M_netInstance) || !off_netPlayerMap) return;

    void *mgr = ((void *(*)(void *))MP(M_netInstance))(M_netInstance);
    if (!alive(mgr)) return;

    void *dict = readPtr(mgr, off_netPlayerMap);
    if (!dict) return;

    // Dictionary internals: buckets@0x10, entries@0x18, count@0x20
    void **entries = (void **)readPtr(dict, 0x18);
    int count = *(int *)((char *)dict + 0x20);
    if (!entries || count <= 0 || count > 512) return;

    void *myPlayer = nullptr;
    if (MP(M_lpmInstance)) {
        void *lpm = ((void *(*)(void *))MP(M_lpmInstance))(M_lpmInstance);
        if (lpm && off_lpmPlayer) myPlayer = readPtr(lpm, off_lpmPlayer);
    }

    Vec3 myPos = {0.0f, 0.0f, 0.0f};
    if (alive(g_lcam) && MP(M_playerPos) && myPlayer) {
        myPos = ((Vec3 (*)(void *, void *))MP(M_playerPos))(myPlayer, M_playerPos);
    }

    for (int i = 0; i < count && g_targetCount < MAX_TARGETS; i++) {
        char *e = (char *)entries + (size_t)i * 0x18;
        int hashCode = *(int *)e;
        if (hashCode < 0) continue; // Empty slot
        void *np = readPtr(e, 0x10);
        if (!np || np == myPlayer) continue;

        Vec3 pos = {0.0f, 0.0f, 0.0f};
        if (MP(M_playerPos)) {
            pos = ((Vec3 (*)(void *, void *))MP(M_playerPos))(np, M_playerPos);
        }
        if (pos.x == 0.0f && pos.y == 0.0f && pos.z == 0.0f) continue;

        float dx = pos.x - myPos.x;
        float dy = pos.y - myPos.y;
        float dz = pos.z - myPos.z;
        float dist = sqrtf(dx * dx + dy * dy + dz * dz);

        EspTarget *t = &g_targets[g_targetCount];
        t->obj = np;
        t->head = (Vec3){ pos.x, pos.y + 1.65f, pos.z };
        t->dist = dist;
        t->isAi = MP(M_playerIsAi) ? ((bool (*)(void *, void *))MP(M_playerIsAi))(np, M_playerIsAi) : NO;
        t->name[0] = '\0';

        if (MP(M_playerName)) {
            void *str = ((void *(*)(void *, void *))MP(M_playerName))(np, M_playerName);
            if (str) {
                int len = *(int *)((char *)str + 0x10);
                if (len > 0 && len < 31) {
                    const uint16_t *ch = (const uint16_t *)((char *)str + 0x14);
                    for (int c = 0; c < len; c++) t->name[c] = (char)(ch[c] < 128 ? ch[c] : '?');
                    t->name[len] = '\0';
                }
            }
        }
        g_targetCount++;
    }
}

#pragma mark - Silent Aim Target Selection

static BOOL pickBestTargetHead(Vec3 *outHead) {
    if (!g_targetCount || !outHead) return NO;
    void *cam = MP(M_camMain) ? ((void *(*)(void *))MP(M_camMain))(M_camMain) : nullptr;
    if (!alive(cam)) cam = g_lcam;
    if (!cam) return NO;

    CGFloat cx = ScreenW() * 0.5f;
    CGFloat cy = ScreenH() * 0.5f;
    CGFloat maxRadius = (g_aimFov / 90.0f) * cx;
    float bestDist = 1e9f;
    BOOL found = NO;

    for (int i = 0; i < g_targetCount; i++) {
        EspTarget *t = &g_targets[i];
        CGPoint sp;
        if (!worldToScreen(cam, t->head, &sp)) continue;
        float dx = (float)(sp.x - cx);
        float dy = (float)(sp.y - cy);
        float d = sqrtf(dx * dx + dy * dy);
        if (d <= (float)maxRadius && d < bestDist) {
            bestDist = d;
            *outHead = t->head;
            found = YES;
        }
    }
    return found;
}

static Vec3 hk_computerFireDirection(void *self, void *shootData, void *method) {
    if (g_silentAim && shootData && g_targetCount > 0) {
        Vec3 targetHead;
        if (pickBestTargetHead(&targetHead)) {
            // ModelShotData: shootPos @0x48, shootDir @0x54
            Vec3 shootPos = *(Vec3 *)((char *)shootData + 0x48);
            Vec3 dir = { targetHead.x - shootPos.x, targetHead.y - shootPos.y, targetHead.z - shootPos.z };
            float len = sqrtf(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
            if (len > 0.0001f) {
                dir.x /= len;
                dir.y /= len;
                dir.z /= len;
                *(Vec3 *)((char *)shootData + 0x54) = dir;
                return dir;
            }
        }
    }
    if (O_computerFireDirection) {
        return ((Vec3 (*)(void *, void *, void *))O_computerFireDirection)(self, shootData, method);
    }
    return shootData ? *(Vec3 *)((char *)shootData + 0x54) : (Vec3){0.0f, 0.0f, 1.0f};
}

#pragma mark - ESP Overlay View

@interface MWMEspView : UIView
@end

@implementation MWMEspView
- (BOOL)isUserInteractionEnabled { return NO; }

- (void)drawRect:(CGRect)rect {
    if (!g_espOn || !g_targetCount) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    void *cam = MP(M_camMain) ? ((void *(*)(void *))MP(M_camMain))(M_camMain) : nullptr;
    if (!alive(cam)) cam = g_lcam;
    if (!alive(cam)) return;

    CGFloat sw = ScreenW();
    CGFloat sh = ScreenH();
    CGPoint snapOrigin = CGPointMake(sw * 0.5f, sh);

    CGContextSetLineWidth(ctx, 1.2f);

    for (int i = 0; i < g_targetCount; i++) {
        EspTarget *t = &g_targets[i];
        Vec3 headWorld = t->head;
        Vec3 feetWorld = { headWorld.x, headWorld.y - 1.70f, headWorld.z };

        CGPoint headPt, feetPt;
        if (!worldToScreen(cam, headWorld, &headPt)) continue;
        if (!worldToScreen(cam, feetWorld, &feetPt)) continue;

        CGFloat h = feetPt.y - headPt.y;
        if (h < 4.0f) continue;
        CGFloat w = h * 0.48f;
        CGRect box = CGRectMake(headPt.x - w * 0.5f, headPt.y, w, h);

        UIColor *color = t->isAi ? [UIColor colorWithRed:1.0f green:0.85f blue:0.0f alpha:0.95f]
                                 : [UIColor colorWithRed:0.2f green:1.0f blue:0.3f alpha:0.95f];

        [color setStroke];
        [color setFill];

        // 1. Box
        CGContextStrokeRect(ctx, box);

        // 2. Snapline
        CGContextMoveToPoint(ctx, snapOrigin.x, snapOrigin.y);
        CGContextAddLineToPoint(ctx, feetPt.x, feetPt.y);
        CGContextStrokePath(ctx);

        // 3. Name & Distance tag
        NSString *nameStr = (t->name[0] != '\0') ? [NSString stringWithUTF8String:t->name] : @"Player";
        if (!nameStr) nameStr = @"Player";
        NSString *tag = [NSString stringWithFormat:@"%@ [%dm]%s",
                         nameStr, (int)t->dist, t->isAi ? " [BOT]" : ""];

        UIFont *font = [UIFont boldSystemFontOfSize:10.0f];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: color
        };
        CGSize sz = [tag sizeWithAttributes:attrs];
        CGPoint textPos = CGPointMake(headPt.x - sz.width * 0.5f, headPt.y - sz.height - 2.0f);
        [tag drawAtPoint:textPos withAttributes:attrs];
    }
}
@end

#pragma mark - UI Menu & Floating Button

@interface MWMMenuView : UIView
@property (retain) UILabel *statusLabel;
@property (retain) UISwitch *recoilSwitch;
@property (retain) UISwitch *espSwitch;
@property (retain) UISwitch *aimSwitch;
@property (retain) UISlider *aimFovSlider;
@property (retain) UILabel *aimFovLabel;
@property (retain) UISlider *fovSlider;
@property (retain) UILabel *fovLabel;
@end

@implementation MWMMenuView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.96];
    self.layer.cornerRadius = 14.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithRed:0.25 green:0.45 blue:0.85 alpha:0.7].CGColor;
    self.layer.masksToBounds = YES;

    CGFloat y = 14;
    CGFloat w = frame.size.width;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 22)];
    title.text = @"Mini World Menu (VIP)";
    title.font = [UIFont boldSystemFontOfSize:16];
    title.textColor = [UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];
    y += 26;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 16)];
    self.statusLabel.text = @"Status: Initializing...";
    self.statusLabel.font = [UIFont systemFontOfSize:11];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.statusLabel];
    y += 24;

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(16, y, w - 32, 1)];
    div.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [self addSubview:div];
    y += 12;

    self.recoilSwitch = [self toggleAt:&y title:@"No Recoil" sel:@selector(recoilToggled:)];
    self.espSwitch = [self toggleAt:&y title:@"ESP (Box + Line + Dist)" sel:@selector(espToggled:)];
    self.aimSwitch = [self toggleAt:&y title:@"Silent Aim (Auto Head)" sel:@selector(aimToggled:)];

    self.aimFovLabel = [self labelAt:&y text:[NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov]];
    self.aimFovSlider = [self sliderAt:&y min:10 max:90 val:g_aimFov sel:@selector(aimFovChanged:)];

    self.fovLabel = [self labelAt:&y text:g_fov > 0 ? [NSString stringWithFormat:@"Camera FOV: %d°", (int)g_fov] : @"Camera FOV: Default"];
    self.fovSlider = [self sliderAt:&y min:60 max:120 val:g_fov > 0 ? g_fov : 90 sel:@selector(fovChanged:)];

    y += 8;
    UIButton *rst = [UIButton buttonWithType:UIButtonTypeCustom];
    rst.frame = CGRectMake(16, y, (w - 40) / 2, 32);
    rst.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:0.8];
    rst.layer.cornerRadius = 8;
    [rst setTitle:@"Reset" forState:UIControlStateNormal];
    [rst setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    rst.titleLabel.font = [UIFont systemFontOfSize:13];
    [rst addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:rst];

    UIButton *cls = [UIButton buttonWithType:UIButtonTypeCustom];
    cls.frame = CGRectMake(24 + (w - 40) / 2, y, (w - 40) / 2, 32);
    cls.backgroundColor = [UIColor colorWithRed:0.8 green:0.25 blue:0.25 alpha:0.8];
    cls.layer.cornerRadius = 8;
    [cls setTitle:@"Close" forState:UIControlStateNormal];
    [cls setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cls.titleLabel.font = [UIFont systemFontOfSize:13];
    [cls addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:cls];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (UISwitch *)toggleAt:(CGFloat *)yp title:(NSString *)t sel:(SEL)action {
    CGFloat y = *yp;
    CGFloat w = self.frame.size.width;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 4, w - 80, 24)];
    lbl.text = t;
    lbl.font = [UIFont systemFontOfSize:13];
    lbl.textColor = [UIColor whiteColor];
    [self addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 68, y, 51, 31)];
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self addSubview:sw];

    *yp += 38;
    return sw;
}

- (UILabel *)labelAt:(CGFloat *)yp text:(NSString *)t {
    CGFloat y = *yp;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.frame.size.width - 32, 18)];
    lbl.text = t;
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [self addSubview:lbl];
    *yp += 20;
    return lbl;
}

- (UISlider *)sliderAt:(CGFloat *)yp min:(float)mn max:(float)mx val:(float)v sel:(SEL)action {
    CGFloat y = *yp;
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(16, y, self.frame.size.width - 32, 28)];
    sl.minimumValue = mn;
    sl.maximumValue = mx;
    sl.value = v;
    [sl addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self addSubview:sl];
    *yp += 32;
    return sl;
}

- (void)recoilToggled:(UISwitch *)s { g_norecoil = s.isOn; }
- (void)espToggled:(UISwitch *)s { g_espOn = s.isOn; }
- (void)aimToggled:(UISwitch *)s { g_silentAim = s.isOn; }
- (void)aimFovChanged:(UISlider *)s {
    g_aimFov = s.value;
    self.aimFovLabel.text = [NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov];
}
- (void)fovChanged:(UISlider *)s {
    g_fov = s.value;
    self.fovLabel.text = [NSString stringWithFormat:@"Camera FOV: %d°", (int)g_fov];
}

- (void)resetTapped {
    g_norecoil = NO;
    g_espOn = NO;
    g_silentAim = NO;
    g_fov = 0.0f;
    self.recoilSwitch.on = NO;
    self.espSwitch.on = NO;
    self.aimSwitch.on = NO;
    self.fovSlider.value = 90.0f;
    self.fovLabel.text = @"Camera FOV: Default";
    self.aimFovSlider.value = 35.0f;
    self.aimFovLabel.text = @"Aim FOV: 35°";
}

- (void)closeTapped { self.hidden = YES; }

- (void)handlePan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.superview];
}

@end

#pragma mark - UI Manager

@interface MWMUIManager : NSObject
+ (instancetype)shared;
@property (retain) UIButton *floatingBtn;
@property (retain) MWMMenuView *menuView;
@property (retain) MWMEspView *espView;
@property (retain) CADisplayLink *displayLink;
- (void)setupUI;
@end

@implementation MWMUIManager

+ (instancetype)shared {
    static MWMUIManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [MWMUIManager new]; });
    return inst;
}

- (void)setupUI {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) {
        id wins = [UIApplication sharedApplication].windows;
        if ([wins isKindOfClass:[NSObject class]]) w = (UIWindow *)wins;
    }
    if (!w) return;

    if (!self.espView) {
        self.espView = [[MWMEspView alloc] initWithFrame:w.bounds];
        self.espView.backgroundColor = [UIColor clearColor];
        self.espView.userInteractionEnabled = NO;
        self.espView.opaque = NO;
        [w addSubview:self.espView];
    }

    if (!self.floatingBtn) {
        CGFloat size = 46.0;
        self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingBtn.frame = CGRectMake(20, 100, size, size);
        self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.4 blue:0.9 alpha:0.85];
        self.floatingBtn.layer.cornerRadius = size / 2;
        self.floatingBtn.layer.borderWidth = 1.5;
        self.floatingBtn.layer.borderColor = [UIColor whiteColor].CGColor;
        [self.floatingBtn setTitle:@"M" forState:UIControlStateNormal];
        [self.floatingBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.floatingBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [self.floatingBtn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(btnPanned:)];
        [self.floatingBtn addGestureRecognizer:p];
        [w addSubview:self.floatingBtn];
    }

    if (!self.menuView) {
        self.menuView = [[MWMMenuView alloc] initWithFrame:CGRectMake(40, 120, 260, 360)];
        self.menuView.hidden = YES;
        [w addSubview:self.menuView];
    }

    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)btnTapped {
    self.menuView.hidden = !self.menuView.hidden;
    if (!self.menuView.hidden) {
        [self.menuView.superview bringSubviewToFront:self.menuView];
    }
}

- (void)btnPanned:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.floatingBtn.superview];
    self.floatingBtn.center = CGPointMake(self.floatingBtn.center.x + t.x, self.floatingBtn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.floatingBtn.superview];
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

    // 1. No recoil
    if (g_norecoil && off_recoilAngles) {
        *(Vec2 *)((char *)g_lcam + off_recoilAngles) = (Vec2){0.0f, 0.0f};
    }

    // 2. Camera FOV: applies to both FPP and TPP
    if (g_fov > 0.0f) {
        // FP: update PlayerCamera
        if (alive(g_lcam) && MP(M_setFpCameraFov)) {
            ((void (*)(void *, float, float, void *))MP(M_setFpCameraFov))(g_lcam, g_fov, 0.0f, M_setFpCameraFov);
        }
        // TP & Main Camera: update Camera.main directly
        void *mainCam = MP(M_camMain) ? ((void *(*)(void *))MP(M_camMain))(M_camMain) : nullptr;
        if (alive(mainCam) && MP(M_fov)) {
            ((void (*)(void *, float, void *))MP(M_fov))(mainCam, g_fov, M_fov);
        }
    }

    // 3. Scan targets for ESP and Silent Aim
    if (g_espOn || g_silentAim) {
        scanPlayers();
    }
}
@end

#pragma mark - Resolution & Hooking

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

    g_apiResolved = (i_domain_get && i_thread_attach && i_get_assemblies &&
                     i_assembly_image && i_image_name && i_class_from_name &&
                     i_method_from_name && i_field_from_name && i_field_offset);
    if (!g_apiResolved) NSLog(@"[MWM] il2cpp exports missing");
    return g_apiResolved;
}

// Bypasses dummy implementations
static void dummy_ret(void *self, void *mi) { (void)self; (void)mi; }
static bool dummy_false(void *mi) { (void)mi; return false; }
static bool dummy_true(int32_t id, void *mi) { (void)id; (void)mi; return true; }
static bool dummy_true_2(int32_t id, void *cb, void *mi) { (void)id; (void)cb; (void)mi; return true; }

static void (*pMSHookFunction)(void *, void *, void **) = nullptr;

static BOOL resolveIl2Cpp(void) {
    void *game = findImage("Assembly-CSharp.dll");
    void *core = findImage("UnityEngine.CoreModule.dll");
    if (!game || !core) return NO;

    void *K_obj       = i_class_from_name(core, "UnityEngine", "Object");
    void *K_netPlayer = i_class_from_name(game, "WildWest.NetControllers", "NetPlayer");
    void *K_netMgr    = i_class_from_name(game, "WildWest.NetControllers", "NetManager");
    K_weaponProc      = i_class_from_name(game, "", "WeaponProcessBase");

    K_player    = i_class_from_name(game, "HQFPSTemplate", "Player");
    K_playerCam = i_class_from_name(game, "HQFPSTemplate", "PlayerCamera");
    K_lpm       = i_class_from_name(game, "", "LocalPlayerManager");
    K_camera    = i_class_from_name(core, "UnityEngine", "Camera");

    off_cachedPtr = fieldOff(K_obj, "m_CachedPtr");
    off_lpmPlayer = fieldOff(K_lpm, "<LocalPlayer>k__BackingField");
    off_playerType = fieldOff(K_lpm, "<LocalPlayerType>k__BackingField");
    off_playerCam = fieldOff(K_player, "m_PlayerCamera");
    off_recoilAngles = fieldOff(K_playerCam, "m_RecoilAngles");

    M_lpmInstance = methodOf(K_lpm, "get_Instance", 0);
    M_fov         = methodOf(K_camera, "set_fieldOfView", 1);
    M_w2s         = methodOf(K_camera, "WorldToScreenPoint", 1);
    M_camMain     = methodOf(K_camera, "get_main", 0);
    M_setFpCameraFov = methodOf(K_playerCam, "SetFPCameraFieldOfView", 2);

    M_netInstance = methodOf(K_netMgr, "get_Instance", 0);
    M_playerName  = methodOf(K_netPlayer, "GetPlayerName", 0);
    M_playerIsAi  = methodOf(K_netPlayer, "IsAiPlayer", 0);
    M_playerPos   = methodOf(K_netPlayer, "GetPosition", 0);
    off_netPlayerMap = fieldOff(K_netMgr, "NetPlayerMap");

    M_fireDir = methodOf(K_weaponProc, "computerFireDirection", 1);

    void *K_sceneHelper = i_class_from_name(game, "", "LogicSceneHelper");
    void *K_guideMgr    = i_class_from_name(game, "", "BattleGuideManager");
    void *K_lua         = i_class_from_name(game, "", "LuaHelper");

    M_checkGuideScene = methodOf(K_sceneHelper, "CheckIsGuideScene", 0);
    M_isNewbieGame    = methodOf(K_sceneHelper, "IsNewbieGame", 0);
    M_guideInit       = methodOf(K_guideMgr, "Init", 0);
    M_checkFuncOpen   = methodOf(K_lua, "CheckFunctionIsOpen", 1);
    M_checkFuncUnlock = methodOf(K_lua, "CheckFuncUnlock", 2);

    if (!off_cachedPtr || !off_lpmPlayer || !off_playerType || !off_playerCam ||
        !off_recoilAngles || !MP(M_lpmInstance)) return NO;

    pMSHookFunction = (void (*)(void *, void *, void **))dlsym(RTLD_DEFAULT, "MSHookFunction");

    // Install Silent Aim
    if (MP(M_fireDir)) {
        if (pMSHookFunction) {
            pMSHookFunction(MP(M_fireDir), (void *)&hk_computerFireDirection, (void **)&O_computerFireDirection);
        }
        *(void **)M_fireDir = (void *)&hk_computerFireDirection;
    }

    // Install Tutorial Bypass
    if (g_bypassTutorial) {
        if (MP(M_guideInit)) {
            if (pMSHookFunction) pMSHookFunction(MP(M_guideInit), (void *)&dummy_ret, nullptr);
            *(void **)M_guideInit = (void *)&dummy_ret;
        }
        if (MP(M_checkGuideScene)) {
            if (pMSHookFunction) pMSHookFunction(MP(M_checkGuideScene), (void *)&dummy_false, nullptr);
            *(void **)M_checkGuideScene = (void *)&dummy_false;
        }
        if (MP(M_isNewbieGame)) {
            if (pMSHookFunction) pMSHookFunction(MP(M_isNewbieGame), (void *)&dummy_false, nullptr);
            *(void **)M_isNewbieGame = (void *)&dummy_false;
        }
    }

    // Install Rank / Level Lock Bypass
    if (g_bypassRankLock) {
        if (MP(M_checkFuncOpen)) {
            if (pMSHookFunction) pMSHookFunction(MP(M_checkFuncOpen), (void *)&dummy_true, nullptr);
            *(void **)M_checkFuncOpen = (void *)&dummy_true;
        }
        if (MP(M_checkFuncUnlock)) {
            if (pMSHookFunction) pMSHookFunction(MP(M_checkFuncUnlock), (void *)&dummy_true_2, nullptr);
            *(void **)M_checkFuncUnlock = (void *)&dummy_true_2;
        }
    }

    g_il2cppReady = YES;
    NSLog(@"[MWM] armed | netMgr=%p espOff=%zu fov=%p fireDir=%p",
          MP(M_netInstance), off_netPlayerMap, MP(M_fov), MP(M_fireDir));
    return YES;
}

#pragma mark - Lifecycle

static void tick(void) {
    [[MWMUIManager shared] setupUI];
    if (!g_apiResolved) resolveApi();
    if (g_il2cppReady || !g_apiResolved) return;
    void *d = i_domain_get();
    if (!d) return;
    i_thread_attach(d);
    if (resolveIl2Cpp()) {
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
                          const void *obj, CFDictionaryRef info) {
    (void)c; (void)o; (void)n; (void)obj; (void)info;
    pollUntilArmed(0);
}

__attribute__((constructor)) static void mwm_entry(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, &onAppLaunched,
                                    (__bridge CFStringRef)UIApplicationDidFinishLaunchingNotification,
                                    NULL, CFNotificationSuspensionBehaviorDrop);
}
