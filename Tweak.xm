// Tweak.xm — Race Toolkit (iOS, il2cpp / UnityFramework)
//
// Every hook below is a verified function start in UnityFramework.i64 (imagebase 0, arm64),
// signature taken from the Il2CppDumper script.json:
//
//   0x53D8430  void  GameGoState::ImpEnter()                        race start marker
//   0x9CF33DC  void  SingleNitrogenCollect::Update(float)           nitro tick
//   0x9CF2340  uint  SingleNitrogenCollect::get_NitrogenValue()     *(uint*)(this+208)
//   0x9CF229C  float SingleNitrogenCollect::get_ProgressBarPowerValue()
//   0x50A40C4  void  EvtMini::Update(float)
//   0x50A5468  bool  EvtMini::UpdateIsCanTrigger()
//   0x50A62C8  int   EvtMini::Trigger()
//   0x50A6BA0  bool  EvtN2O::IsCanTrigger()
//   0x50A6E18  int   EvtN2O::Trigger()
//   0x50DE3D8  bool  ExtraVelocityTriggerMgr::IsCanTriggerExtraVelocity(int type)
//   0x7C6E51C  void  NssVehicleDriftCtrl::ReleaseDrifting()
//   0x7C6E664  void  NssVehicleDriftCtrl::ForceEndDrifting()
//   0x7AF9964  float NssPhyVehicleECU::ReadNormalTopMPS()          *(float*)(this+264)
//
// Build: Theos (`make package`).

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <math.h>
#import <string.h>
#import <time.h>
#import <mach-o/dyld.h>

#pragma mark - State

static BOOL   gFullNitro     = NO;
static BOOL   gFullMiniBoost = NO;
static BOOL   gAutoDriftEnd  = NO;
static float  gSpeedKmh      = 0.f;
static double gGoTime        = 0.0;

static const float    kSpeedDelaySeconds = 5.0f;
static const uint32_t kNitroMaxPower     = 1000;
static const int      kTypeN2O           = 1;
static const int      kTypeMini          = 2;

// Il2cpp field offsets, DECIMAL (as printed by Hex-Rays).
enum {
    kOffNitroCurPower   = 208,  // 0xD0 mCurPower (uint)
    kOffEvtVdAngleMax   = 116,  // 0x74 mDriftingMaxAbsVDAngle
    kOffEvtDriftingTime = 124,  // 0x7C mDriftingTime
    kOffEvtInCanTrigger = 133,  // 0x85 mInCanTriggerTime (bool)
    kOffEvtMiniVdMax    = 136,  // 0x88 mMiniBoostDriftingMaxAbsVDAngle
    kOffEvtInChecking   = 140,  // 0x8C mIsInCheckingCanTrigger (bool)
    kOffEvtCheckTime    = 144,  // 0x90 mNewCheckMiniBoostTime (float)
    kOffEvtLastDrift    = 160,  // 0xA0 mLastIsDrifting (bool)
};

#pragma mark - Trampolines

static void  (*orig_GameGo_ImpEnter)(void *);
static void  (*orig_Nitro_Update)(void *, float);
static uint32_t (*orig_Nitro_GetValue)(void *);
static float (*orig_Nitro_GetProgress)(void *);
static void  (*orig_EvtMini_Update)(void *, float);
static BOOL  (*orig_EvtMini_CanTrigger)(void *);
static int   (*orig_EvtMini_Trigger)(void *);
static BOOL  (*orig_EvtN2O_CanTrigger)(void *);
static int   (*orig_EvtN2O_Trigger)(void *);
static BOOL  (*orig_IsCanTriggerExVel)(void *, int);
static void  (*orig_Drift_Release)(void *);
static void  (*orig_Drift_ForceEnd)(void *);
static float (*orig_ECU_ReadTopMPS)(void *);

static void *g_evtMini = NULL;
static void *g_evtN2O  = NULL;

// NssVehicle layout: mIsMainPlayer @ 0xF8 (bool).
// NssVehicleDriftCtrl.mVehicle @ 0x10. NssPhyVehicleECUBase.mVehicle @ 0x18.
static inline BOOL vehicleIsMainPlayer(void *vehicle) {
    if (!vehicle) return NO;
    return *(uint8_t *)((char *)vehicle + 0xF8) != 0;
}

static inline double nowSeconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static inline BOOL speedWindowOpen(void) {
    if (gSpeedKmh <= 0.f || gGoTime <= 0.0) return NO;
    return (nowSeconds() - gGoTime) >= (double)kSpeedDelaySeconds;
}

#pragma mark - Hooks

static void hook_GoImpEnter(void *self) {
    orig_GameGo_ImpEnter(self);
    gGoTime = nowSeconds();
}

static void hook_NitroUpdate(void *self, float dt) {
    orig_Nitro_Update(self, dt);
    if (!gFullNitro || !self) return;
    void *veh = *(void **)((char *)self + 0x60);        // SingleNitrogenCollect.mVehicle
    if (!vehicleIsMainPlayer(veh)) return;
    *(uint32_t *)((char *)self + kOffNitroCurPower) = kNitroMaxPower;
}

static uint32_t hook_NitroGetValue(void *self) {
    if (gFullNitro && self &&
        vehicleIsMainPlayer(*(void **)((char *)self + 0x60))) return kNitroMaxPower;
    return orig_Nitro_GetValue(self);
}

static float hook_NitroGetProgress(void *self) {
    if (gFullNitro && self &&
        vehicleIsMainPlayer(*(void **)((char *)self + 0x60))) return 1.0f;
    return orig_Nitro_GetProgress(self);
}

// EvtMini window gate fields, forced open while the toggle is on.
static inline void armMiniWindow(void *self) {
    *(float *)   ((char *)self + kOffEvtVdAngleMax)   = 999.0f;
    *(float *)   ((char *)self + kOffEvtMiniVdMax)    = 999.0f;
    *(float *)   ((char *)self + kOffEvtDriftingTime) = 999.0f;
    *(float *)   ((char *)self + kOffEvtCheckTime)    = 0.0f;
    *(uint8_t *) ((char *)self + kOffEvtInCanTrigger) = 1;
    *(uint8_t *) ((char *)self + kOffEvtInChecking)   = 1;
    *(uint8_t *) ((char *)self + kOffEvtLastDrift)    = 1;
}

static void hook_EvtMiniUpdate(void *self, float dt) {
    orig_EvtMini_Update(self, dt);
    if (!gFullMiniBoost || !self) return;
    if (!vehicleIsMainPlayer(*(void **)((char *)self + 0x18))) return;
    g_evtMini = self;
    armMiniWindow(self);
}

// ExtraVelocityTriggerBase.mVehicle @ 0x18
static inline BOOL evtIsMainPlayer(void *evt) {
    if (!evt) return NO;
    return vehicleIsMainPlayer(*(void **)((char *)evt + 0x18));
}

static BOOL hook_EvtMiniCanTrigger(void *self) {
    if (gFullMiniBoost && evtIsMainPlayer(self)) {
        g_evtMini = self;
        armMiniWindow(self);
        return YES;
    }
    return orig_EvtMini_CanTrigger(self);
}

static int hook_EvtMiniTrigger(void *self) {
    if (gFullMiniBoost && evtIsMainPlayer(self)) g_evtMini = self;
    return orig_EvtMini_Trigger(self);
}

static BOOL hook_EvtN2OCanTrigger(void *self) {
    if (gFullNitro && evtIsMainPlayer(self)) {
        g_evtN2O = self;
        return YES;
    }
    BOOL r = orig_EvtN2O_CanTrigger(self);
    if (r) g_evtN2O = self;
    return r;
}

static int hook_EvtN2OTrigger(void *self) {
    if (gFullNitro && evtIsMainPlayer(self)) g_evtN2O = self;
    return orig_EvtN2O_Trigger(self);
}

// Single gate every boost request funnels through.
// ExtraVelocityTriggerMgr.mVehicle @ 0x68.
static BOOL hook_IsCanTriggerExVel(void *self, int type) {
    BOOL mine = self && vehicleIsMainPlayer(*(void **)((char *)self + 0x68));
    if (mine && type == kTypeMini && gFullMiniBoost) return YES;
    if (mine && type == kTypeN2O  && gFullNitro)     return YES;
    return orig_IsCanTriggerExVel(self, type);
}

// Exposed so Auto End Drift can hard-stop the drift state machine.
static void hook_DriftForceEnd(void *self) {
    orig_Drift_ForceEnd(self);
}

// Drift key released -> hard-end the drift, then fire N2O / mini boost.
static void hook_DriftRelease(void *self) {
    orig_Drift_Release(self);
    if (!gAutoDriftEnd || !self) return;

    void *dyn = *(void **)((char *)self + 0x10);        // NssVehicleDriftCtrl.mVehicle : IDynamicVehicle
    if (!dyn) return;
    void *veh = *(void **)((char *)dyn + 0x10);         // DynamicVehicle.mVehicle : IVehicle -> NssVehicle
    if (!vehicleIsMainPlayer(veh)) return;              // never touch other cars

    if (orig_Drift_ForceEnd) orig_Drift_ForceEnd(self);
    if (gFullMiniBoost && g_evtMini && orig_EvtMini_Trigger) orig_EvtMini_Trigger(g_evtMini);
    if (gFullNitro     && g_evtN2O  && orig_EvtN2O_Trigger)  orig_EvtN2O_Trigger(g_evtN2O);
}

static float hook_ReadTopMPS(void *self) {
    float base = orig_ECU_ReadTopMPS(self);
    if (!speedWindowOpen()) return base;

    void *veh = *(void **)((char *)self + 0x18);        // NssPhyVehicleECUBase.mVehicle
    if (!vehicleIsMainPlayer(veh)) return base;

    return base + gSpeedKmh / 3.6f;                     // km/h -> m/s
}

#pragma mark - Install

static uintptr_t unityFrameworkBase(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static void installHooks(void) {
    uintptr_t b = unityFrameworkBase();
    if (!b) return;

#define H(rva, repl, origp) MSHookFunction((void *)(b + (rva)), (void *)(repl), (void **)&(origp))
    H(0x53D8430, hook_GoImpEnter,       orig_GameGo_ImpEnter);
    H(0x9CF33DC, hook_NitroUpdate,      orig_Nitro_Update);
    H(0x9CF2340, hook_NitroGetValue,    orig_Nitro_GetValue);
    H(0x9CF229C, hook_NitroGetProgress, orig_Nitro_GetProgress);
    H(0x50A40C4, hook_EvtMiniUpdate,    orig_EvtMini_Update);
    H(0x50A5468, hook_EvtMiniCanTrigger, orig_EvtMini_CanTrigger);
    H(0x50A62C8, hook_EvtMiniTrigger,   orig_EvtMini_Trigger);
    H(0x50A6BA0, hook_EvtN2OCanTrigger, orig_EvtN2O_CanTrigger);
    H(0x50A6E18, hook_EvtN2OTrigger,    orig_EvtN2O_Trigger);
    H(0x50DE3D8, hook_IsCanTriggerExVel, orig_IsCanTriggerExVel);
    H(0x7C6E51C, hook_DriftRelease,     orig_Drift_Release);
    H(0x7C6E664, hook_DriftForceEnd,    orig_Drift_ForceEnd);
    H(0x7AF9964, hook_ReadTopMPS,       orig_ECU_ReadTopMPS);
#undef H
}

#pragma mark - UI

@interface RCRaceToolkitMenu : NSObject
@property (nonatomic, strong) UIWindow *window;
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

    self.window = [[UIWindow alloc] initWithFrame:screen];
    self.window.windowLevel = UIWindowLevelAlert + 100;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    [self.window makeKeyAndVisible];

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

    CGFloat w = 300, h = 300;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2, (screen.size.height - h) / 2, w, h)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.panel.hidden = YES;
    [host addSubview:self.panel];

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
    note.text = @"Speed applies only after race start + 5s.\nAuto End Drift ends the drift and fires N2O / mini boost when the drift key is released.";
    [self.panel addSubview:note];
}

- (NSString *)speedText {
    return [NSString stringWithFormat:@"Boost speed: %d km/h (+5s)", (int)gSpeedKmh];
}

- (void)togglePanel { self.panel.hidden = !self.panel.hidden; }

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}

- (void)onNitro:(UISwitch *)s     { gFullNitro = s.isOn; }
- (void)onMini:(UISwitch *)s      { gFullMiniBoost = s.isOn; }
- (void)onAutoDrift:(UISwitch *)s { gAutoDriftEnd = s.isOn; }

- (void)onSpeedChanged:(UISlider *)s {
    gSpeedKmh = s.value;
    self.speedLabel.text = [self speedText];
}

@end

#pragma mark - Bootstrap

static void startToolkit(void) {
    if (!unityFrameworkBase()) return;
    installHooks();
    dispatch_async(dispatch_get_main_queue(), ^{
        gMenu = [RCRaceToolkitMenu new];
        [gMenu build];
    });
}

__attribute__((constructor)) static void RCInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ startToolkit(); });
}
