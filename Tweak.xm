// Mini World : Royale — com.miniworldroyale.sparkgame
// TrollFools-injected dylib. Target: UnityFramework (Mach-O arm64, imagebase 0).
// All classes/methods/fields verified in UnityFramework.i64 via IDA MCP.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdarg.h>
#import <stdint.h>
#import <unistd.h>

// Substrate/ElleKit. TrollFools injects into a process that already has one of them;
// when neither is present this declaration simply stays unused (see hook() below).
extern "C" void MSHookFunction(void *symbol, void *hook, void **old);

#pragma mark - il2cpp ABI (UnityFramework exports 232 _il2cpp_* symbols)

typedef struct { float x, y, w, h; } UIRect;   // UnityEngine.Rect
typedef struct { float x, y; } Vec2;           // UnityEngine.Vector2 (HFA -> s0,s1)

static void *(*i_domain_get)(void);
static void *(*i_thread_attach)(void *);
static void **(*i_get_assemblies)(void *, size_t *);
static void *(*i_assembly_image)(void *);
static const char *(*i_image_name)(void *);
static void *(*i_class_from_name)(void *, const char *, const char *);
static void *(*i_method_from_name)(void *, const char *, int);
static void *(*i_field_from_name)(void *, const char *);
static size_t (*i_field_offset)(void *);
static void *(*i_class_get_type)(void *);
static void *(*i_type_get_object)(void *);
static void *(*i_string_new)(const char *);
static void *(*i_object_new)(void *);
static void *(*i_object_unbox)(void *);
static void *(*i_runtime_invoke)(void *, void *, void **, void **);

typedef void (*mshook_t)(void *, void *, void **);
static mshook_t g_mshook;

static inline void *MP(void *mi) { return mi ? *(void **)mi : nullptr; }

static void hookMethod(void *mi, void *hook, void **orig) {
    if (MP(mi) && g_mshook) g_mshook(MP(mi), hook, orig);
}

static void *callN(void *mi, void *obj, int argc, ...) {
    if (!mi) return nullptr;
    void *p[3] = {nullptr};
    va_list ap; va_start(ap, argc);
    for (int k = 0; k < argc && k < 3; k++) p[k] = va_arg(ap, void *);
    va_end(ap);
    void *exc = nullptr;
    void *r = i_runtime_invoke(mi, obj, argc ? p : nullptr, &exc);
    return exc ? nullptr : r;
}
#define call0(mi, obj) callN(mi, obj, 0)
#define call1(mi, obj, a) callN(mi, obj, 1, (void *)(a))

static void *methodOf(void *k, const char *n, int argc) {
    return k ? i_method_from_name(k, n, argc) : nullptr;
}

#pragma mark - resolved symbols

static void *K_playerCam, *K_dmgPlayer, *K_lpm, *K_debugInfo, *K_propComp;
static void *K_gameObject, *K_gui, *K_camera;

static void *M_getCamera, *M_getDamageable, *M_getPropComp, *M_lpmInstance, *M_lpmLocal;
static void *M_fpCamera, *M_forceAdd, *M_canDamage, *M_gmUpdate, *M_ongui, *M_speedRate;
static void *M_goCtor, *M_goAdd, *M_lbl, *M_btn, *M_fov;

static void *O_forceAdd, *O_canDamage, *O_gmUpdate, *O_ongui, *O_speedRate;

static size_t off_recoilAngles;

static void *g_ui, *g_lcam, *g_ldmg, *g_lprop;
static BOOL   spawned = NO, menuOpen = NO;
static BOOL   c_god = NO, c_norecoil = NO;
static float  c_speed = 1.0f, c_fov = 0.f;

#pragma mark - hooks

static void hk_forceAdd(void *self, Vec2 v, void *mi) {
    if (c_norecoil && self == g_lcam) return;
    ((void (*)(void *, Vec2, void *))O_forceAdd)(self, v, mi);
}

// ModelCheckCanDamage is 12 bytes -> x1:x2 (AAPCS64 C.10 composite).
// CheckCanDamage(0x32AE040) is the funnel every incoming damage packet passes.
static bool hk_canDamage(void *self, uint64_t lo, uint64_t hi, void *mi) {
    if (c_god && self == g_ldmg) return false;
    return ((bool (*)(void *, uint64_t, uint64_t, void *))O_canDamage)(self, lo, hi, mi);
}

// PlayerPropertyComp::GetSpeedRate (0x3A460D0) is the computed move-speed rate for
// one player, not a cached field, so a multiplier here survives config refreshes.
// PlayerMovement::getCurSpeedRate feeds it into calcTargetVelocitySpeed.
static float hk_speedRate(void *self, bool withNoFov, void *mi) {
    float r = ((float (*)(void *, bool, void *))O_speedRate)(self, withNoFov, mi);
    if (c_speed == 1.f || !self || self != g_lprop) return r;
    return r * c_speed;
}

#pragma mark - menu (game SDK IMGUI)

static const float ROW = 30.f;

static void lbl(float x, float y, float w, const char *text) {
    void *s = i_string_new(text);
    UIRect r = { x, y, w, ROW - 8 };
    callN(M_lbl, nullptr, 2, &r, &s);
}
static BOOL btn(float x, float y, float w, float h, const char *text) {
    void *s = i_string_new(text);
    UIRect r = { x, y, w, h };
    void *res = callN(M_btn, nullptr, 2, &r, &s);
    void *u = res ? i_object_unbox(res) : nullptr;
    return u ? *(bool *)u : NO;
}
static void toggleRow(float x, float y, float w, const char *name, BOOL *flag) {
    char buf[80];
    snprintf(buf, sizeof buf, "%s %s", *flag ? "[X]" : "[ ]", name);
    if (btn(x, y, w, ROW - 8, buf)) *flag = !*flag;
}
static void stepRow(float x, float y, const char *name, float *v, float step, float lo, float hi) {
    char buf[32];
    lbl(x, y + 3, 110, name);
    if (btn(x + 112, y, 34, ROW - 10, "-")) { *v -= step; if (*v < lo) *v = lo; }
    snprintf(buf, sizeof buf, "%.2f", *v);
    lbl(x + 150, y + 3, 60, buf);
    if (btn(x + 200, y, 34, ROW - 10, "+")) { *v += step; if (*v > hi) *v = hi; }
}

static void refreshLocal(void) {
    void *lpm = call0(M_lpmInstance, nullptr);
    void *pl  = lpm ? call0(M_lpmLocal, lpm) : nullptr;
    g_lcam  = pl ? call0(M_getCamera, pl)     : nullptr;
    g_ldmg  = pl ? call0(M_getDamageable, pl) : nullptr;
    g_lprop = pl ? call0(M_getPropComp, pl)   : nullptr;
}

// Runs inside the Update hook, i.e. before PlayerCamera::LateUpdate consumes
// m_RecoilAngles, so the zeroed value is what the camera actually applies.
static void applyPerFrame(void) {
    if (c_norecoil && g_lcam && off_recoilAngles)
        *(Vec2 *)((char *)g_lcam + off_recoilAngles) = Vec2{0.f, 0.f};
}

// IMGUI events run after LateUpdate — the only phase where writing the FP
// camera's fieldOfView survives the camera's own LateUpdate.
static void applyFov(void) {
    if (c_fov > 0.f && g_lcam) {
        void *cam = call0(M_fpCamera, g_lcam);
        if (cam) call1(M_fov, cam, &c_fov);
    }
}

static void drawMenu(void) {
    if (btn(10, 60, 74, 40, menuOpen ? "CLOSE" : "MENU")) menuOpen = !menuOpen;
    if (!menuOpen) return;

    float px = 96, py = 60, pw = 300, y = py + 30;
    lbl(px, py, pw, "-- MINI WORLD ROYALE --");
    toggleRow(px, y, pw, "GOD MODE", &c_god);             y += ROW;
    toggleRow(px, y, pw, "NO RECOIL", &c_norecoil);       y += ROW;
    stepRow(px, y, "SPEED", &c_speed, 0.25f, 0.25f, 8.f); y += ROW;
    stepRow(px, y, "FOV", &c_fov, 5.f, 0.f, 120.f);       y += ROW;
    lbl(px, y + 4, pw, g_lprop ? "status: in-game" : "status: waiting player");
}

static void hk_ongui(void *self, void *mi) {
    if (self != g_ui) { ((void (*)(void *, void *))O_ongui)(self, mi); return; }
    @autoreleasepool { applyFov(); drawMenu(); }
}

#pragma mark - bootstrap

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

static void spawnUI(void) {
    void *go = i_object_new(K_gameObject);
    if (!go) return;
    call0(M_goCtor, go);                    // GameObject.ctor() -> Internal_CreateGameObject

    void *ktype = i_class_get_type(K_debugInfo);
    void *type = ktype ? i_type_get_object(ktype) : nullptr;
    if (!type) return;
    g_ui = call1(M_goAdd, go, &type);       // DebugInfo::Start() calls DontDestroyOnLoad
    NSLog(@"[MWM] ui=%p", g_ui);
}

// GameMain::Update is the per-frame tick: resolve the local player and apply
// continuous tweaks here, so nothing depends on the menu being visible.
static void hk_gmUpdate(void *self, void *mi) {
    ((void (*)(void *, void *))O_gmUpdate)(self, mi);
    if (!spawned) { spawned = YES; @autoreleasepool { spawnUI(); } }
    refreshLocal();
    applyPerFrame();
}

static void *sym(const char *n) { return dlsym(RTLD_DEFAULT, n); }

static void bootstrap(void) {
    @autoreleasepool {
        g_mshook = (mshook_t)sym("MSHookFunction");
        if (!g_mshook) g_mshook = (mshook_t)sym("MSHookFunctionUnsafe");

        i_domain_get      = (void *(*)(void))sym("il2cpp_domain_get");
        i_thread_attach   = (void *(*)(void *))sym("il2cpp_thread_attach");
        i_get_assemblies  = (void **(*)(void *, size_t *))sym("il2cpp_domain_get_assemblies");
        i_assembly_image  = (void *(*)(void *))sym("il2cpp_assembly_get_image");
        i_image_name      = (const char *(*)(void *))sym("il2cpp_image_get_name");
        i_class_from_name = (void *(*)(void *, const char *, const char *))sym("il2cpp_class_from_name");
        i_method_from_name= (void *(*)(void *, const char *, int))sym("il2cpp_class_get_method_from_name");
        i_field_from_name = (void *(*)(void *, const char *))sym("il2cpp_class_get_field_from_name");
        i_field_offset    = (size_t (*)(void *))sym("il2cpp_field_get_offset");
        i_class_get_type  = (void *(*)(void *))sym("il2cpp_class_get_type");
        i_type_get_object = (void *(*)(void *))sym("il2cpp_type_get_object");
        i_string_new      = (void *(*)(const char *))sym("il2cpp_string_new");
        i_object_new      = (void *(*)(void *))sym("il2cpp_object_new");
        i_object_unbox    = (void *(*)(void *))sym("il2cpp_object_unbox");
        i_runtime_invoke  = (void *(*)(void *, void *, void **, void **))sym("il2cpp_runtime_invoke");

        if (!i_domain_get || !i_runtime_invoke || !g_mshook) {
            NSLog(@"[MWM] prerequisites missing (mshook=%p il2cpp=%p)", g_mshook, i_runtime_invoke);
            return;
        }
        while (!i_domain_get() || !findImage("mscorlib.dll")) usleep(50000);
        i_thread_attach(i_domain_get());
        while (!findImage("Assembly-CSharp.dll")) usleep(100000);

        void *game = findImage("Assembly-CSharp.dll");
        void *core = findImage("UnityEngine.CoreModule.dll");
        if (!game || !core) { NSLog(@"[MWM] image lookup failed"); return; }

        void *K_player = i_class_from_name(game, "HQFPSTemplate", "Player");
        void *K_gm     = i_class_from_name(game, "", "GameMain");
        K_playerCam    = i_class_from_name(game, "HQFPSTemplate", "PlayerCamera");
        K_dmgPlayer    = i_class_from_name(game, "", "DamageablePlayer");
        K_lpm          = i_class_from_name(game, "", "LocalPlayerManager");
        K_debugInfo    = i_class_from_name(game, "", "DebugInfo");
        K_propComp     = i_class_from_name(game, "", "PlayerPropertyComp");
        K_gameObject   = i_class_from_name(core, "UnityEngine", "GameObject");
        K_gui          = i_class_from_name(core, "UnityEngine", "GUI");
        K_camera       = i_class_from_name(core, "UnityEngine", "Camera");

        M_getCamera     = methodOf(K_player, "get_Camera", 0);
        M_getDamageable = methodOf(K_player, "get_DamageablePlayer", 0);
        M_getPropComp   = methodOf(K_player, "get_PropertyComp", 0);
        M_lpmInstance   = methodOf(K_lpm, "get_Instance", 0);
        M_lpmLocal      = methodOf(K_lpm, "get_LocalPlayer", 0);
        M_fpCamera      = methodOf(K_playerCam, "GetFPCamera", 0);
        M_forceAdd      = methodOf(K_playerCam, "AddForceAngle", 1);
        M_canDamage     = methodOf(K_dmgPlayer, "CheckCanDamage", 1);
        M_speedRate     = methodOf(K_propComp, "GetSpeedRate", 1);
        M_gmUpdate      = methodOf(K_gm, "Update", 0);
        M_ongui         = methodOf(K_debugInfo, "OnGUI", 0);
        M_goCtor        = methodOf(K_gameObject, ".ctor", 0);
        M_goAdd         = methodOf(K_gameObject, "AddComponent", 1);
        M_lbl           = methodOf(K_gui, "Label", 2);
        M_btn           = methodOf(K_gui, "Button", 2);
        M_fov           = methodOf(K_camera, "set_fieldOfView", 1);

        void *f = K_playerCam ? i_field_from_name(K_playerCam, "m_RecoilAngles") : nullptr;
        off_recoilAngles = f ? i_field_offset(f) : 0;

        hookMethod(M_gmUpdate,  (void *)hk_gmUpdate,  &O_gmUpdate);
        hookMethod(M_ongui,     (void *)hk_ongui,     &O_ongui);
        hookMethod(M_canDamage, (void *)hk_canDamage, &O_canDamage);
        hookMethod(M_forceAdd,  (void *)hk_forceAdd,  &O_forceAdd);
        hookMethod(M_speedRate, (void *)hk_speedRate, &O_speedRate);

        NSLog(@"[MWM] ready update=%p ongui=%p canDamage=%p forceAdd=%p speed=%p recoilOff=0x%zx",
              MP(M_gmUpdate), MP(M_ongui), MP(M_canDamage), MP(M_forceAdd),
              MP(M_speedRate), off_recoilAngles);
    }
}

__attribute__((constructor)) static void mwm_init(void) {
    NSThread *t = [[NSThread alloc] initWithBlock:^{ bootstrap(); }];
    t.name = @"MWM";
    [t start];
}
