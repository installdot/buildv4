// Mini World : Royale (com.miniworldroyale.sparkgame)
// TrollFools injected tweak — native UIKit menu, ESP overlay, silent aim.
//
// Symbol names below are taken verbatim from Il2CppDumper dump.cs for this build.
// Any name that does not exist makes resolveIl2Cpp() return NO and every feature
// dies silently, so each lookup is logged and the status label shows the failure.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdint.h>
#import <unistd.h>
#import <math.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>

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

#pragma mark - Diagnostic

static char g_diag[96] = "Status: Booting...";

#pragma mark - Resolved Symbols

static void *K_lpm, *K_camera, *K_player;
static void *K_weaponProc;

static void *M_lpmInstance;       // LocalPlayerManager::get_Instance()
static void *M_w2s;               // Camera::WorldToScreenPoint(Vector3)
static void *M_camMain;           // Camera::get_main()
static void *M_getTransform;      // Component::get_transform()
static void *M_getPos;            // Transform::get_position()

// ESP / Aim
static void *M_netInstance;       // NetManager::get_Instance()
static void *M_playerName;        // NetPlayer::GetPlayerName()
static void *M_playerIsAi;        // NetPlayer::IsAiPlayer()
static void *M_playerPos;         // NetPlayer::GetPosition()
static void *M_netPlayerId;       // NetPlayer::GetNetPlayerId()
static void *M_netTeamId;         // NetPlayer::GetTeamId()
static size_t off_bindNetId;      // LocalPlayerManager.curBindNetPlayerId
static size_t off_netPlayerMap;

// Silent aim
static void *M_fireDir;           // WeaponProcessBase::computerFireDirection
static void *O_computerFireDirection = nullptr;

// Bypasses
static void *M_guideInit;         // BattleGuideManager::Init()
static void *M_checkGuideScene;   // LogicSceneHelper::CheckIsGuideScene()
static void *M_isNewbieGame;      // LogicSceneHelper::IsNewbieGame()
static void *M_checkFuncOpen;     // LuaHelper::CheckFunctionIsOpen(int)
static void *M_checkFuncUnlock;   // LuaHelper::CheckFuncUnlock(int, Action<uint>)

// Field offsets (this build)
//   UnityEngine.Object.m_CachedPtr           0x10
//   LocalPlayerManager.mLocalPlayer          0x18
//   Player._PlayerCamera                     0x4E8
//   Player.LocalPlayerType                   0x4C8
//   PlayerCamera.m_RecoilAngles              0x58
//   NetManagerBase.NetPlayerMap              0x18
static size_t off_cachedPtr, off_lpmPlayer, off_playerType;
static size_t off_playerCam;

static void *g_lcam = nullptr;

#pragma mark - State

static BOOL  g_il2cppReady = NO;

static BOOL  g_espOn = NO;
static BOOL  g_silentAim = NO;
static float g_aimFov = 35.0f;
static BOOL  g_showAimFov = NO;

// Cached every frame by onFrame() on the main thread. The fire hook must never call
// into Unity/il2cpp: doing so from inside the weapon-fire path re-enters the physics
// update and crashed the game 1-2s after enabling silent aim.
static Vec3  g_aimHead = {0.0f, 0.0f, 0.0f};
static volatile BOOL g_aimHeadValid = NO;
static volatile uint16_t g_myNetId = 0;   // written by scanPlayers, read by the hook
static BOOL  g_bypassTutorial = YES;
static BOOL  g_bypassRankLock = YES;

static BOOL installSilentAim(void);   // defined below; installed at arm time
static BOOL g_fireDirPatched;

static inline BOOL alive(void *obj) {
    return obj && off_cachedPtr && *(void **)((char *)obj + off_cachedPtr) != nullptr;
}

#pragma mark - WorldToScreen

static BOOL worldToScreen(void *cam, Vec3 world, CGPoint *outPt) {
    if (!cam || !outPt || !MP(M_w2s)) return NO;
    Vec3 p = ((Vec3 (*)(void *, Vec3, void *))MP(M_w2s))(cam, world, M_w2s);
    if (p.z <= 0.0f) return NO;
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

// Il2CppString: klass@0, monitor@8, length@0x10, utf16 chars@0x14
static BOOL il2cppStrEqual(void *a, void *b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    int la = *(int *)((char *)a + 0x10);
    int lb = *(int *)((char *)b + 0x10);
    if (la != lb || la <= 0 || la > 64) return NO;
    return memcmp((char *)a + 0x14, (char *)b + 0x14, (size_t)la * 2) == 0;
}

static void scanPlayersImpl(void);

static void scanPlayers(void) {
    @try {
        scanPlayersImpl();
    } @catch (NSException *e) {
        g_targetCount = 0;
        NSLog(@"[MWM] scan: %@", e);
    }
}

static void scanPlayersImpl(void) {
    g_targetCount = 0;
    if (!g_il2cppReady || !MP(M_netInstance) || !off_netPlayerMap) return;

    // NetManagerBase is a plain managed class (not a UnityEngine.Object), so there is
    // no m_CachedPtr -- use a plain null check, never alive().
    void *mgr = ((void *(*)(void *))MP(M_netInstance))(M_netInstance);
    if (!mgr) return;

    void *dict = readPtr(mgr, off_netPlayerMap);
    if (!dict) return;

    // Dictionary<ushort,NetPlayer>: buckets@0x10, entries@0x18, count@0x20
    // entries is an Il2CppArray OBJECT: klass@0, monitor@8, bounds@0x10,
    // max_length@0x18, items@0x20. Reading items from +0 was the ESP/silent-aim crash.
    void *entriesObj = readPtr(dict, 0x18);
    if (!entriesObj) return;
    int count = *(int *)((char *)dict + 0x20);
    if (count <= 0 || count > 256) return;
    size_t maxLength = *(size_t *)((char *)entriesObj + 0x18);
    // The dictionary can be mutated by the network thread between the two reads
    // above; a stale maxLength is exactly what turned ESP into a crash. Refuse to
    // walk anything that does not look consistent.
    if (maxLength == 0 || maxLength > 4096 || maxLength < (size_t)count) return;
    char *entries = (char *)entriesObj + 0x20;          // inline item storage

    void *lpm = MP(M_lpmInstance) ? ((void *(*)(void *))MP(M_lpmInstance))(M_lpmInstance) : nullptr;
    void *myPlayer = (lpm && off_lpmPlayer) ? readPtr(lpm, off_lpmPlayer) : nullptr;
    // Entries hold NetPlayer while the local player is a Player, so pointer equality
    // never matches -- exclude self by net id instead.
    uint16_t myNetId = 0;
    if (lpm && off_bindNetId) myNetId = *(uint16_t *)((char *)lpm + off_bindNetId);
    g_myNetId = myNetId;

    // Player is a MonoBehaviour (not a NetPlayer), so its position comes from Transform.
    Vec3 myPos = {0.0f, 0.0f, 0.0f};
    if (myPlayer && MP(M_getTransform) && MP(M_getPos)) {
        void *tr = ((void *(*)(void *, void *))MP(M_getTransform))(myPlayer, M_getTransform);
        if (alive(tr)) myPos = ((Vec3 (*)(void *, void *))MP(M_getPos))(tr, M_getPos);
    }

    // Pass 1: locate our own NetPlayer so its team id can be compared.
    void *myTeam = nullptr;
    if (myNetId && MP(M_netPlayerId) && MP(M_netTeamId)) {
        for (int i = 0; i < count; i++) {
            char *e = entries + (size_t)i * 0x18;
            if (*(int *)e < 0) continue;
            void *np = readPtr(e, 0x10);
            if (!np || !alive(np)) continue;
            if (((uint16_t (*)(void *, void *))MP(M_netPlayerId))(np, M_netPlayerId) != myNetId) continue;
            myTeam = ((void *(*)(void *, void *))MP(M_netTeamId))(np, M_netTeamId);
            break;
        }
    }

    // Pass 2: build targets, skipping ourselves and (when known) our own team.
    for (int i = 0; i < count && g_targetCount < MAX_TARGETS; i++) {
        char *e = entries + (size_t)i * 0x18;
        if (*(int *)e < 0) continue;            // empty slot
        void *np = readPtr(e, 0x10);            // TValue
        if (!np || !alive(np)) continue;        // NetPlayer is a NetworkBehaviour
        if (myNetId && MP(M_netPlayerId) &&
            ((uint16_t (*)(void *, void *))MP(M_netPlayerId))(np, M_netPlayerId) == myNetId) continue;
        // Teammate: same non-empty team id as ours. Solo modes expose no team id,
        // so the compare simply never matches there.
        if (myTeam && MP(M_netTeamId)) {
            void *theirTeam = ((void *(*)(void *, void *))MP(M_netTeamId))(np, M_netTeamId);
            if (il2cppStrEqual(myTeam, theirTeam)) continue;
        }

        Vec3 pos = {0.0f, 0.0f, 0.0f};
        if (MP(M_playerPos)) pos = ((Vec3 (*)(void *, void *))MP(M_playerPos))(np, M_playerPos);
        if (pos.x == 0.0f && pos.y == 0.0f && pos.z == 0.0f) continue;

        float dx = pos.x - myPos.x, dy = pos.y - myPos.y, dz = pos.z - myPos.z;

        EspTarget *t = &g_targets[g_targetCount];
        t->obj = np;
        t->head = (Vec3){ pos.x, pos.y + 1.65f, pos.z };
        t->dist = sqrtf(dx * dx + dy * dy + dz * dz);
        t->isAi = MP(M_playerIsAi) ? ((bool (*)(void *, void *))MP(M_playerIsAi))(np, M_playerIsAi) : NO;
        t->name[0] = '\0';

        if (MP(M_playerName)) {
            void *str = ((void *(*)(void *, void *))MP(M_playerName))(np, M_playerName);
            if (str) {
                int len = *(int *)((char *)str + 0x10);   // Il2CppString.length
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

#pragma mark - Silent Aim

static BOOL pickBestTargetHead(Vec3 *outHead) {
    if (!g_targetCount || !outHead || !MP(M_camMain)) return NO;
    void *cam = ((void *(*)(void *))MP(M_camMain))(M_camMain);
    if (!alive(cam)) return NO;

    CGFloat cx = ScreenW() * 0.5f;
    CGFloat cy = ScreenH() * 0.5f;
    CGFloat maxRadius = (g_aimFov / 90.0f) * cx;
    float best = 1e9f;
    BOOL found = NO;

    for (int i = 0; i < g_targetCount; i++) {
        CGPoint sp;
        if (!worldToScreen(cam, g_targets[i].head, &sp)) continue;
        float dx = (float)(sp.x - cx), dy = (float)(sp.y - cy);
        float d = sqrtf(dx * dx + dy * dy);
        if (d <= (float)maxRadius && d < best) {
            best = d;
            *outHead = g_targets[i].head;
            found = YES;
        }
    }
    return found;
}

// Runs on the game's fire path, once per bullet/pellet.
//
// Rules learned from the "crash on trigger pull" report:
//   * ALWAYS run the original body. Skipping it left shootData in a state the
//     caller then fed to Physics.RaycastNonAlloc, which is what killed the process.
//   * NEVER write into shootData. Only the returned direction is consumed by both
//     callers (computerVirtualBullet reads s0-s2, computerEntityBullet forwards it).
//   * Reject non-finite vectors. g_aimHead is published from another thread and a
//     torn 12-byte read yields NaN, and a NaN ray direction crashes Unity physics.
static inline BOOL vec3Finite(Vec3 v) {
    return v.x == v.x && v.y == v.y && v.z == v.z &&
           fabsf(v.x) < 1e6f && fabsf(v.y) < 1e6f && fabsf(v.z) < 1e6f;
}

static Vec3 hk_computerFireDirection(void *self, void *shootData, void *method) {
    Vec3 dir = { 0.0f, 0.0f, 1.0f };

    // The hook is only ever installed when a usable trampoline exists, so this
    // branch is always taken. If it is not, returning a fabricated vector would
    // hand the caller a direction the original never produced -> crash on fire.
    if (!O_computerFireDirection) return dir;

    // Original first, unconditionally: identical side effects every time.
    dir = ((Vec3 (*)(void *, void *, void *))O_computerFireDirection)(self, shootData, method);

    if (!shootData) return dir;
    if (!g_silentAim || !g_aimHeadValid) return dir;
    if (!vec3Finite(dir)) return (Vec3){ 0.0f, 0.0f, 1.0f };

    // Only steer OUR bullets: ModelShotData.shooterId at +0x4.
    uint16_t shooter = *(uint16_t *)((char *)shootData + 0x4);
    if (!g_myNetId || shooter != g_myNetId) return dir;

    Vec3 head = g_aimHead;
    Vec3 sp = *(Vec3 *)((char *)shootData + 0x48);   // shootPos
    if (!vec3Finite(head) || !vec3Finite(sp)) return dir;

    Vec3 aimed = { head.x - sp.x, head.y - sp.y, head.z - sp.z };
    float len = sqrtf(aimed.x * aimed.x + aimed.y * aimed.y + aimed.z * aimed.z);
    if (!(len > 0.01f) || len != len || len > 1e6f) return dir;

    aimed.x /= len; aimed.y /= len; aimed.z /= len;
    return aimed;                      // return only -- no write into shootData
}

#pragma mark - ESP Overlay

@interface MWMEspView : UIView
@end

@implementation MWMEspView
- (BOOL)isUserInteractionEnabled { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event { (void)point; (void)event; return nil; }

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if ((!g_espOn && !g_showAimFov) || !MP(M_camMain)) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    void *cam = ((void *(*)(void *))MP(M_camMain))(M_camMain);
    if (!alive(cam)) return;

    CGPoint snapOrigin = CGPointMake(ScreenW() * 0.5f, ScreenH());

    // Silent-aim cone radius, mirrored from pickBestTargetHead() so what you see
    // is exactly the radius the aim code searches inside.
    if (g_showAimFov) {
        CGFloat cx = ScreenW() * 0.5f;
        CGFloat cy = ScreenH() * 0.5f;
        CGFloat r = (g_aimFov / 90.0f) * cx;
        CGContextSetLineWidth(ctx, 1.0f);
        CGContextSetRGBStrokeColor(ctx, 1.0f, 0.4f, 0.9f, 0.85f);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - r, cy - r, r * 2.0f, r * 2.0f));
    }

    CGContextSetLineWidth(ctx, 1.2f);

    for (int i = 0; g_espOn && i < g_targetCount; i++) {
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

        UIColor *color = t->isAi
            ? [UIColor colorWithRed:1.0f green:0.85f blue:0.0f alpha:0.95f]
            : [UIColor colorWithRed:0.2f green:1.0f blue:0.3f alpha:0.95f];
        [color setStroke];
        [color setFill];

        CGContextStrokeRect(ctx, box);
        CGContextMoveToPoint(ctx, snapOrigin.x, snapOrigin.y);
        CGContextAddLineToPoint(ctx, feetPt.x, feetPt.y);
        CGContextStrokePath(ctx);

        NSString *nameStr = (t->name[0] != '\0') ? [NSString stringWithUTF8String:t->name] : @"Player";
        NSString *tag = [NSString stringWithFormat:@"%@ [%dm]%s",
                         nameStr, (int)t->dist, t->isAi ? " [BOT]" : ""];
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:10.0f],
            NSForegroundColorAttributeName: color
        };
        CGSize sz = [tag sizeWithAttributes:attrs];
        [tag drawAtPoint:CGPointMake(headPt.x - sz.width * 0.5f, headPt.y - sz.height - 2.0f)
          withAttributes:attrs];
    }
}
@end

#pragma mark - UI Menu

@interface MWMMenuView : UIView
@property (retain) UILabel *statusLabel;
@property (retain) UISwitch *espSwitch;
@property (retain) UISwitch *aimSwitch;
@property (retain) UISwitch *aimFovShowSwitch;
@property (retain) UISlider *aimFovSlider;
@property (retain) UILabel *aimFovLabel;
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

    CGFloat y = 14, w = frame.size.width;

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

    self.espSwitch = [self toggleAt:&y title:@"ESP (Box + Line + Dist)" sel:@selector(espToggled:)];
    self.aimSwitch = [self toggleAt:&y title:@"Silent Aim (Auto Head)" sel:@selector(aimToggled:)];
    self.aimFovShowSwitch = [self toggleAt:&y title:@"Show Silent FOV" sel:@selector(aimFovShowToggled:)];

    self.aimFovLabel = [self labelAt:&y text:[NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov]];
    self.aimFovSlider = [self sliderAt:&y min:10 max:90 val:g_aimFov sel:@selector(aimFovChanged:)];


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

    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
    return self;
}

- (UISwitch *)toggleAt:(CGFloat *)yp title:(NSString *)t sel:(SEL)action {
    CGFloat y = *yp, w = self.frame.size.width;
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
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, *yp, self.frame.size.width - 32, 18)];
    lbl.text = t;
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [self addSubview:lbl];
    *yp += 20;
    return lbl;
}

- (UISlider *)sliderAt:(CGFloat *)yp min:(float)mn max:(float)mx val:(float)v sel:(SEL)action {
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(16, *yp, self.frame.size.width - 32, 28)];
    sl.minimumValue = mn;
    sl.maximumValue = mx;
    sl.value = v;
    [sl addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self addSubview:sl];
    *yp += 32;
    return sl;
}

- (void)espToggled:(UISwitch *)s { g_espOn = s.isOn; }
- (void)aimFovShowToggled:(UISwitch *)s { g_showAimFov = s.isOn; }

- (void)aimToggled:(UISwitch *)s {
    g_silentAim = s.isOn;
}
- (void)aimFovChanged:(UISlider *)s {
    g_aimFov = s.value;
    self.aimFovLabel.text = [NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov];
}
- (void)resetTapped {
    g_espOn = NO; g_silentAim = NO; g_showAimFov = NO;
    self.espSwitch.on = NO; self.aimSwitch.on = NO; self.aimFovShowSwitch.on = NO;
    self.aimFovSlider.value = 35.0f; self.aimFovLabel.text = @"Aim FOV: 35°";
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
@property (retain) UIWindow *host;
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

// Host window: the game's own window. Creating a full-screen window of our own at a
// high windowLevel swallowed every touch that hitTest returned nil for, which made
// the game unplayable. Attaching to the existing window has no such side effect --
// touches that miss our subviews go straight to Unity.
- (UIWindow *)hostWindow {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w && !w.hidden) return w;

    UIWindow *best = nil;
    for (UIWindow *cand in [UIApplication sharedApplication].windows) {
        if (cand.hidden) continue;
        if (cand.windowLevel > 1.0) continue;      // skip alerts / status bar
        if (!best || cand.windowLevel < best.windowLevel) best = cand;
    }
    return best;
}

- (void)setupUI {
    UIWindow *w = [self hostWindow];
    if (!w) return;
    self.host = w;

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
        [self.floatingBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(btnPanned:)]];
        [w addSubview:self.floatingBtn];
    }

    if (!self.menuView) {
        self.menuView = [[MWMMenuView alloc] initWithFrame:CGRectMake(40, 120, 260, 340)];
        self.menuView.hidden = YES;
        [w addSubview:self.menuView];
    }

    // Unity may replace its window; move our views to the current one.
    if (self.espView.superview != w) {
        [w addSubview:self.espView];
        [w addSubview:self.floatingBtn];
        if (self.menuView) [w addSubview:self.menuView];
    }
    if (!CGRectEqualToRect(self.espView.frame, w.bounds)) self.espView.frame = w.bounds;

    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)btnTapped {
    self.menuView.hidden = !self.menuView.hidden;
    if (!self.menuView.hidden) [self.menuView.superview bringSubviewToFront:self.menuView];
}
- (void)btnPanned:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.floatingBtn.superview];
    self.floatingBtn.center = CGPointMake(self.floatingBtn.center.x + t.x, self.floatingBtn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.floatingBtn.superview];
}

- (void)setStatus:(const char *)s color:(UIColor *)col {
    if (!self.menuView) return;
    self.menuView.statusLabel.text = [NSString stringWithUTF8String:s];
    self.menuView.statusLabel.textColor = col;
}

- (void)onFrame {
    if (g_espOn || g_showAimFov) [self.espView setNeedsDisplay];
    g_aimHeadValid = NO;   // re-set below only while a target is actually visible

    if (!g_il2cppReady) {
        [self setStatus:g_diag color:[UIColor colorWithRed:1.0 green:0.55 blue:0.2 alpha:1.0]];
        return;
    }
    void *mp = MP(M_lpmInstance);
    if (!mp) {
        [self setStatus:"Status: LPM instance null" color:[UIColor colorWithRed:1.0 green:0.55 blue:0.2 alpha:1.0]];
        return;
    }

    void *lpm = ((void *(*)(void *))mp)(M_lpmInstance);
    void *player = readPtr(lpm, off_lpmPlayer);

    if (!alive(player)) {
        g_lcam = nullptr;
        g_aimHeadValid = NO;
        g_myNetId = 0;
        [self setStatus:"Status: Lobby / Loading" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }
    // LocalPlayerType lives on Player, not on LocalPlayerManager.
    int type = off_playerType ? *(int *)((char *)player + off_playerType) : 1;
    if (type == 0 || type == 4) {
        g_lcam = nullptr;
        g_aimHeadValid = NO;
        [self setStatus:"Status: In Lobby" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    void *cam = readPtr(player, off_playerCam);
    g_lcam = alive(cam) ? cam : nullptr;
    if (!g_lcam) {
        g_aimHeadValid = NO;
        [self setStatus:"Status: Loading Match..." color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    [self setStatus:"Status: In-Game (Active)" color:[UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0]];

    if (g_espOn || g_silentAim) scanPlayers();

    // Publish the aim point for the fire hook. All Unity calls stay on this thread.
    g_aimHeadValid = NO;              // publish gate: invalid while we mutate
    if (g_silentAim && g_targetCount > 0) {
        Vec3 head;
        if (pickBestTargetHead(&head) && vec3Finite(head)) {
            g_aimHead = head;
            g_aimHeadValid = YES;     // only now is the snapshot readable
        }
    }
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

    g_apiResolved = (i_domain_get && i_thread_attach && i_get_assemblies &&
                     i_assembly_image && i_image_name && i_class_from_name &&
                     i_method_from_name && i_field_from_name && i_field_offset);
    if (!g_apiResolved) snprintf(g_diag, sizeof(g_diag), "Status: no il2cpp exports");
    return g_apiResolved;
}

// ---------------------------------------------------------------------------
// Hook provider.
// NO in-place __TEXT patching: TrollFools/TrollStore builds are ad-hoc signed, and
// vm_protect()+memcpy on a code page gets the process killed by the codesign
// monitor the moment the page is executed. Only two safe mechanisms are used:
//   1. MSHookFunction (ElleKit, shipped inside the TrollFools injection) for the
//      one hook that needs a trampoline.
//   2. MethodInfo->methodPointer replacement for plain return-value overrides.
//      That is a write to writable il2cpp metadata, never to executable pages.
// Anything unavailable is skipped: a missing feature must never be a crash.
// ---------------------------------------------------------------------------
static void (*pMSHookFunction)(void *, void *, void **) = nullptr;

static void resolveHookProvider(void) {
    static const char *libs[] = {
        NULL,
        "@executable_path/Frameworks/libellekit.dylib",
        "@executable_path/libellekit.dylib",
        "@executable_path/Frameworks/libsubstrate.dylib",
        "/usr/lib/libellekit.dylib",
        "/usr/lib/libsubstrate.dylib",
        "/usr/lib/libhooker.dylib",
        "/usr/lib/libsubstitute.dylib",
    };
    for (unsigned i = 0; i < sizeof(libs) / sizeof(libs[0]) && !pMSHookFunction; i++) {
        if (libs[i]) dlopen(libs[i], RTLD_NOW | RTLD_GLOBAL);
        pMSHookFunction = (void (*)(void *, void *, void **))dlsym(RTLD_DEFAULT, "MSHookFunction");
    }
    NSLog(@"[MWM] hook provider: %s", pMSHookFunction ? "yes" : "no");
}

// ---------------------------------------------------------------------------
// MethodInfo replacement (writable metadata only, no code patching).
// Takes effect for virtual / delegate / reflection dispatch. A direct BL call
// inside the same assembly still reaches the original body -- the feature then
// simply does nothing, which is the intended failure mode.
// ---------------------------------------------------------------------------
static void dummy_ret(void *self, void *mi) { (void)self; (void)mi; }
static bool dummy_false(void *mi) { (void)mi; return false; }
static bool dummy_true_i(int32_t a, void *mi) { (void)a; (void)mi; return true; }
static bool dummy_true_ic(int32_t a, void *cb, void *mi) { (void)a; (void)cb; (void)mi; return true; }

// Write to a MethodInfo/methodSlot that may sit on a read-only data page.
// Executable pages are never touched: vm_protect()+write on __TEXT makes the
// codesign monitor kill the process on the next page-in. A skipped patch is a
// disabled feature; a bad patch is a crash.
static BOOL addrIsExecutable(void *addr) {
    if (!addr || (uintptr_t)addr < 0x1000) return NO;
    vm_address_t q = (vm_address_t)addr;
    vm_size_t qsize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &q, &qsize, VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &count, &obj);
    if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
    if (kr != KERN_SUCCESS) return NO;
    return (info.protection & VM_PROT_EXECUTE) != 0;
}

static BOOL safeWritePtr(void *addr, void *value) {
    if (!addr) return NO;

    vm_address_t page = (vm_address_t)addr & ~(vm_address_t)0x3FFF;
    vm_size_t span = 0x4000;

    // Refuse executable pages: patching __TEXT is what killed the process before.
    vm_address_t q = page;
    vm_size_t qsize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &q, &qsize, VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &count, &obj);
    if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[MWM] skip patch: vm_region(%p) failed %d", addr, kr);
        return NO;
    }
    if (info.protection & VM_PROT_EXECUTE) {
        NSLog(@"[MWM] skip patch: executable page %p", addr);
        return NO;
    }

    // il2cpp metadata is read-only after init; make the single page writable.
    kr = vm_protect(mach_task_self(), page, span, false, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[MWM] skip patch: vm_protect(%p) failed %d", addr, kr);
        return NO;
    }
    *(void **)addr = value;
    return YES;
}

static BOOL replaceMethod(void *mi, void *repl) {
    if (!MP(mi)) return NO;
    return safeWritePtr(mi, repl);   // MethodInfo.methodPointer is field 0
}

// ---------------------------------------------------------------------------
// Silent aim. Requires a trampoline, so it only installs when ElleKit is present.
// ---------------------------------------------------------------------------

static BOOL installSilentAim(void) {
    void *fn = MP(M_fireDir);
    if (!fn || g_fireDirPatched) return g_fireDirPatched;
    if (!pMSHookFunction) {
        NSLog(@"[MWM] silent aim skipped: no MSHookFunction");
        return NO;
    }
    pMSHookFunction(fn, (void *)&hk_computerFireDirection, (void **)&O_computerFireDirection);

    // A hook library that is not really a hook library hands back the original
    // address (or garbage) as the "trampoline". Calling it re-enters the patched
    // entry and recurses until the stack dies -- which is exactly "crash on fire".
    void *tramp = O_computerFireDirection;
    if (tramp == fn || !addrIsExecutable(tramp)) {
        NSLog(@"[MWM] fireDir trampoline rejected: %p (fn=%p)", tramp, fn);
        O_computerFireDirection = nullptr;
    }
    g_fireDirPatched = (O_computerFireDirection != nullptr);
    if (!g_fireDirPatched) {
        NSLog(@"[MWM] silent aim disabled: unusable trampoline");
        return NO;
    }
    return YES;
}

static BOOL resolveIl2Cpp(void) {
    void *game = findImage("Assembly-CSharp.dll");
    void *core = findImage("UnityEngine.CoreModule.dll");
    if (!game || !core) {
        snprintf(g_diag, sizeof(g_diag), "Status: image missing");
        return NO;
    }

    void *K_obj       = i_class_from_name(core, "UnityEngine", "Object");
    void *K_netPlayer = i_class_from_name(game, "WildWest.NetControllers", "NetPlayer");
    void *K_netMgr    = i_class_from_name(game, "WildWest.NetControllers", "NetManager");
    // il2cpp_class_get_field_from_name only sees fields declared on the class itself,
    // so NetPlayerMap must be looked up on its declaring class NetManagerBase.
    void *K_netMgrBase = i_class_from_name(game, "WildWest.NetControllers", "NetManagerBase");
    K_weaponProc      = i_class_from_name(game, "", "WeaponProcessBase");

    K_player    = i_class_from_name(game, "HQFPSTemplate", "Player");
    K_lpm       = i_class_from_name(game, "", "LocalPlayerManager");
    K_camera    = i_class_from_name(core, "UnityEngine", "Camera");

    // Field names verified against this build's dump.cs.
    off_cachedPtr    = fieldOff(K_obj, "m_CachedPtr");        // 0x10
    off_lpmPlayer    = fieldOff(K_lpm, "mLocalPlayer");       // 0x18
    off_playerType   = fieldOff(K_player, "LocalPlayerType"); // 0x4C8 (on Player)
    off_playerCam    = fieldOff(K_player, "_PlayerCamera");   // 0x4E8

    M_lpmInstance    = methodOf(K_lpm, "get_Instance", 0);
    M_w2s            = methodOf(K_camera, "WorldToScreenPoint", 1);
    M_camMain        = methodOf(K_camera, "get_main", 0);

    void *K_component = i_class_from_name(core, "UnityEngine", "Component");
    void *K_transform = i_class_from_name(core, "UnityEngine", "Transform");
    M_getTransform = methodOf(K_component, "get_transform", 0);
    M_getPos       = methodOf(K_transform, "get_position", 0);

    M_netInstance  = methodOf(K_netMgr, "get_Instance", 0);
    M_playerName   = methodOf(K_netPlayer, "GetPlayerName", 0);
    M_playerIsAi   = methodOf(K_netPlayer, "IsAiPlayer", 0);
    M_playerPos    = methodOf(K_netPlayer, "GetPosition", 0);
    M_netPlayerId  = methodOf(K_netPlayer, "GetNetPlayerId", 0);
    M_netTeamId    = methodOf(K_netPlayer, "GetTeamId", 0);
    off_bindNetId  = fieldOff(K_lpm, "curBindNetPlayerId");
    off_netPlayerMap = fieldOff(K_netMgrBase, "NetPlayerMap"); // 0x18

    M_fireDir = methodOf(K_weaponProc, "computerFireDirection", 1);

    void *K_sceneHelper = i_class_from_name(game, "", "LogicSceneHelper");
    void *K_guideMgr    = i_class_from_name(game, "", "BattleGuideManager");
    void *K_lua         = i_class_from_name(game, "", "LuaHelper");   // global ns (TcpSocket.LuaHelper is a different class)

    M_checkGuideScene = methodOf(K_sceneHelper, "CheckIsGuideScene", 0);
    M_isNewbieGame    = methodOf(K_sceneHelper, "IsNewbieGame", 0);
    M_guideInit       = methodOf(K_guideMgr, "Init", 0);
    M_checkFuncOpen   = methodOf(K_lua, "CheckFunctionIsOpen", 1);
    M_checkFuncUnlock = methodOf(K_lua, "CheckFuncUnlock", 2);

    // Only the essentials are mandatory; everything else degrades one feature.
    if (!off_cachedPtr) { snprintf(g_diag, sizeof(g_diag), "Status: no m_CachedPtr"); return NO; }
    if (!off_lpmPlayer) { snprintf(g_diag, sizeof(g_diag), "Status: no mLocalPlayer"); return NO; }
    if (!off_playerCam) { snprintf(g_diag, sizeof(g_diag), "Status: no _PlayerCamera"); return NO; }
    if (!MP(M_lpmInstance)) { snprintf(g_diag, sizeof(g_diag), "Status: no get_Instance"); return NO; }
    if (!MP(M_w2s) || !MP(M_camMain)) { snprintf(g_diag, sizeof(g_diag), "Status: no Camera API"); return NO; }

    resolveHookProvider();

    // Install the fire hook HERE, while still in the lobby. In a match the game
    // thread is inside computerFireDirection constantly (bots shoot), and patching
    // its first bytes under a running thread is what crashed 2-3s after enabling.
    // The body is inert until g_silentAim is set, so arming early costs nothing.
    BOOL aimOk = installSilentAim();

    if (g_bypassTutorial) {
        replaceMethod(M_guideInit, (void *)&dummy_ret);              // Init(): no step machine
        replaceMethod(M_checkGuideScene, (void *)&dummy_false);      // static bool
        replaceMethod(M_isNewbieGame, (void *)&dummy_false);         // static bool
    }
    if (g_bypassRankLock) {
        replaceMethod(M_checkFuncOpen, (void *)&dummy_true_i);       // bool (int)
        replaceMethod(M_checkFuncUnlock, (void *)&dummy_true_ic);    // bool (int, Action)
    }

    NSLog(@"[MWM] armed hook=%d aim=%d netMap=%zu",
          pMSHookFunction != nullptr, aimOk, off_netPlayerMap);
    snprintf(g_diag, sizeof(g_diag), "Status: Armed (hook=%s aim=%s)",
             pMSHookFunction ? "yes" : "no", aimOk ? "yes" : "no");
    g_il2cppReady = YES;
    return YES;
}

#pragma mark - Lifecycle

static void tick(void) {
    if (!g_apiResolved && !resolveApi()) {
        @try { [[MWMUIManager shared] setupUI]; } @catch (NSException *e) { NSLog(@"[MWM] UI: %@", e); }
        return;
    }
    if (g_il2cppReady) return;
    void *d = i_domain_get();
    if (!d) { snprintf(g_diag, sizeof(g_diag), "Status: domain null"); return; }
    i_thread_attach(d);
    if (resolveIl2Cpp()) NSLog(@"[MWM] ready");
    @try { [[MWMUIManager shared] setupUI]; } @catch (NSException *e) { NSLog(@"[MWM] UI: %@", e); }
}

static void pollUntilArmed(int attempt) {
    static BOOL running = NO;
    if (attempt == 0) {
        if (running) return;
        running = YES;
    }
    int64_t delay = (attempt == 0) ? 2 * (int64_t)NSEC_PER_SEC : (int64_t)NSEC_PER_SEC;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try { tick(); } @catch (NSException *e) { NSLog(@"[MWM] tick: %@", e); }
        }
        // Keep going until the overlay exists: the app may still be inactive when
        // the first few ticks run, and a single early failure must not be final.
        BOOL uiReady = [MWMUIManager shared].host != nil;
        if (!g_il2cppReady && attempt < 180) pollUntilArmed(attempt + 1);
        else if (!uiReady && attempt < 400) pollUntilArmed(attempt + 1);
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
    // TrollFools may inject into UnityFramework *after* didFinishLaunching already fired,
    // in which case the notification above never arrives. Start polling immediately too;
    // pollUntilArmed only retries until armed, so a double start is harmless.
    pollUntilArmed(0);
}
