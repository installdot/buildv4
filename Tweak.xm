// RaceRec — Ghi / Phát lại đường đua (record & playback)
// Fix: crash khi start, luôn nạp đúng map, tách biệt AUTO vs ANTI-AFK để khoanh vùng crash.

#import <UIKit/UIKit.h>
#import <math.h>
#import <string.h>
#import <stdarg.h>
#import <stdio.h>
#import <stdlib.h>
#import <time.h>
#import <dlfcn.h>
#import <unistd.h>
#import <fcntl.h>
#import <mach-o/dyld.h>

#pragma mark - Log

static int gLogFd = -1;

static void rtLogOpen(void) {
    if (gLogFd >= 0) return;
    NSArray *p = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [(p.firstObject ?: NSTemporaryDirectory()) stringByAppendingPathComponent:@"racekit_rp.log"];
    gLogFd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
}

static void rtLog(const char *fmt, ...) {
    if (gLogFd < 0) rtLogOpen();
    if (gLogFd < 0) return;
    char buf[1024];
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    int n = snprintf(buf, sizeof buf, "[%ld.%03ld] ", (long)ts.tv_sec, ts.tv_nsec / 1000000);
    va_list ap; va_start(ap, fmt);
    int m = vsnprintf(buf + n, sizeof buf - (size_t)n, fmt, ap);
    va_end(ap);
    if (m < 0 || n < 0 || (size_t)n >= sizeof buf) return;
    size_t total = (size_t)n + (size_t)m;
    if (total >= sizeof buf - 1) total = sizeof buf - 2;
    buf[total++] = '\n';
    ssize_t w = write(gLogFd, buf, total); (void)w;
}

static uintptr_t gUnityBase = 0;
static uintptr_t rtGetUnityBase(void) {
    if (gUnityBase) return gUnityBase;
    uint32_t cnt = _dyld_image_count();
    for (uint32_t i = 0; i < cnt; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            gUnityBase = (uintptr_t)_dyld_get_image_header(i);
            rtLog("UnityFramework base: 0x%lx", (unsigned long)gUnityBase);
            break;
        }
    }
    if (!gUnityBase) rtLog("WARN: UnityFramework base not found (dlsym/PHY calls disabled)");
    return gUnityBase;
}

#pragma mark - IL2CPP

typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppDomain Il2CppDomain;

typedef struct VirtualInvokeData { void *methodPtr; const MethodInfo *method; } VirtualInvokeData;

static Il2CppDomain *(*il2cpp_domain_get)(void);
static const Il2CppAssembly **(*il2cpp_domain_get_assemblies)(const Il2CppDomain *, size_t *);
static Il2CppImage *(*il2cpp_assembly_get_image)(const Il2CppAssembly *);
static Il2CppClass *(*il2cpp_class_from_name)(const Il2CppImage *, const char *, const char *);
static const MethodInfo *(*il2cpp_class_get_method_from_name)(Il2CppClass *, const char *, int);
static void *(*il2cpp_array_new)(void *elemClass, size_t length);
static void *(*il2cpp_object_new)(void *klass);

static BOOL rtInitIl2Cpp(void) {
    if (il2cpp_domain_get) return YES;
    void *h = dlopen("Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW);
    if (!h) h = RTLD_DEFAULT;
    *(void **)&il2cpp_domain_get                 = dlsym(h, "il2cpp_domain_get");
    *(void **)&il2cpp_domain_get_assemblies      = dlsym(h, "il2cpp_domain_get_assemblies");
    *(void **)&il2cpp_assembly_get_image         = dlsym(h, "il2cpp_assembly_get_image");
    *(void **)&il2cpp_class_from_name            = dlsym(h, "il2cpp_class_from_name");
    *(void **)&il2cpp_class_get_method_from_name = dlsym(h, "il2cpp_class_get_method_from_name");
    *(void **)&il2cpp_array_new                  = dlsym(h, "il2cpp_array_new");
    *(void **)&il2cpp_object_new                 = dlsym(h, "il2cpp_object_new");
    BOOL ok = il2cpp_domain_get && il2cpp_domain_get_assemblies && il2cpp_assembly_get_image
           && il2cpp_class_from_name && il2cpp_class_get_method_from_name;
    rtLog("il2cpp api: %s (arrNew=%p objNew=%p)", ok ? "OK" : "MISSING", il2cpp_array_new, il2cpp_object_new);
    return ok;
}

static Il2CppClass *rtFindClass(const char *ns, const char *name) {
    if (!rtInitIl2Cpp()) return NULL;
    size_t n = 0;
    const Il2CppAssembly **asms = il2cpp_domain_get_assemblies(il2cpp_domain_get(), &n);
    if (!asms) return NULL;
    for (size_t i = 0; i < n; i++) {
        Il2CppImage *img = il2cpp_assembly_get_image(asms[i]);
        if (!img) continue;
        Il2CppClass *k = il2cpp_class_from_name(img, ns, name);
        if (k) return k;
    }
    return NULL;
}

static BOOL rtPtrOk(const void *p) { return p && (uintptr_t)p > 0x1000 && (uintptr_t)p < 0x00007fffffffffffULL; }

static NSString *rtIl2CppString(void *il2cppStr) {
    if (!rtPtrOk(il2cppStr)) return nil;
    int32_t len = *(int32_t *)((char *)il2cppStr + 0x10);
    if (len <= 0 || len > 2048) return nil;
    const unichar *chars = (const unichar *)((char *)il2cppStr + 0x14);
    return [NSString stringWithCharacters:chars length:len];
}

static void *rtHookMethod(const char *ns, const char *cls, const char *mth, int argc, void *rep) {
    Il2CppClass *k = rtFindClass(ns, cls);
    if (!k) { rtLog("il2cpp: %s::%s class NOT FOUND", cls, mth); return NULL; }

    const MethodInfo *m = il2cpp_class_get_method_from_name(k, mth, argc);
    if (!m) { rtLog("il2cpp: %s::%s(%d) NOT FOUND", cls, mth, argc); return NULL; }

    void *orig = *(void **)((char *)m + 0);
    if (!orig) { rtLog("il2cpp: %s::%s null", cls, mth); return NULL; }
    if (orig == rep) return NULL;

    const uint16_t slot = *(const uint16_t *)((const char *)m + 0x58);
    *(void **)((char *)m + 0) = rep;

    BOOL vt = NO;
    if (slot < 512) {
        VirtualInvokeData *e = (VirtualInvokeData *)((char *)k + 328) + slot;
        e->methodPtr = rep; vt = YES;
    }
    rtLog("il2cpp: HOOK %s::%s slot=%u vtable=%s", cls, mth, (unsigned)slot, vt ? "OK" : "none");
    return orig;
}

#pragma mark - Offsets (đã kiểm chứng bằng dump.cs)

enum {
    kOffVehicleActorType      = 0x14,   // NssVehicle.mActorType
    kOffVehicleIsMainPlayer   = 0xF8,   // NssVehicle.mIsMainPlayer (bool)

    kOffMotionSteerData       = 0x10,   // NssPhyVehicleMotionCtrlHelper.mSteeringData
    kOffMotionVehicle         = 0x18,   // .mVehicle
    kOffMotionPhyCtrl         = 0x20,   // .mVehiclePhyCtrl
    kOffMotionDriving         = 0x38,   // .mDrivingCtrl
    kOffMotionForcePos        = 0x40,   // .mForceSetPos (Vector3)
    kOffMotionForceRot        = 0x4C,   // .mForceSetRot (Quaternion)
    kOffMotionIsSetTransform  = 0x70,   // .mIsSetTransform (bool)

    kOffPhySimOutput          = 0x28,   // NssPhyVehicleCtrl.mSimulateOutput
    kOffPhyIsInitFrame        = 0x74,   // NssPhyVehicleCtrl.mIsInitPhyFrame (bool)
    kOffPhyEnableUpdate       = 0x9C,   // NssPhyVehicleCtrl.mEnableUpdatePhy (bool)

    kOffSimKmph               = 0x10,   // NssVehicleSimOutput.mKmph
    kOffSimMps                = 0x14,   // .mMps
    kOffSimLinearVel          = 0x38,   // .mLinearVelocity
    kOffSimChassisPos         = 0x64,   // .mChassisPosition
    kOffSimChassisRot         = 0x70,   // .mChassisRotation
    kOffSimForwardForce       = 0xB4,   // .mForwardForce

    kOffSteerForward          = 0x10,   // NssSteeringData.mForward
    kOffSteerLeft             = 0x1C,   // .mSteeringLeft

    kOffDrvThrottle           = 0x3C,   // NssPhyVehicleDrivingCtrl.mThrottle
    kOffDrvSteering           = 0x40,   // .mSteering
    kOffDrvInputX             = 0x68,   // NssPlayerVehicleDrivingCtrl.mInputXPosition

    kOffCpMgrMapId            = 0x40,   // CheckPointMgr.mMapId  (IDA: a1+64)
    kOffCpMapId               = 0x1C,   // CheckPointConfig.MapId (IDA: a2+28)
    kOffCpCurveLength         = 0x2C,   // CheckPointConfig.MainCurveLength

    kOffInputKeyData          = 0xA8,   // InputModule.mInputKeyData
    kOffKeyDataFlags          = 0x10,   // InputKeyData.KeyFlags

    kOffSdcVehEndData         = 0x58,   // SdcVehicleInput.mEndData
    kOffSdcVehNotControlTime  = 0x9C,   // SdcVehicleInput.mNotControlTime
    kOffSdcVehLastIsControl   = 0xA0,   // SdcVehicleInput.mLastIsControl
    kOffSdcVehLastCtrlTime    = 0xA4,   // SdcVehicleInput.mLastControlTime
};

#pragma mark - Frame format

#define RC_MAGIC "RKR3"
#define RC_MAX_FRAMES 21600

typedef struct {
    float    t;
    float    px, py, pz;
    float    qx, qy, qz, qw;
    float    vx, vy, vz;
    float    kmph;
    float    steer;
    uint32_t keys;
    uint8_t  flags;
    uint8_t  pad[3];
} RCFrame;

typedef struct {
    float    t;
    float    px, py, pz;
    float    qx, qy, qz, qw;
    float    steer;
    uint32_t keys;
    uint8_t  flags;
    uint8_t  pad[3];
} RCFrameV2;

typedef struct {
    char     magic[4];
    uint32_t ver;
    uint32_t count;
    float    trackLen;
    int32_t  mapId;
    uint32_t frameSize;
} RCHeader;

static RCFrame *gFrames;
static uint32_t gFrameCount;
static int      gMapId;
static float    gTrackLen;
static double   gGoTime;
static BOOL gAutoArmed, gPlaying;
// CÔNG TẮC TÁCH BIỆT: bật/tắt ANTI-AFK để khoanh vùng crash
static BOOL gAntiAfk = YES;
static void *gPlayerVehicle;
static void *gInputModule;
static int   gKeyMask;
static float gCurPlaybackSteer;
static void *gMapDataComponent = NULL;
static BOOL gDownloading = NO;
static BOOL gPhyReadyLogged = NO;
static int  gAfkTickLog = 0;

#pragma mark - Storage & Parser .rep

static NSString *rtDir(void) {
    NSArray *p = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *d = [(p.firstObject ?: NSTemporaryDirectory()) stringByAppendingPathComponent:@"RaceKit"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}

static NSString *rtPathForTrack(void) {
    int mid = gMapId > 0 ? gMapId : 1;
    return [rtDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"rec_map%d.rk", mid]];
}

static BOOL rtSaveRecord(void) {
    if (!gFrameCount) return NO;
    int mid = gMapId > 0 ? gMapId : 1;
    NSString *path = rtPathForTrack();
    if (!path) return NO;
    FILE *f = fopen(path.fileSystemRepresentation, "wb");
    if (!f) return NO;

    RCHeader h;
    memcpy(h.magic, RC_MAGIC, 4);
    h.ver = 3; h.count = gFrameCount;
    h.trackLen = gTrackLen; h.mapId = mid; h.frameSize = sizeof(RCFrame);
    fwrite(&h, sizeof h, 1, f);
    fwrite(gFrames, sizeof(RCFrame), gFrameCount, f);
    fclose(f);
    rtLog("save: %u frames (%.2fs) map=%d -> %s", gFrameCount,
          gFrames[gFrameCount - 1].t, mid, path.UTF8String);
    return YES;
}

static BOOL rtExtractFramesFromDesHelper(void *desHelper) {
    if (!rtPtrOk(desHelper)) return NO;
    void *summary = *(void **)((char *)desHelper + 0x40); // <SummaryInfo>k__BackingField
    if (!rtPtrOk(summary)) {
        rtLog("[Rep] SummaryInfo is null");
        return NO;
    }

    uint32_t mapId = *(uint32_t *)((char *)summary + 0x20); // MapID
    uint64_t uid   = *(uint64_t *)((char *)summary + 0x30); // RecordPlayerUID
    rtLog("[Rep] Summary: mapId=%u, uid=%llu", mapId, (unsigned long long)uid);

    uintptr_t base = rtGetUnityBase();
    if (!base) return NO;

    typedef void *(*fn_GetTransInfos_t)(void *, uint64_t);
    fn_GetTransInfos_t fn_GetTransInfos = (fn_GetTransInfos_t)(base + 0x71B5608);

    void *p2p = fn_GetTransInfos ? fn_GetTransInfos(desHelper, uid) : NULL;
    if (!rtPtrOk(p2p)) {
        rtLog("[Rep] GetTransInfos null (uid=%llu)", (unsigned long long)uid);
        return NO;
    }

    void *moveList = *(void **)((char *)p2p + 0x10);
    if (!rtPtrOk(moveList)) { rtLog("[Rep] MoveInfo null"); return NO; }

    int count = *(int *)((char *)moveList + 0x18);
    void *arr = *(void **)((char *)moveList + 0x10);
    if (!rtPtrOk(arr) || count <= 0) { rtLog("[Rep] MoveInfo empty (%d)", count); return NO; }

    if (count > RC_MAX_FRAMES) count = RC_MAX_FRAMES;
    if (gFrames) { free(gFrames); gFrames = NULL; }
    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * count);
    if (!gFrames) return NO;

    void **items = (void **)((char *)arr + 0x20);
    for (int i = 0; i < count; i++) {
        void *m = items[i];
        if (!rtPtrOk(m)) continue;

        RCFrame fr;
        memset(&fr, 0, sizeof fr);
        fr.t    = *(float *)((char *)m + 0x18); // mClientTime
        fr.px   = *(float *)((char *)m + 0x24);
        fr.py   = *(float *)((char *)m + 0x28);
        fr.pz   = *(float *)((char *)m + 0x2C);
        fr.qx   = *(float *)((char *)m + 0x30);
        fr.qy   = *(float *)((char *)m + 0x34);
        fr.qz   = *(float *)((char *)m + 0x38);
        fr.qw   = *(float *)((char *)m + 0x3C);
        fr.vx   = *(float *)((char *)m + 0x40);
        fr.vy   = *(float *)((char *)m + 0x44);
        fr.vz   = *(float *)((char *)m + 0x48);

        float ql = sqrtf(fr.qx * fr.qx + fr.qy * fr.qy + fr.qz * fr.qz + fr.qw * fr.qw);
        if (ql > 1e-4f) { fr.qx /= ql; fr.qy /= ql; fr.qz /= ql; fr.qw /= ql; }

        float v_mps = sqrtf(fr.vx * fr.vx + fr.vy * fr.vy + fr.vz * fr.vz);
        float spd_kmh = v_mps * 3.6f;
        if (spd_kmh < 1.0f && i > 0) {
            float dt = fr.t - gFrames[i - 1].t;
            if (dt > 1e-4f) {
                float ddx = fr.px - gFrames[i - 1].px;
                float ddy = fr.py - gFrames[i - 1].py;
                float ddz = fr.pz - gFrames[i - 1].pz;
                spd_kmh = (sqrtf(ddx * ddx + ddy * ddy + ddz * ddz) / dt) * 3.6f;
                fr.vx = ddx / dt; fr.vy = ddy / dt; fr.vz = ddz / dt;
            }
        }
        if (spd_kmh > 400.f) spd_kmh = 400.f; // chặn vận tốc rác gây nổ PhysX
        fr.kmph = spd_kmh;

        uint32_t repKeys = *(uint32_t *)((char *)m + 0x20); // mKeyFlag
        uint32_t inputKeys = 0;
        if (repKeys & ((1 << 1) | (1 << 13)))  inputKeys |= (1 << 1); // Left
        if (repKeys & ((1 << 2) | (1 << 14)))  inputKeys |= (1 << 2); // Right
        if (repKeys & ((1 << 3) | (1 << 4)))   inputKeys |= (1 << 3); // Nitro
        if (repKeys & ((1 << 7) | (1 << 8)))   inputKeys |= (1 << 5); // MiniBoost
        if (repKeys & ((1 << 9) | (1 << 10)))  inputKeys |= (1 << 6); // Brake
        if (repKeys & ((1 << 13) | (1 << 14))) inputKeys |= (1 << 8); // Drift

        int state = *(int *)((char *)m + 0x74); // mState
        if (state == 2) inputKeys |= (1 << 8);

        fr.keys = inputKeys;

        float yawRate = *(float *)((char *)m + 0x50); // mAngVel.y
        if (inputKeys & (1 << 1)) fr.steer = -0.90f;
        else if (inputKeys & (1 << 2)) fr.steer = 0.90f;
        else if (fabsf(yawRate) > 0.08f) {
            float s = -yawRate * 0.45f;
            if (s > 1.0f) s = 1.0f;
            if (s < -1.0f) s = -1.0f;
            fr.steer = s;
        } else fr.steer = 0.f;

        uint8_t flags = 0;
        if (inputKeys & (1 << 6)) flags |= 0x01;
        if (inputKeys & (1 << 8)) flags |= 0x04;
        if (inputKeys & (1 << 3)) flags |= 0x08;
        if (inputKeys & (1 << 5)) flags |= 0x10;
        fr.flags = flags;

        gFrames[i] = fr;
    }
    gFrameCount = count;
    if (mapId > 0) gMapId = (int)mapId;
    rtLog("[Rep] EXTRACTED %u frames (mapId=%d)", gFrameCount, gMapId);

    rtSaveRecord();
    return YES;
}

static BOOL rtLoadRepFromDisk(NSString *repPath) {
    if (!repPath || ![[NSFileManager defaultManager] fileExistsAtPath:repPath]) return NO;
    NSData *data = [NSData dataWithContentsOfFile:repPath];
    if (!data || data.length < 16) return NO;

    rtLog("[Rep] Feeding %lu bytes into parser...", (unsigned long)data.length);

    void *byteClass = rtFindClass("System", "Byte");
    void *desClass  = rtFindClass("", "MatchVideoDesHelper");
    if (!byteClass || !desClass || !il2cpp_array_new || !il2cpp_object_new) {
        rtLog("[Rep] il2cpp missing: byte=%p des=%p arrNew=%p objNew=%p",
              byteClass, desClass, il2cpp_array_new, il2cpp_object_new);
        return NO;
    }

    uintptr_t base = rtGetUnityBase();
    if (!base) return NO;

    void *arr = il2cpp_array_new(byteClass, data.length);
    if (!arr) return NO;
    memcpy((char *)arr + 0x20, data.bytes, data.length);

    typedef void *(*fn_unzip_t)(void *, ...);
    fn_unzip_t fn_unzip = (fn_unzip_t)(base + 0x71E28EC);
    void *unzipArr = fn_unzip ? fn_unzip(arr) : arr;
    if (!unzipArr) unzipArr = arr;

    void *helper = il2cpp_object_new(desClass);
    if (!helper) return NO;
    typedef void (*fn_ctor_t)(void *);
    fn_ctor_t fn_ctor = (fn_ctor_t)(base + 0x71B6A88);
    if (fn_ctor) fn_ctor(helper);

    typedef BOOL (*fn_init_t)(void *, void *, ...);
    fn_init_t fn_init = (fn_init_t)(base + 0x71B3E20);
    BOOL ok = fn_init ? fn_init(helper, unzipArr) : NO;
    rtLog("[Rep] Parser InitByVideoBytes=%d", (int)ok);
    if (ok) return rtExtractFramesFromDesHelper(helper);
    return NO;
}

static NSString *rtFindRepFile(int targetMapId) {
    if (targetMapId <= 0) return nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *top3Path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d_3.rep", targetMapId]];
    if ([fm fileExistsAtPath:top3Path]) return top3Path;

    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
    NSString *prefix = [NSString stringWithFormat:@"%d_", targetMapId];
    NSString *exact  = [NSString stringWithFormat:@"%d.rep", targetMapId];
    NSString *newest = nil;
    NSDate *newestDate = [NSDate distantPast];

    for (NSString *name in files) {
        if (![name.pathExtension.lowercaseString isEqualToString:@"rep"]) continue;
        if (!([name hasPrefix:prefix] || [name isEqualToString:exact])) continue;
        NSString *full = [dir stringByAppendingPathComponent:name];
        NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
        NSDate *mod = attr.fileModificationDate ?: [NSDate date];
        if ([mod compare:newestDate] == NSOrderedDescending) { newestDate = mod; newest = full; }
    }
    // KHÔNG fallback sang map khác
    return newest;
}

static BOOL rtLoadRecord(void) {
    gFrameCount = 0;
    if (gFrames) { free(gFrames); gFrames = NULL; }

    rtLog("Searching .rep for map %d...", gMapId);
    NSString *rep = rtFindRepFile(gMapId);
    if (rep && rtLoadRepFromDisk(rep)) {
        if (gFrameCount > 0) { rtLog("LOADED %u frames from .rep", gFrameCount); return YES; }
    }

    NSString *path = rtPathForTrack();
    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        FILE *f = fopen(path.fileSystemRepresentation, "rb");
        if (f) {
            RCHeader h;
            if (fread(&h, sizeof h, 1, f) == 1 && h.count > 0 && h.count <= RC_MAX_FRAMES) {
                if (!memcmp(h.magic, RC_MAGIC, 4) && h.frameSize == sizeof(RCFrame)) {
                    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * h.count);
                    if (gFrames) gFrameCount = (uint32_t)fread(gFrames, sizeof(RCFrame), h.count, f);
                } else if (!memcmp(h.magic, "RKR2", 4) && h.frameSize == sizeof(RCFrameV2)) {
                    RCFrameV2 *v2 = (RCFrameV2 *)malloc(sizeof(RCFrameV2) * h.count);
                    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * h.count);
                    if (v2 && gFrames) {
                        uint32_t n = (uint32_t)fread(v2, sizeof(RCFrameV2), h.count, f);
                        for (uint32_t i = 0; i < n; i++) {
                            memset(&gFrames[i], 0, sizeof(RCFrame));
                            gFrames[i].t  = v2[i].t;
                            gFrames[i].px = v2[i].px; gFrames[i].py = v2[i].py; gFrames[i].pz = v2[i].pz;
                            gFrames[i].qx = v2[i].qx; gFrames[i].qy = v2[i].qy;
                            gFrames[i].qz = v2[i].qz; gFrames[i].qw = v2[i].qw;
                            gFrames[i].steer = v2[i].steer;
                            gFrames[i].keys  = v2[i].keys;
                            gFrames[i].flags = v2[i].flags;
                        }
                        gFrameCount = n;
                    }
                    if (v2) free(v2);
                }
                fclose(f);
                if (gFrameCount) { rtLog("LOADED %u frames from .rk", gFrameCount); return YES; }
            } else fclose(f);
        }
    }
    rtLog("No record for map %d", gMapId);
    return NO;
}

#pragma mark - Tải Replay Top 3 tất cả map

static void rtDownloadAllPeakSpeedReplays(void (^onProgress)(int done, int total, NSString *info), void (^onComplete)(int totalDownloaded)) {
    if (gDownloading) return;
    gDownloading = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
        NSString *tempDir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:NULL];

        NSMutableArray *queue = [NSMutableArray array];
        NSMutableSet *queuedMaps = [NSMutableSet set];

        if (rtPtrOk(gMapDataComponent)) {
            void *list = *(void **)((char *)gMapDataComponent + 0x98); // ListView<VideoDetailCfg>
            if (rtPtrOk(list)) {
                int count = *(int *)((char *)list + 0x18);
                void *arr = *(void **)((char *)list + 0x10);
                if (rtPtrOk(arr) && count > 0) {
                    void **items = (void **)((char *)arr + 0x20);
                    for (int i = 0; i < count; i++) {
                        void *cfg = items[i];
                        if (!rtPtrOk(cfg)) continue;
                        int mapId = *(int *)((char *)cfg + 0x14);
                        uint8_t gradeId = *(uint8_t *)((char *)cfg + 0x18);
                        if (gradeId != 3) continue; // chỉ Top 3
                        if ([queuedMaps containsObject:@(mapId)]) continue;
                        [queuedMaps addObject:@(mapId)];

                        NSString *urlStr = rtIl2CppString(*(void **)((char *)cfg + 0x30));
                        if (urlStr.length > 0) {
                            [queue addObject:@{
                                @"url": urlStr,
                                @"path": [tempDir stringByAppendingPathComponent:
                                          [NSString stringWithFormat:@"%d_3.rep", mapId]],
                                @"map": @(mapId)
                            }];
                        }
                    }
                }
            }
        }

        int total = (int)queue.count;
        if (total == 0) {
            NSArray *files = [fm contentsOfDirectoryAtPath:tempDir error:NULL];
            int c = 0;
            for (NSString *n in files) if ([n.pathExtension.lowercaseString isEqualToString:@"rep"]) c++;
            gDownloading = NO;
            if (onComplete) dispatch_async(dispatch_get_main_queue(), ^{ onComplete(c); });
            return;
        }

        __block int done = 0;
        __block int successCount = 0;
        dispatch_semaphore_t sem = dispatch_semaphore_create(4);

        for (NSDictionary *item in queue) {
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            NSString *urlStr = item[@"url"];
            NSString *destPath = item[@"path"];
            int mapId = [item[@"map"] intValue];

            if ([fm fileExistsAtPath:destPath]) {
                done++; successCount++;
                if (onProgress) { int d = done; dispatch_async(dispatch_get_main_queue(), ^{ onProgress(d, total, [NSString stringWithFormat:@"Map %d (có sẵn)", mapId]); }); }
                dispatch_semaphore_signal(sem);
                continue;
            }

            NSURL *url = [NSURL URLWithString:urlStr];
            if (!url && ![urlStr hasPrefix:@"http"])
                url = [NSURL URLWithString:[@"http://" stringByAppendingString:urlStr]];

            if (!url) { done++; dispatch_semaphore_signal(sem); continue; }

            NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
                completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                    if (!error && location) {
                        [fm removeItemAtPath:destPath error:NULL];
                        NSError *mErr = nil;
                        [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:destPath] error:&mErr];
                        if (!mErr) successCount++;
                    }
                    done++;
                    int d = done;
                    if (onProgress) dispatch_async(dispatch_get_main_queue(), ^{ onProgress(d, total, [NSString stringWithFormat:@"Map %d (Top 3)", mapId]); });
                    dispatch_semaphore_signal(sem);
                    if (done >= total) {
                        gDownloading = NO;
                        int sc = successCount;
                        if (onComplete) dispatch_async(dispatch_get_main_queue(), ^{ onComplete(sc); });
                    }
                }];
            [task resume];
        }
    });
}

#pragma mark - Key injection

static int *rtKeyFlagsPtr(void) {
    if (!rtPtrOk(gInputModule)) return NULL;
    void *kd = *(void **)((char *)gInputModule + kOffInputKeyData);
    if (!rtPtrOk(kd)) return NULL;
    return (int *)((char *)kd + kOffKeyDataFlags);
}

static void rtWriteKeyFlags(int mask) {
    int *p = rtKeyFlagsPtr();
    if (p) *p = mask;
    gKeyMask = mask;
}

#pragma mark - Playback

static double rtNow(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void rtPlaybackTick(void *motionCtrl, void *steerData, void *drivingCtrl, void *sim, double now) {
    if (!gPlaying || !gFrames || gFrameCount < 2) return;
    if (!rtPtrOk(motionCtrl)) return;

    float t = (float)(now - gGoTime);
    if (t < 0.f) return;
    if (t >= gFrames[gFrameCount - 1].t) {
        gPlaying = NO;
        gCurPlaybackSteer = 0.f;
        rtWriteKeyFlags(0);
        return;
    }

    // CHỐNG CRASH: chỉ teleport PhysX khi thân vật lý đã init xong.
    // Playback (state/sim/keys) vẫn chạy để auto không bị chết.
    void *phyCtrl = *(void **)((char *)motionCtrl + kOffMotionPhyCtrl);
    if (!rtPtrOk(phyCtrl)) return;
    const bool phyReady = *(bool *)((char *)phyCtrl + kOffPhyIsInitFrame);
    if (!gPhyReadyLogged) {
        rtLog("PHY initFrame=%d enableUpdate=%d -> physx %s",
              (int)phyReady,
              (int)*(bool *)((char *)phyCtrl + kOffPhyEnableUpdate),
              phyReady ? "ON" : "SKIP (chờ init)");
        gPhyReadyLogged = YES;
    }

    uint32_t lo = 0, hi = gFrameCount - 1;
    while (lo + 1 < hi) {
        uint32_t mid = (lo + hi) >> 1;
        if (gFrames[mid].t <= t) lo = mid; else hi = mid;
    }
    const RCFrame *a = &gFrames[lo], *b = &gFrames[hi];
    float span = b->t - a->t;
    float al = span > 1e-5f ? (t - a->t) / span : 0.f;
    if (al < 0.f) al = 0.f;
    if (al > 1.f) al = 1.f;

    float tx = a->px + (b->px - a->px) * al;
    float ty = a->py + (b->py - a->py) * al;
    float tz = a->pz + (b->pz - a->pz) * al;

    float dot = a->qx * b->qx + a->qy * b->qy + a->qz * b->qz + a->qw * b->qw;
    float bx = b->qx, by = b->qy, bz = b->qz, bw = b->qw;
    if (dot < 0.0f) { bx = -bx; by = -by; bz = -bz; bw = -bw; }
    float qx = a->qx + (bx - a->qx) * al;
    float qy = a->qy + (by - a->qy) * al;
    float qz = a->qz + (bz - a->qz) * al;
    float qw = a->qw + (bw - a->qw) * al;
    float ql = sqrtf(qx * qx + qy * qy + qz * qz + qw * qw);
    if (ql > 1e-4f) { qx /= ql; qy /= ql; qz /= ql; qw /= ql; }
    else { qx = 0; qy = 0; qz = 0; qw = 1; }

    float vx = a->vx + (b->vx - a->vx) * al;
    float vy = a->vy + (b->vy - a->vy) * al;
    float vz = a->vz + (b->vz - a->vz) * al;
    float kmph = a->kmph + (b->kmph - a->kmph) * al;

    // 1. Teleport PhysX (chỉ khi entity vật lý đã sẵn sàng)
    void *ent = phyReady ? *(void **)((char *)phyCtrl + 0x18) : NULL; // mPhyHandle
    if (rtPtrOk(ent) && rtPtrOk(*(void **)ent)) {
        float pos[3]  = { tx, ty, tz };
        float quat[4] = { qx, qy, qz, qw };
        float vel[3]  = { vx, vy, vz };
        uintptr_t base = rtGetUnityBase();
        if (base) {
            typedef void (*fn_SetTrans_t)(void *, float *, float *);
            typedef void (*fn_SetLinVel_t)(void *, float *);
            ((fn_SetTrans_t)(base + 0xF718248))(ent, pos, quat);
            ((fn_SetLinVel_t)(base + 0xF7181F4))(ent, vel);
        }
    }

    // 2. Khóa state motion ctrl
    *(float *)((char *)motionCtrl + kOffMotionForcePos + 0) = tx;
    *(float *)((char *)motionCtrl + kOffMotionForcePos + 4) = ty;
    *(float *)((char *)motionCtrl + kOffMotionForcePos + 8) = tz;
    *(float *)((char *)motionCtrl + kOffMotionForceRot + 0)  = qx;
    *(float *)((char *)motionCtrl + kOffMotionForceRot + 4)  = qy;
    *(float *)((char *)motionCtrl + kOffMotionForceRot + 8)  = qz;
    *(float *)((char *)motionCtrl + kOffMotionForceRot + 12) = qw;
    *(bool  *)((char *)motionCtrl + kOffMotionIsSetTransform) = true;

    // 3. Ghi sim output (guard đầy đủ)
    if (rtPtrOk(sim)) {
        *(float *)((char *)sim + kOffSimChassisPos + 0) = tx;
        *(float *)((char *)sim + kOffSimChassisPos + 4) = ty;
        *(float *)((char *)sim + kOffSimChassisPos + 8) = tz;
        *(float *)((char *)sim + kOffSimChassisRot + 0)  = qx;
        *(float *)((char *)sim + kOffSimChassisRot + 4)  = qy;
        *(float *)((char *)sim + kOffSimChassisRot + 8)  = qz;
        *(float *)((char *)sim + kOffSimChassisRot + 12) = qw;
        *(float *)((char *)sim + kOffSimLinearVel + 0) = vx;
        *(float *)((char *)sim + kOffSimLinearVel + 4) = vy;
        *(float *)((char *)sim + kOffSimLinearVel + 8) = vz;
        *(float *)((char *)sim + kOffSimKmph) = kmph;
        *(float *)((char *)sim + kOffSimMps)  = kmph / 3.6f;
        *(float *)((char *)sim + kOffSimForwardForce) = 1.0f;
    }

    // 4. Đánh lái + ga
    float steer = a->steer + (b->steer - a->steer) * al;
    if (steer >  1.0f) steer =  1.0f;
    if (steer < -1.0f) steer = -1.0f;
    gCurPlaybackSteer = steer;

    if (rtPtrOk(steerData)) {
        *(float *)((char *)steerData + kOffSteerLeft) = steer;
        *(float *)((char *)steerData + kOffSteerForward) = 1.0f;
    }
    if (rtPtrOk(drivingCtrl)) {
        *(float *)((char *)drivingCtrl + kOffDrvSteering) = steer;
        *(float *)((char *)drivingCtrl + kOffDrvThrottle) = 1.0f;
        *(float *)((char *)drivingCtrl + kOffDrvInputX)   = steer;
    }

    // 5. Phím
    uint32_t keys = a->keys;
    if (a->flags & 0x01) keys |= (1 << 6);
    if (a->flags & 0x04) keys |= (1 << 8);
    if (a->flags & 0x08) keys |= (1 << 3);
    if (a->flags & 0x10) keys |= (1 << 5);
    if (t >= 0.06f && t <= 0.45f) keys |= (1 << 5);

    if (steer < -0.15f)      { keys |= (1 << 1); keys &= ~(1 << 2); }
    else if (steer > 0.15f)  { keys |= (1 << 2); keys &= ~(1 << 1); }

    gKeyMask = (int)keys;
    rtWriteKeyFlags((int)keys);
}

#pragma mark - UI

@interface RCPanel : NSObject
@property (nonatomic, strong) UIWindow *win;
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *bDl;
@property (nonatomic, strong) UIButton *bAuto;
@property (nonatomic, strong) UIButton *bAfk;
- (void)show;
- (void)refresh;
@end

@interface RCPassWindow : UIWindow
@property (nonatomic, weak) UIView *panel;
@end

@implementation RCPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.hidden && self.panel) {
        CGPoint p = [self convertPoint:point toView:self.panel];
        if ([self.panel pointInside:p withEvent:event]) return [super hitTest:point withEvent:event];
    }
    return nil;
}
@end

static RCPanel *gPanel;

static UIViewController *rtTopVC(void) {
    UIWindow *best = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (!w.isKeyWindow) continue;
        if ([w isKindOfClass:[RCPassWindow class]]) continue;
        best = w;
    }
    if (!best) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if ([w isKindOfClass:[RCPassWindow class]]) continue;
            if (w.windowLevel < UIWindowLevelAlert) best = w;
        }
    }
    UIViewController *vc = best.rootViewController;
    if (!vc) vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void rtAlert(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = rtTopVC();
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

#pragma mark - Hooks

static void   (*orig_MotionCtrl_Update)(void *, float, const void *);
static void   (*orig_Input_Update)(void *, float, const void *);
static BOOL   (*orig_Input_GetKey)(void *, int, const void *);
static BOOL   (*orig_GetSteeringValue)(void *, void *, float, float *, float *, const void *);
static void   (*orig_GoImpEnter)(void *, const void *);
static void   (*orig_RaceKingGoImpEnter)(void *, const void *);
static void   (*orig_ReplayGoImpEnter)(void *, const void *);
static void   (*orig_ReplayActionGoImpEnter)(void *, const void *);
static void   (*orig_GameFinishImpEnter)(void *, const void *);
static BOOL   (*orig_MatchVideoDesHelper_InitByVideoBytes)(void *, void *, const void *);
static void   (*orig_CheckPointMgr_Init)(void *, void *, bool, bool, const void *);
static void   (*orig_MapDataComponent_InitComponent)(void *, const void *);
static void  *(*orig_DataCenterMdl_GetMapDataComponent)(void *, bool, const void *);

static void   (*orig_SdcVehicleInput_UpdateVehicleNotControlMaxTime)(void *, float, const void *);
static void   (*orig_SdcVehicleInput_Update)(void *, float, const void *);
static void   (*orig_SdcPlayerInput_Update)(void *, float, const void *);
static void   (*orig_CPR_FillVehicleInputData)(void *, void **, const void *);
static void   (*orig_CPR_FillPVPButtonUseData)(void *, void **, const void *);
static BOOL   (*orig_MatchUIMgr_Trusteeship)(void *, int, const void *);

static void hook_Input_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) gInputModule = self;
    if (orig_Input_Update) orig_Input_Update(self, dt, m);
    if (gPlaying) rtWriteKeyFlags(gKeyMask);
}

static BOOL hook_Input_GetKey(void *self, int keyType, const void *m) {
    if (rtPtrOk(self)) gInputModule = self;
    if (gPlaying && keyType > 0 && keyType < 18 && ((gKeyMask >> keyType) & 1)) return TRUE;
    return orig_Input_GetKey ? orig_Input_GetKey(self, keyType, m) : FALSE;
}

static BOOL hook_GetSteeringValue(void *self, void *carParams, float dt,
                                  float *steerValue, float *steeringTime, const void *m) {
    if (gPlaying && steerValue) {
        *steerValue = gCurPlaybackSteer;
        if (steeringTime) *steeringTime = 0.5f;
        return TRUE;
    }
    return orig_GetSteeringValue ? orig_GetSteeringValue(self, carParams, dt, steerValue, steeringTime, m) : FALSE;
}

static void rtBeginRace(void) {
    gGoTime = rtNow();
    gCurPlaybackSteer = 0.f;
    gPhyReadyLogged = NO;

    if (gAutoArmed) {
        BOOL ok = rtLoadRecord();   // LUÔN nạp lại cho map hiện tại
        gPlaying = ok;
        rtLog("AUTO map=%d -> %s (%u frames)", gMapId, ok ? "playing" : "no record", gFrameCount);
        if (!ok) {
            rtAlert(@"Đua lập trình",
                    [NSString stringWithFormat:@"Không tìm thấy file .rep cho map %d trong TempMatchVideos", gMapId]);
        }
    } else gPlaying = NO;
}

static void hook_GoImpEnter(void *self, const void *m) {
    if (orig_GoImpEnter) orig_GoImpEnter(self, m);
    rtBeginRace();
}

static void hook_RaceKingGoImpEnter(void *self, const void *m) {
    if (orig_RaceKingGoImpEnter) orig_RaceKingGoImpEnter(self, m);
    rtBeginRace();
}

static void hook_ReplayGoImpEnter(void *self, const void *m) {
    if (orig_ReplayGoImpEnter) orig_ReplayGoImpEnter(self, m);
    rtLog("ENTER ReplayGameGoState");
    rtBeginRace();
}

static void hook_ReplayActionGoImpEnter(void *self, const void *m) {
    if (orig_ReplayActionGoImpEnter) orig_ReplayActionGoImpEnter(self, m);
    rtLog("ENTER ReplayActionSpeedGameGoState");
    rtBeginRace();
}

static void hook_GameFinishImpEnter(void *self, const void *m) {
    if (orig_GameFinishImpEnter) orig_GameFinishImpEnter(self, m);
    rtLog("FINISH reached");
    gPlaying = NO;
    rtWriteKeyFlags(0);
}

static BOOL hook_MatchVideoDesHelper_InitByVideoBytes(void *self, void *videoBytes, const void *m) {
    BOOL res = orig_MatchVideoDesHelper_InitByVideoBytes
             ? orig_MatchVideoDesHelper_InitByVideoBytes(self, videoBytes, m) : NO;
    rtLog("HOOK InitByVideoBytes res=%d", (int)res);
    if (res && rtPtrOk(self)) rtExtractFramesFromDesHelper(self);
    return res;
}

static void hook_CheckPointMgr_Init(void *self, void *config, bool crc, bool reset, const void *m) {
    gPlaying = NO;
    gPlayerVehicle = NULL;
    gPhyReadyLogged = NO;
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, crc, reset, m);

    int mid = rtPtrOk(self) ? *(int *)((char *)self + kOffCpMgrMapId) : 0;
    if (mid <= 0 && rtPtrOk(config)) mid = *(int *)((char *)config + kOffCpMapId);
    if (mid > 0) gMapId = mid;
    gTrackLen = rtPtrOk(config) ? *(float *)((char *)config + kOffCpCurveLength) : 0.f;
    rtLog("MAP LOAD: self=%p cfg=%p mapId=%d", self, config, gMapId);

    // xóa cache frame của map cũ
    if (gFrames) { free(gFrames); gFrames = NULL; gFrameCount = 0; }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gAutoArmed) rtLoadRecord();
        if (gPanel) [gPanel refresh];
    });
}

static void hook_MapDataComponent_InitComponent(void *self, const void *m) {
    if (rtPtrOk(self)) { gMapDataComponent = self; rtLog("Captured MapDataComponent=%p", self); }
    if (orig_MapDataComponent_InitComponent) orig_MapDataComponent_InitComponent(self, m);
}

static void *hook_DataCenterMdl_GetMapDataComponent(void *self, bool withInit, const void *m) {
    void *res = orig_DataCenterMdl_GetMapDataComponent
              ? orig_DataCenterMdl_GetMapDataComponent(self, withInit, m) : NULL;
    if (rtPtrOk(res)) gMapDataComponent = res;
    return res;
}

static void hook_MotionCtrl_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) {
        void *vehicle = *(void **)((char *)self + kOffMotionVehicle);
        if (rtPtrOk(vehicle)) {
            int actorType = *(int *)((char *)vehicle + kOffVehicleActorType);
            bool isMain = *(bool *)((char *)vehicle + kOffVehicleIsMainPlayer);
            BOOL isTarget = isMain || (actorType == 0) || (actorType == 3) || (actorType == 5);
            if (isTarget) {
                gPlayerVehicle = vehicle;
                if (gPlaying) {
                    void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
                    void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
                    void *drivingCtrl = *(void **)((char *)self + kOffMotionDriving);
                    void *sim = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + kOffPhySimOutput) : NULL;
                    // KHÔNG ghi vtable ở đây nữa (write vào __DATA_CONST -> SIGBUS crash).
                    // GetSteeringValue đã được hook an toàn qua rtHookMethod lúc khởi động.
                    rtPlaybackTick(self, steerData, drivingCtrl, sim, rtNow());
                }
            }
        }
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, m);
}

#pragma mark - Anti-AFK (có công tắc để khoanh vùng crash)

static void hook_SdcVehicleInput_UpdateVehicleNotControlMaxTime(void *self, float dt, const void *m) {
    if (!gAntiAfk) {
        if (orig_SdcVehicleInput_UpdateVehicleNotControlMaxTime)
            orig_SdcVehicleInput_UpdateVehicleNotControlMaxTime(self, dt, m);
        return;
    }
    if (!rtPtrOk(self)) return;
    if ((gAfkTickLog++ % 120) == 0) rtLog("AFK tick: notControl reset");

    *(float *)((char *)self + kOffSdcVehNotControlTime) = 0.f;
    *(bool  *)((char *)self + kOffSdcVehLastIsControl)  = true;
    *(float *)((char *)self + kOffSdcVehLastCtrlTime)   = 0.f;

    void *endData = *(void **)((char *)self + kOffSdcVehEndData);
    if (rtPtrOk(endData)) {
        *(int *)((char *)endData + 0x2C) = 0;
        *(int *)((char *)endData + 0x30) = 0;
    }
    // không gọi orig: khoá hoàn toàn bộ đếm
}

static void hook_SdcVehicleInput_Update(void *self, float dt, const void *m) {
    if (orig_SdcVehicleInput_Update) orig_SdcVehicleInput_Update(self, dt, m);
    if (!gAntiAfk || !rtPtrOk(self)) return;

    *(float *)((char *)self + kOffSdcVehNotControlTime) = 0.f;
    *(bool  *)((char *)self + kOffSdcVehLastIsControl)  = true;
    *(float *)((char *)self + kOffSdcVehLastCtrlTime)   = 0.f;

    void *endData = *(void **)((char *)self + kOffSdcVehEndData);
    if (rtPtrOk(endData)) {
        *(int *)((char *)endData + 0x2C) = 0;
        *(int *)((char *)endData + 0x30) = 0;
        if (gPlaying) {
            (*(int *)((char *)endData + 0x10))++;
            (*(int *)((char *)endData + 0x18))++;
            (*(int *)((char *)endData + 0x24))++;
        }
    }
}

static void hook_SdcPlayerInput_Update(void *self, float dt, const void *m) {
    if (orig_SdcPlayerInput_Update) orig_SdcPlayerInput_Update(self, dt, m);
    if (!gAntiAfk || !rtPtrOk(self) || !gPlaying) return;

    void *endData = *(void **)((char *)self + 0x58);
    if (rtPtrOk(endData)) {
        (*(int *)((char *)endData + 0x14))++; // UserLeftTurnCount
        (*(int *)((char *)endData + 0x18))++; // UserRightTurnCount
        (*(int *)((char *)endData + 0x20))++; // UserDriftingCount
        (*(int *)((char *)endData + 0x24))++; // UserMiniJetCount
    }
}

static void hook_CPR_FillVehicleInputData(void *self, void **fillData, const void *m) {
    if (orig_CPR_FillVehicleInputData) orig_CPR_FillVehicleInputData(self, fillData, m);
    if (!gAntiAfk) return;
    if (fillData && rtPtrOk(*fillData)) {
        char *d = (char *)*fillData;
        *(uint32_t *)(d + 0x48) = 0; // dwCarNonControlTimeMax
        *(uint32_t *)(d + 0x4C) = 0; // dwCarNonControlTimeTotal
    }
}

static void hook_CPR_FillPVPButtonUseData(void *self, void **fillData, const void *m) {
    if (orig_CPR_FillPVPButtonUseData) orig_CPR_FillPVPButtonUseData(self, fillData, m);
    if (!gAntiAfk) return;
    if (fillData && rtPtrOk(*fillData)) {
        char *d = (char *)*fillData;
        if (*(uint16_t *)(d + 0x12) < 15) *(uint16_t *)(d + 0x12) = 15 + (rand() % 10);
        if (*(uint16_t *)(d + 0x14) < 15) *(uint16_t *)(d + 0x14) = 15 + (rand() % 10);
        if (*(uint16_t *)(d + 0x18) < 8)  *(uint16_t *)(d + 0x18) = 8 + (rand() % 5);
        if (*(uint16_t *)(d + 0x1A) < 10) *(uint16_t *)(d + 0x1A) = 10 + (rand() % 6);
    }
}

static BOOL hook_MatchUIMgr_Trusteeship(void *self, int aiActionID, const void *m) {
    if (!gAntiAfk)
        return orig_MatchUIMgr_Trusteeship ? orig_MatchUIMgr_Trusteeship(self, aiActionID, m) : FALSE;
    rtLog("ANTI-AFK: blocked Trusteeship(%d)", aiActionID);
    return FALSE;
}

#pragma mark - UI impl

@implementation RCPanel

- (UIButton *)mk:(NSString *)t sel:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)onPan:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.win];
    CGRect f = self.host.frame;
    f.origin.x += trans.x;
    f.origin.y += trans.y;
    CGRect scr = UIScreen.mainScreen.bounds;
    if (f.origin.x < 5) f.origin.x = 5;
    if (f.origin.y < 20) f.origin.y = 20;
    if (f.origin.x + f.size.width  > scr.size.width  - 5) f.origin.x = scr.size.width  - f.size.width  - 5;
    if (f.origin.y + f.size.height > scr.size.height - 20) f.origin.y = scr.size.height - f.size.height - 20;
    self.host.frame = f;
    [p setTranslation:CGPointZero inView:self.win];
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect scr = UIScreen.mainScreen.bounds;
        self.win = [[RCPassWindow alloc] initWithFrame:scr];
        self.win.windowLevel = UIWindowLevelAlert + 2;
        self.win.backgroundColor = UIColor.clearColor;
        self.win.opaque = NO;
        self.win.rootViewController = [UIViewController new];
        self.win.rootViewController.view.backgroundColor = UIColor.clearColor;
        self.win.rootViewController.view.userInteractionEnabled = YES;

        if (@available(iOS 13.0, *)) {
            if (!self.win.windowScene) {
                for (UIWindow *w in UIApplication.sharedApplication.windows) {
                    if ([w isKindOfClass:[RCPassWindow class]]) continue;
                    if (w.windowScene) { self.win.windowScene = w.windowScene; break; }
                }
            }
        }

        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(14, scr.size.height * 0.28, 132, 202)];
        host.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.88];
        host.layer.cornerRadius = 12;
        host.layer.borderWidth = 1;
        host.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        host.userInteractionEnabled = YES;
        [self.win.rootViewController.view addSubview:host];
        self.host = host;
        ((RCPassWindow *)self.win).panel = host;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [host addGestureRecognizer:pan];

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 112, 18)];
        t.text = @"RaceKit Pro";
        t.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        t.font = [UIFont boldSystemFontOfSize:12];
        [host addSubview:t];

        self.bDl = [self mk:@"⬇ TẢI .REP" sel:@selector(tapDownload)];
        self.bDl.frame = CGRectMake(10, 28, 112, 34);
        [host addSubview:self.bDl];

        self.bAuto = [self mk:@"▶ AUTO" sel:@selector(tapAuto)];
        self.bAuto.frame = CGRectMake(10, 68, 112, 34);
        [host addSubview:self.bAuto];

        self.bAfk = [self mk:@"🛡 ANTI-AFK" sel:@selector(tapAfk)];
        self.bAfk.frame = CGRectMake(10, 108, 112, 34);
        [host addSubview:self.bAfk];

        self.status = [[UILabel alloc] initWithFrame:CGRectMake(10, 148, 112, 48)];
        self.status.numberOfLines = 3;
        self.status.font = [UIFont systemFontOfSize:9];
        self.status.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        [host addSubview:self.status];

        self.win.hidden = NO;
        [self.win makeKeyAndVisible];

        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIWindow *w in UIApplication.sharedApplication.windows) {
                if ([w isKindOfClass:[RCPassWindow class]]) continue;
                if (w.windowLevel >= UIWindowLevelNormal) { [w makeKeyAndVisible]; break; }
            }
        });
        [self refresh];
    });
}

- (void)refresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.bAuto.backgroundColor = gAutoArmed ? [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95]
                                                : [UIColor colorWithWhite:0.12 alpha:0.92];
        self.bAfk.backgroundColor  = gAntiAfk  ? [UIColor colorWithRed:0.10 green:0.35 blue:0.65 alpha:0.95]
                                                : [UIColor colorWithWhite:0.12 alpha:0.92];
        if (!gDownloading) {
            self.status.text = [NSString stringWithFormat:@"Map: %d (%u frame)\nAUTO: %@  AFK: %@\nPlay: %d",
                                gMapId, gFrameCount,
                                gAutoArmed ? @"BẬT" : @"TẮT",
                                gAntiAfk ? @"BẬT" : @"TẮT",
                                (int)gPlaying];
        }
    });
}

- (void)tapDownload {
    if (gDownloading) return;
    self.status.text = @"Đang quét BXH...";
    [self.bDl setTitle:@"⏳ ĐANG TẢI" forState:UIControlStateNormal];

    rtDownloadAllPeakSpeedReplays(^(int done, int total, NSString *sub) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.status.text = [NSString stringWithFormat:@"Tải: %d/%d\n(%@)", done, total, sub];
        });
    }, ^(int totalDownloaded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.bDl setTitle:@"⬇ TẢI .REP" forState:UIControlStateNormal];
            self.status.text = [NSString stringWithFormat:@"Đã tải %d rep!\nMap %d sẵn sàng", totalDownloaded, gMapId];
            if (gAutoArmed) rtLoadRecord();
            [self refresh];
        });
    });
}

- (void)tapAuto {
    gAutoArmed = gAutoArmed ? NO : YES;
    if (!gAutoArmed) { gPlaying = NO; rtWriteKeyFlags(0); }
    rtLog("AUTO armed=%d", (int)gAutoArmed);
    [self refresh];
}

- (void)tapAfk {
    gAntiAfk = gAntiAfk ? NO : YES;
    rtLog("ANTI-AFK enabled=%d", (int)gAntiAfk);
    [self refresh];
}

@end

#pragma mark - Install

static void rtInstallHooks(void) {
    orig_MotionCtrl_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "NssPhyVehicleMotionCtrl", "Update", 1, (void *)hook_MotionCtrl_Update);
    orig_Input_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "InputModule", "Update", 1, (void *)hook_Input_Update);
    orig_Input_GetKey = (BOOL (*)(void *, int, const void *))
        rtHookMethod("", "InputModule", "GetKey", 1, (void *)hook_Input_GetKey);
    orig_GetSteeringValue = (BOOL (*)(void *, void *, float, float *, float *, const void *))
        rtHookMethod("", "NssPlayerVehicleDrivingCtrl", "GetSteeringValue", 4, (void *)hook_GetSteeringValue);
    rtHookMethod("", "NssPhyVehicleDrivingCtrl", "GetSteeringValue", 4, (void *)hook_GetSteeringValue);
    orig_GoImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    orig_RaceKingGoImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_RaceKingGoImpEnter);
    orig_ReplayGoImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "ReplayGameGoState", "ImpEnter", 0, (void *)hook_ReplayGoImpEnter);
    orig_ReplayActionGoImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "ReplayActionSpeedGameGoState", "ImpEnter", 0, (void *)hook_ReplayActionGoImpEnter);
    orig_GameFinishImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameFinishState", "ImpEnter", 0, (void *)hook_GameFinishImpEnter);
    orig_CheckPointMgr_Init = (void (*)(void *, void *, bool, bool, const void *))
        rtHookMethod("", "CheckPointMgr", "Init", 3, (void *)hook_CheckPointMgr_Init);
    orig_MatchVideoDesHelper_InitByVideoBytes = (BOOL (*)(void *, void *, const void *))
        rtHookMethod("", "MatchVideoDesHelper", "InitByVideoBytes", 1, (void *)hook_MatchVideoDesHelper_InitByVideoBytes);
    orig_MapDataComponent_InitComponent = (void (*)(void *, const void *))
        rtHookMethod("", "MapDataComponent", "InitComponent", 0, (void *)hook_MapDataComponent_InitComponent);
    orig_DataCenterMdl_GetMapDataComponent = (void *(*)(void *, bool, const void *))
        rtHookMethod("", "DataCenterMdl", "GetMapDataComponent", 1, (void *)hook_DataCenterMdl_GetMapDataComponent);

    orig_SdcVehicleInput_UpdateVehicleNotControlMaxTime = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleInput", "UpdateVehicleNotControlMaxTime", 1, (void *)hook_SdcVehicleInput_UpdateVehicleNotControlMaxTime);
    orig_SdcVehicleInput_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleInput", "Update", 1, (void *)hook_SdcVehicleInput_Update);
    orig_SdcPlayerInput_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcPlayerInput", "Update", 1, (void *)hook_SdcPlayerInput_Update);
    orig_CPR_FillVehicleInputData = (void (*)(void *, void **, const void *))
        rtHookMethod("", "CPR_STPVPEndGame", "FillVehicleInputData", 1, (void *)hook_CPR_FillVehicleInputData);
    orig_CPR_FillPVPButtonUseData = (void (*)(void *, void **, const void *))
        rtHookMethod("", "CPR_STPVPEndGame", "FillPVPButtonUseData", 1, (void *)hook_CPR_FillPVPButtonUseData);
    orig_MatchUIMgr_Trusteeship = (BOOL (*)(void *, int, const void *))
        rtHookMethod("", "MatchUIMgr", "Trusteeship", 1, (void *)hook_MatchUIMgr_Trusteeship);
}

__attribute__((constructor))
static void rcInit(void) {
    rtLogOpen();
    rtLog("=== RaceRec loaded ===");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        rtInstallHooks();
        gPanel = [RCPanel new];
        [gPanel show];
    });
}
