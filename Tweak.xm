// Tweak.xm — Race Toolkit (iOS, il2cpp / UnityFramework)
//
// Logs to  <app Documents>/racetoolkit.log   (O_APPEND + fsync on every line,
// so the file survives a hard crash; no NSLog / os_log dependency).
//
// Every hook target is verified against its expected 8-byte prologue taken from
// the Il2Cpp dump BEFORE patching. A mismatch means the on-device UnityFramework
// does not match the dump -> the hook is skipped and logged instead of writing a
// 16-byte patch into unrelated code (that was the "crash on entering game" bug).
//
//   RVA          function                                          size
//   0x53D8430    void GameGoState::ImpEnter()                      1408
//   0x9CF33DC    void SingleNitrogenCollect::Update(float)          716
//   0x9CF229C    float SingleNitrogenCollect::get_ProgressBarPowerValue() 132
//   0x50A40C4    void EvtMini::Update(float)                        924
//   0x50A5468    bool EvtMini::UpdateIsCanTrigger()                 888
//   0x50A62C8    int  EvtMini::Trigger()                            996
//   0x50A6BA0    bool EvtN2O::IsCanTrigger()                        632
//   0x50A6E18    int  EvtN2O::Trigger()                             264
//   0x50DE3D8    bool ExtraVelocityTriggerMgr::IsCanTriggerExtraVelocity(int) 236
//   0x7C6E51C    void NssVehicleDriftCtrl::ReleaseDrifting()        328
//   0x7C6E664    void NssVehicleDriftCtrl::ForceEndDrifting()       208
//   0x7AF996C    void NssPhyVehicleECU::SetNormalTopMPS(float)      220
//
// NOT hooked (8-byte leaf functions — a 16-byte MSHookFunction patch would
// overwrite the next function):
//   0x9CF2340  get_NitrogenValue        (overwrote get_CollisionPickLossPowerNum)
//   0x7AF9964  ReadNormalTopMPS         (overwrote SetNormalTopMPS)

// Feature-test macros MUST come before the first system header, otherwise
// iPhoneOS26.sdk's <ucontext.h> errors out with
//   "The deprecated ucontext routines require _XOPEN_SOURCE to be defined".
// _DARWIN_C_SOURCE keeps the Darwin-specific extensions available.
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE 1
#endif

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <execinfo.h>
// arm64 Darwin: ucontext_t + mcontext64 live here; avoids the deprecated
// <ucontext.h> wrapper entirely.
#include <sys/ucontext.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <time.h>
#include <sys/time.h>
#include <mach-o/dyld.h>

#pragma mark - File logger (async-signal-safe)

static int gLogFd = -1;
static char gLogPath[1024];

static void rtLogOpen(void) {
    if (gLogFd >= 0) return;
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                             NSUserDomainMask, YES).firstObject;
        if (!docs.length) docs = NSTemporaryDirectory();
        NSString *p = [docs stringByAppendingPathComponent:@"racetoolkit.log"];
        strncpy(gLogPath, p.fileSystemRepresentation, sizeof(gLogPath) - 1);
        gLogFd = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
}

// Pure C, no ObjC/allocation: callable from hooks. Escalates to fsync so the
// line survives a crash immediately after it is written.
static void rtLog(const char *fmt, ...) {
    if (gLogFd < 0) return;
    char buf[768];
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int n = snprintf(buf, sizeof(buf), "[%ld.%03ld] ",
                     (long)ts.tv_sec, (long)(ts.tv_nsec / 1000000));
    if (n < 0) return;
    va_list ap;
    va_start(ap, fmt);
    int m = vsnprintf(buf + n, sizeof(buf) - (size_t)n - 2, fmt, ap);
    va_end(ap);
    if (m > 0) n += m;
    if (n > (int)sizeof(buf) - 2) n = (int)sizeof(buf) - 2;
    buf[n++] = '\n';
    ssize_t w = write(gLogFd, buf, (size_t)n);
    (void)w;
    fsync(gLogFd);
}

// Log at most `max` times per call site, then go silent (hot paths run per frame).
#define RT_TRACE(max, ...)                        \
    do {                                          \
        static int _rt_n = 0;                     \
        if (_rt_n < (max)) { ++_rt_n; rtLog(__VA_ARGS__); } \
    } while (0)

#pragma mark - Crash handler with backtrace

// Async-signal-safe hex append (no snprintf / malloc / ObjC in the handler).
static int rtAppendHex(char *dst, int off, uintptr_t v) {
    static const char hexd[] = "0123456789abcdef";
    char tmp[2 + sizeof(uintptr_t) * 2];
    int i = 0;
    tmp[i++] = '0'; tmp[i++] = 'x';
    int started = 0;
    for (int shift = (int)(sizeof(uintptr_t) * 8) - 4; shift >= 0; shift -= 4) {
        unsigned d = (unsigned)((v >> shift) & 0xF);
        if (d || started || shift == 0) { tmp[i++] = hexd[d]; started = 1; }
    }
    for (int j = 0; j < i; j++) dst[off++] = tmp[j];
    return off;
}

// Precomputed at init (not in the handler) so the handler only reads memory.
#define RT_MAX_IMG 96
static uintptr_t gImgBase[RT_MAX_IMG];
static char      gImgName[RT_MAX_IMG][64];
static int       gImgCount = 0;

static void rtSnapshotImages(void) {
    int n = 0;
    for (uint32_t i = 0; i < _dyld_image_count() && n < RT_MAX_IMG; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (!nm) continue;
        gImgBase[n] = (uintptr_t)_dyld_get_image_header(i);
        const char *slash = strrchr(nm, '/');
        strncpy(gImgName[n], slash ? slash + 1 : nm, sizeof(gImgName[n]) - 1);
        n++;
    }
    // insertion sort by base -> lets the handler locate an address by range
    for (int i = 1; i < n; i++) {
        uintptr_t b = gImgBase[i]; char tmp[64];
        strncpy(tmp, gImgName[i], sizeof(tmp));
        int j = i - 1;
        while (j >= 0 && gImgBase[j] > b) {
            gImgBase[j + 1] = gImgBase[j];
            strncpy(gImgName[j + 1], gImgName[j], sizeof(gImgName[j + 1]) - 1);
            j--;
        }
        gImgBase[j + 1] = b;
        strncpy(gImgName[j + 1], tmp, sizeof(gImgName[j + 1]) - 1);
    }
    gImgCount = n;
}

// Signal-safe: returns "Img+0xoff" into dst, or just the hex address.
static int rtDescribeAddr(char *dst, int off, uintptr_t a) {
    for (int i = gImgCount - 1; i >= 0; i--) {
        if (a < gImgBase[i]) continue;
        const char *nm = gImgName[i];
        while (*nm) dst[off++] = *nm++;
        dst[off++] = '+';
        return rtAppendHex(dst, off, a - gImgBase[i]);
    }
    return rtAppendHex(dst, off, a);
}

static void rtSignalHandler(int sig, siginfo_t *info, void *uap) {
    ucontext_t *uc = (ucontext_t *)uap;
    if (gLogFd < 0) { signal(sig, SIG_DFL); raise(sig); return; }

    char hdr[192];
    int n = 0;
    const char *pre = "\n===== CRASH signal=";
    while (*pre) hdr[n++] = *pre++;
    n = rtAppendHex(hdr, n, (uintptr_t)sig);
    const char *mid = " faultAddr=";
    while (*mid) hdr[n++] = *mid++;
    n = rtAppendHex(hdr, n, info ? (uintptr_t)info->si_addr : 0);
    const char *end = " =====\n";
    while (*end) hdr[n++] = *end++;
    ssize_t w = write(gLogFd, hdr, (size_t)n);
    (void)w;

    // Where it actually died: PC/LR from ucontext beats backtrace_symbols_fd,
    // which returns 0 frames when the crash is outside a valid frame chain.
    char loc[320];
    int k = 0;
    const char *p1 = "  PC="; while (*p1) loc[k++] = *p1++;
    k = rtDescribeAddr(loc, k, uc && uc->uc_mcontext ? (uintptr_t)uc->uc_mcontext->__ss.__pc : 0);
    const char *p2 = "  LR="; while (*p2) loc[k++] = *p2++;
    k = rtDescribeAddr(loc, k, uc && uc->uc_mcontext ? (uintptr_t)uc->uc_mcontext->__ss.__lr : 0);
    const char *p3 = "\n"; loc[k++] = *p3++;
    ssize_t w2 = write(gLogFd, loc, (size_t)k);
    (void)w2;

    void *frames[64];
    int c = backtrace(frames, 64);
    if (c > 0) backtrace_symbols_fd(frames, c, gLogFd);
    fsync(gLogFd);

    signal(sig, SIG_DFL);
    raise(sig);
}

static void rtInstallCrashHandler(void) {
    static char altStack[64 * 1024];   // fixed size: constant on every SDK
    stack_t ss;
    ss.ss_sp = altStack;
    ss.ss_size = sizeof(altStack);
    ss.ss_flags = 0;
    sigaltstack(&ss, NULL);   // survive stack-overflow crashes

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = rtSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
        sigaction(sigs[i], &sa, NULL);
    }
}

#pragma mark - Toolkit state

static BOOL   gFullNitro     = NO;
static BOOL   gFullMiniBoost = NO;
static BOOL   gAutoDriftEnd  = NO;
static float  gSpeedKmh      = 0.f;
static double gGoTime        = 0.0;

static const float    kSpeedDelaySeconds = 5.0f;
static const uint32_t kNitroMaxPower     = 1000;
static const int      kTypeMini          = 2;

// Il2cpp field offsets, DECIMAL (as printed by Hex-Rays).
enum {
    kOffNitroCurPower   = 208,  // 0xD0 mCurPower (uint)
    kOffTopMps          = 264,  // 0x108 NssPhyVehicleECUBase::mNormalTopMPS (float)
    kOffEvtVdAngleMax   = 116,  // 0x74 mDriftingMaxAbsVDAngle
    kOffEvtDriftingTime = 124,  // 0x7C mDriftingTime
    kOffEvtInCanTrigger = 133,  // 0x85 mInCanTriggerTime (bool)
    kOffEvtMiniVdMax    = 136,  // 0x88 mMiniBoostDriftingMaxAbsVDAngle
    kOffEvtInChecking   = 140,  // 0x8C mIsInCheckingCanTrigger (bool)
    kOffEvtCheckTime    = 144,  // 0x90 mNewCheckMiniBoostTime (float)
    kOffEvtLastDrift    = 160,  // 0xA0 mLastIsDrifting (bool)
};

static inline double nowSeconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static inline BOOL speedWindowOpen(void) {
    if (gSpeedKmh <= 0.f || gGoTime <= 0.0) return NO;
    return (nowSeconds() - gGoTime) >= (double)kSpeedDelaySeconds;
}

// NssVehicle::mIsMainPlayer @ 0xF8
static inline BOOL vehicleIsMainPlayer(void *vehicle) {
    if (!vehicle) return NO;
    return *(uint8_t *)((char *)vehicle + 0xF8) != 0;
}

// ExtraVelocityTriggerBase::mVehicle @ 0x18
static inline BOOL evtIsMainPlayer(void *evt) {
    if (!evt) return NO;
    return vehicleIsMainPlayer(*(void **)((char *)evt + 0x18));
}

#pragma mark - Trampolines

static void  (*orig_GameGo_ImpEnter)(void *);
static void  (*orig_Nitro_Update)(void *, float);
static float (*orig_Nitro_GetProgress)(void *);
static void  (*orig_EvtMini_Update)(void *, float);
static BOOL  (*orig_EvtMini_CanTrigger)(void *);
static int   (*orig_EvtMini_Trigger)(void *);
static BOOL  (*orig_EvtN2O_CanTrigger)(void *);
static int   (*orig_EvtN2O_Trigger)(void *);
static BOOL  (*orig_IsCanTriggerExVel)(void *, int);
static void  (*orig_Drift_Release)(void *);
static void  (*orig_Drift_ForceEnd)(void *);
static void  (*orig_ECU_SetNormalTopMPS)(void *, float);

#pragma mark - Hooks

static void hook_GoImpEnter(void *self) {
    RT_TRACE(4, "hook GameGoState::ImpEnter self=%p", self);
    if (!orig_GameGo_ImpEnter) return;
    orig_GameGo_ImpEnter(self);
    gGoTime = nowSeconds();
    rtLog("race started -> speed gate armed (%.1fs delay)", kSpeedDelaySeconds);
}

static void hook_NitroUpdate(void *self, float dt) {
    RT_TRACE(3, "hook Nitro::Update self=%p dt=%.3f", self, dt);
    if (!orig_Nitro_Update) return;
    orig_Nitro_Update(self, dt);
    if (!gFullNitro || !self) return;
    void *veh = *(void **)((char *)self + 0x60);
    if (!vehicleIsMainPlayer(veh)) return;
    *(uint32_t *)((char *)self + kOffNitroCurPower) = kNitroMaxPower;
}

static float hook_NitroGetProgress(void *self) {
    RT_TRACE(3, "hook Nitro::get_ProgressBarPowerValue self=%p", self);
    if (gFullNitro && self &&
        vehicleIsMainPlayer(*(void **)((char *)self + 0x60))) return 1.0f;
    return orig_Nitro_GetProgress ? orig_Nitro_GetProgress(self) : 0.0f;
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
    RT_TRACE(3, "hook EvtMini::Update self=%p", self);
    if (!orig_EvtMini_Update) return;
    orig_EvtMini_Update(self, dt);
    if (!gFullMiniBoost || !self) return;
    if (!evtIsMainPlayer(self)) return;
    armMiniWindow(self);
}

static BOOL hook_EvtMiniCanTrigger(void *self) {
    RT_TRACE(5, "hook EvtMini::UpdateIsCanTrigger self=%p", self);
    if (gFullMiniBoost && evtIsMainPlayer(self)) {
        armMiniWindow(self);
        return YES;
    }
    return orig_EvtMini_CanTrigger ? orig_EvtMini_CanTrigger(self) : NO;
}

static int hook_EvtMiniTrigger(void *self) {
    RT_TRACE(5, "hook EvtMini::Trigger self=%p", self);
    return orig_EvtMini_Trigger ? orig_EvtMini_Trigger(self) : -1;
}

static BOOL hook_EvtN2OCanTrigger(void *self) {
    RT_TRACE(5, "hook EvtN2O::IsCanTrigger self=%p", self);
    if (gFullNitro && evtIsMainPlayer(self)) return YES;
    return orig_EvtN2O_CanTrigger ? orig_EvtN2O_CanTrigger(self) : NO;
}

static int hook_EvtN2OTrigger(void *self) {
    RT_TRACE(5, "hook EvtN2O::Trigger self=%p", self);
    return orig_EvtN2O_Trigger ? orig_EvtN2O_Trigger(self) : -1;
}

// ExtraVelocityTriggerMgr::mVehicle @ 0x68
static BOOL hook_IsCanTriggerExVel(void *self, int type) {
    RT_TRACE(6, "hook IsCanTriggerExtraVelocity self=%p type=%d", self, type);
    BOOL mine = self && vehicleIsMainPlayer(*(void **)((char *)self + 0x68));
    if (mine && type == kTypeMini && gFullMiniBoost) return YES;
    return orig_IsCanTriggerExVel ? orig_IsCanTriggerExVel(self, type) : NO;
}

static void hook_DriftForceEnd(void *self) {
    RT_TRACE(4, "hook DriftCtrl::ForceEndDrifting self=%p", self);
    if (orig_Drift_ForceEnd) orig_Drift_ForceEnd(self);
}

static void hook_DriftRelease(void *self) {
    RT_TRACE(4, "hook DriftCtrl::ReleaseDrifting self=%p", self);
    if (!orig_Drift_Release) return;
    orig_Drift_Release(self);
    if (!gAutoDriftEnd || !self) return;

    void *dyn = *(void **)((char *)self + 0x10);   // NssVehicleDriftCtrl.mVehicle : IDynamicVehicle
    if (!dyn) return;
    void *veh = *(void **)((char *)dyn + 0x10);    // DynamicVehicle.mVehicle : IVehicle
    if (!vehicleIsMainPlayer(veh)) return;

    if (orig_Drift_ForceEnd) orig_Drift_ForceEnd(self);
}

static void hook_SetNormalTopMPS(void *self, float topMps) {
    RT_TRACE(3, "hook ECU::SetNormalTopMPS self=%p mps=%.3f", self, topMps);
    if (orig_ECU_SetNormalTopMPS) orig_ECU_SetNormalTopMPS(self, topMps);

    if (!self || !speedWindowOpen()) return;
    void *veh = *(void **)((char *)self + 0x18);   // NssPhyVehicleECUBase.mVehicle
    if (!vehicleIsMainPlayer(veh)) return;
    *(float *)((char *)self + kOffTopMps) += gSpeedKmh / 3.6f;
}

#pragma mark - Install with prologue verification

typedef struct {
    uint32_t rva;
    const char *name;
    uint8_t  expect[8];      // first 2 AArch64 instructions, from the dump
    void    *replacement;
    void   **trampoline;
} RTHookSpec;

static uintptr_t unityFrameworkBase(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// MSHookFunction returns void: on failure it leaves *orig == NULL and may have
// already written part of its 16-byte patch into the target. That is exactly
// what the log showed (6/12 orig=0x0, then SIGBUS). So: snapshot the bytes
// first, and restore them if the trampoline came back NULL.
#define RT_PATCH_LEN 32

static BOOL rtMakeWritable(void *addr, size_t len) {
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)addr, len,
                                  false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    return kr == KERN_SUCCESS;
}

static void rtRestoreBytes(void *addr, const uint8_t *saved, size_t len) {
    if (!rtMakeWritable(addr, len)) {
        rtLog("restore: vm_protect FAILED for %p", addr);
        return;
    }
    memcpy(addr, saved, len);
    sys_icache_invalidate(addr, len);
}

static void installHooks(void) {
    uintptr_t b = unityFrameworkBase();
    if (!b) { rtLog("install: UnityFramework base not found"); return; }
    rtLog("install: UnityFramework base = %p", (void *)b);

    static RTHookSpec specs[] = {
        { 0x53D8430, "GameGoState::ImpEnter",
          {0xFA,0x67,0xBB,0xA9,0xF8,0x5F,0x01,0xA9},
          (void *)hook_GoImpEnter, (void **)&orig_GameGo_ImpEnter },
        { 0x9CF33DC, "SingleNitrogenCollect::Update",
          {0xE9,0x23,0xBB,0x6D,0xF8,0x5F,0x01,0xA9},
          (void *)hook_NitroUpdate, (void **)&orig_Nitro_Update },
        { 0x9CF229C, "Nitro::get_ProgressBarPowerValue",
          {0xF4,0x4F,0xBE,0xA9,0xFD,0x7B,0x01,0xA9},
          (void *)hook_NitroGetProgress, (void **)&orig_Nitro_GetProgress },
        { 0x50A40C4, "EvtMini::Update",
          {0xE9,0x23,0xBA,0x6D,0xFA,0x67,0x01,0xA9},
          (void *)hook_EvtMiniUpdate, (void **)&orig_EvtMini_Update },
        { 0x50A5468, "EvtMini::UpdateIsCanTrigger",
          {0xF8,0x5F,0xBC,0xA9,0xF6,0x57,0x01,0xA9},
          (void *)hook_EvtMiniCanTrigger, (void **)&orig_EvtMini_CanTrigger },
        { 0x50A62C8, "EvtMini::Trigger",
          {0xF8,0x5F,0xBC,0xA9,0xF6,0x57,0x01,0xA9},
          (void *)hook_EvtMiniTrigger, (void **)&orig_EvtMini_Trigger },
        { 0x50A6BA0, "EvtN2O::IsCanTrigger",
          {0xF8,0x5F,0xBC,0xA9,0xF6,0x57,0x01,0xA9},
          (void *)hook_EvtN2OCanTrigger, (void **)&orig_EvtN2O_CanTrigger },
        { 0x50A6E18, "EvtN2O::Trigger",
          {0xF4,0x4F,0xBE,0xA9,0xFD,0x7B,0x01,0xA9},
          (void *)hook_EvtN2OTrigger, (void **)&orig_EvtN2O_Trigger },
        { 0x50DE3D8, "TriggerMgr::IsCanTriggerExtraVelocity",
          {0xF6,0x57,0xBD,0xA9,0xF4,0x4F,0x01,0xA9},
          (void *)hook_IsCanTriggerExVel, (void **)&orig_IsCanTriggerExVel },
        { 0x7C6E51C, "DriftCtrl::ReleaseDrifting",
          {0xF6,0x57,0xBD,0xA9,0xF4,0x4F,0x01,0xA9},
          (void *)hook_DriftRelease, (void **)&orig_Drift_Release },
        { 0x7C6E664, "DriftCtrl::ForceEndDrifting",
          {0xF4,0x4F,0xBE,0xA9,0xFD,0x7B,0x01,0xA9},
          (void *)hook_DriftForceEnd, (void **)&orig_Drift_ForceEnd },
        { 0x7AF996C, "NssPhyVehicleECU::SetNormalTopMPS",
          {0xE9,0x23,0xBD,0x6D,0xF4,0x4F,0x01,0xA9},
          (void *)hook_SetNormalTopMPS, (void **)&orig_ECU_SetNormalTopMPS },
    };

    size_t count = sizeof(specs) / sizeof(specs[0]);
    rtLog("install: %zu hook targets", count);

    for (size_t i = 0; i < count; i++) {
        RTHookSpec *s = &specs[i];
        uint8_t *addr = (uint8_t *)(b + s->rva);

        uint8_t have[8];
        memcpy(have, addr, sizeof(have));

        if (memcmp(have, s->expect, sizeof(have)) != 0) {
            rtLog("SKIP %-40s @%p  prologue MISMATCH\n"
                  "        have     %02X %02X %02X %02X %02X %02X %02X %02X\n"
                  "        expected %02X %02X %02X %02X %02X %02X %02X %02X",
                  s->name, addr,
                  have[0],have[1],have[2],have[3],have[4],have[5],have[6],have[7],
                  s->expect[0],s->expect[1],s->expect[2],s->expect[3],
                  s->expect[4],s->expect[5],s->expect[6],s->expect[7]);
            continue;   // wrong build/version -> do not patch
        }

        uint8_t saved[RT_PATCH_LEN];
        memcpy(saved, addr, sizeof(saved));

        MSHookFunction(addr, s->replacement, s->trampoline);

        if (*(s->trampoline) == NULL) {
            // Trampoline creation failed. Undo whatever the patcher wrote.
            rtRestoreBytes(addr, saved, sizeof(saved));
            uint8_t after[8];
            memcpy(after, addr, sizeof(after));
            BOOL restored = memcmp(after, s->expect, sizeof(after)) == 0;
            rtLog("FAIL %-40s @%p orig=NULL -> bytes %s",
                  s->name, addr, restored ? "RESTORED" : "STILL CORRUPT");
            continue;
        }

        rtLog("HOOK %-40s @%p orig=%p", s->name, addr, *(s->trampoline));
    }
    rtLog("install: done");
}

#pragma mark - UI

// Window that only takes touches landing on our own controls.
@interface RCPassThroughWindow : UIWindow
@end

@implementation RCPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if (hit == self) return nil;
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeFocused  { return NO; }
@end

@interface RCRaceToolkitMenu : NSObject
@property (nonatomic, strong) RCPassThroughWindow *window;
@property (nonatomic, strong) UIView *host;
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

    self.window = [[RCPassThroughWindow alloc] initWithFrame:screen];

    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            if (sc.activationState != UISceneActivationStateForegroundActive) continue;
            self.window.windowScene = (UIWindowScene *)sc;
            break;
        }
    }
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.opaque = NO;
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.rootViewController.view.opaque = NO;
    self.window.hidden = NO;   // never makeKeyAndVisible: keep the game key

    self.host = self.window.rootViewController.view;

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
    [self.host addSubview:self.fab];

    CGFloat w = 300, h = 300;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - w) / 2,
                                                        (screen.size.height - h) / 2, w, h)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.panel.hidden = YES;
    [self.host addSubview:self.panel];

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
    note.text = @"Speed applies only after race start + 5s.\nAuto End Drift ends the drift when the drift key is released.";
    [self.panel addSubview:note];
}

- (NSString *)speedText {
    return [NSString stringWithFormat:@"Boost speed: %d km/h (+5s)", (int)gSpeedKmh];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.hidden = NO;
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.fab.superview];
}

- (void)onNitro:(UISwitch *)s     { gFullNitro = s.isOn;     rtLog("toggle FullNitro=%d", s.isOn); }
- (void)onMini:(UISwitch *)s      { gFullMiniBoost = s.isOn; rtLog("toggle FullMiniBoost=%d", s.isOn); }
- (void)onAutoDrift:(UISwitch *)s { gAutoDriftEnd = s.isOn;  rtLog("toggle AutoEndDrift=%d", s.isOn); }

- (void)onSpeedChanged:(UISlider *)s {
    gSpeedKmh = s.value;
    self.speedLabel.text = [self speedText];
    rtLog("speed slider = %.0f km/h", gSpeedKmh);
}

@end

#pragma mark - Bootstrap

static BOOL gHooksInstalled = NO;

static void buildMenuSafely(void) {
    if (gMenu) return;
    @try {
        gMenu = [RCRaceToolkitMenu new];
        [gMenu build];
        rtLog("UI: menu built");
    } @catch (NSException *e) {
        gMenu = nil;
        rtLog("UI: menu build FAILED: %s", e.reason.UTF8String ?: "?");
    }
}

static void startToolkit(void) {
    static int tries = 0;
    if (!unityFrameworkBase()) {
        if (++tries > 240) { rtLog("bootstrap: gave up waiting for UnityFramework"); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ startToolkit(); });
        return;
    }
    rtLog("bootstrap: UnityFramework mapped after %d polls", tries);
    if (!gHooksInstalled) {
        gHooksInstalled = YES;
        installHooks();
    }
    buildMenuSafely();
}

__attribute__((constructor)) static void RCInit(void) {
    rtLogOpen();
    rtSnapshotImages();
    rtInstallCrashHandler();
    rtLog("=== RaceToolkit session start ===\nlog: %s\npid=%d", gLogPath, getpid());

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ startToolkit(); });
}
