// Tweak.xm — Race Toolkit v3 (IL2CPP VTable Hook)
//
// 1. Drift không mất tốc: hook DriftingSlideVelDamping (0x7C713DC) — chặn ma sát native
// 2. Gia tốc ẩn: mExtraKMPH/mExtraTorque trên PowerChain — km/h UI KHÔNG đổi
// 3. Drift trượt: mDriftColliderLossRate=0 + SetAngularVel zero khi drift (slider)
// 4. Tự động điều hướng: RoadMap.GetNearestTrackPoint + SetKey trái/phải (slider độ mạnh)
// 5. Hồi nitro drift %: cộng thẳng mCurPower (0xD0) trên SingleNitrogenCollect mỗi frame
// 6. End Drift phóng: khi thả drift → đọc vận tốc qua PHY_EntityGetLinearVelocity,
//    chiếu lên hướng xe → SetLinearVelocity chỉ giữ thành phần tiến (tiêu diệt drift ngang)
// 7. No2 kéo dài: ForceDelayEndExtraVelocity(N2O) định kỳ
// 8. Inf Mini Boost: ForceCanTriggerOnce(Mini/Air/FallingGround)

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

static BOOL gDriftNoSlow    = YES;   // drift không ma sát
static float gDriftSlide    = 0.60f; // 0..1 độ trượt khi drift
static BOOL gSpeedBoost     = NO;
static float gSpeedKmh      = 0.f;   // extra km/h ẩn (không đổi km/h UI)
static BOOL gAutoNavigate   = YES;   // tự điều hướng track line
static float gNavStrength   = 0.60f; // 0..1
static BOOL gNavInvert      = NO;
static BOOL gNitroBoost     = NO;    // hồi nitro drift %
static float gNitroPct      = 200.f; // 0..1000%
static BOOL gEndDriftLaunch = YES;   // thả drift → chỉ giữ vector tiến
static BOOL gProlongN2O     = YES;
static BOOL gFullMiniBoost  = NO;
static BOOL gAutoDriftEnd   = YES;
static double gGoTime       = 0.0;
static double gNextN2O      = 0.0;
static double gNextNitroAdd = 0.0;
static BOOL   gPrevDriftKey = NO;
static BOOL   gHooksInstalled = NO;

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
typedef struct { float x, y, z; } V3;

static Il2CppDomain *(*i_domain)(void) = NULL;
static const Il2CppAssembly **(*i_asms)(const Il2CppDomain *, size_t *) = NULL;
static const Il2CppImage *(*i_img)(const Il2CppAssembly *) = NULL;
static Il2CppClass *(*i_cls)(const Il2CppImage *, const char *, const char *) = NULL;
static const MethodInfo *(*i_meth)(Il2CppClass *, const char *, int) = NULL;
static void *(*i_parent)(Il2CppClass *) = NULL;
static void *(*i_strNew)(const char *) = NULL;

static uintptr_t unityBase(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static BOOL rtInitApi(void) {
    if (i_domain) return YES;
    void *h = RTLD_DEFAULT;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) { h = dlopen(n, RTLD_NOW | RTLD_NOLOAD); break; }
    }
    *(void **)&i_domain = dlsym(h ?: RTLD_DEFAULT, "il2cpp_domain_get");
    *(void **)&i_asms = dlsym(h ?: RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    *(void **)&i_img = dlsym(h ?: RTLD_DEFAULT, "il2cpp_assembly_get_image");
    *(void **)&i_cls = dlsym(h ?: RTLD_DEFAULT, "il2cpp_class_from_name");
    *(void **)&i_meth = dlsym(h ?: RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    *(void **)&i_parent = dlsym(h ?: RTLD_DEFAULT, "il2cpp_class_get_parent");
    *(void **)&i_strNew = dlsym(h ?: RTLD_DEFAULT, "il2cpp_string_new");
    if (!i_domain || !i_cls || !i_meth) return NO;
    rtLog("il2cpp: api ok");
    return YES;
}

static Il2CppClass *rtFindClass(const char *ns, const char *name) {
    if (!i_domain) return NULL;
    Il2CppDomain *d = i_domain();
    if (!d) return NULL;
    size_t n = 0;
    const Il2CppAssembly **a = i_asms(d, &n);
    if (!a || !n) return NULL;
    for (size_t i = 0; i < n; i++) {
        const Il2CppImage *img = i_img(a[i]);
        if (!img) continue;
        Il2CppClass *k = i_cls(img, ns ?: "", name);
        if (k) return k;
    }
    return NULL;
}

static void *rtMOf(void *klass, const char *name, int argc) {
    if (!klass) return NULL;
    const MethodInfo *m = i_meth(klass, name, argc);
    if (m) return *(void **)m;
    void *cur = klass;
    for (int d = 0; d < 10 && i_parent; d++) {
        cur = i_parent(cur);
        if (!cur) break;
        m = i_meth(cur, name, argc);
        if (m) return *(void **)m;
    }
    return NULL;
}

static void *rtHookMethod(const char *ns, const char *cls, const char *name,
                          int argc, void *repl) {
    Il2CppClass *k = rtFindClass(ns, cls);
    if (!k) { rtLog("il2cpp: class %s NOT FOUND", cls); return NULL; }
    const MethodInfo *m = i_meth(k, name, argc);
    if (!m) { rtLog("il2cpp: %s::%s(%d) NOT FOUND", cls, name, argc); return NULL; }
    void *orig = *(void **)m;
    *(void **)m = repl;
    uint16_t slot = *(uint16_t *)((char *)m + 88);
    uint16_t vc = *(uint16_t *)((char *)k + 306);
    if (slot < vc) ((VirtualInvokeData *)((char *)k + 336))[slot].methodPtr = repl;
    uintptr_t base = unityBase();
    rtLog("il2cpp: HOOK %s::%s (rva=0x%lx)", cls, name,
          orig && base ? (unsigned long)(orig - base) : 0UL);
    return orig;
}

static void *rtMethod(const char *ns, const char *cls, const char *name, int argc) {
    Il2CppClass *k = rtFindClass(ns, cls);
    if (!k) return NULL;
    const MethodInfo *m = i_meth(k, name, argc);
    return m ? *(void **)m : NULL;
}

#pragma mark - Originals

static void (*orig_GoImpEnter)(void *, const void *) = NULL;
static void (*orig_PowerChainUpd)(void *, float, const void *) = NULL;
static void (*orig_DriftDamp)(void *, float, float, int, float, const void *) = NULL;
static void (*orig_DriftRelease)(void *, const void *) = NULL;
static void (*orig_ExVelUpd)(void *, float, const void *) = NULL;

static void  (*pForceMini)(void *, int) = NULL;
static int   (*pForceDelayN2O)(void *, int) = NULL;
static void  (*pSetKey)(void *, int, unsigned char) = NULL;
static int   (*pGetKeyFlags)(void *) = NULL;
static void *(*pNearestTP)(void *, float, float, float, float) = NULL;
static V3    (*pGetLinVel)(void *) = NULL;          // PHY_EntityGetLinearVelocity(ent)
static void  (*pSetLinVel)(void *, float, float, float) = NULL; // (ent, x,y,z)
static V3    (*pGetVehFwd)(void *) = NULL;          // IVehicle.get_Forward
static V3    (*pGetVehPos)(void *) = NULL;
static void *(*pGetDynVeh)(void *) = NULL;
static void *(*pGetPhyCtrl)(void *) = NULL;
static void *(*pGetMgr)(void *, void *, void *) = NULL;   // PlayVehicleModule.GetNitrogenCollectMgr(uid)
static void *(*pGetMyVehicle)(void) = NULL;                // VehicleFast.GetMyVehicle()
static void *(*pGetInst)(void) = NULL;
static void *(*pGetModByName)(void *, void *, void *) = NULL;

// NitrogenCollectMgr fields
#define kNMgr_Single    0x60  // <SingleNitrogenCollect>k__BackingField
#define kSingle_CurPow  0xD0  // uint mCurPower
#define kSingle_Veh     0x60  // IVehicle mVehicle (SingleNitrogenCollect)

// PowerChain
#define kPc_ExtraKMPH   0x44
#define kPc_ExtraTorque 0x48
#define kPc_Vehicle     0x10

// VehicleInputHelper keyflags
#define kInp_Invoke 0xD8
#define kInp_Down   0xDC
#define kInp_Keys   0xE0

// ECU state offset
#define kEcu_State 0x10

static void *g_veh = nil;
static void *g_ecu = nil;
static void *g_nMgr = nil;
static void *g_input = nil;
static void *g_road = nil;
static void *g_lastTP = nil;

#pragma mark - Hooks

// 1. Race start
static void hook_GoImpEnter(void *self, const void *method) {
    if (orig_GoImpEnter) orig_GoImpEnter(self, method);
    gGoTime = nowSeconds();
    gNextN2O = 0.0;
    gNextNitroAdd = 0.0;
    gPrevDriftKey = NO;
    rtLog("race started");
}

// 2. Gia tốc ẩn (mExtraKMPH = extra velocity riêng, không đụng top speed → km/h UI giữ nguyên)
//    + N2O prolong
static void hook_PowerChainUpdate(void *self, float dt, const void *method) {
    if (orig_PowerChainUpd) orig_PowerChainUpd(self, dt, method);
    if (!self) return;

    if (gSpeedBoost && gSpeedKmh > 0.f && gGoTime > 0.0 && (nowSeconds() - gGoTime) >= 5.0) {
        *(float *)((char *)self + kPc_ExtraKMPH)   = gSpeedKmh;
        *(float *)((char *)self + kPc_ExtraTorque) = gSpeedKmh * 0.35f;
    }

    // No2 kéo dài: ForceDelayEndExtraVelocity(N2O) mỗi 0.5s
    if (gProlongN2O && pForceDelayN2O && gGoTime > 0.0 && nowSeconds() >= gNextN2O) {
        void *veh = *(void **)((char *)self + kPc_Vehicle);
        if (veh) { pForceDelayN2O(veh, 1); pForceDelayN2O(veh, 14); }
        gNextN2O = nowSeconds() + 0.5;
    }
}

// 3. Drift không mất tốc
static void hook_DriftDamping(void *self, float curMPS, float dampingCoef,
                              int stateType, float dt, const void *method) {
    if (gDriftNoSlow) return;  // chặn ma sát drift native
    if (orig_DriftDamp) orig_DriftDamp(self, curMPS, dampingCoef, stateType, dt, method);
}

// 4. Mini boost
static void hook_ExVelUpdate(void *self, float dt, const void *method) {
    if (orig_ExVelUpd) orig_ExVelUpd(self, dt, method);
    if (!gFullMiniBoost || !self) return;
    if (pForceMini) { pForceMini(self, 2); pForceMini(self, 3); pForceMini(self, 11); }
}

// 5. Auto End Drift: khi thả nút drift → lọc vector chỉ giữ hướng xe nhìn
static void hook_DriftRelease(void *self, const void *method) {
    if (orig_DriftRelease) orig_DriftRelease(self, method);
    if (!gAutoDriftEnd || !gEndDriftLaunch || !self || !g_veh) return;

    // self = NssVehicleDriftCtrl; mVehicle @0x10 (IDynamicVehicle)
    void *dyn = *(void **)((char *)self + 0x10);
    if (!dyn) return;
    void *phy = *(void **)((char *)dyn + 0x40);   // DynamicVehicle.mVehiclePhyCtrl
    if (!phy) return;
    void *ent = *(void **)((char *)phy + 0x18);   // NssPhyVehicleCtrl.mPhyHandle (IntPtr)
    if (!ent) return;

    V3 v = pGetLinVel(ent);
    V3 f = pGetVehFwd(g_veh);
    float fl = sqrtf(f.x*f.x + f.z*f.z);
    if (fl < 1e-4f) return;
    f.x /= fl; f.z /= fl;
    float speed = v.x*f.x + v.z*f.z;   // thành phần tiến theo hướng xe
    // giữ tốc độ tiến + y; triệt tiêu vector ngang (drift sideways)
    pSetLinVel(ent, f.x * speed, v.y, f.z * speed);
    rtLog("end-drift: speed=%.1f aligned", speed);
}

// 6. Per-frame il2cpp work: chạy trong PowerChain::Update (player loop thread)
static void frameWork(void) {
    // ---- capture state (cached, chỉ refresh khi null) ----
    if (pGetMyVehicle) g_veh = pGetMyVehicle();
    if (!g_veh) { g_ecu=nil; g_nMgr=nil; g_input=nil; g_road=nil; g_lastTP=nil; return; }

    if (!g_input || !g_road || !g_nMgr) {
        void *gp = pGetInst ? pGetInst() : nil;
        if (gp && pGetModByName && i_strNew) {
            if (!g_input) g_input = pGetModByName(gp, i_strNew("InputModule"), nil);
            if (!g_road)  g_road  = pGetModByName(gp, i_strNew("RoadMap"), nil);
        }
        if (!g_input) return;
    }
    if (!g_ecu && pGetDynVeh) {
        void *dyn = pGetDynVeh(g_veh);
        if (dyn) g_ecu = *(void **)((char *)dyn + 0x18);   // DynamicVehicle.mECU @0x18
    }
    if (!g_nMgr && pGetMgr && i_strNew) {
        void *gp = pGetInst ? pGetInst() : nil;
        void *pvm = gp ? pGetModByName(gp, i_strNew("PlayVehicleModule"), nil) : nil;
        if (pvm) {
            // GetNitrogenCollectMgr(ulong uid) — lấy UID từ vehicle
            void *mUid = rtMOf(*(Il2CppClass **)g_veh, "get_UID", 0);
            if (mUid) {
                unsigned long long uid = ((unsigned long long(*)(void *))((void*)mUid))();
                g_nMgr = pGetMgr(pvm, (void *)uid, nil);
            }
        }
    }
    if (!g_veh || !g_input) return;

    // ---- key state đọc thẳng field ----
    // ---- auto navigate ----
    if (gAutoNavigate && pNearestTP && g_road && pSetKey) {
        V3 p = pGetVehPos(g_veh);
        V3 f = pGetVehFwd(g_veh);
        float fl = sqrtf(f.x*f.x + f.z*f.z);
        if (fl > 1e-4f) {
            void *tp = pNearestTP(g_road, p.x, p.y, p.z, 3.4e38f);
            if (tp && tp != g_lastTP) {
                g_lastTP = tp;
                void *mDir = rtMOf(*(Il2CppClass **)tp, "get_Direction", 0);
                if (mDir) {
                    V3 (*getDir)(void *) = (V3 (*)(void *))mDir;
                    V3 d = getDir(tp);
                    float cx = f.x*d.z - f.z*d.x;
                    float dot = f.x*d.x + f.z*d.z;
                    float deg = atan2f(cx, dot) * 57.29578f;
                    if (gNavInvert) deg = -deg;
                    float dead = 30.0f - 28.0f * gNavStrength;
                    unsigned char pr = (deg < -dead) ? 1 : 0;
                    unsigned char pr2 = (deg > dead) ? 1 : 0;
                    pSetKey(g_input, 1, pr);
                    pSetKey(g_input, 2, pr2);
                }
            }
        }
    }

    // ---- nitro drift % ----
    if (gNitroBoost && gNitroPct > 0.f && g_nMgr && nowSeconds() >= gNextNitroAdd) {
        void *single = *(void **)((char *)g_nMgr + kNMgr_Single);
        if (single) {
            uint32_t cur = *(uint32_t *)((char *)single + kSingle_CurPow);
            if (cur < 999) {
                uint32_t add = (uint32_t)(1000.0f * gNitroPct / 100.0f * 0.016f);  // % mỗi frame ~16ms
                if (add < 1) add = 1;
                uint32_t nv = cur + add;
                if (nv > 999) nv = 999;
                *(uint32_t *)((char *)single + kSingle_CurPow) = nv;
            }
        }
        gNextNitroAdd = nowSeconds() + 0.016;
    }

    // ---- auto end drift (nhận phím drift thả từ InputHelper keyflags) ----
    if (gAutoDriftEnd && g_input && pGetKeyFlags) {
        int kf = pGetKeyFlags(g_input);
        bool driftKey = (kf >> 8) & 1;
        if (gPrevDriftKey && !driftKey && g_ecu) {
            int st = *(int *)((char *)g_ecu + kEcu_State);
            if (st == 2) {  // Drifting
                void *mForceEnd = rtMOf(*(Il2CppClass **)g_veh, "ForceEndDrifting", 0);
                if (!mForceEnd) {
                    // VehicleFast.ForceEndDrifting(IVehicle)
                    void *fp = rtMethod("", "VehicleFast", "ForceEndDrifting", 1);
                    if (fp) ((void(*)(void*))fp)(g_veh);
                }
            }
        }
        gPrevDriftKey = driftKey;
    }
}

static double gNextFrame = 0.0;
static void hook_PowerChainUpdateFull(void *self, float dt, const void *method) {
    hook_PowerChainUpdate(self, dt, method);
    double t = nowSeconds();
    if (t >= gNextFrame) { gNextFrame = t + 0.1; frameWork(); }
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
    rtLog("install: v3 hooks");

    orig_GoImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "FreePracticeGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "ActionSpeedGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);

    // PowerChain — gộp gia tốc + N2O + frameWork
    orig_PowerChainUpd = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehiclePowerChain", "Update", 1, (void *)hook_PowerChainUpdateFull);

    // Drift no-slow
    orig_DriftDamp = (void (*)(void *, float, float, int, float, const void *))
        rtHookMethod("", "NssVehicleDriftHelper", "DriftingSlideVelDamping", 4, (void *)hook_DriftDamping);

    // Mini boost
    orig_ExVelUpd = (void (*)(void *, float, const void *))
        rtHookMethod("", "ExtraVelocityTriggerMgr", "Update", 1, (void *)hook_ExVelUpdate);
    pForceMini = (void (*)(void *, int))
        rtMethod("", "ExtraVelocityTriggerMgr", "ForceCanTriggerOnce", 1);

    // N2O prolong
    pForceDelayN2O = (int (*)(void *, int))
        rtMethod("", "ExtraVelocityFast", "ForceDelayEndExtraVelocity", 2);

    // Drift release — auto end drift + vector realign
    orig_DriftRelease = (void (*)(void *, const void *))
        rtHookMethod("", "NssVehicleDriftCtrl", "ReleaseDrifting", 0, (void *)hook_DriftRelease);

    // ---- resolve function pointers ----
    pGetInst = (void *(*)(void))rtMethod("", "GamePub", "GetInstance", 0);
    pGetModByName = (void *(*)(void *, void *, void *))rtMethod("", "GamePub", "GetModuleByName", 2);
    pGetMyVehicle = (void *(*)(void))rtMethod("", "VehicleFast", "GetMyVehicle", 0);
    pGetLinVel = (V3 (*)(void *))rtMethod("", "PhyDllWrapper", "PHY_EntityGetLinearVelocity", 1);
    {
        // overload Vector3 (1 arg) — dùng RVA trực tiếp 0xCF16850
        uintptr_t base = unityBase();
        if (base) pGetLinVel = (V3 (*)(void *))(base + 0xCF16850);
    }
    {
        uintptr_t base = unityBase();
        if (base) pSetLinVel = (void (*)(void *, float, float, float))(base + 0xCF17608);
    }
    {
        void *k = rtFindClass("", "VehicleInputCtrl");
        if (k) {
            const MethodInfo *m = i_meth(k, "get_KeyFlags", 0);
            if (m) pGetKeyFlags = (int (*)(void *))*(void **)m;
        }
    }
    pNearestTP = (void *(*)(void *, float, float, float, float))
        rtMethod("", "RoadMap", "GetNearestTrackPoint", 2);
    {
        void *k = rtFindClass("", "NssVehicle");
        if (k) {
            const MethodInfo *m = i_meth(k, "get_Forward", 0);
            if (m) pGetVehFwd = (V3 (*)(void *))*(void **)m;
            m = i_meth(k, "get_Position", 0);
            if (m) pGetVehPos = (V3 (*)(void *))*(void **)m;
            m = i_meth(k, "GetDynamicVehicle", 0);
            if (m) pGetDynVeh = (void *(*)(void *))*(void **)m;
        }
    }
    {
        void *k = rtFindClass("", "PlayVehicleModule");
        if (k) {
            const MethodInfo *m = i_meth(k, "GetNitrogenCollectMgr", 1);
            if (m) pGetMgr = (void *(*)(void *, void *, void *))*(void **)m;
        }
    }
    // pSetKey qua InputModule.SetKey (instance)
    {
        void *k = rtFindClass("", "InputModule");
        if (k) {
            const MethodInfo *m = i_meth(k, "SetKey", 2);
            if (m) pSetKey = (void (*)(void *, int, unsigned char))*(void **)m;
        }
    }

    rtLog("install: done");
}

#pragma mark - UI (small, distinctive)

@interface RCWin : UIWindow
@end
@implementation RCWin
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)ev {
    UIView *v = [super hitTest:pt withEvent:ev];
    return (v == self) ? nil : v;
}
- (BOOL)canBecomeKeyWindow { return NO; }
@end

@interface RCMenu : NSObject
@property (nonatomic, strong) RCWin *win;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *speedLbl;
@end

static RCMenu *gMenu = nil;

@implementation RCMenu

- (UILabel *)row:(CGFloat)y text:(NSString *)t size:(CGFloat)fs color:(UIColor *)c {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y, 180, 22)];
    l.text = t; l.textColor = c ?: UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:fs weight:UIFontWeightMedium];
    [self.card addSubview:l];
    return l;
}
- (UISwitch *)sw:(CGFloat)y on:(BOOL)v act:(SEL)a {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(196, y - 2, 44, 26)];
    sw.transform = CGAffineTransformMakeScale(0.75, 0.75);
    sw.onTintColor = [UIColor colorWithRed:0.95 green:0.42 blue:0.15 alpha:1];
    sw.on = v;
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [self.card addSubview:sw];
    return sw;
}
- (UISlider *)sl:(CGFloat)y mn:(float)mn mx:(float)mx val:(float)v act:(SEL)a {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(14, y, 210, 24)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = v;
    s.tintColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.15 alpha:1];
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [self.card addSubview:s];
    return s;
}

- (void)build {
    CGRect sc = UIScreen.mainScreen.bounds;
    self.win = [[RCWin alloc] initWithFrame:sc];
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            self.win.windowScene = (UIWindowScene *)s;
            break;
        }
    }
    self.win.windowLevel = UIWindowLevelAlert + 1;
    self.win.backgroundColor = UIColor.clearColor;
    self.win.rootViewController = [[UIViewController alloc] init];
    self.win.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.win.hidden = NO;

    UIView *host = self.win.rootViewController.view;

    // FAB nhỏ, góc phải trên
    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(sc.size.width - 50, 70, 42, 42);
    self.fab.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.85];
    self.fab.layer.cornerRadius = 21;
    self.fab.layer.borderWidth = 1;
    self.fab.layer.borderColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.15 alpha:0.9].CGColor;
    [self.fab setTitle:@"⚡" forState:UIControlStateNormal];
    self.fab.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [self.fab addGestureRecognizer:pan];
    [host addSubview:self.fab];

    // Card — style tối + accent cam
    CGFloat cw = 240, ch = 344;
    self.card = [[UIView alloc] initWithFrame:CGRectMake(sc.size.width - cw - 8, 118, cw, ch)];
    self.card.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.93];
    self.card.layer.cornerRadius = 12;
    self.card.layer.borderWidth = 0.5;
    self.card.layer.borderColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.15 alpha:0.35].CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = 0.5;
    self.card.layer.shadowRadius = 10;
    self.card.hidden = YES;
    [host addSubview:self.card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, cw - 28, 22)];
    title.text = @"⚡ RACE TOOLKIT";
    title.textColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.15 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:12];
    [self.card addSubview:title];

    // rows
    [self row:36 text:@"Drift no-slow" size:12 color:nil];
    [self sw:36 on:gDriftNoSlow act:@selector(onDriftSlow:)];
    [self row:58 text:@"Auto navigate" size:12 color:nil];
    [self sw:58 on:gAutoNavigate act:@selector(onNav:)];
    [self row:80 text:@"Steer strength" size:10 color:UIColor.lightGrayColor];
    [self sl:94 mn:0 mx:1 val:gNavStrength act:@selector(onNavStr:)];
    [self row:116 text:@"End-drift launch" size:12 color:nil];
    [self sw:116 on:gEndDriftLaunch act:@selector(onLaunch:)];
    [self row:138 text:@"Nitro drift gain" size:12 color:nil];
    [self sw:138 on:gNitroBoost act:@selector(onNitro:)];
    [self row:160 text:@"Gain %" size:10 color:UIColor.lightGrayColor];
    [self sl:174 mn:0 mx:1000 val:gNitroPct act:@selector(onNitroPct:)];
    [self row:196 text:@"Speed boost (hidden)" size:12 color:nil];
    [self sw:196 on:gSpeedBoost act:@selector(onSpeed:)];
    [self row:218 text:@"Extra km/h" size:10 color:UIColor.lightGrayColor];
    [self sl:232 mn:0 mx:120 val:gSpeedKmh act:@selector(onSpd:)];
    [self row:254 text:@"No2 prolong" size:12 color:nil];
    [self sw:254 on:gProlongN2O act:@selector(onN2O:)];
    [self row:276 text:@"Inf mini boost" size:12 color:nil];
    [self sw:276 on:gFullMiniBoost act:@selector(onMini:)];
    [self row:298 text:@"Auto end drift" size:12 color:nil];
    [self sw:298 on:gAutoDriftEnd act:@selector(onAutoDrift:)];

    self.speedLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 322, cw - 28, 16)];
    self.speedLbl.textColor = UIColor.lightGrayColor;
    self.speedLbl.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.speedLbl.text = [NSString stringWithFormat:@"extra %d km/h | nav %.0f%% | nitro %d%%",
                          (int)gSpeedKmh, gNavStrength*100, (int)gNitroPct];
    [self.card addSubview:self.speedLbl];
}

- (void)toggle { self.card.hidden = !self.card.hidden; }
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}
- (void)onDriftSlow:(UISwitch *)s { gDriftNoSlow = s.isOn; }
- (void)onNav:(UISwitch *)s        { gAutoNavigate = s.isOn; }
- (void)onNavStr:(UISlider *)s     { gNavStrength = s.value; }
- (void)onLaunch:(UISwitch *)s     { gEndDriftLaunch = s.isOn; }
- (void)onNitro:(UISwitch *)s      { gNitroBoost = s.isOn; }
- (void)onNitroPct:(UISlider *)s   { gNitroPct = s.value; }
- (void)onSpeed:(UISwitch *)s      { gSpeedBoost = s.isOn; }
- (void)onSpd:(UISlider *)s        { gSpeedKmh = s.value; }
- (void)onN2O:(UISwitch *)s        { gProlongN2O = s.isOn; }
- (void)onMini:(UISwitch *)s       { gFullMiniBoost = s.isOn; }
- (void)onAutoDrift:(UISwitch *)s  { gAutoDriftEnd = s.isOn; }
@end

#pragma mark - Bootstrap

static void buildMenu(void) {
    if (gMenu) return;
    @try {
        gMenu = [RCMenu new];
        [gMenu build];
        rtLog("UI: ok");
    } @catch (NSException *e) {
        gMenu = nil;
        rtLog("UI: FAIL %s", e.reason.UTF8String ?: "?");
    }
}

static void startToolkit(void) {
    static int tries = 0;
    if (!rtInitApi()) {
        if (++tries > 60) { rtLog("boot: gave up api"); buildMenu(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }
    Il2CppDomain *d = i_domain();
    size_t n = 0;
    const Il2CppAssembly **a = d ? i_asms(d, &n) : NULL;
    if (!a || !n) {
        if (++tries > 60) { rtLog("boot: gave up domain"); buildMenu(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }
    rtLog("boot: il2cpp ready (%zu assemblies)", n);
    if (!gHooksInstalled) { gHooksInstalled = YES; installHooks(); }
    buildMenu();
}

__attribute__((constructor)) static void RCInit(void) {
    rtLogOpen();
    rtInstallCrashHandler();
    rtLog("=== RaceToolkit v3 === pid=%d", getpid());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ startToolkit(); });
}
