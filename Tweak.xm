// RaceRec — Ghi / Phát lại đường đua (record & playback)
// Hỗ trợ tải replay Top 3 tất cả map trong Đỉnh Cực Tốc, menu di chuyển được, auto update UI khi đổi map.

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
        const Il2CppImage *img = il2cpp_assembly_get_image(asms[i]);
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

#pragma mark - Offsets (đã kiểm chứng)

enum {
    kOffVehicleActorType      = 0x14,   // NssVehicle.mActorType
    kOffVehicleDyn            = 0x20,   // NssVehicle.mDynamicVehicle
    kOffVehicleIsMainPlayer   = 0xF8,   // NssVehicle.mIsMainPlayer (bool)

    kOffMotionSteerData       = 0x10,   // NssPhyVehicleMotionCtrlHelper.mSteeringData
    kOffMotionVehicle         = 0x18,   // .mVehicle
    kOffMotionPhyCtrl         = 0x20,   // .mVehiclePhyCtrl
    kOffMotionDynVehicle      = 0x28,   // .mDynamicVehicle
    kOffMotionDriving         = 0x38,   // .mDrivingCtrl
    kOffMotionForcePos        = 0x40,   // .mForceSetPos (Vector3)
    kOffMotionForceRot        = 0x4C,   // .mForceSetRot (Quaternion)
    kOffMotionDrift           = 0x60,   // .mDriftCtrl (IVehicleDriftCtrl)
    kOffMotionIsSetTransform  = 0x70,   // .mIsSetTransform (bool)

    kOffPhySimOutput          = 0x28,   // NssPhyVehicleCtrl.mSimulateOutput

    kOffSimKmph               = 0x10,   // NssVehicleSimOutput.mKmph
    kOffSimMps                = 0x14,   // .mMps
    kOffSimLinearVel          = 0x38,   // .mLinearVelocity (Vector3)
    kOffSimChassisPos         = 0x64,   // .mChassisPosition (Vector3)
    kOffSimChassisRot         = 0x70,   // .mChassisRotation (Quaternion)

    kOffSteerForward          = 0x10,   // NssSteeringData.mForward
    kOffSteerBraking          = 0x14,   // .mBrakingState
    kOffSteerHandbrake        = 0x18,   // .mIsHandbrake
    kOffSteerLeft             = 0x1C,   // .mSteeringLeft

    kOffDrvThrottle           = 0x3C,   // NssPhyVehicleDrivingCtrl.mThrottle
    kOffDrvSteering           = 0x40,   // .mSteering

    kOffCpMapId               = 0x1C,   // CheckPointConfig.MapId (offset 28)
    kOffCpCurveLength         = 0x2C,   // CheckPointConfig.MainCurveLength

    kOffInputKeyData          = 0xA8,   // InputModule.mInputKeyData
    kOffKeyDataFlags          = 0x10,   // InputKeyData.KeyFlags
};

#pragma mark - Frame format

#define RC_MAGIC "RKR3"
#define RC_MAX_FRAMES 21600
#define RC_SAMPLE_DT  0.008f

typedef struct {
    float    t;               // Thời gian tương đối (s)
    float    px, py, pz;      // Vị trí 3D
    float    qx, qy, qz, qw;  // Góc xoay Quaternion
    float    vx, vy, vz;      // Vận tốc tuyến tính
    float    kmph;            // Tốc độ km/h
    float    steer;           // Góc đánh lái (-1.0 đến 1.0)
    uint32_t keys;            // Cờ phím (Nitro, MiniBoost, Drift, Brake, Left, Right)
    uint8_t  flags;           // b0: phanh, b1: phanh tay, b2: drift, b3: nitro, b4: miniboost
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
    char     magic[4];        // "RKR3"
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
static float    gSpeedMultiplier = 1.0f;
static double   sLastPlaybackRealTime = 0.0;
static float    sAccumulatedPlaybackTime = 0.0f;
static BOOL gAutoArmed, gPlaying;
static BOOL gNoReplay = YES;

// Tính toán độ lệch vị trí
static BOOL   gEnableOffsetFix = YES;
static BOOL   gOffsetApplied = NO;
static float  gOffsetDelta[3] = {0.f, 0.f, 0.f};
static float  gRepOriginPos[3] = {0.f, 0.f, 0.f};
static float  gMapActualPos[3] = {0.f, 0.f, 0.f};
static int    gRepStartSlot = 0;
static int    gMapStartSlot = 0;
static void *gPlayerVehicle;
static void *gInputModule;
static int   gKeyMask;
static float gCurPlaybackSteer;
static void *gMapDataComponent = NULL;
static void *gCheckPointMgr = NULL;
static BOOL gDownloading = NO;

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
    rtLog("[Rep] Found Summary: mapId=%u, uid=%llu", mapId, (unsigned long long)uid);

    uintptr_t base = rtGetUnityBase();
    if (!base) return NO;

    typedef void *(*fn_GetTransInfos_t)(void *, uint64_t);
    fn_GetTransInfos_t fn_GetTransInfos = (fn_GetTransInfos_t)(base + 0x71B5608);

    void *p2p = fn_GetTransInfos ? fn_GetTransInfos(desHelper, uid) : NULL;
    if (!rtPtrOk(p2p)) {
        rtLog("[Rep] GetTransInfos returned null for uid %llu", (unsigned long long)uid);
        return NO;
    }

    void *moveList = *(void **)((char *)p2p + 0x10); // MoveInfo (ListView<VideoVehicleMoveInfo>)
    if (!rtPtrOk(moveList)) {
        rtLog("[Rep] MoveInfo list is null");
        return NO;
    }

    int count = *(int *)((char *)moveList + 0x18); // _size
    void *arr = *(void **)((char *)moveList + 0x10); // Context array
    if (!rtPtrOk(arr) || count <= 0) {
        rtLog("[Rep] MoveInfo empty (count=%d)", count);
        return NO;
    }

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
        fr.px   = *(float *)((char *)m + 0x24); // mPos.x
        fr.py   = *(float *)((char *)m + 0x28); // mPos.y
        fr.pz   = *(float *)((char *)m + 0x2C); // mPos.z
        fr.qx   = *(float *)((char *)m + 0x30); // mRot.x
        fr.qy   = *(float *)((char *)m + 0x34); // mRot.y
        fr.qz   = *(float *)((char *)m + 0x38); // mRot.z
        fr.qw   = *(float *)((char *)m + 0x3C); // mRot.w
        fr.vx   = *(float *)((char *)m + 0x40); // mLinVel.x
        fr.vy   = *(float *)((char *)m + 0x44); // mLinVel.y
        fr.vz   = *(float *)((char *)m + 0x48); // mLinVel.z

        // Chuẩn hóa Quaternion ngay khi trích xuất
        float ql = sqrtf(fr.qx * fr.qx + fr.qy * fr.qy + fr.qz * fr.qz + fr.qw * fr.qw);
        if (ql > 1e-4f) { fr.qx /= ql; fr.qy /= ql; fr.qz /= ql; fr.qw /= ql; }

        // ĐỌC VÀ TÍNH TỐC ĐỘ:
        // mKMPH ở 0x5C trong Replay bằng 0, tính tốc độ chuẩn từ vector mLinVel:
        float v_mps = sqrtf(fr.vx * fr.vx + fr.vy * fr.vy + fr.vz * fr.vz);
        float spd_kmh = v_mps * 3.6f;
        if (spd_kmh < 1.0f && i > 0) {
            float dt = fr.t - gFrames[i - 1].t;
            if (dt > 1e-4f) {
                float ddx = fr.px - gFrames[i - 1].px;
                float ddy = fr.py - gFrames[i - 1].py;
                float ddz = fr.pz - gFrames[i - 1].pz;
                spd_kmh = (sqrtf(ddx * ddx + ddy * ddy + ddz * ddz) / dt) * 3.6f;
                fr.vx = ddx / dt;
                fr.vy = ddy / dt;
                fr.vz = ddz / dt;
            }
        }
        fr.kmph = spd_kmh;

        // Chuyển đổi mã phím Replay sang InputKeyType chuẩn:
        uint32_t repKeys = *(uint32_t *)((char *)m + 0x20); // mKeyFlag
        uint32_t inputKeys = 0;
        if (repKeys & ((1 << 1) | (1 << 13))) inputKeys |= (1 << 1); // Left (1)
        if (repKeys & ((1 << 2) | (1 << 14))) inputKeys |= (1 << 2); // Right (2)
        if (repKeys & ((1 << 3) | (1 << 4)))  inputKeys |= (1 << 3); // Nitro (3)
        if (repKeys & ((1 << 7) | (1 << 8)))  inputKeys |= (1 << 5); // MiniBoost (5)
        if (repKeys & ((1 << 9) | (1 << 10))) inputKeys |= (1 << 6); // Brake (6)
        if (repKeys & ((1 << 13) | (1 << 14))) inputKeys |= (1 << 8); // Drift (8)

        int state = *(int *)((char *)m + 0x74); // mState
        if (state == 2) inputKeys |= (1 << 8);  // NssVehicleState.Drifting

        fr.keys = inputKeys;

        // Góc đánh lái (steer)
        float yawRate = *(float *)((char *)m + 0x50); // mAngVel.y
        if (inputKeys & (1 << 1)) fr.steer = -0.90f;
        else if (inputKeys & (1 << 2)) fr.steer = 0.90f;
        else if (fabsf(yawRate) > 0.08f) {
            float s = -yawRate * 0.45f;
            if (s > 1.0f) s = 1.0f;
            if (s < -1.0f) s = -1.0f;
            fr.steer = s;
        } else {
            fr.steer = 0.f;
        }

        uint8_t flags = 0;
        if (inputKeys & (1 << 6)) flags |= 0x01; // Brake
        if (inputKeys & (1 << 8)) flags |= 0x04; // Drift
        if (inputKeys & (1 << 3)) flags |= 0x08; // Nitro
        if (inputKeys & (1 << 5)) flags |= 0x10; // MiniBoost
        fr.flags = flags;

        gFrames[i] = fr;
    }
    gFrameCount = count;
    if (mapId > 0) gMapId = (int)mapId;
    rtLog("[Rep] SUCCESSFULLY extracted %u frames from .rep! MapId=%d", gFrameCount, gMapId);

    // Ghi nhận vị trí xuất phát gốc và slot của rep
    if (count > 0) {
        gRepOriginPos[0] = gFrames[0].px;
        gRepOriginPos[1] = gFrames[0].py;
        gRepOriginPos[2] = gFrames[0].pz;
        gOffsetApplied = NO;
        memset(gOffsetDelta, 0, sizeof(gOffsetDelta));

        void *playerInfos = *(void **)((char *)summary + 0x38); // ListView<PlayerMatchVideoInfo>
        if (rtPtrOk(playerInfos)) {
            int pCount = *(int *)((char *)playerInfos + 0x18);
            void *pArr = *(void **)((char *)playerInfos + 0x10);
            if (rtPtrOk(pArr) && pCount > 0) {
                void *p0 = *(void **)((char *)pArr + 0x20);
                if (rtPtrOk(p0)) {
                    gRepStartSlot = (int)*(uint8_t *)((char *)p0 + 0x28); // StartPosIndex (0-5)
                }
            }
        }
    }

    rtSaveRecord();
    return YES;
}

static BOOL rtLoadRepFromDisk(NSString *repPath) {
    if (!repPath || ![[NSFileManager defaultManager] fileExistsAtPath:repPath]) return NO;
    NSData *data = [NSData dataWithContentsOfFile:repPath];
    if (!data || !data.length) return NO;

    rtLog("[Rep] Feeding %lu bytes into game parser...", (unsigned long)data.length);

    Il2CppClass *byteClass = rtFindClass("System", "Byte");
    Il2CppClass *desClass  = rtFindClass("", "MatchVideoDesHelper");
    if (!byteClass || !desClass || !il2cpp_array_new || !il2cpp_object_new) {
        rtLog("[Rep] il2cpp functions missing: byteClass=%p desClass=%p arrNew=%p objNew=%p",
              byteClass, desClass, il2cpp_array_new, il2cpp_object_new);
        return NO;
    }

    uintptr_t base = rtGetUnityBase();
    if (!base) return NO;

    // 1. Tạo Il2CppArray chứa dữ liệu byte file .rep
    void *arr = il2cpp_array_new(byteClass, data.length);
    if (!arr) return NO;
    memcpy((char *)arr + 0x20, data.bytes, data.length);

    // 2. Gọi hàm giải nén của game: MatchVideoStaticHelper.GetUnZipData (0x71E28EC)
    typedef void *(*fn_unzip_t)(void *, ...);
    fn_unzip_t fn_unzip = (fn_unzip_t)(base + 0x71E28EC);
    void *unzipArr = fn_unzip ? fn_unzip(arr) : arr;
    if (!unzipArr) unzipArr = arr;

    // 3. Khởi tạo đối tượng parser của game: MatchVideoDesHelper
    void *helper = il2cpp_object_new(desClass);
    if (!helper) return NO;
    typedef void (*fn_ctor_t)(void *);
    fn_ctor_t fn_ctor = (fn_ctor_t)(base + 0x71B6A88);
    if (fn_ctor) fn_ctor(helper);

    // 4. Giải mã toàn bộ qua parser của game: InitByVideoBytes (0x71B3E20)
    typedef BOOL (*fn_init_t)(void *, void *, ...);
    fn_init_t fn_init = (fn_init_t)(base + 0x71B3E20);
    BOOL ok = fn_init ? fn_init(helper, unzipArr) : NO;
    rtLog("[Rep] Parser InitByVideoBytes result=%d", (int)ok);
    if (ok) {
        return rtExtractFramesFromDesHelper(helper);
    }
    return NO;
}

static NSString *rtFindRepFile(int targetMapId) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
    if (!files || !files.count) {
        rtLog("[Rep] TempMatchVideos is empty or not found: %s", dir.UTF8String);
        return nil;
    }

    NSString *bestMatch = nil;
    NSString *newestFile = nil;
    NSDate *newestDate = [NSDate distantPast];

    NSString *targetPrefix = targetMapId > 0 ? [NSString stringWithFormat:@"%d_", targetMapId] : nil;
    NSString *targetContain = targetMapId > 0 ? [NSString stringWithFormat:@"%d", targetMapId] : nil;

    for (NSString *name in files) {
        if ([name.pathExtension.lowercaseString isEqualToString:@"rep"]) {
            NSString *full = [dir stringByAppendingPathComponent:name];
            if (targetPrefix && [name hasPrefix:targetPrefix]) {
                return full;
            }
            if (targetContain && [name containsString:targetContain]) {
                bestMatch = full;
            }
            NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
            NSDate *mod = attr.fileModificationDate ?: [NSDate date];
            if ([mod compare:newestDate] == NSOrderedDescending) {
                newestDate = mod;
                newestFile = full;
            }
        }
    }
    return bestMatch ?: newestFile;
}

static BOOL rtLoadRecord(void) {
    gFrameCount = 0;
    if (gFrames) { free(gFrames); gFrames = NULL; }

    // 1. Quét tìm và đưa file .rep từ TempMatchVideos vào parser của game
    rtLog("Searching TempMatchVideos for map %d .rep file...", gMapId);
    NSString *rep = rtFindRepFile(gMapId);
    if (rep && rtLoadRepFromDisk(rep)) {
        if (gFrameCount > 0) {
            rtLog("LOADED %u frames from .rep file!", gFrameCount);
            return YES;
        }
    }

    // 2. Fallback nếu có file .rk
    NSString *path = rtPathForTrack();
    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        FILE *f = fopen(path.fileSystemRepresentation, "rb");
        if (f) {
            RCHeader h;
            if (fread(&h, sizeof h, 1, f) == 1 && h.count > 0 && h.count <= RC_MAX_FRAMES) {
                if (!memcmp(h.magic, "RKR3", 4) && h.frameSize == sizeof(RCFrame)) {
                    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * h.count);
                    if (gFrames) {
                        gFrameCount = (uint32_t)fread(gFrames, sizeof(RCFrame), h.count, f);
                    }
                } else if (!memcmp(h.magic, "RKR2", 4) && h.frameSize == sizeof(RCFrameV2)) {
                    RCFrameV2 *v2 = (RCFrameV2 *)malloc(sizeof(RCFrameV2) * h.count);
                    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * h.count);
                    if (v2 && gFrames) {
                        uint32_t n = (uint32_t)fread(v2, sizeof(RCFrameV2), h.count, f);
                        for (uint32_t i = 0; i < n; i++) {
                            memset(&gFrames[i], 0, sizeof(RCFrame));
                            gFrames[i].t      = v2[i].t;
                            gFrames[i].px     = v2[i].px;
                            gFrames[i].py     = v2[i].py;
                            gFrames[i].pz     = v2[i].pz;
                            gFrames[i].qx     = v2[i].qx;
                            gFrames[i].qy     = v2[i].qy;
                            gFrames[i].qz     = v2[i].qz;
                            gFrames[i].qw     = v2[i].qw;
                            gFrames[i].steer  = v2[i].steer;
                            gFrames[i].keys   = v2[i].keys;
                            gFrames[i].flags  = v2[i].flags;
                        }
                        gFrameCount = n;
                    }
                    if (v2) free(v2);
                }
                fclose(f);
                if (gFrameCount) return YES;
            } else {
                fclose(f);
            }
        }
    }
    return NO;
}

#pragma mark - Tải Replay Top 3 tất cả map (Đỉnh Cực Tốc)

static void rtDownloadAllPeakSpeedReplays(void (^onProgress)(int done, int total, NSString *info), void (^onComplete)(int totalDownloaded)) {
    if (gDownloading) return;
    gDownloading = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
        NSString *tempDir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:NULL];

        // 1. Quét MapDataComponent.VideoDetailCfgs lấy URL Replay Top 1, 2, 3 của tất cả map
        NSMutableArray *queue = [NSMutableArray array];

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
                        if (gradeId < 1 || gradeId > 3) continue; // Chỉ tải Top 3

                        void *urlPtr = *(void **)((char *)cfg + 0x30);
                        NSString *urlStr = rtIl2CppString(urlPtr);
                        if (urlStr.length > 0) {
                            NSString *fileName = [NSString stringWithFormat:@"%d_%d.rep", mapId, gradeId];
                            NSString *destPath = [tempDir stringByAppendingPathComponent:fileName];
                            [queue addObject:@{
                                @"url": urlStr,
                                @"path": destPath,
                                @"map": @(mapId),
                                @"grade": @(gradeId)
                            }];
                        }
                    }
                }
            }
        }

        // 2. Đồng bộ các file .rep có sẵn trong documents/bundle (LocLo, MatchVideos) vào TempMatchVideos
        NSArray *localDirs = @[@"LocLo", @"MatchVideos", @"RaceKit"];
        for (NSString *sub in localDirs) {
            NSString *dir = [doc stringByAppendingPathComponent:sub];
            NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
            for (NSString *name in files) {
                if ([name.pathExtension.lowercaseString isEqualToString:@"rep"]) {
                    NSString *src = [dir stringByAppendingPathComponent:name];
                    NSString *dst = [tempDir stringByAppendingPathComponent:name];
                    if (![fm fileExistsAtPath:dst]) {
                        [fm copyItemAtPath:src toPath:dst error:NULL];
                    }
                }
            }
        }

        int total = (int)queue.count;
        if (total == 0) {
            NSArray *files = [fm contentsOfDirectoryAtPath:tempDir error:NULL];
            int count = 0;
            for (NSString *n in files) {
                if ([n.pathExtension.lowercaseString isEqualToString:@"rep"]) count++;
            }
            gDownloading = NO;
            if (onComplete) onComplete(count);
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
                done++;
                successCount++;
                if (onProgress) onProgress(done, total, [NSString stringWithFormat:@"Map %d", mapId]);
                dispatch_semaphore_signal(sem);
                continue;
            }

            NSURL *url = [NSURL URLWithString:urlStr];
            if (!url && ![urlStr hasPrefix:@"http"]) {
                url = [NSURL URLWithString:[@"http://" stringByAppendingString:urlStr]];
            }

            if (!url) {
                done++;
                dispatch_semaphore_signal(sem);
                continue;
            }

            NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
                completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                    if (!error && location) {
                        [fm removeItemAtPath:destPath error:NULL];
                        NSError *mErr = nil;
                        [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:destPath] error:&mErr];
                        if (!mErr) successCount++;
                    }
                    done++;
                    if (onProgress) onProgress(done, total, [NSString stringWithFormat:@"Map %d", mapId]);
                    dispatch_semaphore_signal(sem);

                    if (done >= total) {
                        gDownloading = NO;
                        if (onComplete) onComplete(successCount);
                    }
                }];
            [task resume];
        }
    });
}

static void rtRedownloadRepForMap(int targetMapId, void (^onComplete)(BOOL success, NSString *msg)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
        NSString *tempDir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
        NSFileManager *fm = [NSFileManager defaultManager];

        // 1. Xóa toàn bộ file .rep cũ của mapId này trong TempMatchVideos
        NSArray *files = [fm contentsOfDirectoryAtPath:tempDir error:NULL];
        NSString *prefix = [NSString stringWithFormat:@"%d_", targetMapId];
        NSString *exact  = [NSString stringWithFormat:@"%d.rep", targetMapId];
        for (NSString *name in files) {
            if ([name.pathExtension.lowercaseString isEqualToString:@"rep"]) {
                if ([name hasPrefix:prefix] || [name isEqualToString:exact]) {
                    NSString *full = [tempDir stringByAppendingPathComponent:name];
                    [fm removeItemAtPath:full error:NULL];
                    rtLog("[FixMap] Deleted old rep: %s", full.UTF8String);
                }
            }
        }

        // 2. Xóa cache .rk
        NSString *rkPath = [rtDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"rec_map%d.rk", targetMapId]];
        [fm removeItemAtPath:rkPath error:NULL];

        // 3. Giải phóng bộ nhớ RAM
        if (gFrames) {
            free(gFrames);
            gFrames = NULL;
            gFrameCount = 0;
        }

        // 4. Tìm URL tải mới trong gMapDataComponent
        if (!rtPtrOk(gMapDataComponent)) {
            if (onComplete) onComplete(NO, @"Chưa có dữ liệu bản đồ. Vui lòng vào màn hình Chọn Map hoặc BXH một lần!");
            return;
        }

        void *list = *(void **)((char *)gMapDataComponent + 0x98); // ListView<VideoDetailCfg>
        if (!rtPtrOk(list)) {
            if (onComplete) onComplete(NO, @"Không tìm thấy danh sách VideoDetailCfg!");
            return;
        }

        int count = *(int *)((char *)list + 0x18);
        void *arr = *(void **)((char *)list + 0x10);
        if (!rtPtrOk(arr) || count <= 0) {
            if (onComplete) onComplete(NO, @"Danh sách video trống!");
            return;
        }

        void **items = (void **)((char *)arr + 0x20);
        NSString *bestUrlStr = nil;
        uint8_t bestGrade = 0;

        for (int i = 0; i < count; i++) {
            void *cfg = items[i];
            if (!rtPtrOk(cfg)) continue;
            int mid = *(int *)((char *)cfg + 0x14);
            if (mid != targetMapId) continue;

            uint8_t gradeId = *(uint8_t *)((char *)cfg + 0x18);
            void *urlPtr = *(void **)((char *)cfg + 0x30);
            NSString *urlStr = rtIl2CppString(urlPtr);
            if (!urlStr || !urlStr.length) continue;

            if (!bestUrlStr || gradeId >= bestGrade) {
                bestGrade = gradeId;
                bestUrlStr = urlStr;
            }
        }

        if (!bestUrlStr || !bestUrlStr.length) {
            if (onComplete) onComplete(NO, [NSString stringWithFormat:@"Không tìm thấy video kỷ lục cho Map %d trên BXH!", targetMapId]);
            return;
        }

        NSURL *url = [NSURL URLWithString:bestUrlStr];
        if (!url && ![bestUrlStr hasPrefix:@"http"]) {
            url = [NSURL URLWithString:[@"http://" stringByAppendingString:bestUrlStr]];
        }
        if (!url) {
            if (onComplete) onComplete(NO, @"URL video không hợp lệ!");
            return;
        }

        NSString *destPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d_3.rep", targetMapId]];
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
            completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                if (!error && location) {
                    [fm removeItemAtPath:destPath error:NULL];
                    NSError *mErr = nil;
                    [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:destPath] error:&mErr];
                    if (!mErr) {
                        rtLog("[FixMap] Successfully saved new .rep for map %d to %s", targetMapId, destPath.UTF8String);
                        if (onComplete) onComplete(YES, nil);
                        return;
                    }
                }
                if (onComplete) onComplete(NO, error.localizedDescription ?: @"Lỗi khi ghi file .rep!");
            }];
        [task resume];
    });
}

static BOOL rtCalculateStartSlotPosInMap(void *cpMgr, int slotIndex, float *outPos) {
    if (!rtPtrOk(cpMgr) || !outPos) return NO;

    float sx = *(float *)((char *)cpMgr + 0x1C8 + 0);
    float sy = *(float *)((char *)cpMgr + 0x1C8 + 4);
    float sz = *(float *)((char *)cpMgr + 0x1C8 + 8);

    float dx = *(float *)((char *)cpMgr + 0x1D4 + 0);
    float dy = *(float *)((char *)cpMgr + 0x1D4 + 4);
    float dz = *(float *)((char *)cpMgr + 0x1D4 + 8);

    // Nếu CheckPointMgr chưa khởi tạo xong mRaceStartPosition, gọi fallback hàm của game: GetRoadStartPoint (0x9488AC4)
    if (fabsf(sx) < 1e-3f && fabsf(sz) < 1e-3f) {
        uintptr_t base = rtGetUnityBase();
        if (base) {
            typedef void (*fn_GetRoadStart_t)(void *, float *, float *);
            fn_GetRoadStart_t fn_road = (fn_GetRoadStart_t)(base + 0x9488AC4);
            if (fn_road) {
                float tempPos[3] = {0}, tempDir[3] = {0};
                fn_road(cpMgr, tempPos, tempDir);
                sx = tempPos[0]; sy = tempPos[1]; sz = tempPos[2];
                dx = tempDir[0]; dy = tempDir[1]; dz = tempDir[2];
            }
        }
    }

    if (fabsf(sx) < 1e-3f && fabsf(sz) < 1e-3f) return NO;

    // Đọc gapX, gapY trực tiếp từ mAlignmentPosHelper (offset 0x148 của CheckPointMgr)
    float gapX = 4.5f;
    float gapY = 6.0f;
    void *helper = *(void **)((char *)cpMgr + 0x148);
    if (rtPtrOk(helper)) {
        float gx = *(float *)((char *)helper + 0x10);
        float gy = *(float *)((char *)helper + 0x14);
        if (gx > 0.5f && gx < 20.0f) gapX = gx;
        if (gy > 0.5f && gy < 30.0f) gapY = gy;
    }

    int carsPerRow = 6; // Hằng số CAR_START_ROW_NUM_NORMAL trong VehicleMgr

    // Chuẩn hóa vector Forward (dx, dy, dz)
    float flen = sqrtf(dx * dx + dy * dy + dz * dz);
    float fx = (flen > 1e-4f) ? dx / flen : 0.f;
    float fy = (flen > 1e-4f) ? dy / flen : 0.f;
    float fz = (flen > 1e-4f) ? dz / flen : 1.f;

    // Vector3.Cross(Forward, Vector3.up (0, 1, 0)) chuẩn xác từ assembly sub_D7E7D98:
    // rx = fy * 0 - fz * 1 = -fz
    // ry = fz * 0 - fx * 0 = 0
    // rz = fx * 1 - fy * 0 = fx
    float rx = -fz;
    float ry = 0.f;
    float rz = fx;
    float rlen = sqrtf(rx * rx + rz * rz);
    if (rlen > 1e-4f) {
        rx /= rlen;
        rz /= rlen;
    }

    // Thuật toán chuẩn của hàm sub_ACDE250 (VehicleMgr.CalcuCarStartPosition):
    int slot = (slotIndex >= 0 && slotIndex <= 5) ? slotIndex : 0;
    int row = slot / carsPerRow;
    int col = slot % carsPerRow;

    float lateralMult = ((float)col - 0.5f * (float)(carsPerRow - 1)) * gapX;
    float longitudinalMult = (float)row * gapY;

    // Vector3.op_Addition(startPoint, lateralVec + longitudinalVec)
    outPos[0] = sx + (rx * lateralMult) + (fx * longitudinalMult);
    outPos[1] = sy + (ry * lateralMult) + (fy * longitudinalMult);
    outPos[2] = sz + (rz * lateralMult) + (fz * longitudinalMult);
    return YES;
}

static BOOL rtCalculateAndApplyOffset(void) {
    if (!gEnableOffsetFix) return NO;
    if (!gFrames || gFrameCount < 2) return NO;
    if (gOffsetApplied) return YES;

    // TÍNH TỌA ĐỘ VỊ TRÍ XUẤT PHÁT CỦA MAP THEO THỨ TỰ Ô CỦA REP (KHÔNG LẤY TỌA ĐỘ XE!)
    if (!rtCalculateStartSlotPosInMap(gCheckPointMgr, gRepStartSlot, gMapActualPos)) {
        rtLog("[Offset] Map start slot position not available yet (CheckPointMgr=%p)", gCheckPointMgr);
        return NO;
    }

    float dx = gMapActualPos[0] - gRepOriginPos[0];
    float dy = gMapActualPos[1] - gRepOriginPos[1];
    float dz = gMapActualPos[2] - gRepOriginPos[2];

    float dist = sqrtf(dx * dx + dy * dy + dz * dz);
    rtLog("[Offset] AUTO CALC: RepSlot=%d Rep0=(%.2f, %.2f, %.2f) MapSlot%d=(%.2f, %.2f, %.2f) -> Delta=(%.2f, %.2f, %.2f) dist=%.2fm",
          gRepStartSlot, gRepOriginPos[0], gRepOriginPos[1], gRepOriginPos[2],
          gRepStartSlot, gMapActualPos[0], gMapActualPos[1], gMapActualPos[2],
          dx, dy, dz, dist);

    if (dist > 0.05f) {
        gOffsetDelta[0] = dx;
        gOffsetDelta[1] = dy;
        gOffsetDelta[2] = dz;

        // Bù độ lệch vào từng frame của Replay
        for (uint32_t i = 0; i < gFrameCount; i++) {
            gFrames[i].px += dx;
            gFrames[i].py += dy;
            gFrames[i].pz += dz;
        }
        gOffsetApplied = YES;
        rtLog("[Offset] AUTO CALIBRATED all %u frames with delta (%.2f, %.2f, %.2f)!", gFrameCount, dx, dy, dz);
        return YES;
    }
    gOffsetApplied = YES;
    return NO;
}

#pragma mark - Key injection (đúng cơ chế game)

// InputModule.mInputKeyData (0xA8) -> InputKeyData.KeyFlags (0x10)
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
    if (!gFrames || !gFrameCount) return;

    double dt = now - sLastPlaybackRealTime;
    if (dt < 0.0) dt = 0.0;
    if (dt > 0.1) dt = 0.1; // clamp lag spike
    sLastPlaybackRealTime = now;
    sAccumulatedPlaybackTime += (float)dt * gSpeedMultiplier;
    float t = sAccumulatedPlaybackTime;

    if (t < 0.f) return;
    if (t >= gFrames[gFrameCount - 1].t) {
        gPlaying = NO;
        gCurPlaybackSteer = 0.f;
        rtWriteKeyFlags(0);
        return;
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

    // --- 1. TỌA ĐỘ VÀ VẬN TỐC NỘI SUY ---
    float tx = a->px + (b->px - a->px) * al;
    float ty = a->py + (b->py - a->py) * al;
    float tz = a->pz + (b->pz - a->pz) * al;

    // --- 2. NỘI SUY GÓC XOAY QUATERNION CHUẨN XÁC (Shortest-path NLerp chống lật góc 180 độ) ---
    float dot = a->qx * b->qx + a->qy * b->qy + a->qz * b->qz + a->qw * b->qw;
    float bx = b->qx, by = b->qy, bz = b->qz, bw = b->qw;
    if (dot < 0.0f) {
        bx = -bx; by = -by; bz = -bz; bw = -bw; // Triệt tiêu góc lật
    }
    float qx = a->qx + (bx - a->qx) * al;
    float qy = a->qy + (by - a->qy) * al;
    float qz = a->qz + (bz - a->qz) * al;
    float qw = a->qw + (bw - a->qw) * al;
    float ql = sqrtf(qx * qx + qy * qy + qz * qz + qw * qw);
    if (ql > 1e-4f) { qx /= ql; qy /= ql; qz /= ql; qw /= ql; }

    float vx = (a->vx + (b->vx - a->vx) * al) * gSpeedMultiplier;
    float vy = (a->vy + (b->vy - a->vy) * al) * gSpeedMultiplier;
    float vz = (a->vz + (b->vz - a->vz) * al) * gSpeedMultiplier;
    float kmph = (a->kmph + (b->kmph - a->kmph) * al) * gSpeedMultiplier;

    // --- 2. TELEPORT TRỰC TIẾP THỰC THỂ VẬT LÝ PHYSX (mPhyHandle) ---
    void *phyCtrl = rtPtrOk(motionCtrl) ? *(void **)((char *)motionCtrl + kOffMotionPhyCtrl) : NULL;
    if (rtPtrOk(phyCtrl)) {
        void *ent = *(void **)((char *)phyCtrl + 0x18); // mPhyHandle
        if (rtPtrOk(ent)) {
            float pos[3]  = { tx, ty, tz };
            float quat[4] = { qx, qy, qz, qw };
            float vel[3]  = { vx, vy, vz };

            typedef void (*fn_SetTrans_t)(void *, float *, float *);
            typedef void (*fn_SetLinVel_t)(void *, float *);
            uintptr_t base = rtGetUnityBase();
            if (base) {
                fn_SetTrans_t fn_SetTrans = (fn_SetTrans_t)(base + 0xF718248);
                fn_SetLinVel_t fn_SetLinVel = (fn_SetLinVel_t)(base + 0xF7181F4);
                fn_SetTrans(ent, pos, quat);
                fn_SetLinVel(ent, vel);
            } else {
                fn_SetTrans_t set_transform = (fn_SetTrans_t)*(void **)(*(char **)ent + 112);
                fn_SetLinVel_t set_vel = (fn_SetLinVel_t)*(void **)(*(char **)ent + 136);
                if (set_transform) set_transform(ent, pos, quat);
                if (set_vel) set_vel(ent, vel);
            }
        }
    }

    // --- 3. CƯỠNG BỨC SET STATE TỌA ĐỘ & VẬN TỐC (State-Locking TAS) ---
    // Dù người chơi không có nitro/miniboost, xe vẫn được khóa chặt theo frame:
    if (rtPtrOk(motionCtrl)) {
        *(float *)((char *)motionCtrl + kOffMotionForcePos + 0) = tx;
        *(float *)((char *)motionCtrl + kOffMotionForcePos + 4) = ty;
        *(float *)((char *)motionCtrl + kOffMotionForcePos + 8) = tz;

        *(float *)((char *)motionCtrl + kOffMotionForceRot + 0) = qx;
        *(float *)((char *)motionCtrl + kOffMotionForceRot + 4) = qy;
        *(float *)((char *)motionCtrl + kOffMotionForceRot + 8) = qz;
        *(float *)((char *)motionCtrl + kOffMotionForceRot + 12) = qw;

        *(bool *)((char *)motionCtrl + kOffMotionIsSetTransform) = true;
    }

    if (rtPtrOk(sim)) {
        *(float *)((char *)sim + kOffSimChassisPos + 0) = tx;
        *(float *)((char *)sim + kOffSimChassisPos + 4) = ty;
        *(float *)((char *)sim + kOffSimChassisPos + 8) = tz;

        *(float *)((char *)sim + kOffSimChassisRot + 0) = qx;
        *(float *)((char *)sim + kOffSimChassisRot + 4) = qy;
        *(float *)((char *)sim + kOffSimChassisRot + 8) = qz;
        *(float *)((char *)sim + kOffSimChassisRot + 12) = qw;

        // ÁP DỤNG VẬN TỐC & TỐC ĐỘ:
        *(float *)((char *)sim + kOffSimLinearVel + 0) = vx;
        *(float *)((char *)sim + kOffSimLinearVel + 4) = vy;
        *(float *)((char *)sim + kOffSimLinearVel + 8) = vz;
        *(float *)((char *)sim + kOffSimKmph)          = kmph;        // 0x10 mKmph
        *(float *)((char *)sim + 0x14)                 = kmph / 3.6f; // 0x14 mMps (HUD Speedometer)
        *(float *)((char *)sim + 0xB4)                 = 1.0f;        // 0xB4 mForwardForce
    }

    // --- 4. ĐÁNH LÁI & GA (CUA) ---
    float steer = a->steer + (b->steer - a->steer) * al;
    if (steer >  1.0f) steer =  1.0f;
    if (steer < -1.0f) steer = -1.0f;
    gCurPlaybackSteer = steer;

    *(float *)((char *)steerData + kOffSteerLeft) = steer;
    *(float *)((char *)steerData + kOffSteerForward) = 1.0f;
    if (rtPtrOk(drivingCtrl)) {
        *(float *)((char *)drivingCtrl + 0x40) = steer; // mSteering
        *(float *)((char *)drivingCtrl + 0x68) = steer; // mInputXPosition
        *(float *)((char *)drivingCtrl + 0x34) = steer; // mVehicleCtrlParams.steering
        *(float *)((char *)drivingCtrl + 0x3C) = 1.0f;  // mThrottle
        *(float *)((char *)drivingCtrl + 0x38) = 1.0f;  // mVehicleCtrlParams.throttle
    }

    // --- 5. BƠM PHÍM BẤM (Nitro, MiniBoost, Drift, Phanh, Trái, Phải) ---
    uint32_t keys = a->keys;
    if (a->flags & 0x01) keys |= (1 << 6); // Phanh
    if (a->flags & 0x04) keys |= (1 << 8); // Drift
    if (a->flags & 0x08) keys |= (1 << 3); // Nitro
    if (a->flags & 0x10) keys |= (1 << 5); // MiniBoost

    if (t >= 0.06f && t <= 0.45f) {
        keys |= (1 << 5); // Start MiniBoost
    }

    if (steer < -0.15f) {
        keys |= (1 << 1);  // Left
        keys &= ~(1 << 2);
    } else if (steer > 0.15f) {
        keys |= (1 << 2);  // Right
        keys &= ~(1 << 1);
    }

    gKeyMask = (int)keys;
    rtWriteKeyFlags((int)keys);
}

#pragma mark - UI Interface

@interface RCPanel : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIWindow *win;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIView *menu;
@property (nonatomic, strong) UISegmentedControl *tabSeg;

// Tab 0: Điều khiển chính
@property (nonatomic, strong) UIView *tab0View;
@property (nonatomic, strong) UIButton *bDl;
@property (nonatomic, strong) UIButton *bNoRep;
@property (nonatomic, strong) UIButton *bAuto;
@property (nonatomic, strong) UIButton *bFixMap;
@property (nonatomic, strong) UISlider *sliderSpeed;
@property (nonatomic, strong) UILabel *lblSpeed;
@property (nonatomic, strong) UILabel *status;

// Tab 1: Tính toán độ lệch vị trí
@property (nonatomic, strong) UIView *tab1View;
@property (nonatomic, strong) UIButton *bToggleOffset;
@property (nonatomic, strong) UIButton *bFixNow;
@property (nonatomic, strong) UILabel *lblOffsetInfo;

- (void)show;
- (void)refresh;
@end

@interface RCPassWindow : UIWindow
@property (nonatomic, weak) UIView *bubble;
@property (nonatomic, weak) UIView *menu;
@end

@implementation RCPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden) return nil;
    if (self.bubble && [self.bubble pointInside:[self convertPoint:point toView:self.bubble] withEvent:event]) {
        return [super hitTest:point withEvent:event];
    }
    if (self.menu && !self.menu.hidden && [self.menu pointInside:[self convertPoint:point toView:self.menu] withEvent:event]) {
        return [super hitTest:point withEvent:event];
    }
    return nil;
}
@end

static RCPanel *gPanel;

static UIViewController *rtTopVC(void) {
    if (gPanel && gPanel.win && gPanel.win.rootViewController) {
        UIViewController *vc = gPanel.win.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        return vc;
    }
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
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                  message:msg
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

// No Replay Hooks
static int    (*orig_MatchVideoMdl_StartEnterGame)(void *, int, void *, void *, const void *);
static int    (*orig_MatchVideoMdl_ChallengeShadow_info)(void *, void *, uint64_t, const void *);
static int    (*orig_MatchVideoMdl_ChallengeShadow_mark)(void *, int64_t, uint64_t, const void *);
static int    (*orig_MatchVideoMdl_ReplayVideo_bytes)(void *, void *, uint64_t, void *, void *, const void *);
static int    (*orig_MatchVideoMdl_ReplayVideo_mark)(void *, int64_t, uint64_t, const void *);
static int    (*orig_MatchVideoMdl_ReplayTeachingVideo)(void *, int, void *, bool, const void *);

// Anti-AFK & Anti-Speed-Report Hooks
static void   (*orig_SdcVehicleInput_UpdateVehicleNotControlMaxTime)(void *, float, const void *);
static void   (*orig_SdcVehicleInput_Update)(void *, float, const void *);
static void   (*orig_SdcPlayerInput_Update)(void *, float, const void *);
static void   (*orig_SdcVehicleVel_Update)(void *, float, const void *);
static void   (*orig_CPR_FillVehicleInputData)(void *, void **, const void *);
static void   (*orig_CPR_FillVehicleVelData)(void *, void **, const void *);
static void   (*orig_CPR_FillPVPButtonUseData)(void *, void **, const void *);
static void   (*orig_CPR_ReportData)(void *, void **, const void *);
static BOOL   (*orig_MatchUIMgr_Trusteeship)(void *, int, const void *);

static void hook_Input_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) gInputModule = self;
    if (orig_Input_Update) orig_Input_Update(self, dt, m);
    if (gPlaying) {
        rtWriteKeyFlags(gKeyMask);
    }
}

static BOOL hook_Input_GetKey(void *self, int keyType, const void *m) {
    if (rtPtrOk(self)) gInputModule = self;
    if (gPlaying && keyType > 0 && keyType < 18) {
        if ((gKeyMask >> keyType) & 1) return TRUE;
    }
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
    sLastPlaybackRealTime = gGoTime;
    sAccumulatedPlaybackTime = 0.0f;
    gCurPlaybackSteer = 0.f;

    if (gAutoArmed) {
        BOOL ok = (gFrames && gFrameCount > 0) ? YES : rtLoadRecord();
        if (ok && gEnableOffsetFix && !gOffsetApplied) {
            rtCalculateAndApplyOffset();
        }
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
    BOOL res = orig_MatchVideoDesHelper_InitByVideoBytes ? orig_MatchVideoDesHelper_InitByVideoBytes(self, videoBytes, m) : NO;
    rtLog("HOOK MatchVideoDesHelper::InitByVideoBytes res=%d", (int)res);
    if (res && rtPtrOk(self)) {
        rtExtractFramesFromDesHelper(self);
    }
    return res;
}

static void hook_CheckPointMgr_Init(void *self, void *config, bool crc, bool reset, const void *m) {
    gPlaying = NO;
    gPlayerVehicle = NULL;
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, crc, reset, m);
    gMapId = rtPtrOk(self) ? *(int *)((char *)self + 0x40) : 0;
    if (gMapId <= 0 && rtPtrOk(config)) {
        gMapId = *(int *)((char *)config + kOffCpMapId);
    }
    gTrackLen = 0.f;

    // Lưu con trỏ CheckPointMgr và reset cờ
    gCheckPointMgr = self;
    gOffsetApplied = NO;
    memset(gOffsetDelta, 0, sizeof(gOffsetDelta));
    memset(gMapActualPos, 0, sizeof(gMapActualPos));

    rtLog("MAP resolved from CheckPointMgr self=%p config=%p mapId=%d", self, config, gMapId);

    // KHI VÀO MAP MỚI: TỰ ĐỘNG NẠP .REP VÀ TỰ ĐỘNG BÙ LỆCH NGAY LẬP TỨC!
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gAutoArmed) {
            BOOL ok = rtLoadRecord();
            if (ok && gEnableOffsetFix) {
                // TỰ ĐỘNG BÙ LỆCH VỊ TRÍ THEO Ô XUẤT PHÁT CỦA MAP (KHÔNG LẤY VỊ TRÍ XE)
                rtCalculateAndApplyOffset();
            }
        }
        if (gPanel) [gPanel refresh];
    });
}

static void hook_MapDataComponent_InitComponent(void *self, const void *m) {
    if (rtPtrOk(self)) {
        gMapDataComponent = self;
        rtLog("Captured MapDataComponent=%p", self);
    }
    if (orig_MapDataComponent_InitComponent) orig_MapDataComponent_InitComponent(self, m);
}

static void *hook_DataCenterMdl_GetMapDataComponent(void *self, bool withInit, const void *m) {
    void *res = orig_DataCenterMdl_GetMapDataComponent ? orig_DataCenterMdl_GetMapDataComponent(self, withInit, m) : NULL;
    if (rtPtrOk(res)) {
        gMapDataComponent = res;
    }
    return res;
}

// ==================== NO REPLAY HOOKS (CHẶN MỞ REPLAY / BÓNG) ====================
static int hook_MatchVideoMdl_StartEnterGame(void *self, int videoId, void *bytes, void *summaryInfo, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted StartEnterGame (id=%d)", videoId);
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động vào trận.");
        return 0; // NotErr
    }
    return orig_MatchVideoMdl_StartEnterGame ? orig_MatchVideoMdl_StartEnterGame(self, videoId, bytes, summaryInfo, m) : 0;
}

static int hook_MatchVideoMdl_ChallengeShadow_info(void *self, void *summaryInfo, uint64_t shadowUID, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ChallengeShadow(info)");
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động vào trận bóng.");
        return 0;
    }
    return orig_MatchVideoMdl_ChallengeShadow_info ? orig_MatchVideoMdl_ChallengeShadow_info(self, summaryInfo, shadowUID, m) : 0;
}

static int hook_MatchVideoMdl_ChallengeShadow_mark(void *self, int64_t videoMark, uint64_t shadowUID, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ChallengeShadow(mark=%lld)", (long long)videoMark);
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động vào trận bóng.");
        return 0;
    }
    return orig_MatchVideoMdl_ChallengeShadow_mark ? orig_MatchVideoMdl_ChallengeShadow_mark(self, videoMark, shadowUID, m) : 0;
}

static int hook_MatchVideoMdl_ReplayVideo_bytes(void *self, void *videoBytes, uint64_t uid, void *name, void *icon, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ReplayVideo(bytes)");
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động mở Replay.");
        return 0; // NotErr
    }
    return orig_MatchVideoMdl_ReplayVideo_bytes ? orig_MatchVideoMdl_ReplayVideo_bytes(self, videoBytes, uid, name, icon, m) : 0;
}

static int hook_MatchVideoMdl_ReplayVideo_mark(void *self, int64_t mark, uint64_t uid, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ReplayVideo(mark=%lld)", (long long)mark);
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động mở Replay.");
        return 0; // NotErr
    }
    return orig_MatchVideoMdl_ReplayVideo_mark ? orig_MatchVideoMdl_ReplayVideo_mark(self, mark, uid, m) : 0;
}

static int hook_MatchVideoMdl_ReplayTeachingVideo(void *self, int videoId, void *url, bool uncomp, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ReplayTeachingVideo(id=%d)", videoId);
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động mở Replay.");
        return 0; // NotErr
    }
    return orig_MatchVideoMdl_ReplayTeachingVideo ? orig_MatchVideoMdl_ReplayTeachingVideo(self, videoId, url, uncomp, m) : 0;
}

// ==================== ANTI-AFK (4 TẦNG CHỐNG TREO MÁY) ====================
// Tầng 1: Khóa bộ đếm thời gian không điều khiển của xe
static void hook_SdcVehicleInput_UpdateVehicleNotControlMaxTime(void *self, float dt, const void *m) {
    if (!rtPtrOk(self)) return;
    *(float *)((char *)self + 0x9C) = 0.f;  // mNotControlTime = 0
    *(bool  *)((char *)self + 0xA0) = true; // mLastIsControl = true
    *(float *)((char *)self + 0xA4) = 0.f;  // mLastControlTime = 0

    void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcVehicleInputEndData)
    if (rtPtrOk(endData)) {
        *(int *)((char *)endData + 0x2C) = 0; // CarNonControlTimeMax = 0
        *(int *)((char *)endData + 0x30) = 0; // CarNonControlTimeTotal = 0
    }
}

static void hook_SdcVehicleInput_Update(void *self, float dt, const void *m) {
    if (orig_SdcVehicleInput_Update) orig_SdcVehicleInput_Update(self, dt, m);
    if (rtPtrOk(self)) {
        *(float *)((char *)self + 0x9C) = 0.f;  // mNotControlTime = 0
        *(bool  *)((char *)self + 0xA0) = true; // mLastIsControl = true
        *(float *)((char *)self + 0xA4) = 0.f;  // mLastControlTime = 0

        void *endData = *(void **)((char *)self + 0x58);
        if (rtPtrOk(endData)) {
            *(int *)((char *)endData + 0x2C) = 0; // CarNonControlTimeMax = 0
            *(int *)((char *)endData + 0x30) = 0; // CarNonControlTimeTotal = 0
            if (gPlaying) {
                (*(int *)((char *)endData + 0x10))++; // CarLeftTurnCount++
                (*(int *)((char *)endData + 0x18))++; // CarRightTurnCount++
                (*(int *)((char *)endData + 0x24))++; // CarDriftingCount++
            }
        }
    }
}

static void hook_SdcPlayerInput_Update(void *self, float dt, const void *m) {
    if (orig_SdcPlayerInput_Update) orig_SdcPlayerInput_Update(self, dt, m);
    if (rtPtrOk(self) && gPlaying) {
        void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcPlayerInputEndData)
        if (rtPtrOk(endData)) {
            (*(int *)((char *)endData + 0x14))++; // UserLeftTurnCount++
            (*(int *)((char *)endData + 0x18))++; // UserRightTurnCount++
            (*(int *)((char *)endData + 0x20))++; // UserDriftingCount++
            (*(int *)((char *)endData + 0x24))++; // UserMiniJetCount++
        }
    }
}

// Tầng 2: Làm sạch dữ liệu NonControlTime trên gói tin EndGame gửi lên Server
static void hook_CPR_FillVehicleInputData(void *self, void **fillData, const void *m) {
    if (orig_CPR_FillVehicleInputData) orig_CPR_FillVehicleInputData(self, fillData, m);
    if (fillData && rtPtrOk(*fillData)) {
        char *d = (char *)*fillData;
        *(uint32_t *)(d + 0x48) = 0; // dwCarNonControlTimeMax = 0
        *(uint32_t *)(d + 0x4C) = 0; // dwCarNonControlTimeTotal = 0
    }
}

// Tầng 3: Bổ sung số lượt thao tác phím hợp lệ gửi lên Server
static void hook_CPR_FillPVPButtonUseData(void *self, void **fillData, const void *m) {
    if (orig_CPR_FillPVPButtonUseData) orig_CPR_FillPVPButtonUseData(self, fillData, m);
    if (fillData && rtPtrOk(*fillData)) {
        char *d = (char *)*fillData;
        if (*(uint16_t *)(d + 0x12) < 15) *(uint16_t *)(d + 0x12) = 15 + (rand() % 10);
        if (*(uint16_t *)(d + 0x14) < 15) *(uint16_t *)(d + 0x14) = 15 + (rand() % 10);
        if (*(uint16_t *)(d + 0x18) < 8)  *(uint16_t *)(d + 0x18) = 8 + (rand() % 5);
        if (*(uint16_t *)(d + 0x1A) < 10) *(uint16_t *)(d + 0x1A) = 10 + (rand() % 6);
    }
}

// Tầng 4: Chặn Game chuyển sang trạng thái AFK / Trusteeship (xe AI tự lái)
static BOOL hook_MatchUIMgr_Trusteeship(void *self, int aiActionID, const void *m) {
    if (gPlaying) {
        rtLog("ANTI-AFK: Blocked in-game Trusteeship (%d)", aiActionID);
        return FALSE; // Không cho game chuyển sang xe AI tự lái của AFK
    }
    return orig_MatchUIMgr_Trusteeship ? orig_MatchUIMgr_Trusteeship(self, aiActionID, m) : FALSE;
}

// ==================== ANTI-SPEED-REPORT (CHỐNG REPORT TỐC ĐỘ / FAST FRAME) ====================
static void hook_SdcVehicleVel_Update(void *self, float dt, const void *m) {
    if (orig_SdcVehicleVel_Update) orig_SdcVehicleVel_Update(self, dt, m);
    if (rtPtrOk(self)) {
        // Giới hạn vận tốc đo đạc trong bộ nhớ về mức xe bình thường (tránh trigger Anti-Cheat khi tua nhanh)
        if (*(float *)((char *)self + 0x94) > 295.f) *(float *)((char *)self + 0x94) = 290.f + (rand() % 5); // mMaxVehicleKMPH
        if (*(float *)((char *)self + 0xAC) > 295.f) *(float *)((char *)self + 0xAC) = 290.f + (rand() % 5); // mVehicleKMPH
        if (*(float *)((char *)self + 0xB0) > 295.f) *(float *)((char *)self + 0xB0) = 290.f + (rand() % 5); // mLastVehicleKMPH

        void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcVehicleVelEndData)
        if (rtPtrOk(endData)) {
            if (*(int *)((char *)endData + 0x10) > 295) *(int *)((char *)endData + 0x10) = 292 + (rand() % 5); // CarSpeedMax
            *(int *)((char *)endData + 0x14) = 15; // CarSpeedOverBase
            *(float *)((char *)endData + 0x58) = 0.f; // SpeedRangeTime_Greater350Less400
            *(float *)((char *)endData + 0x5C) = 0.f; // SpeedRangeTime_Greater400Less450
            *(float *)((char *)endData + 0x60) = 0.f; // SpeedRangeTime_Greater450Less500
            *(float *)((char *)endData + 0x64) = 0.f; // SpeedRangeTime_Greater500
            *(int *)((char *)endData + 0x7C) = 0;   // SpeedReach_350
            *(int *)((char *)endData + 0x80) = 0;   // SpeedReach_400
        }
    }
}

static void hook_CPR_FillVehicleVelData(void *self, void **fillData, const void *m) {
    if (orig_CPR_FillVehicleVelData) orig_CPR_FillVehicleVelData(self, fillData, m);
    if (fillData && rtPtrOk(*fillData)) {
        char *d = (char *)*fillData;
        // dwCarSpeedMax (offset 0x28)
        if (*(uint32_t *)(d + 0x28) > 298) *(uint32_t *)(d + 0x28) = 292 + (rand() % 6);
        // dwCarSpeedOverBase (offset 0x2C)
        if (*(uint32_t *)(d + 0x2C) > 25)  *(uint32_t *)(d + 0x2C) = 12 + (rand() % 5);
    }
}

static void hook_CPR_ReportData(void *self, void **reqData, const void *m) {
    if (orig_CPR_ReportData) orig_CPR_ReportData(self, reqData, m);
    if (reqData && rtPtrOk(*reqData)) {
        char *req = (char *)*reqData;
        *(uint8_t *)(req + 0x40) = 0; // bCheatEndGame = 0 (Tuyệt đối không bị Server đánh dấu gian lận)
        *(uint8_t *)(req + 0x54) = 0; // bClientReportAnti = 0 (Báo cáo client bình thường)
        rtLog("ANTI-REPORT: Cleared bCheatEndGame & bClientReportAnti");
    }
}

static void hook_MotionCtrl_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) {
        void *vehicle = *(void **)((char *)self + kOffMotionVehicle);
        if (rtPtrOk(vehicle)) {
            int actorType = *(int *)((char *)vehicle + kOffVehicleActorType);
            bool isMain = *(bool *)((char *)vehicle + kOffVehicleIsMainPlayer);
            // Chấp nhận: RealPlayer (0), ReplayPlayer (3), BeObservePlayer (5), hoặc xe mIsMainPlayer (0xF8)
            BOOL isTarget = isMain || (actorType == 0) || (actorType == 3) || (actorType == 5);
            if (isTarget) {
                gPlayerVehicle = vehicle;
                void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
                void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
                void *drivingCtrl = *(void **)((char *)self + kOffMotionDriving);
                void *sim = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + kOffPhySimOutput) : NULL;

                // Đọc thứ tự xuất phát của xe trong trận (InputCarPos) để hiển thị thông tin
                if (!gPlaying && rtPtrOk(vehicle)) {
                    gMapStartSlot = *(int *)((char *)vehicle + 0xE8);
                }

                if (gPlaying) {

                    // Hook vtable slot 33 (GetSteeringValue) trực tiếp trên instance của drivingCtrl
                    if (rtPtrOk(drivingCtrl)) {
                        void *k = *(void **)drivingCtrl;
                        if (rtPtrOk(k)) {
                            void **vt_slot = (void **)((char *)k + 856);
                            if (*vt_slot != (void *)hook_GetSteeringValue) {
                                if (!orig_GetSteeringValue) {
                                    orig_GetSteeringValue = (BOOL (*)(void *, void *, float, float *, float *, const void *))*vt_slot;
                                }
                                *vt_slot = (void *)hook_GetSteeringValue;
                            }
                        }
                    }

                    if (rtPtrOk(steerData) && rtPtrOk(sim)) {
                        double now = rtNow();
                        rtPlaybackTick(self, steerData, drivingCtrl, sim, now);
                    }
                }
            }
        }
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, m);
}

#pragma mark - UI



@implementation RCPanel

- (UIButton *)mk:(NSString *)t sel:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.layer.cornerRadius = 7;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)onPanBubble:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.win];
    CGRect f = self.bubble.frame;
    f.origin.x += trans.x;
    f.origin.y += trans.y;
    CGRect scr = UIScreen.mainScreen.bounds;
    if (f.origin.x < 5) f.origin.x = 5;
    if (f.origin.y < 20) f.origin.y = 20;
    if (f.origin.x + f.size.width  > scr.size.width  - 5) f.origin.x = scr.size.width  - f.size.width  - 5;
    if (f.origin.y + f.size.height > scr.size.height - 20) f.origin.y = scr.size.height - f.size.height - 20;
    self.bubble.frame = f;
    [p setTranslation:CGPointZero inView:self.win];
}

- (void)onPanMenu:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.win];
    CGRect f = self.menu.frame;
    f.origin.x += trans.x;
    f.origin.y += trans.y;
    CGRect scr = UIScreen.mainScreen.bounds;
    if (f.origin.x < 5) f.origin.x = 5;
    if (f.origin.y < 20) f.origin.y = 20;
    if (f.origin.x + f.size.width  > scr.size.width  - 5) f.origin.x = scr.size.width  - f.size.width  - 5;
    if (f.origin.y + f.size.height > scr.size.height - 20) f.origin.y = scr.size.height - f.size.height - 20;
    self.menu.frame = f;
    [p setTranslation:CGPointZero inView:self.win];
}

- (void)onToggleMenu {
    self.menu.hidden = (self.menu.hidden ? NO : YES);
    if (!self.menu.hidden) {
        [self refresh];
    }
}

- (void)onTabChange:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) {
        self.tab0View.hidden = NO;
        self.tab1View.hidden = YES;
    } else {
        self.tab0View.hidden = YES;
        self.tab1View.hidden = NO;
    }
    [self refresh];
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect scr = UIScreen.mainScreen.bounds;
        RCPassWindow *win = [[RCPassWindow alloc] initWithFrame:scr];
        win.windowLevel = UIWindowLevelAlert + 2;
        win.backgroundColor = UIColor.clearColor;
        win.opaque = NO;
        win.rootViewController = [UIViewController new];
        win.rootViewController.view.backgroundColor = UIColor.clearColor;
        win.rootViewController.view.userInteractionEnabled = YES;

        if (@available(iOS 13.0, *)) {
            if (!win.windowScene) {
                for (UIWindow *w in UIApplication.sharedApplication.windows) {
                    if ([w isKindOfClass:[RCPassWindow class]]) continue;
                    if (w.windowScene) { win.windowScene = w.windowScene; break; }
                }
            }
        }

        // 1. Bong bóng nổi (Floating Bubble 46x46)
        UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(scr.size.width - 56, scr.size.height * 0.35, 46, 46)];
        bubble.backgroundColor = [UIColor colorWithRed:0.06 green:0.12 blue:0.18 alpha:0.92];
        bubble.layer.cornerRadius = 23;
        bubble.layer.borderWidth = 1.5;
        bubble.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.9].CGColor;
        bubble.clipsToBounds = YES;
        [win addSubview:bubble];
        self.bubble = bubble;
        win.bubble = bubble;

        UIButton *btnBubble = [UIButton buttonWithType:UIButtonTypeCustom];
        btnBubble.frame = bubble.bounds;
        [btnBubble setTitle:@"⚡RK" forState:UIControlStateNormal];
        btnBubble.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [btnBubble setTitleColor:[UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
        [btnBubble addTarget:self action:@selector(onToggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [bubble addSubview:btnBubble];

        UIPanGestureRecognizer *panBubble = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
        [bubble addGestureRecognizer:panBubble];

        // 2. Menu chính chia Tab (215x310, mặc định ẩn, bấm bubble để mở)
        UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(scr.size.width - 225, scr.size.height * 0.22, 215, 310)];
        menu.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.96];
        menu.layer.cornerRadius = 14;
        menu.layer.borderWidth = 1.5;
        menu.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.75].CGColor;
        menu.clipsToBounds = YES;
        menu.hidden = YES;
        [win addSubview:menu];
        self.menu = menu;
        win.menu = menu;

        UIPanGestureRecognizer *panMenu = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanMenu:)];
        panMenu.delegate = self;
        [menu addGestureRecognizer:panMenu];

        // Tiêu đề & Nút đóng
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, 150, 20)];
        t.text = @"RaceKit Pro";
        t.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
        t.font = [UIFont boldSystemFontOfSize:13];
        [menu addSubview:t];

        UIButton *bClose = [UIButton buttonWithType:UIButtonTypeSystem];
        bClose.frame = CGRectMake(180, 5, 24, 24);
        [bClose setTitle:@"✕" forState:UIControlStateNormal];
        [bClose setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
        bClose.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [bClose addTarget:self action:@selector(onToggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:bClose];

        // Segmented Control chia 2 Tab
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Chính", @"Lệch Vị Trí"]];
        seg.frame = CGRectMake(10, 30, 195, 26);
        seg.selectedSegmentIndex = 0;
        if (@available(iOS 13.0, *)) {
            seg.selectedSegmentTintColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.75 alpha:0.95];
            [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont boldSystemFontOfSize:11]} forState:UIControlStateSelected];
            [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.75 alpha:1.0], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
        }
        [seg addTarget:self action:@selector(onTabChange:) forControlEvents:UIControlEventValueChanged];
        [menu addSubview:seg];
        self.tabSeg = seg;

        // Container Tab 0: Điều khiển chính
        UIView *c0 = [[UIView alloc] initWithFrame:CGRectMake(10, 62, 195, 238)];
        [menu addSubview:c0];
        self.tab0View = c0;

        self.bDl = [self mk:@"⬇ TẢI .REP" sel:@selector(tapDownload)];
        self.bDl.frame = CGRectMake(0, 0, 195, 28);
        [c0 addSubview:self.bDl];

        self.bNoRep = [self mk:@"NO REP: BẬT" sel:@selector(tapNoRep)];
        self.bNoRep.frame = CGRectMake(0, 32, 195, 28);
        [c0 addSubview:self.bNoRep];

        self.bAuto = [self mk:@"▶ AUTO" sel:@selector(tapAuto)];
        self.bAuto.frame = CGRectMake(0, 64, 195, 28);
        [c0 addSubview:self.bAuto];

        self.bFixMap = [self mk:@"⚠ LỖI MAP" sel:@selector(tapFixMap)];
        self.bFixMap.frame = CGRectMake(0, 96, 195, 28);
        self.bFixMap.backgroundColor = [UIColor colorWithRed:0.75 green:0.20 blue:0.18 alpha:0.92];
        [c0 addSubview:self.bFixMap];

        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 130, 195, 22)];
        sl.minimumValue = 1.0f;
        sl.maximumValue = 5.0f;
        sl.value = gSpeedMultiplier;
        sl.continuous = YES;
        [sl addTarget:self action:@selector(onSpeedChange:) forControlEvents:UIControlEventValueChanged];
        [c0 addSubview:sl];
        self.sliderSpeed = sl;

        UILabel *ls = [[UILabel alloc] initWithFrame:CGRectMake(0, 154, 195, 14)];
        ls.font = [UIFont boldSystemFontOfSize:10];
        ls.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.9];
        ls.textAlignment = NSTextAlignmentCenter;
        ls.text = [NSString stringWithFormat:@"Tốc độ: %.1fx", gSpeedMultiplier];
        [c0 addSubview:ls];
        self.lblSpeed = ls;

        self.status = [[UILabel alloc] initWithFrame:CGRectMake(0, 172, 195, 62)];
        self.status.numberOfLines = 3;
        self.status.font = [UIFont systemFontOfSize:9];
        self.status.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        [c0 addSubview:self.status];

        // Container Tab 1: Tính toán độ lệch vị trí
        UIView *c1 = [[UIView alloc] initWithFrame:CGRectMake(10, 62, 195, 238)];
        c1.hidden = YES;
        [menu addSubview:c1];
        self.tab1View = c1;

        self.bToggleOffset = [self mk:@"BÙ LỆCH: BẬT" sel:@selector(tapToggleOffset)];
        self.bToggleOffset.frame = CGRectMake(0, 0, 195, 28);
        self.bToggleOffset.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95];
        [c1 addSubview:self.bToggleOffset];

        self.bFixNow = [self mk:@"⚡ TÍNH & FIX NGAY" sel:@selector(tapFixNow)];
        self.bFixNow.frame = CGRectMake(0, 32, 195, 28);
        self.bFixNow.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.75 alpha:0.92];
        [c1 addSubview:self.bFixNow];

        self.lblOffsetInfo = [[UILabel alloc] initWithFrame:CGRectMake(0, 64, 195, 168)];
        self.lblOffsetInfo.numberOfLines = 11;
        self.lblOffsetInfo.font = [UIFont systemFontOfSize:9];
        self.lblOffsetInfo.textColor = [UIColor colorWithWhite:0.92 alpha:0.95];
        self.lblOffsetInfo.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.75];
        self.lblOffsetInfo.layer.cornerRadius = 6;
        self.lblOffsetInfo.layer.borderWidth = 0.5;
        self.lblOffsetInfo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
        self.lblOffsetInfo.clipsToBounds = YES;
        [c1 addSubview:self.lblOffsetInfo];

        self.win = win;
        win.hidden = NO;
        [win makeKeyAndVisible];

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
        self.bNoRep.backgroundColor = gNoReplay ? [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95]
                                                : [UIColor colorWithWhite:0.12 alpha:0.92];
        [self.bNoRep setTitle:gNoReplay ? @"NO REP: BẬT" : @"NO REP: TẮT" forState:UIControlStateNormal];

        if (!gDownloading) {
            NSString *stateStr = gAutoArmed ? @"AUTO: BẬT" : @"AUTO: TẮT";
            self.status.text = [NSString stringWithFormat:@"Map: %d (%u frame)\n%@\nPlay: %d",
                                gMapId, gFrameCount, stateStr, (int)gPlaying];
        }

        // Cập nhật thông số Tab 1
        self.bToggleOffset.backgroundColor = gEnableOffsetFix ? [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95]
                                                              : [UIColor colorWithWhite:0.12 alpha:0.92];
        [self.bToggleOffset setTitle:gEnableOffsetFix ? @"BÙ LỆCH: BẬT" : @"BÙ LỆCH: TẮT" forState:UIControlStateNormal];

        NSString *statusStr = !gEnableOffsetFix ? @"ĐANG TẮT" : (gOffsetApplied ? @"TỰ ĐỘNG BÙ XONG" : @"CHỜ NẠP MAP");
        self.lblOffsetInfo.text = [NSString stringWithFormat:
            @" • Tự động bù map: BẬT\n"
            @" • Rep Ô: %d | Trận Ô: %d\n"
            @" • Rep F0 (Ô %d):\n"
            @"   (%.1f, %.1f, %.1f)\n"
            @" • Map chuẩn (Ô %d):\n"
            @"   (%.1f, %.1f, %.1f)\n"
            @" • Độ lệch (Map - Rep):\n"
            @"   ΔX: %+.2f | ΔY: %+.2f | ΔZ: %+.2f\n"
            @" • Trạng thái: %@",
            gRepStartSlot, gMapStartSlot,
            gRepStartSlot,
            gRepOriginPos[0], gRepOriginPos[1], gRepOriginPos[2],
            gRepStartSlot,
            gMapActualPos[0], gMapActualPos[1], gMapActualPos[2],
            gOffsetDelta[0], gOffsetDelta[1], gOffsetDelta[2],
            statusStr];
    });
}

- (void)tapToggleOffset {
    gEnableOffsetFix = (gEnableOffsetFix ? NO : YES);
    if (!gEnableOffsetFix) {
        rtLoadRecord();
    } else {
        gOffsetApplied = NO;
        rtCalculateAndApplyOffset();
    }
    [self refresh];
}

- (void)tapFixNow {
    if (!rtPtrOk(gCheckPointMgr)) {
        rtAlert(@"Chưa nạp Map", @"Vui lòng vào trận hoặc phòng để game nạp cấu trúc Map!");
        return;
    }
    if (!gFrames || gFrameCount < 2) {
        rtAlert(@"Chưa nạp .rep", @"Chưa có file replay của map này để tính độ lệch!");
        return;
    }
    gOffsetApplied = NO;
    BOOL ok = rtCalculateAndApplyOffset();
    if (ok) {
        rtAlert(@"Bù lệch thành công", [NSString stringWithFormat:@"Ô xuất phát: %d\nĐộ lệch: ΔX=%.2f, ΔY=%.2f, ΔZ=%.2f\nĐã điều chỉnh toàn bộ %u frame của Replay!", gRepStartSlot, gOffsetDelta[0], gOffsetDelta[1], gOffsetDelta[2], gFrameCount]);
    } else {
        rtAlert(@"Khớp hoàn toàn", [NSString stringWithFormat:@"Tọa độ Ô %d của Rep và Map đã khớp chính xác (lệch < 0.05m)!", gRepStartSlot]);
    }
    [self refresh];
}

- (void)tapNoRep {
    gNoReplay = gNoReplay ? NO : YES;
    rtLog("NO REPLAY changed to %d", (int)gNoReplay);
    [self refresh];
}

- (void)onSpeedChange:(UISlider *)sender {
    gSpeedMultiplier = sender.value;
    self.lblSpeed.text = [NSString stringWithFormat:@"Tốc độ: %.1fx", gSpeedMultiplier];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[UISlider class]] ||
        [touch.view isKindOfClass:[UIButton class]] ||
        [touch.view isKindOfClass:[UISegmentedControl class]]) {
        return NO;
    }
    return YES;
}

- (void)tapDownload {
    if (gDownloading) return;
    self.status.text = @"Đang quét BXH\nĐỉnh Cực Tốc...";
    [self.bDl setTitle:@"⏳ ĐANG TẢI" forState:UIControlStateNormal];

    rtDownloadAllPeakSpeedReplays(^(int done, int total, NSString *sub) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.status.text = [NSString stringWithFormat:@"Tải: %d/%d\n(%@)", done, total, sub];
        });
    }, ^(int totalDownloaded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.bDl setTitle:@"⬇ TẢI .REP" forState:UIControlStateNormal];
            self.status.text = [NSString stringWithFormat:@"Đã tải %d rep!\nMap %d sẵn sàng", totalDownloaded, gMapId];
            if (gAutoArmed) {
                rtLoadRecord();
            }
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

- (void)tapFixMap {
    if (gMapId <= 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sửa Lỗi Map"
                                                                       message:@"Chưa vào trận! Vui lòng nhập Map ID cần xóa và tải lại (ví dụ: 46, 105):"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"Map ID (số)";
            textField.keyboardType = UIKeyboardTypeNumberPad;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Tải lại (Yes)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            UITextField *tf = alert.textFields.firstObject;
            int mid = tf.text.intValue;
            if (mid > 0) {
                [self doFixMap:mid];
            }
        }]];
        UIViewController *vc = rtTopVC();
        if (vc) [vc presentViewController:alert animated:YES completion:nil];
        return;
    }

    int curMap = gMapId;
    NSString *msg = [NSString stringWithFormat:@"Bạn có chắc chắn muốn xóa file .rep cũ của Map %d và tải lại bản kỷ lục mới nhất từ BXH không?", curMap];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sửa Lỗi Map"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đồng ý (Yes)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self doFixMap:curMap];
    }]];

    UIViewController *vc = rtTopVC();
    if (vc) [vc presentViewController:alert animated:YES completion:nil];
}

- (void)doFixMap:(int)mapId {
    self.status.text = [NSString stringWithFormat:@"Đang xóa & tải lại\nMap %d...", mapId];
    rtRedownloadRepForMap(mapId, ^(BOOL success, NSString *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                rtAlert(@"Sửa lỗi Map", [NSString stringWithFormat:@"Đã xóa file cũ và nạp lại file .rep mới của Map %d thành công!", mapId]);
                if (gAutoArmed) {
                    rtLoadRecord();
                }
            } else {
                rtAlert(@"Lỗi tải lại", msg ?: @"Không tìm thấy video kỷ lục của map này trên BXH!");
            }
            [self refresh];
        });
    });
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

    // No Replay Hooks (chặn game tự động mở Replay & Bóng khi tải .rep)
    orig_MatchVideoMdl_StartEnterGame = (int (*)(void *, int, void *, void *, const void *))
        rtHookMethod("", "MatchVideoMdl", "StartEnterGame", 3, (void *)hook_MatchVideoMdl_StartEnterGame);
    orig_MatchVideoMdl_ChallengeShadow_info = (int (*)(void *, void *, uint64_t, const void *))
        rtHookMethod("", "MatchVideoMdl", "ChallengeShadow", 2, (void *)hook_MatchVideoMdl_ChallengeShadow_info);
    orig_MatchVideoMdl_ChallengeShadow_mark = (int (*)(void *, int64_t, uint64_t, const void *))
        rtHookMethod("", "MatchVideoMdl", "ChallengeShadow", 2, (void *)hook_MatchVideoMdl_ChallengeShadow_mark);
    orig_MatchVideoMdl_ReplayVideo_bytes = (int (*)(void *, void *, uint64_t, void *, void *, const void *))
        rtHookMethod("", "MatchVideoMdl", "ReplayVideo", 4, (void *)hook_MatchVideoMdl_ReplayVideo_bytes);
    orig_MatchVideoMdl_ReplayVideo_mark = (int (*)(void *, int64_t, uint64_t, const void *))
        rtHookMethod("", "MatchVideoMdl", "ReplayVideo", 2, (void *)hook_MatchVideoMdl_ReplayVideo_mark);
    orig_MatchVideoMdl_ReplayTeachingVideo = (int (*)(void *, int, void *, bool, const void *))
        rtHookMethod("", "MatchVideoMdl", "ReplayTeachingVideo", 3, (void *)hook_MatchVideoMdl_ReplayTeachingVideo);

// Anti-AFK Hooks (4 tầng chống treo máy & chống phạt)
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

    // Anti-Speed-Report Hooks (chống phát hiện tốc độ / fast frame)
    orig_SdcVehicleVel_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleVel", "Update", 1, (void *)hook_SdcVehicleVel_Update);
    orig_CPR_FillVehicleVelData = (void (*)(void *, void **, const void *))
        rtHookMethod("", "CPR_STPVPEndGame", "FillVehicleVelData", 1, (void *)hook_CPR_FillVehicleVelData);
    orig_CPR_ReportData = (void (*)(void *, void **, const void *))
        rtHookMethod("", "CPR_STPVPEndGame", "ReportData", 1, (void *)hook_CPR_ReportData);
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
