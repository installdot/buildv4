// RT — Speed Drifters helper (IL2CPP metadata hook, zero code patch)
//
// Gia tốc ẩn | Auto end drift + kill drift vector | Drift no-friction
// Inf miniboost | Drift nitro gain

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <math.h>
#import <string.h>
#import <time.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>

// ───────────────────────────── LOG ─────────────────────────────
static int gLFd = -1;

static void LOpen(void) {
    if (gLFd >= 0) return;
    NSString *d = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                  ?: NSTemporaryDirectory();
    gLFd = open([[d stringByAppendingPathComponent:@"rt.log"] fileSystemRepresentation],
                O_WRONLY | O_CREAT | O_APPEND, 0644);
}

static void L(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void L(const char *fmt, ...) {
    LOpen();
    if (gLFd < 0) return;
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    char b[1024];
    int n = snprintf(b, sizeof(b), "[%ld.%03ld] ", ts.tv_sec % 100000, ts.tv_nsec / 1000000);
    va_list ap; va_start(ap, fmt);
    vsnprintf(b + n, sizeof(b) - n, fmt, ap);
    va_end(ap);
    strcat(b, "\n");
    write(gLFd, b, strlen(b));
}

// ───────────────────────────── CONFIG ─────────────────────────────
static BOOL  cAccel        = NO;    // gia tốc ẩn
static float cAccelKmh     = 30.f;  // 0..120
static BOOL  cAutoEndDrift = YES;   // thả nút → ngắt drift + kill vector ngang
static BOOL  cDriftSlide   = YES;   // drift không giảm tốc
static BOOL  cInfMini      = NO;    // inf miniboost
static BOOL  cNitroGain    = NO;    // hồi nitro drift nhiều hơn
static BOOL  cAutoNavigate = NO;
static float cNitroRate    = 300.f; // 0..1000 %
static float cNavStr       = 0.60f;

static void CfgSave(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:cAccel forKey:@"rt_acc"];       [d setFloat:cAccelKmh forKey:@"rt_accK"];
    [d setBool:cAutoEndDrift forKey:@"rt_end"];[d setBool:cDriftSlide forKey:@"rt_slide"];
    [d setBool:cInfMini forKey:@"rt_mini"];    [d setBool:cNitroGain forKey:@"rt_nit"];
    [d setFloat:cNitroRate forKey:@"rt_nitR"];[d setBool:cAutoNavigate forKey:@"rt_nav"];[d setFloat:cNavStr forKey:@"rt_navS"];
    [d synchronize];
}
static void CfgLoad(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:@"rt_acc"])   cAccel     = [d boolForKey:@"rt_acc"];
    if ([d floatForKey:@"rt_accK"])   cAccelKmh  = [d floatForKey:@"rt_accK"];
    if ([d objectForKey:@"rt_end"])   cAutoEndDrift = [d boolForKey:@"rt_end"];
    if ([d objectForKey:@"rt_slide"]) cDriftSlide   = [d boolForKey:@"rt_slide"];
    if ([d objectForKey:@"rt_mini"])  cInfMini      = [d boolForKey:@"rt_mini"];
    if ([d objectForKey:@"rt_nit"])   cNitroGain    = [d boolForKey:@"rt_nit"];
    if ([d floatForKey:@"rt_nitR"])   cNitroRate    = [d floatForKey:@"rt_nitR"];
    if ([d objectForKey:@"rt_nav"])   cAutoNavigate = [d boolForKey:@"rt_nav"];
    if ([d floatForKey:@"rt_navS"])   cNavStr       = [d floatForKey:@"rt_navS"];
}

// ───────────────────────────── STATE ─────────────────────────────
typedef struct { float x, y, z; } V3;

static double gGoT      = 0;      // race start
static BOOL   gPrevDrft = NO;
static double gNextTick = 0;      // 10 Hz il2cpp work
static double gNextNit  = 0;      // ~60 Hz nitro add

static void *g_domain = nil;
static void *(*fpAttach)(void*) = NULL;
static void *gVeh = nil;          // IVehicle (main player)
static void *gEcu = nil;          // NssPhyVehicleECU
static void *gInp = nil;          // InputModule
static void *gRoad = nil;         // IRoadMap
static void *gNG = nil;           // INitrogenCollectMgr
static void *gLastTP = nil;

// PowerChain
#define PC_EXKMH   0x44
#define PC_EXTORQ  0x48
#define PC_VEH     0x10
// ECU
#define ECU_STATE  0x10
// NitrogenCollectMgr → ISingleNitrogenCollect
#define NG_SINGLE  0x60
#define SN_POW     0xD0   // uint mCurPower 0..999

// ───────────────────────────── IL2CPP ─────────────────────────────
typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct { void *ptr; const void *method; } VID;

static Il2CppDomain *(*fpDomain)(void);
static const Il2CppAssembly **(*fpAsms)(const Il2CppDomain *, size_t *);
static const Il2CppImage *(*fpImage)(const Il2CppAssembly *);
static Il2CppClass *(*fpClass)(const Il2CppImage *, const char *, const char *);
static const MethodInfo *(*fpMeth)(Il2CppClass *, const char *, int);
static Il2CppClass *(*fpParent)(Il2CppClass *);
static void *(*fpStr)(const char *);

static uintptr_t Base(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
        if (strstr(_dyld_get_image_name(i) ?: "", "UnityFramework"))
            return (uintptr_t)_dyld_get_image_header(i);
    return 0;
}

static BOOL ApiInit(void) {
    static BOOL done = NO;
    if (done) return YES;
    void *h = RTLD_DEFAULT;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) { h = dlopen(n, RTLD_NOW | RTLD_NOLOAD); break; }
    }
    if (!h) return NO;
    #define G(v, sym) *(void **)&v = dlsym(h, sym); if (!v) return NO;
    G(fpDomain, "il2cpp_domain_get")
    G(fpAsms,   "il2cpp_domain_get_assemblies")
    G(fpImage,  "il2cpp_assembly_get_image")
    G(fpClass,  "il2cpp_class_from_name")
    G(fpMeth,   "il2cpp_class_get_method_from_name")
    G(fpParent, "il2cpp_class_get_parent")
    G(fpStr,    "il2cpp_string_new")
    G(fpAttach, "il2cpp_thread_attach")
    G(i_ocls,   "il2cpp_object_get_class")
    #undef G
    done = YES;
    return YES;
}

static Il2CppClass *FindClass(const char *ns, const char *nm) {
    if (!fpDomain) return NULL;
    Il2CppDomain *d = fpDomain();
    if (!d) return NULL;
    size_t n = 0;
    const Il2CppAssembly **a = fpAsms(d, &n);
    if (!a) return NULL;
    for (size_t i = 0; i < n; i++) {
        const Il2CppImage *img = fpImage(a[i]);
        if (!img) continue;
        Il2CppClass *k = fpClass(img, ns ?: "", nm);
        if (k) return k;
    }
    return NULL;
}

// method pointer theo tên, walk parent nếu không thấy
static void *MP(Il2CppClass *k, const char *nm, int argc) {
    if (!k) return NULL;
    const MethodInfo *m = fpMeth(k, nm, argc);
    if (m) return *(void **)m;
    Il2CppClass *cur = k;
    for (int i = 0; i < 10 && fpParent; i++) {
        cur = fpParent(cur);
        if (!cur) break;
        m = fpMeth(cur, nm, argc);
        if (m) return *(void **)m;
    }
    return NULL;
}

// vtable hook — ghi methodPointer + vtable slot, không đụng __TEXT
static void *Hook(const char *ns, const char *cls, const char *mname, int argc, void *repl) {
    Il2CppClass *k = FindClass(ns, cls);
    if (!k) { L("hook: class %s missing", cls); return NULL; }
    const MethodInfo *m = fpMeth(k, mname, argc);
    if (!m) { L("hook: %s::%s(%d) missing", cls, mname, argc); return NULL; }
    void *orig = *(void **)m;
    *(void **)m = repl;
    uint16_t slot = *(uint16_t *)((char *)m + 88);
    uint16_t vc   = *(uint16_t *)((char *)k + 306);
    if (slot < vc) ((VID *)((char *)k + 336))[slot].ptr = repl;
    uintptr_t b = Base();
    L("hook: %s::%s rva=0x%lx", cls, mname,
      orig && b ? (unsigned long)((uintptr_t)orig - b) : 0UL);
    return orig;
}

static void *GetM(const char *ns, const char *cls, const char *mname, int argc) {
    return MP(FindClass(ns, cls), mname, argc);
}

// ───────────────────────────── ORIGINALS ─────────────────────────────
static void (*o_GoEnter)(void *, const void *);
static void (*o_PcUpdate)(void *, float, const void *);
static void (*o_DriftDamp)(void *, float, float, int, float, const void *);
static void (*o_DriftRel)(void *, const void *);
static void (*o_XvUpdate)(void *, float, const void *);

static void  (*pMini)(void *, int) = NULL;                    // static
static void  (*pSetKey)(void *, int, unsigned char) = NULL;   // instance
static int   (*pKeyFlags)(void *) = NULL;                     // instance
static V3    (*pLinVel)(void *) = NULL;                       // native wrapper
static void  (*pSetVel)(void *, float, float, float) = NULL;  // native
static V3    (*pFwd)(void *) = NULL;                          // IVehicle
static V3    (*pPos)(void *) = NULL;
static void *(*pNearest)(void *, float, float, float, float) = NULL;
static void *(*pInst)(void) = NULL;
static void *(*pMod)(void *, void *, void *) = NULL;
static void *(*pMyVeh)(void) = NULL;
static void *(*pMgrByUid)(void *, unsigned long long) = NULL;
static void *(*pDynVeh)(void *) = NULL;
static void *(*pGetDir)(void *) = NULL;
static Il2CppClass *(*i_ocls)(void*) = NULL;

static inline double now2(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// ───────────────────────────── HOOKS ─────────────────────────────
static void Tick10(void);   // fwd
static double now2(void);

// race start → mở cửa boost 5s
static void h_GoEnter(void *self, const void *mi) {
    if (o_GoEnter) o_GoEnter(self, mi);
    gGoT = now2();
    gNextNit = 0;
    gPrevDrft = NO;
    L("race go");
}



// PowerChain::Update — gia tốc ẩn + nitro gain + heartbeat 10Hz
static void h_PcUpdate(void *self, float dt, const void *mi) {
    if (o_PcUpdate) o_PcUpdate(self, dt, mi);
    if (!self) return;

    // gia tốc ẩn: mExtraKMPH — extra velocity channel sẵn có, km/h UI không đổi
    if (cAccel && cAccelKmh > 0.f && gGoT > 0 && now2() - gGoT >= 5.0) {
        *(float *)((char *)self + PC_EXKMH)  = cAccelKmh;
        *(float *)((char *)self + PC_EXTORQ) = cAccelKmh * 0.35f;
    }

    // nitro gain: cộng mCurPower theo % mỗi frame (60Hz)
    if (cNitroGain && gNG && now2() >= gNextNit) {
        void *sn = *(void **)((char *)gNG + NG_SINGLE);
        if (sn) {
            uint32_t cur = *(uint32_t *)((char *)sn + SN_POW);
            if (cur < 999) {
                uint32_t add = (uint32_t)(10.f * cNitroRate / 100.f);  // ~60fps → 10 frames/s chunk
                if (add < 2) add = 2;
                uint32_t nv = cur + add;
                *(uint32_t *)((char *)sn + SN_POW) = nv > 999 ? 999 : nv;
            }
        }
        gNextNit = now2() + 0.05;
    }

    // heartbeat 10Hz — chỉ chạy khi trong race
    static double nxt = 0;
    double t = now2();
    if (t < nxt || gGoT <= 0) return;
    nxt = t + 0.1;
    Tick10();
}

// DriftingSlideVelDamping — chặn ma sát drift
static void h_DriftDamp(void *self, float curMPS, float coef, int st, float dt, const void *mi) {
    if (cDriftSlide) return;
    if (o_DriftDamp) o_DriftDamp(self, curMPS, coef, st, dt, mi);
}

// ReleaseDrifting — auto end + kill drift vector
static void h_DriftRel(void *self, const void *mi) {
    if (o_DriftRel) o_DriftRel(self, mi);
    if (!cAutoEndDrift || !self) return;

    // dyn = NssVehicleDriftCtrl.mVehicle @0x10 → phyCtrl @0x40 → phyHandle @0x18
    void *dyn = *(void **)((char *)self + 0x10);
    if (!dyn) return;
    void *phy = *(void **)((char *)dyn + 0x40);
    if (!phy) return;
    void *ent = *(void **)((char *)phy + 0x18);
    if (!ent || !pLinVel || !pSetVel || !pFwd || !gVeh) return;

    V3 v = pLinVel(ent);
    V3 f = pFwd(gVeh);
    float fl = sqrtf(f.x * f.x + f.z * f.z);
    if (fl < 1e-4f) return;
    f.x /= fl; f.z /= fl;
    float sp = v.x * f.x + v.z * f.z;          // thành phần tiến
    pSetVel(ent, f.x * sp, v.y, f.z * sp);     // triệt tiêu vector ngang
    L("drift-end align sp=%.0f", sp);
}

// ExtraVelocityTriggerMgr::Update — inf miniboost
static void h_XvUpdate(void *self, float dt, const void *mi) {
    if (o_XvUpdate) o_XvUpdate(self, dt, mi);
    if (!cInfMini || !self || !pMini) return;
    pMini(self, 2);   // Mini
    pMini(self, 3);   // Air
    pMini(self, 11);  // FallingGround
}

// ───────────────────────────── 10Hz WORK ─────────────────────────────
static void Tick10(void) {
    // refresh vehicle
    if (pMyVeh) gVeh = pMyVeh();
    if (!gVeh) { gEcu = gInp = gRoad = gNG = gLastTP = nil; gPrevDrft = NO; return; }

    // modules
    if ((!gInp || !gRoad || !gNG) && pInst && pMod && fpStr) {
        void *gp = pInst();
        if (gp) {
            if (!gInp)  gInp  = pMod(gp, fpStr("InputModule"), nil);
            if (!gRoad) gRoad = pMod(gp, fpStr("RoadMap"), nil);
        }
    }
    // nitrogen mgr qua PlayVehicleModule.GetNitrogenCollectMgr(uid)
    if (!gNG && pMgrByUid && fpStr) {
        void *gp = pInst ? pInst() : nil;
        void *pvm = gp ? pMod(gp, fpStr("PlayVehicleModule"), nil) : nil;
        if (pvm) {
            void *mUid = MP((Il2CppClass *)i_ocls(gVeh), "get_UID", 0);
            if (mUid) {
                unsigned long long uid = ((unsigned long long(*)(void *))mUid)(gVeh);
                gNG = pMgrByUid(pvm, uid);
            }
        }
    }
    // ECU
    if (!gEcu && pDynVeh) {
        void *dv = pDynVeh(gVeh);
        if (dv) gEcu = *(void **)((char *)dv + 0x18);   // DynamicVehicle.mECU @0x18
    }

    // ---- auto end drift: phát hiện thả nút drift ----
    if (cAutoEndDrift && gInp && pKeyFlags && gEcu) {
        int kf = pKeyFlags(gInp);
        bool dk = (kf >> 8) & 1;
        if (gPrevDrft && !dk) {
            int st = *(int *)((char *)gEcu + ECU_STATE);
            if (st == 2) {   // Drifting
                void *fp = GetM("", "VehicleFast", "ForceEndDrifting", 1);
                if (fp) ((void (*)(void *))fp)(gVeh);
                // kill drift vector luôn (hook_DriftRel chỉ chạy khi game tự gọi Release)
                void *dv = pDynVeh ? pDynVeh(gVeh) : nil;
                if (dv) {
                    void *phy = *(void **)((char *)dv + 0x40);
                    if (phy) {
                        void *ent = *(void **)((char *)phy + 0x18);
                        if (ent && pLinVel && pSetVel && pFwd) {
                            V3 v = pLinVel(ent);
                            V3 f = pFwd(gVeh);
                            float fl = sqrtf(f.x * f.x + f.z * f.z);
                            if (fl > 1e-4f) {
                                f.x /= fl; f.z /= fl;
                                float sp = v.x * f.x + v.z * f.z;
                                pSetVel(ent, f.x * sp, v.y, f.z * sp);
                            }
                        }
                    }
                }
                L("auto end drift");
            }
        }
        gPrevDrft = dk;
    }

    // ---- auto navigate ----
    if (pNearest && gRoad && pSetKey && gVeh && pFwd && pPos) {
        V3 p = pPos(gVeh);
        V3 f = pFwd(gVeh);
        float fl = sqrtf(f.x * f.x + f.z * f.z);
        if (fl > 1e-4f) {
            void *tp = pNearest(gRoad, p.x, p.y, p.z, 3.4e38f);
            if (tp && tp != gLastTP) {
                gLastTP = tp;
                if (!pGetDir) pGetDir = (void *(*)(void *))MP((Il2CppClass *)i_ocls(tp), "get_Direction", 0);
                if (pGetDir) {
                    V3 d = ((V3(*)(void *))pGetDir)(tp);
                    float cx = f.x * d.z - f.z * d.x;
                    float dot = f.x * d.x + f.z * d.z;
                    float deg = atan2f(cx, dot) * 57.29578f;
                    float dead = 30.f - 28.f * cNavStr;
                    pSetKey(gInp, 1, deg < -dead);
                    pSetKey(gInp, 2, deg >  dead);
                }
            }
        }
    }
}

// ───────────────────────────── INSTALL ─────────────────────────────
static BOOL gHooked = NO;

static void Install(void) {
    if (gHooked) return;
    gHooked = YES;

    o_GoEnter = (void (*)(void *, const void *))
        Hook("", "GameGoState", "ImpEnter", 0, (void *)h_GoEnter);
    Hook("", "RaceKingGameGoState", "ImpEnter", 0, (void *)h_GoEnter);
    Hook("", "FreePracticeGameGoState", "ImpEnter", 0, (void *)h_GoEnter);
    Hook("", "ActionSpeedGameGoState", "ImpEnter", 0, (void *)h_GoEnter);

    o_PcUpdate = (void (*)(void *, float, const void *))
        Hook("", "NssPhyVehiclePowerChain", "Update", 1, (void *)h_PcUpdate);

    o_DriftDamp = (void (*)(void *, float, float, int, float, const void *))
        Hook("", "NssVehicleDriftHelper", "DriftingSlideVelDamping", 4, (void *)h_DriftDamp);

    o_DriftRel = (void (*)(void *, const void *))
        Hook("", "NssVehicleDriftCtrl", "ReleaseDrifting", 0, (void *)h_DriftRel);

    o_XvUpdate = (void (*)(void *, float, const void *))
        Hook("", "ExtraVelocityTriggerMgr", "Update", 1, (void *)h_XvUpdate);

    // ---- resolve pointers ----
    pMini = (void (*)(void *, int))GetM("", "ExtraVelocityTriggerMgr", "ForceCanTriggerOnce", 1);
    pInst = (void *(*)(void))GetM("", "GamePub", "GetInstance", 0);
    pMod  = (void *(*)(void *, void *, void *))GetM("", "GamePub", "GetModuleByName", 2);
    pMyVeh = (void *(*)(void))GetM("", "VehicleFast", "GetMyVehicle", 0);
    {
        void *k = (void *)FindClass("", "VehicleInputCtrl");
        pKeyFlags = (int (*)(void *))MP((Il2CppClass *)k, "get_KeyFlags", 0);
    }
    {
        void *k = (void *)FindClass("", "InputModule");
        pSetKey = (void (*)(void *, int, unsigned char))MP((Il2CppClass *)k, "SetKey", 2);
    }
    {
        void *k = (void *)FindClass("", "NssVehicle");
        pFwd = (V3 (*)(void *))MP((Il2CppClass *)k, "get_Forward", 0);
        pPos = (V3 (*)(void *))MP((Il2CppClass *)k, "get_Position", 0);
        pDynVeh = (void *(*)(void *))MP((Il2CppClass *)k, "GetDynamicVehicle", 0);
    }
    {
        void *k = (void *)FindClass("", "PlayVehicleModule");
        pMgrByUid = (void *(*)(void *, unsigned long long))MP((Il2CppClass *)k, "GetNitrogenCollectMgr", 1);
    }
    {
        uintptr_t b = Base();
        if (b) {
            pLinVel = (V3 (*)(void *))(b + 0xCF16850);   // PHY_EntityGetLinearVelocity(ent)
            pSetVel = (void (*)(void *, float, float, float))(b + 0xCF17608);  // Set(ent,V3)
        }
    }
    {
        void *k = (void *)FindClass("", "RoadMap");
        pNearest = (void *(*)(void *, float, float, float, float))MP((Il2CppClass *)k, "GetNearestTrackPoint", 2);
    }

    L("install done: mini=%p key=%p setk=%p fwd=%p lin=%p setv=%p near=%p mgr=%p",
      pMini, pKeyFlags, pSetKey, pFwd, pLinVel, pSetVel, pNearest, pMgrByUid);
}

// ───────────────────────────── UI — native list, no icon ─────────────────────────────
// Layout: pill button "RT" — panel dạng danh sách phẳng, kicker + controls,
//         không icon, card kéo được bằng header.

@interface RTWindow : UIWindow
@end
@implementation RTWindow
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)ev {
    UIView *v = [super hitTest:pt withEvent:ev];
    if (!v || v == self || v == self.rootViewController.view) return nil;
    return v;
}
- (BOOL)canBecomeKeyWindow { return NO; }
@end

@interface RTMenu : NSObject
@property (strong) RTWindow *win;
@property (strong) UIView   *pill;    // nút nhỏ
@property (strong) UIView   *panel;   // panel list
@property (strong) UILabel  *status;
@property (assign) CGPoint  pillDragStart;
@property (assign) BOOL     dragging;
@end

static RTMenu *menu = nil;

@implementation RTMenu

// helpers — label / switch / slider theo hàng
- (UILabel *)lbl:(NSString *)t y:(CGFloat)y sz:(CGFloat)fs col:(UIColor *)c {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 170, 20)];
    l.text = t; l.textColor = c ?: [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:fs weight:UIFontWeightRegular];
    return l;
}

- (UISwitch *)mkSw:(CGFloat)y val:(BOOL)v act:(SEL)a {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(198, y - 3, 44, 26)];
    sw.transform = CGAffineTransformMakeScale(0.72, 0.72);
    sw.onTintColor = [UIColor colorWithRed:0.92 green:0.49 blue:0.13 alpha:1];
    sw.on = v;
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:sw];
    return sw;
}
- (UISlider *)mkSl:(CGFloat)y mn:(float)mn mx:(float)mx val:(float)v act:(SEL)a {
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(16, y, 234, 26)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = v;
    sl.tintColor = [UIColor colorWithRed:0.92 green:0.49 blue:0.13 alpha:1];
    [sl addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:sl];
    return sl;
}
- (UILabel *)mkRow:(CGFloat)y t:(NSString *)t {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 178, 20)];
    l.text = t; l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:12];
    [self.panel addSubview:l];
    return l;
}
- (UILabel *)mkSub:(CGFloat)y t:(NSString *)t {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 178, 16)];
    l.text = t; l.textColor = UIColor.lightGrayColor;
    l.font = [UIFont systemFontOfSize:10];
    [self.panel addSubview:l];
    return l;
}

- (void)build {
    CGRect sc = UIScreen.mainScreen.bounds;
    self.win = [[RTWindow alloc] initWithFrame:sc];
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            self.win.windowScene = (UIWindowScene *)s;
            break;
        }
    }
    self.win.windowLevel = UIWindowLevelAlert - 1;
    self.win.backgroundColor = UIColor.clearColor;
    self.win.rootViewController = [UIViewController new];
    self.win.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.win.hidden = NO;

    // pill "RT" — kéo + tap
    self.pill = [[UIView alloc] initWithFrame:CGRectMake(sc.size.width - 58, 64, 44, 30)];
    self.pill.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    self.pill.layer.cornerRadius = 6;
    self.pill.layer.borderWidth = 0.5;
    self.pill.layer.borderColor = [UIColor colorWithRed:0.92 green:0.49 blue:0.13 alpha:0.8].CGColor;
    UILabel *t = [[UILabel alloc] initWithFrame:self.pill.bounds];
    t.text = @"RT"; t.textAlignment = NSTextAlignmentCenter;
    t.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    t.textColor = [UIColor colorWithRed:0.92 green:0.49 blue:0.13 alpha:1];
    t.userInteractionEnabled = NO;
    [self.pill addSubview:t];
    [self.pill addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePanel)]];
    UIPanGestureRecognizer *pp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPill:)];
    pp.maximumNumberOfTouches = 1;
    [self.pill addGestureRecognizer:pp];
    [self.win addSubview:self.pill];

    // panel
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(20, 90, 250, 356)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.03 alpha:0.95];
    self.panel.layer.cornerRadius = 8;
    self.panel.layer.borderWidth = 0.5;
    self.panel.layer.borderColor = [UIColor colorWithRed:0.92 green:0.49 blue:0.13 alpha:0.4].CGColor;
    self.panel.hidden = YES;
    self.panel.userInteractionEnabled = YES;
    [self.panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];
    [self.win addSubview:self.panel];

    UILabel *hd = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 218, 18)];
    hd.text = @"RACE TOOLKIT";
    hd.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    hd.textColor = [UIColor colorWithRed:0.92 green:0.49 blue:0.13 alpha:1];
    [self.panel addSubview:hd];
    UIView *ln = [[UIView alloc] initWithFrame:CGRectMake(16, 32, 218, 0.5)];
    ln.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    [self.panel addSubview:ln];

    CGFloat y = 40;
    [self mkRow:y t:@"Hidden acceleration"];        [self mkSw:y val:cAccel        act:@selector(tAccel:)];  y += 28;
    [self mkSub:y t:@"Boost km/h"];                                                          y += 15;
    [self mkSl:y mn:0 mx:120 val:cAccelKmh act:@selector(sAccel:)];                          y += 32;
    [self mkRow:y t:@"Auto end drift"];             [self mkSw:y val:cAutoEndDrift act:@selector(tEnd:)];     y += 28;
    [self mkRow:y t:@"Drift no-friction"];          [self mkSw:y val:cDriftSlide  act:@selector(tSlide:)];    y += 28;
    [self mkRow:y t:@"Inf miniboost"];              [self mkSw:y val:cInfMini     act:@selector(tMini:)];     y += 28;
    [self mkRow:y t:@"Drift nitro gain"];           [self mkSw:y val:cNitroGain   act:@selector(tNitro:)];    y += 28;
    [self mkSub:y t:@"Gain %"];                                                              y += 15;
    [self mkSl:y mn:0 mx:1000 val:cNitroRate act:@selector(sNitro:)];                        y += 32;
    [self mkRow:y t:@"Auto navigate"];              [self mkSw:y val:cAutoNavigate act:@selector(tNav:)];     y += 28;
    [self mkSub:y t:@"Nav strength"];                                                        y += 15;
    [self mkSl:y mn:0 mx:1 val:cNavStr act:@selector(sNav:)];                                y += 32;
}

- (void)togglePanel { self.panel.hidden = !self.panel.hidden; }
- (void)dragPill:(UIPanGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateChanged) return;
    CGPoint t = [g translationInView:self.pill.superview];
    CGRect b = UIScreen.mainScreen.bounds;
    CGPoint c = self.pill.center;
    c.x = MAX(28, MIN(b.size.width - 28, c.x + t.x));
    c.y = MAX(24, MIN(b.size.height - 24, c.y + t.y));
    self.pill.center = c;
    [g setTranslation:CGPointZero inView:self.pill.superview];
}
- (void)dragPanel:(UIPanGestureRecognizer *)g {
    static CGPoint start; static BOOL ok = NO;
    if (g.state == UIGestureRecognizerStateBegan) {
        CGPoint p = [g locationInView:self.panel];
        ok = (p.y <= 36);
        start = self.panel.center;
    }
    if (!ok) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:self.panel.superview];
        CGRect b = UIScreen.mainScreen.bounds;
        CGPoint c = start;
        c.x = MAX(self.panel.bounds.size.width/2, MIN(b.size.width - self.panel.bounds.size.width/2, c.x + t.x));
        c.y = MAX(self.panel.bounds.size.height/2, MIN(b.size.height - self.panel.bounds.size.height/2, c.y + t.y));
        self.panel.center = c;
    }
}
- (void)tAccel:(UISwitch *)s  { cAccel = s.isOn; CfgSave(); }
- (void)sAccel:(UISlider *)s  { cAccelKmh = s.value; CfgSave(); }
- (void)tEnd:(UISwitch *)s    { cAutoEndDrift = s.isOn; CfgSave(); }
- (void)tSlide:(UISwitch *)s  { cDriftSlide = s.isOn; CfgSave(); }
- (void)tMini:(UISwitch *)s   { cInfMini = s.isOn; CfgSave(); }
- (void)tNitro:(UISwitch *)s  { cNitroGain = s.isOn; CfgSave(); }
- (void)sNitro:(UISlider *)s  { cNitroRate = s.value; CfgSave(); }
- (void)tNav:(UISwitch *)s    { cAutoNavigate = s.isOn; CfgSave(); }
- (void)sNav:(UISlider *)s    { cNavStr = s.value; CfgSave(); }
@end

// ───────────────────────────── BOOTSTRAP ─────────────────────────────
static RTMenu *menuRef = nil;
static BOOL gMenuMade = NO;


static void BuildMenu(void) {
    if (gMenuMade) return;
    gMenuMade = YES;
    @try {
        menuRef = [RTMenu new];
        [menuRef build];
        L("menu ok");
    } @catch (NSException *e) {
        menuRef = nil; gMenuMade = NO;
        L("menu fail: %s", e.reason.UTF8String ?: "?");
    }
}

static void TryHooks(void) {
    if (gHooked) return;
    if (!pInst) {
        void *k = (void *)FindClass("", "GamePub");
        if (!k) return;
        pInst = (void *(*)(void))MP((Il2CppClass *)k, "GetInstance", 0);
        if (!pInst) return;
    }
    void *gp = pInst();
    if (!gp) return;   // lobby chưa ready → thử lại
    L("GamePub ready");
    Install();
}

static void Poll(void) {
    static int tries = 0;
    if (!ApiInit()) {
        if (++tries > 120) { L("api timeout"); BuildMenu(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ Poll(); });
        return;
    }
    if (!g_domain) { g_domain = fpDomain(); if (g_domain) fpAttach(g_domain); }
    if (!g_domain) {
        if (++tries > 120) { L("domain timeout"); BuildMenu(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ Poll(); });
        return;
    }
    L("il2cpp ready");
    BuildMenu();
    TryHooks();   // nếu GamePub ready → hook ngay; nếu không → h_PcUpdate gate sẽ tự thử
}

__attribute__((constructor))
static void RTEntry(void) {
    LOpen();
    CfgLoad();
    L("RT boot pid=%d", getpid());
    // attach domain cần thread — làm trên background sau khi il2cpp load xong
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ Poll(); });
}
