#ifndef MWM_TWEAK_XM
#define MWM_TWEAK_XM

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
#import <sys/mman.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>

#pragma mark - Geometry & Screen Helpers

typedef struct { float x, y; } Vec2;
typedef struct { float x, y, z; } Vec3;

// Aim point height above the target's feet. 1.65 sat just over the skull, so rays
// clipped the top edge of the head hitbox instead of its centre.
#define MWM_HEAD_HEIGHT 1.55f

static inline BOOL vec3Finite(Vec3 v) {
    return v.x == v.x && v.y == v.y && v.z == v.z &&
           fabsf(v.x) < 1e6f && fabsf(v.y) < 1e6f && fabsf(v.z) < 1e6f;
}

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
static void *(*i_image_get_class)(void *, size_t);
static size_t (*i_image_class_count)(void *);
static void *(*i_class_get_parent)(void *);

extern void sys_icache_invalidate(void *start, size_t len);

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

static BOOL safeWritePtr(void *addr, void *value);   // defined in the patch section

#pragma mark - Resolved Symbols

static void *K_lpm, *K_camera, *K_player;

static void *M_lpmInstance;       // LocalPlayerManager::get_Instance()
static void *M_w2s;               // Camera::WorldToScreenPoint(Vector3)
static void *M_camMain;           // Camera::get_main()
static void *M_getTransform;      // Component::get_transform()
static void *M_getPos;            // Transform::get_position()
static void *M_createShootData;   // ProjectileWeapon::CreateShootData(bool)

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
static size_t off_playerCam, off_playerMovement;
static size_t off_recoilAngles, off_forceAngle, off_recoilEnabled, off_lookAngles;
static size_t off_enableSmooth, off_rotationLerp;
static size_t off_wpnShootAcc, off_wpnCurAcc, off_playerAccurate;
static size_t off_parachuteState;    // PlayerMovementFP.m_ParachuteState (0x1C8)

// Aim-assist core (the game's own targeting path)
static void *M_linecast;             // Physics::Linecast (3- or 4-arg)
static int   g_linecastArgs = 0;
static void *M_barrierLayerMask;     // LayerHelper::GetHeroAssistBarrierLayerMask()
// ParachuteStateModule (constant offsets inside the module object)
#define PS_ENABLED      0x10
#define PS_FREEFALLSPD  0x1C
#define PS_MOVESPEED    0x20
#define PS_FALLMULTI    0x28

static void *g_lcam = nullptr;

#pragma mark - State

static BOOL  g_il2cppReady = NO;

static BOOL  g_espOn = NO;
static BOOL  g_aimlock = NO;
static BOOL  g_noRecoil = NO;
static BOOL  g_noSpread = NO;
static BOOL  g_wallcheck = YES;
static BOOL  g_fastBullet = NO;
static float g_bulletSpeed = 0.0f;    // 0 = game default
static float g_fireRate = 0.1f;       // seconds between shots (lower = faster)
static BOOL  g_fastShoot = NO;
static int   g_instantCount = 8;      // bullets per trigger pull
static BOOL  g_paraCtl = NO;
static BOOL  g_glide = NO;
static int   g_paraDir = 0;          // 0 = neutral, +1 up, -1 down
static float g_glideSpeed = 3.0f;    // MoveSpeed multiplier, user configurable
static float g_aimFov = 35.0f;
static BOOL  g_showAimFov = NO;

// Cached every frame by onFrame() on the main thread. The fire hook must never call
// into Unity/il2cpp: doing so from inside the weapon-fire path re-enters the physics
// update and crashed the game 1-2s after enabling silent aim.
static volatile uint16_t g_myNetId = 0;   // written by scanPlayers
static Vec3  g_aimHead = {0.0f, 0.0f, 0.0f};
static volatile BOOL g_aimHeadValid = NO;
static BOOL  g_aimHookOk = NO;            // true once CreateShootData is swapped

// Original compiled body, saved before the MethodInfo swap. Calling it is a plain
// C call -- no trampoline, no code patching, which is exactly what MSHookFunction
// could not provide on this TrollFools build.
static void *O_createShootData = nullptr;
static BOOL  g_bypassTutorial = YES;
static BOOL  g_bypassRankLock = YES;


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
        t->head = (Vec3){ pos.x, pos.y + MWM_HEAD_HEIGHT, pos.z };
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

// Wall check: does anything on the game's own barrier mask sit between the muzzle
// and the target head? Physics.Linecast is the exact primitive the game's aim assist
// uses (GetHeroAssistBarrierLayerMask), so the result matches what the engine would
// consider "blocked".
// Physics.Linecast with the game's own barrier mask.
//
// If the mask getter is unavailable, -1 (all layers) is the safe fallback: it can
// only ever report MORE occlusion, so the feature degrades toward "do not aim
// through walls" instead of silently aiming through them.
static BOOL lineBlocked(Vec3 from, Vec3 to) {
    if (!g_wallcheck) return NO;
    // Fail closed: if the trace cannot be performed we must assume the line is
    // blocked. Returning NO here is what let the aim keep locking through walls.
    if (!MP(M_linecast)) return YES;
    if (!vec3Finite(from) || !vec3Finite(to)) return YES;

    int mask = -1;
    if (MP(M_barrierLayerMask)) {
        int m = ((int (*)(void *))MP(M_barrierLayerMask))(M_barrierLayerMask);
        if (m) mask = m;
    }

    // 1 == QueryTriggerInteraction.Ignore, so pickups and trigger zones do not
    // register as cover.
    if (g_linecastArgs >= 4) {
        bool hit = ((bool (*)(Vec3, Vec3, int, int, void *))MP(M_linecast))(
                       from, to, mask, 1, M_linecast);
        return hit ? YES : NO;
    }
    bool hit = ((bool (*)(Vec3, Vec3, int, void *))MP(M_linecast))(from, to, mask, M_linecast);
    return hit ? YES : NO;
}

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
        if (d > (float)maxRadius || d >= best) continue;

        // Wall check. Cast from the render camera's eye, falling back to the local
        // player's own transform. If neither is readable the target is rejected:
        // previously this whole block was skipped when the getters were missing,
        // which is exactly how the aim kept locking onto players behind cover.
        if (g_wallcheck) {
            Vec3 eye;
            BOOL haveEye = NO;
            void *src = alive(cam) ? cam : g_lcam;
            if (alive(src) && MP(M_getTransform) && MP(M_getPos)) {
                void *tr = ((void *(*)(void *, void *))MP(M_getTransform))(src, M_getTransform);
                if (alive(tr)) {
                    eye = ((Vec3 (*)(void *, void *))MP(M_getPos))(tr, M_getPos);
                    haveEye = vec3Finite(eye);
                }
            }
            if (!haveEye) continue;                            // cannot verify -> skip
            if (lineBlocked(eye, g_targets[i].head)) continue; // verified blocked
        }
        best = d;
        *outHead = g_targets[i].head;
        found = YES;
    }
    return found;
}

// ---------------------------------------------------------------------------
// Silent aim via il2cpp MethodInfo swap.
//
// CreateShootData() has data-only xrefs (0x85a9220 / 0x85a9228), i.e. the game
// dispatches it through the class vtable. So replacing the compiled pointer works
// and -- unlike an inline hook -- needs no trampoline: the original body is still a
// plain callable C function whose address we saved before the swap.
//
// ABI: ModelShotData is returned through a hidden sret pointer (x8), then
// this (x0), bool isTransform (w1), MethodInfo* (x2).
// ---------------------------------------------------------------------------

// MethodInfo layout (il2cpp.h):
//   methodPointer @0x00, invoker_method @0x08, name @0x10, klass @0x18,
//   ..., token @0x40, flags @0x44, iflags @0x46, slot @0x48
#define MI_NAME  0x10
#define MI_KLASS 0x18

#define VTABLE_STRIDE 0x10        // VirtualInvokeData { methodPtr; method; }
#define VTABLE_SCAN_LO 0x80
#define VTABLE_SCAN_HI 0x2000   // wide: header offset is il2cpp-version specific

static BOOL miNameIs(void *mi, const char *want) {
    if (!mi) return NO;
    const char *n = *(const char **)((char *)mi + MI_NAME);
    return n && strcmp(n, want) == 0;
}

// Locate the vtable entry that dispatches this method. The header offset depends
// on the il2cpp version, so it is searched rather than assumed: an entry counts
// only when its target equals the original AND its MethodInfo names the method.
// Anything else is skipped -- a wrong guess must be a no-op, never a wrong write.
static char *findVtableEntry(void *klass, void *orig, const char *name) {
    if (!klass || !orig) return nullptr;
    char *byName = nullptr, *byPtr = nullptr;
    for (size_t off = VTABLE_SCAN_LO; off < VTABLE_SCAN_HI; off += VTABLE_STRIDE) {
        char *e = (char *)klass + off;
        if (*(void **)e != orig) continue;
        if (!byPtr) byPtr = e;
        if (!byName && miNameIs(*(void **)(e + 8), name)) { byName = e; break; }
    }
    return byName ? byName : byPtr;   // name match wins, pointer match is fallback
}

#pragma mark - Aimlock / recoil / parachute

// ModelShotData offsets (verified against dump.cs)
#define MSD_SHOOTER   0x04
#define MSD_SHOOTPOS  0x48
#define MSD_SHOOTDIR  0x54
#define MSD_ACCURATE  0x80

// ParachuteStateModule of the local player, or null when not parachuting.
static void *parachuteModule(void) {
    if (!off_parachuteState || !off_playerMovement) return nullptr;
    void *lpm = MP(M_lpmInstance) ? ((void *(*)(void *))MP(M_lpmInstance))(M_lpmInstance) : nullptr;
    void *player = (lpm && off_lpmPlayer) ? readPtr(lpm, off_lpmPlayer) : nullptr;
    if (!alive(player)) return nullptr;
    void *mv = readPtr(player, off_playerMovement);
    if (!mv) return nullptr;
    void *mod = readPtr(mv, off_parachuteState);
    if (!mod) return nullptr;
    if (!*(bool *)((char *)mod + PS_ENABLED)) return nullptr;
    return mod;
}

// Vertical motion is:  desiredY = (desiredLocalY - FreeFallSpeed) * dt
// (see PlayerMovementTPCommon.updateParachuteVelocity). So FreeFallSpeed is the
// sink rate, and a negative value makes the player rise. FallSpeedMulti scales
// FreeFallSpeed further whenever there is horizontal input, so it is pinned to 1.
static void applyParachuteControl(void) {
    if (!g_paraCtl) return;
    void *mod = parachuteModule();
    if (!mod) return;

    float *freefall  = (float *)((char *)mod + PS_FREEFALLSPD);
    float *movespeed = (float *)((char *)mod + PS_MOVESPEED);
    float *fallmulti = (float *)((char *)mod + PS_FALLMULTI);

    *fallmulti = 1.0f;

    if (g_glide) {
        // Glide on: lift the player (negative FreeFallSpeed = ascend), Up/Down
        // overlay that by pushing further.
        *movespeed = 8.0f * g_glideSpeed;
        *freefall  = -8.0f;                                  // always rising
        if (g_paraDir > 0) *freefall = -14.0f;               // Up: faster rise
        if (g_paraDir < 0) *freefall = -2.0f;                // Down: nearly stop
    } else {
        // Glide off: drop hard.
        *movespeed = 8.0f;
        *freefall = 22.0f;
    }
}

#pragma mark - Instant fire

// Fire every queued round at once.
//
// ModelShotData.bulletCount (+0x64) drives the loop in computerEntityBullet:
//   do { dir = computerFireDirection(...); computerOneEntityBullet(...); }
//   while (++i < bulletCount);
// so raising it turns one trigger pull into N simultaneous bullets. The value is
// already inside the struct we are allowed to edit, and the ammo/game checks have
// run before this point, so nothing structural is bypassed.
#define MSD_BULLETCOUNT   0x64
#define MSD_SHOOTCOUNTLIM 0x68
#define MSD_BULLTSPEED    0xC4

// ShootBullet() runs processModelShotData() right after CreateShootData, and that
// pass overwrites bulletCount with Clamp(ceil(shootCountLimite * bulletCount),1,25).
// Writing only the count was therefore erased before the bullet loop ever saw it.
// Pinning the limit to 1 makes the count pass through unchanged.
static void applyInstantFire(void *retstr) {
    if (!g_fastBullet || !retstr) return;
    *(int   *)((char *)retstr + MSD_BULLETCOUNT)   = g_instantCount;
    *(float *)((char *)retstr + MSD_SHOOTCOUNTLIM) = 1.0f;
    if (g_bulletSpeed > 0.0f) *(float *)((char *)retstr + MSD_BULLTSPEED) = g_bulletSpeed;
}

// Fast shoot: fire-rate gate. EquipmentItem.m_NextTimeCanUse @0xD4 is compared
// against Time.time inside the game's own check, so lowering it makes the weapon
// ready again immediately -- the fire-rate loop in updateUseTime reads it directly.
static void applyFastShoot(void *item) {
    if (!g_fastShoot || !item) return;
    // m_NextTimeCanUse is compared against Time.time in the game's own check.
    // Setting it to (now - rate) makes the weapon ready again after the configured
    // cooldown instead of on the very next frame (0 = fires every single frame).
    float now = CFAbsoluteTimeGetCurrent();
    *(float *)((char *)item + 0xD4) = now - g_fireRate;
}

#pragma mark - Silent aim / recoil

// finalAngle = m_LookAngles + RecoilAngle + ForceAngle, computed inside
// applyLookAngleFP from the fields below. Zeroing the fields is not enough on its
// own: AddForceAngle also flips m_RecoilEnabled, and a late write races the shot.
// Clearing the flag as well makes the contribution structurally impossible.
// Player.Accurate (Player+0x100) is a Value<float>; m_CurrentValue sits at +0x20
// (klass@0, monitor@8, then the three delegate/field slots of Value<T>). It is the
// value CreateShootData copies into ModelShotData.accurate, so clearing it here
// stops the cone at the source instead of racing the per-shot struct.
static void applyNoSpread(void) {
    if (!g_noSpread || !off_playerAccurate) return;
    void *lpm = MP(M_lpmInstance) ? ((void *(*)(void *))MP(M_lpmInstance))(M_lpmInstance) : nullptr;
    void *player = (lpm && off_lpmPlayer) ? readPtr(lpm, off_lpmPlayer) : nullptr;
    if (!alive(player)) return;
    void *val = readPtr(player, off_playerAccurate);
    if (!val) return;
    *(float *)((char *)val + 0x20) = 0.0f;      // Value<float>.m_CurrentValue
}

static void applyNoRecoil(void) {
    if (!g_noRecoil || !alive(g_lcam)) return;
    if (off_recoilAngles) *(Vec2 *)((char *)g_lcam + off_recoilAngles) = (Vec2){ 0.0f, 0.0f };
    if (off_forceAngle)   *(Vec2 *)((char *)g_lcam + off_forceAngle)   = (Vec2){ 0.0f, 0.0f };
    if (off_recoilEnabled) *(bool *)((char *)g_lcam + off_recoilEnabled) = false;
}

// Hard lock: drive PlayerCamera.m_LookAngles straight at the target head.
//
// applyLookAngleFP builds its rotation from m_LookAngles (+ recoil + force), and
// the smoothing that made the assist feel slow lives in updateRotate/lerp paths,
// not in this field. Writing the field each frame therefore snaps instantly and,
// because it is the same input the game itself consumes, the shot direction and
// the camera stay consistent.
//
// Also clears EnableSmooth / RotationLerpSpeed so no residual interpolation runs
// between our write and the frame's rotation update.
static void applyHardLock(void) {
    if (!g_aimlock || !g_aimHeadValid) return;
    if (!alive(g_lcam) || !off_lookAngles) return;
    if (!MP(M_getTransform) || !MP(M_getPos)) return;

    void *tr = ((void *(*)(void *, void *))MP(M_getTransform))(g_lcam, M_getTransform);
    if (!alive(tr)) return;
    Vec3 eye = ((Vec3 (*)(void *, void *))MP(M_getPos))(tr, M_getPos);
    if (!vec3Finite(eye)) return;

    Vec3 head = g_aimHead;
    float dx = head.x - eye.x;
    float dy = head.y - eye.y;
    float dz = head.z - eye.z;
    float horiz = sqrtf(dx * dx + dz * dz);
    if (!(horiz > 0.01f)) return;

    Vec2 angles;
    angles.x = -atan2f(dy, horiz) * (180.0f / 3.14159265f);   // pitch
    angles.y = atan2f(dx, dz) * (180.0f / 3.14159265f);       // yaw
    if (angles.x != angles.x || angles.y != angles.y) return;

    *(Vec2 *)((char *)g_lcam + off_lookAngles) = angles;

    // Kill any residual interpolation for this frame.
    if (off_enableSmooth) *(bool *)((char *)g_lcam + off_enableSmooth) = false;
    if (off_rotationLerp) *(float *)((char *)g_lcam + off_rotationLerp) = 1000.0f;
}

static void hk_createShootData(void *retstr, void *self, bool isTransform, void *method) {
    if (!O_createShootData) return;
    ((void (*)(void *, void *, bool, void *))O_createShootData)(retstr, self, isTransform, method);

    if (!retstr || !g_myNetId || !alive(self)) return;

    applyInstantFire(retstr);

    // No bullet spread. `accurate` is what computerFireDirection feeds to
    // Random.Range(-acc, acc), so zeroing the built struct is the authoritative
    // fix -- the weapon's cached curAccurate/shootAccurate would only be copied in
    // again on the next shot, which is why clearing them alone did nothing.
    if (g_noSpread) {
        *(float *)((char *)retstr + MSD_ACCURATE) = 0.0f;
        if (off_wpnShootAcc) *(float *)((char *)self + off_wpnShootAcc) = 0.0f;   // 0x114
        if (off_wpnCurAcc)   *(float *)((char *)self + off_wpnCurAcc)   = 0.0f;   // 0x110
    }

    // Fast shoot: reset the fire-rate gate so the next shot can start immediately.
    applyFastShoot(self);

    // Aimlock: the camera is already locked by applyHardLock(), so rewriting the
    // direction here only guarantees the shot matches that camera even if the
    // struct was built a frame earlier.
    if (!g_aimlock || !g_aimHeadValid) return;

    Vec3 head = g_aimHead;                              // snapshot from onFrame
    Vec3 sp = *(Vec3 *)((char *)retstr + MSD_SHOOTPOS);
    if (!vec3Finite(head) || !vec3Finite(sp)) return;

    Vec3 dir = { head.x - sp.x, head.y - sp.y, head.z - sp.z };
    float len = sqrtf(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    if (!(len > 0.01f) || len != len || len > 1e6f) return;

    dir.x /= len; dir.y /= len; dir.z /= len;
    *(Vec3 *)((char *)retstr + MSD_SHOOTDIR) = dir;
}

static BOOL patchVtableSlot(void *mi, void *orig, void *repl, void *klass, const char *name) {
    if (!mi || !orig || !klass) return NO;

    char *entry = findVtableEntry(klass, orig, name);
    if (!entry) {
        NSLog(@"[MWM] vtable entry for %s not found (klass=%p)", name, klass);
        return NO;
    }
    if (!safeWritePtr(entry, repl)) return NO;
    NSLog(@"[MWM] vtable entry %p patched for %s", entry, name);
    return YES;
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
        Vec3 feetWorld = { headWorld.x, headWorld.y - MWM_HEAD_HEIGHT, headWorld.z };

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

@interface MWMMenuView : UIScrollView
@property (retain) UILabel *statusLabel;
@property (retain) UISwitch *espSwitch;
@property (retain) UISwitch *aimSwitch;
@property (retain) UISwitch *aimFovShowSwitch;
@property (retain) UISlider *aimFovSlider;
@property (retain) UILabel *aimFovLabel;
@property (retain) UISwitch *recoilSwitch;
@property (retain) UISwitch *spreadSwitch;
@property (retain) UISwitch *wallcheckSwitch;
@property (retain) UISwitch *instantSwitch;
@property (retain) UISwitch *fastShootSwitch;
@property (retain) UISlider *fireRateSlider;
@property (retain) UILabel *fireRateLabel;
@property (retain) UISwitch *paraSwitch;
@property (retain) UISlider *glideSpeedSlider;
@property (retain) UISlider *bulletSpeedSlider;
@property (retain) UILabel *bulletSpeedLabel;
@property (retain) UILabel *glideSpeedLabel;
@end

@implementation MWMMenuView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.showsVerticalScrollIndicator = YES;
    self.showsHorizontalScrollIndicator = NO;

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
    self.aimSwitch = [self toggleAt:&y title:@"Aimlock (hold fire)" sel:@selector(aimToggled:)];
    self.aimFovShowSwitch = [self toggleAt:&y title:@"Show Aim FOV" sel:@selector(aimFovShowToggled:)];
    self.recoilSwitch = [self toggleAt:&y title:@"No Recoil" sel:@selector(recoilToggled:)];
    self.spreadSwitch = [self toggleAt:&y title:@"No Bullet Spread" sel:@selector(spreadToggled:)];
    self.wallcheckSwitch = [self toggleAt:&y title:@"Wall Check" sel:@selector(wallcheckToggled:)];
    self.instantSwitch = [self toggleAt:&y title:@"Fast Bullet (all at once)" sel:@selector(instantToggled:)];
    self.fastShootSwitch = [self toggleAt:&y title:@"Fast Shoot" sel:@selector(fastShootToggled:)];
    self.fireRateLabel = [self labelAt:&y text:[NSString stringWithFormat:@"Fire Rate: %.1fs", g_fireRate]];
    self.fireRateSlider = [self sliderAt:&y min:0.05f max:0.5f val:g_fireRate sel:@selector(fireRateChanged:)];
    self.paraSwitch = [self toggleAt:&y title:@"Parachute Control" sel:@selector(paraToggled:)];
    self.glideSpeedLabel = [self labelAt:&y text:[NSString stringWithFormat:@"Glide Speed: %.1fx", g_glideSpeed]];
    self.glideSpeedSlider = [self sliderAt:&y min:1.0f max:6.0f val:g_glideSpeed sel:@selector(glideSpeedChanged:)];

    self.bulletSpeedLabel = [self labelAt:&y text:g_bulletSpeed > 0 ? [NSString stringWithFormat:@"Bullet Speed: %.0f m/s", g_bulletSpeed] : @"Bullet Speed: Game Default"];
    self.bulletSpeedSlider = [self sliderAt:&y min:100 max:600 val:g_bulletSpeed > 0 ? g_bulletSpeed : 300 sel:@selector(bulletSpeedChanged:)];

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

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.cancelsTouchesInView = NO;
    [self addGestureRecognizer:pan];

    // The controls sit taller than the visible frame; let the whole panel scroll.
    self.contentSize = CGSizeMake(w, y + 70);
    self.alwaysBounceVertical = YES;

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
- (void)recoilToggled:(UISwitch *)s { g_noRecoil = s.isOn; }
- (void)spreadToggled:(UISwitch *)s { g_noSpread = s.isOn; }
- (void)wallcheckToggled:(UISwitch *)s { g_wallcheck = s.isOn; }
- (void)instantToggled:(UISwitch *)s { g_fastBullet = s.isOn; }
- (void)fastShootToggled:(UISwitch *)s { g_fastShoot = s.isOn; }
- (void)fireRateChanged:(UISlider *)s {
    g_fireRate = s.value;
    self.fireRateLabel.text = [NSString stringWithFormat:@"Fire Rate: %.2fs", g_fireRate];
}
- (void)bulletSpeedChanged:(UISlider *)s {
    g_bulletSpeed = s.value;
    self.bulletSpeedLabel.text = g_bulletSpeed > 0
        ? [NSString stringWithFormat:@"Bullet Speed: %.0f m/s", g_bulletSpeed]
        : @"Bullet Speed: Game Default";
}
- (void)paraToggled:(UISwitch *)s { g_paraCtl = s.isOn; }
- (void)glideSpeedChanged:(UISlider *)s {
    g_glideSpeed = s.value;
    self.glideSpeedLabel.text = [NSString stringWithFormat:@"Glide Speed: %.1fx", g_glideSpeed];
}

- (void)aimToggled:(UISwitch *)s {
    g_aimlock = s.isOn;
}
- (void)aimFovChanged:(UISlider *)s {
    g_aimFov = s.value;
    self.aimFovLabel.text = [NSString stringWithFormat:@"Aim FOV: %d°", (int)g_aimFov];
}
- (void)resetTapped {
    g_espOn = NO; g_aimlock = NO; g_showAimFov = NO;
    g_bulletSpeed = 0.0f; self.bulletSpeedSlider.value = 300; self.bulletSpeedLabel.text = @"Bullet Speed: Game Default";
    g_noRecoil = NO; g_noSpread = NO; g_paraCtl = NO; g_glide = NO;
    self.recoilSwitch.on = NO; self.spreadSwitch.on = NO;
    self.paraSwitch.on = NO; g_paraDir = 0; g_glide = NO;
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

#pragma mark - Parachute panel

// Three floating buttons, shown only while Parachute Control is on.
static UIButton *mkBtn(NSString *t, SEL act, id target) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 54, 34);
    b.backgroundColor = [UIColor colorWithRed:0.1f green:0.35f blue:0.8f alpha:0.85f];
    b.layer.cornerRadius = 8;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [b addTarget:target action:act forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - UI Manager

@interface MWMUIManager : NSObject
+ (instancetype)shared;
@property (retain) UIWindow *host;
@property (retain) UIButton *floatingBtn;
@property (retain) MWMMenuView *menuView;
@property (retain) UIView *paraPanel;
@property (retain) UIButton *paraGlideBtn;
@property (retain) UIButton *paraUpBtn;
@property (retain) UIButton *paraDownBtn;
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
        self.menuView = [[MWMMenuView alloc] initWithFrame:CGRectMake(40, 100, 260, 580)];
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

    if (!self.paraPanel) {
        self.paraPanel = [[UIView alloc] initWithFrame:CGRectMake(16, 170, 62, 122)];
        self.paraPanel.backgroundColor = [UIColor clearColor];

        self.paraGlideBtn = mkBtn(@"Glide", @selector(paraGlideTapped), self);
        self.paraGlideBtn.frame = CGRectMake(4, 0, 54, 34);
        [self.paraPanel addSubview:self.paraGlideBtn];

        self.paraUpBtn = mkBtn(@"Up", @selector(paraUpTapped), self);
        self.paraUpBtn.frame = CGRectMake(4, 42, 54, 34);
        [self.paraPanel addSubview:self.paraUpBtn];

        self.paraDownBtn = mkBtn(@"Down", @selector(paraDownTapped), self);
        self.paraDownBtn.frame = CGRectMake(4, 84, 54, 34);
        [self.paraPanel addSubview:self.paraDownBtn];

        self.paraPanel.hidden = YES;
        [w addSubview:self.paraPanel];
    }
    [self refreshParaPanel];

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

- (void)refreshParaPanel {
    if (!self.paraPanel) return;
    self.paraPanel.hidden = !g_paraCtl;
    self.paraGlideBtn.backgroundColor = g_glide
        ? [UIColor colorWithRed:0.15f green:0.75f blue:0.35f alpha:0.9f]
        : [UIColor colorWithRed:0.1f green:0.35f blue:0.8f alpha:0.85f];
    [self.paraGlideBtn setTitle:(g_glide ? @"Glide ON" : @"Glide") forState:UIControlStateNormal];

    UIColor *dim = [UIColor colorWithRed:0.1f green:0.35f blue:0.8f alpha:0.85f];
    UIColor *lit = [UIColor colorWithRed:0.15f green:0.75f blue:0.35f alpha:0.9f];
    self.paraUpBtn.backgroundColor = (g_paraDir > 0) ? lit : dim;
    self.paraDownBtn.backgroundColor = (g_paraDir < 0) ? lit : dim;
}

- (void)paraGlideTapped {
    g_glide = !g_glide;
    [self refreshParaPanel];
}
// Panel must not be reachable while Parachute Control is off.
- (void)paraUpTapped   { g_paraDir = (g_paraDir > 0) ? 0 : 1;  [self refreshParaPanel]; }
- (void)paraDownTapped { g_paraDir = (g_paraDir < 0) ? 0 : -1; [self refreshParaPanel]; }

- (void)setStatus:(const char *)s color:(UIColor *)col {
    if (!self.menuView) return;
    self.menuView.statusLabel.text = [NSString stringWithUTF8String:s];
    self.menuView.statusLabel.textColor = col;
}

- (void)onFrame {
    if (g_espOn || g_showAimFov) [self.espView setNeedsDisplay];

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
        g_myNetId = 0;
        [self setStatus:"Status: Lobby / Loading" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }
    // LocalPlayerType lives on Player, not on LocalPlayerManager.
    int type = off_playerType ? *(int *)((char *)player + off_playerType) : 1;
    if (type == 0 || type == 4) {
        g_lcam = nullptr;
        [self setStatus:"Status: In Lobby" color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    void *cam = readPtr(player, off_playerCam);
    g_lcam = alive(cam) ? cam : nullptr;
    if (!g_lcam) {
        [self setStatus:"Status: Loading Match..." color:[UIColor colorWithWhite:0.7 alpha:1.0]];
        return;
    }

    [self setStatus:"Status: In-Game (Active)" color:[UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1.0]];

    applyNoRecoil();
    applyNoSpread();
    applyParachuteControl();
    [self refreshParaPanel];

    if (g_espOn || g_aimlock) scanPlayers();

    // Publish the aim point for the swapped CreateShootData. Computed here on the
    // main thread so the weapon path only ever reads a plain float snapshot.
    g_aimHeadValid = NO;
    if (g_aimlock && g_targetCount > 0) {
        Vec3 head;
        if (pickBestTargetHead(&head) && vec3Finite(head)) {
            g_aimHead = head;
            g_aimHeadValid = YES;
            applyHardLock();          // snap the camera this frame
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
    i_image_get_class  = (void *(*)(void *, size_t))dlsym(RTLD_DEFAULT, "il2cpp_image_get_class");
    i_image_class_count= (size_t (*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_image_get_class_count");
    i_class_get_parent = (void *(*)(void *))dlsym(RTLD_DEFAULT, "il2cpp_class_get_parent");

    g_apiResolved = (i_domain_get && i_thread_attach && i_get_assemblies &&
                     i_assembly_image && i_image_name && i_class_from_name &&
                     i_method_from_name && i_field_from_name && i_field_offset &&
                     i_image_get_class && i_image_class_count && i_class_get_parent);
    if (!g_apiResolved) snprintf(g_diag, sizeof(g_diag), "Status: no il2cpp exports");
    return g_apiResolved;
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

// Decide whether `k` is ProjectileWeapon or derives from it.
static BOOL klassDerivesFrom(void *k, void *base) {
    int guard = 0;
    while (k && guard++ < 32) {
        if (k == base) return YES;
        if (!i_class_get_parent) break;
        k = i_class_get_parent(k);
    }
    return NO;
}

// Patch CreateShootData in the vtable of EVERY concrete weapon class.
//
// This was the reason nothing took effect: the MethodInfo we resolved belongs to
// ProjectileWeapon, but the object in the player's hands is a GunController (or one
// of a dozen siblings), and each class owns its own vtable. Patching only the base
// left every real weapon dispatching to the untouched body.
static BOOL installAimHook(void) {
    void *mi = M_createShootData;
    if (!mi) return NO;

    void *orig = *(void **)mi;                      // ProjectileWeapon.methodPointer
    if (!orig || (uintptr_t)orig < 0x1000) return NO;

    O_createShootData = orig;
    safeWritePtr(mi, (void *)&hk_createShootData);  // reflection path

    void *game = findImage("Assembly-CSharp.dll");
    void *base = i_class_from_name(game, "HQFPSTemplate.Equipment", "ProjectileWeapon");
    if (!game || !base || !i_image_get_class || !i_image_class_count) return NO;

    size_t n = i_image_class_count(game);
    int patched = 0, seen = 0;
    for (size_t i = 0; i < n; i++) {
        void *k = i_image_get_class(game, i);
        if (!k || !klassDerivesFrom(k, base)) continue;
        seen++;
        if (patchVtableSlot(mi, orig, (void *)&hk_createShootData, k, "CreateShootData"))
            patched++;
    }

    NSLog(@"[MWM] aim hook: %d/%d weapon vtables patched", patched, seen);
    if (!patched) {
        O_createShootData = nullptr;
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

    K_player    = i_class_from_name(game, "HQFPSTemplate", "Player");
    K_lpm       = i_class_from_name(game, "", "LocalPlayerManager");
    K_camera    = i_class_from_name(core, "UnityEngine", "Camera");

    // Field names verified against this build's dump.cs.
    off_cachedPtr    = fieldOff(K_obj, "m_CachedPtr");        // 0x10
    off_lpmPlayer    = fieldOff(K_lpm, "mLocalPlayer");       // 0x18
    off_playerType   = fieldOff(K_player, "LocalPlayerType"); // 0x4C8 (on Player)
    off_playerCam    = fieldOff(K_player, "_PlayerCamera");   // 0x4E8
    off_playerMovement = fieldOff(K_player, "_PlayerMovement"); // 0x4D8

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

    // Recoil / force angle live on PlayerCamera; the parachute module on PlayerMovementFP.
    void *K_playerCam = i_class_from_name(game, "HQFPSTemplate", "PlayerCamera");
    off_recoilAngles  = fieldOff(K_playerCam, "m_RecoilAngles");   // 0x58
    off_forceAngle    = fieldOff(K_playerCam, "m_ForceAngle");     // 0x64
    off_recoilEnabled = fieldOff(K_playerCam, "m_RecoilEnabled");  // 0x60
    off_lookAngles    = fieldOff(K_playerCam, "m_LookAngles");     // 0x50
    off_enableSmooth  = fieldOff(K_playerCam, "EnableSmooth");     // 0x84
    off_rotationLerp  = fieldOff(K_playerCam, "RotationLerpSpeed");// 0x90

    void *K_moveFP = i_class_from_name(game, "HQFPSTemplate", "PlayerMovementFP");
    off_parachuteState = fieldOff(K_moveFP, "m_ParachuteState");  // 0x1C8


    void *K_projWeapon = i_class_from_name(game, "HQFPSTemplate.Equipment", "ProjectileWeapon");
    M_createShootData = methodOf(K_projWeapon, "CreateShootData", 1);
    off_wpnShootAcc   = fieldOff(K_projWeapon, "shootAccurate");  // 0x114
    off_wpnCurAcc     = fieldOff(K_projWeapon, "curAccurate");    // 0x110
    // Accurate is declared on Entity, the base of Player; il2cpp field lookup only
    // sees fields declared on the class itself.
    void *K_entity = i_class_from_name(game, "HQFPSTemplate", "Entity");
    off_playerAccurate= fieldOff(K_entity, "Accurate");           // 0x100

    // Wall check uses the game's own assist masks so the answer matches the engine.
    // Physics is NOT in CoreModule: it lives in UnityEngine.PhysicsModule.dll. Looking
    // it up in `core` returned null, so Linecast never resolved and the wall check
    // silently fell through to "cannot verify".
    void *physMod   = findImage("UnityEngine.PhysicsModule.dll");
    void *K_physics = physMod ? i_class_from_name(physMod, "UnityEngine", "Physics") : nullptr;
    void *K_layer   = i_class_from_name(game, "", "LayerHelper");

    // Unity declares Linecast(start, end, layerMask, queryTriggerInteraction); the
    // 3-argument overload in the C# source is a default argument, not its own
    // MethodInfo. Resolve the 4-arg form first and remember which one we got.
    M_linecast = methodOf(K_physics, "Linecast", 4);
    g_linecastArgs = 4;
    if (!MP(M_linecast)) {
        M_linecast = methodOf(K_physics, "Linecast", 3);
        g_linecastArgs = 3;
    }
    if (!MP(M_linecast))
        NSLog(@"[MWM] Physics.Linecast unresolved - wallcheck fails closed");

    M_barrierLayerMask = methodOf(K_layer, "GetHeroAssistBarrierLayerMask", 0);

    if (g_bypassTutorial) {
        replaceMethod(M_guideInit, (void *)&dummy_ret);              // Init(): no step machine
        replaceMethod(M_checkGuideScene, (void *)&dummy_false);      // static bool
        replaceMethod(M_isNewbieGame, (void *)&dummy_false);         // static bool
    }
    if (g_bypassRankLock) {
        replaceMethod(M_checkFuncOpen, (void *)&dummy_true_i);       // bool (int)
        replaceMethod(M_checkFuncUnlock, (void *)&dummy_true_ic);    // bool (int, Action)
    }

    // Swap happens while still in the lobby: the game is not inside Shoot() yet,
    // so no thread can be executing the pointer being replaced.
    g_aimHookOk = installAimHook();

    NSLog(@"[MWM] armed netMap=%zu aim=%d", off_netPlayerMap, g_aimHookOk);
    snprintf(g_diag, sizeof(g_diag), "Status: Armed (aim=%s)", g_aimHookOk ? "yes" : "no");
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

#endif  // MWM_TWEAK_XM
