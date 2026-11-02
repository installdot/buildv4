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
static BOOL gRecordSelf = NO; // Tự động ghi lại hành trình người chơi lái
// Cấu trúc và bộ đệm ghi hành trình tự làm (Custom Record)
#define RC_MAX_RECORD_FRAMES 15000 // ~4 phút ở 60fps
static RCFrame *gRecordBuffer = NULL;
static uint32_t gRecordCount = 0;
static BOOL     gIsRecordingActive = NO;
static double   gRecordStartTime = 0.0;
static BOOL   gEnableOffsetFix = YES;
static BOOL   gOffsetApplied = NO;
static float  gOffsetDelta[3] = {0.f, 0.f, 0.f};
static float  gOffsetAngleDeg = 0.f;
static float  gRepOriginPos[3] = {0.f, 0.f, 0.f};
static float  gRepOriginRot[4] = {0.f, 0.f, 0.f, 1.f};
static float  gMapActualPos[3] = {0.f, 0.f, 0.f};
static int    gRepStartSlot = 0;
static int    gMapStartSlot = 0;
static void *gPlayerVehicle;
static void *gInputModule;
static int   gKeyMask;
static float gCurPlaybackSteer;
static void *gMapDataComponent = NULL;
static void *gCheckPointMgr = NULL;
static void *gCheckPointConfig = NULL;
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

// Lưu & Đọc Cấu Hình (Settings Persistence)
static NSString *rtSettingsPath(void) {
    return [rtDir() stringByAppendingPathComponent:@"settings.plist"];
}
static void rtLoadSettings(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:rtSettingsPath()];
    if (d) {
        if (d[@"autoArmed"]) gAutoArmed = [d[@"autoArmed"] boolValue];
        if (d[@"speedMultiplier"]) gSpeedMultiplier = [d[@"speedMultiplier"] floatValue];
        if (d[@"noReplay"]) gNoReplay = [d[@"noReplay"] boolValue];
        if (d[@"recordSelf"]) gRecordSelf = [d[@"recordSelf"] boolValue];
        if (d[@"enableOffsetFix"]) gEnableOffsetFix = [d[@"enableOffsetFix"] boolValue];
    }
}
static void rtSaveSettings(void) {
    NSDictionary *d = @{
        @"autoArmed": @(gAutoArmed),
        @"speedMultiplier": @(gSpeedMultiplier),
        @"noReplay": @(gNoReplay),
        @"recordSelf": @(gRecordSelf),
        @"enableOffsetFix": @(gEnableOffsetFix)
    };
    [d writeToFile:rtSettingsPath() atomically:YES];
}
static void rtStopAndSaveCustomRecord(void) {
    if (!gIsRecordingActive) return;
    gIsRecordingActive = NO;
    if (gRecordSelf && gRecordCount > 60 && gMapId > 0 && gRecordBuffer) {
        NSString *path = rtPathForTrack();
        if (path) {
            FILE *f = fopen(path.fileSystemRepresentation, "wb");
            if (f) {
                RCHeader h;
                memcpy(h.magic, "RKR3", 4);
                h.ver = 3;
                h.count = gRecordCount;
                h.trackLen = gTrackLen;
                h.mapId = gMapId;
                h.frameSize = sizeof(RCFrame);
                fwrite(&h, sizeof(RCHeader), 1, f);
                fwrite(gRecordBuffer, sizeof(RCFrame), gRecordCount, f);
                fclose(f);
                rtLog("[Record] Đã lưu record tự làm: %u frames (%.1fs) cho map %d -> %s",
                      gRecordCount, gRecordBuffer[gRecordCount - 1].t, gMapId, path.UTF8String);
            }
        }
    }
    gRecordCount = 0;
}
// Tính toán độ lệch vị trí
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
    // Ghi nhận vị trí xuất phát gốc, góc xoay và slot của rep
    if (count > 0) {
        gRepOriginPos[0] = gFrames[0].px;
        gRepOriginPos[1] = gFrames[0].py;
        gRepOriginPos[2] = gFrames[0].pz;
        gRepOriginRot[0] = gFrames[0].qx;
        gRepOriginRot[1] = gFrames[0].qy;
        gRepOriginRot[2] = gFrames[0].qz;
        gRepOriginRot[3] = gFrames[0].qw;
        gOffsetAngleDeg = 0.f;
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
    // Chỉ lưu file .rk khi người chơi bật ghi lại (gRecordSelf), không tự lưu ở mỗi trận
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
    // 1. ƯU TIÊN SỐ 1: Kiểm tra record tự làm (custom record .rk)
    NSString *customPath = rtPathForTrack();
    if (customPath && [[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
        FILE *f = fopen(customPath.fileSystemRepresentation, "rb");
        if (f) {
            RCHeader h;
            if (fread(&h, sizeof(RCHeader), 1, f) == 1 && h.count > 0 && h.count <= RC_MAX_FRAMES) {
                if (!memcmp(h.magic, "RKR3", 4) && h.frameSize == sizeof(RCFrame)) {
                    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * h.count);
                    if (gFrames) {
                        gFrameCount = (uint32_t)fread(gFrames, sizeof(RCFrame), h.count, f);
                        fclose(f);
                        rtLog("[Priority] ĐÃ NẠP RECORD TỰ LÀM: %u frames cho map %d!", gFrameCount, gMapId);
                        return YES;
                    }
                }
            }
            fclose(f);
        }
    }
    // 2. Nếu không có record tự làm: Quét tìm file .rep từ TempMatchVideos
    rtLog("Searching TempMatchVideos for map %d .rep file...", gMapId);
    NSString *rep = rtFindRepFile(gMapId);
    if (rep && rtLoadRepFromDisk(rep)) {
        if (gFrameCount > 0) {
            rtLog("LOADED %u frames from .rep file!", gFrameCount);
            return YES;
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
static BOOL rtCalculateStartSlotPosAndDirInMap(int slotIndex, float *outPos, float *outDir) {
    if (!rtPtrOk(gCheckPointConfig) || !outPos) return NO;
    int cpSize = *(int *)((char *)gCheckPointConfig + 0x30); // CheckPointDataListSize
    void *cpArr = *(void **)((char *)gCheckPointConfig + 0x38); // CheckPointDataList
    if (!rtPtrOk(cpArr)) return NO;
    int cpCap = *(int *)((char *)cpArr + 0x18);
    if (cpCap <= 0 || cpSize <= 0) return NO;
    int startIndex = *(int *)((char *)gCheckPointConfig + 0x18); // RaceStartCheckPointIndex
    if (startIndex < 0 || startIndex >= cpCap || startIndex >= cpSize) startIndex = 0;
    if (startIndex >= cpCap) return NO;
    void **cpItems = (void **)((char *)cpArr + 0x20);
    if (!cpItems) return NO;
    void *startCP = cpItems[startIndex];
    if (!rtPtrOk(startCP)) return NO;
    void *posObj   = *(void **)((char *)startCP + 0x28); // TDR_Vector3 Position
    void *fwdObj   = *(void **)((char *)startCP + 0x30); // TDR_Vector3 Forward
    void *leftObj  = *(void **)((char *)startCP + 0x38); // TDR_Vector3 LeftPoint
    void *rightObj = *(void **)((char *)startCP + 0x40); // TDR_Vector3 RightPoint
    if (!rtPtrOk(posObj) || !rtPtrOk(fwdObj)) return NO;
    float sx = *(float *)((char *)posObj + 0x10);
    float sy = *(float *)((char *)posObj + 0x14);
    float sz = *(float *)((char *)posObj + 0x18);
    float dx = *(float *)((char *)fwdObj + 0x10);
    float dy = *(float *)((char *)fwdObj + 0x14);
    float dz = *(float *)((char *)fwdObj + 0x18);
    if (fabsf(sx) < 1e-3f && fabsf(sz) < 1e-3f) return NO;
    float flen = sqrtf(dx * dx + dy * dy + dz * dz);
    float fx = (flen > 1e-4f) ? dx / flen : 0.f;
    float fy = (flen > 1e-4f) ? dy / flen : 0.f;
    float fz = (flen > 1e-4f) ? dz / flen : 1.f;
    if (outDir) {
        outDir[0] = fx;
        outDir[1] = fy;
        outDir[2] = fz;
    }
    // Vector Right từ RightPoint - LeftPoint hoặc Cross(Forward, Up)
    float rx = 0.f, ry = 0.f, rz = 0.f;
    if (rtPtrOk(rightObj) && rtPtrOk(leftObj)) {
        rx = *(float *)((char *)rightObj + 0x10) - *(float *)((char *)leftObj + 0x10);
        ry = *(float *)((char *)rightObj + 0x14) - *(float *)((char *)leftObj + 0x14);
        rz = *(float *)((char *)rightObj + 0x18) - *(float *)((char *)leftObj + 0x18);
    }
    float rlen = sqrtf(rx * rx + ry * ry + rz * rz);
    if (rlen > 1e-2f) {
        rx /= rlen; ry /= rlen; rz /= rlen;
    } else {
        rx = -fz; ry = 0.f; rz = fx;
        rlen = sqrtf(rx * rx + rz * rz);
        if (rlen > 1e-4f) { rx /= rlen; rz /= rlen; }
    }
    float gapX = 4.5f;
    int carsPerRow = 6;
    int slot = (slotIndex >= 0 && slotIndex <= 5) ? slotIndex : 0;
    float lateralMult = ((float)slot - 0.5f * (float)(carsPerRow - 1)) * gapX;
    outPos[0] = sx + (rx * lateralMult);
    outPos[1] = sy + (ry * lateralMult);
    outPos[2] = sz + (rz * lateralMult);
    return YES;
}
static BOOL rtCalculateAndApplyOffset(void) {
    if (!gEnableOffsetFix) return NO;
    if (!gFrames || gFrameCount < 2) return NO;
    if (gOffsetApplied) return YES;
    // 1. TÍNH TỌA ĐỘ VÀ HƯỚNG VỊ TRÍ XUẤT PHÁT CỦA MAP (TỪ GCHECKPOINTCONFIG HỢP LỆ)
    float mapStartDir[3] = {0.f, 0.f, 1.f};
    if (!rtCalculateStartSlotPosAndDirInMap(gRepStartSlot, gMapActualPos, mapStartDir)) {
        rtLog("[Offset] Map start position not ready yet (gCheckPointConfig=%p)", gCheckPointConfig);
        return NO;
    }
    // 2. TÍNH VECTOR VÀ GÓC HƯỚNG CỦA MAP
    float fMapLen = sqrtf(mapStartDir[0] * mapStartDir[0] + mapStartDir[2] * mapStartDir[2]);
    float fMapX = (fMapLen > 1e-4f) ? (mapStartDir[0] / fMapLen) : 0.f;
    float fMapZ = (fMapLen > 1e-4f) ? (mapStartDir[2] / fMapLen) : 1.f;
    float thetaMap = atan2f(fMapX, fMapZ);
    // 3. TÍNH VECTOR VÀ GÓC HƯỚNG CỦA REPLAY TẠI FRAME 0
    float rqx = gRepOriginRot[0], rqy = gRepOriginRot[1], rqz = gRepOriginRot[2], rqw = gRepOriginRot[3];
    float fRepX = 2.0f * (rqx * rqz + rqw * rqy);
    float fRepZ = 1.0f - 2.0f * (rqx * rqx + rqy * rqy);
    float fRepLen = sqrtf(fRepX * fRepX + fRepZ * fRepZ);
    if (fRepLen > 1e-4f) { fRepX /= fRepLen; fRepZ /= fRepLen; } else { fRepX = 0.f; fRepZ = 1.f; }
    float thetaRep = atan2f(fRepX, fRepZ);
    // 4. TÍNH ĐỘ LỆCH GÓC XOAY DELTA THETA
    float deltaTheta = thetaMap - thetaRep;
    while (deltaTheta > (float)M_PI)  deltaTheta -= 2.0f * (float)M_PI;
    while (deltaTheta < -(float)M_PI) deltaTheta += 2.0f * (float)M_PI;
    gOffsetAngleDeg = deltaTheta * (180.0f / (float)M_PI);
    // 5. TÍNH ĐỘ LỆCH DỊCH CHUYỂN TỌA ĐỘ
    float dx = gMapActualPos[0] - gRepOriginPos[0];
    float dy = gMapActualPos[1] - gRepOriginPos[1];
    float dz = gMapActualPos[2] - gRepOriginPos[2];
    float dist = sqrtf(dx * dx + dy * dy + dz * dz);
    gOffsetDelta[0] = dx;
    gOffsetDelta[1] = dy;
    gOffsetDelta[2] = dz;
    rtLog("[Offset] AUTO CALC: RepSlot=%d Rep0=(%.2f, %.2f, %.2f) MapSlot%d=(%.2f, %.2f, %.2f) -> DeltaPos=(%.2f, %.2f, %.2f, dist=%.2fm) DeltaAngle=%.1f°",
          gRepStartSlot, gRepOriginPos[0], gRepOriginPos[1], gRepOriginPos[2],
          gRepStartSlot, gMapActualPos[0], gMapActualPos[1], gMapActualPos[2],
          dx, dy, dz, dist, gOffsetAngleDeg);
    // 6. ÁP DỤNG BIẾN ĐỔI RIGID BODY
    if (dist > 0.05f || fabsf(deltaTheta) > 0.008f) {
        float cosA = cosf(deltaTheta);
        float sinA = sinf(deltaTheta);
        float halfA = deltaTheta * 0.5f;
        float dQy = sinf(halfA);
        float dQw = cosf(halfA);
        for (uint32_t i = 0; i < gFrameCount; i++) {
            float relX = gFrames[i].px - gRepOriginPos[0];
            float relY = gFrames[i].py - gRepOriginPos[1];
            float relZ = gFrames[i].pz - gRepOriginPos[2];
            float rotRelX = relX * cosA + relZ * sinA;
            float rotRelY = relY;
            float rotRelZ = -relX * sinA + relZ * cosA;
            gFrames[i].px = gMapActualPos[0] + rotRelX;
            gFrames[i].py = gMapActualPos[1] + rotRelY;
            gFrames[i].pz = gMapActualPos[2] + rotRelZ;
            float qx = gFrames[i].qx, qy = gFrames[i].qy, qz = gFrames[i].qz, qw = gFrames[i].qw;
            gFrames[i].qx = dQw * qx + dQy * qz;
            gFrames[i].qy = dQw * qy + dQy * qw;
            gFrames[i].qz = dQw * qz - dQy * qx;
            gFrames[i].qw = dQw * qw - dQy * qy;
            float vx = gFrames[i].vx, vz = gFrames[i].vz;
            gFrames[i].vx = vx * cosA + vz * sinA;
            gFrames[i].vz = -vx * sinA + vz * cosA;
        }
        gOffsetApplied = YES;
        rtLog("[Offset] RIGID BODY CALIBRATED all %u frames successfully!", gFrameCount);
        return YES;
    }
    gOffsetApplied = YES;
    return NO;
}

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
@class RCPanel;
@interface RCPanel : NSObject <UIGestureRecognizerDelegate>
- (void)show;
- (void)refresh;
- (void)showPlayFrameHud:(BOOL)show;
- (void)updatePlayFrameHud:(uint32_t)cur count:(uint32_t)total time:(float)t;
@end
static RCPanel *gPanel;

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
        if (gPanel) [gPanel showPlayFrameHud:NO];
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
        if (rtPtrOk(ent) && rtPtrOk(*(void **)ent)) {
            if (!isnan(tx) && !isnan(ty) && !isnan(tz) &&
                !isnan(qx) && !isnan(qy) && !isnan(qz) && !isnan(qw)) {
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
    if (gPanel) {
        [gPanel updatePlayFrameHud:lo count:gFrameCount time:t];
    }
}
#pragma mark - UI Interface
@interface RCPassWindow : UIWindow
@property (nonatomic, strong) UITextField *secureTextField;
@property (nonatomic, strong) UIView *secureContainer;
@property (nonatomic, weak) UIView *bubble;
@property (nonatomic, weak) UIView *menu;
@property (nonatomic, weak) UIView *hudPlayFrame;
@end
@implementation RCPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    // 0. Nhận diện tương tác nếu có Popup Alert hệ thống
    if (self.rootViewController && self.rootViewController.presentedViewController) {
        return [super hitTest:point withEvent:event];
    }
    // 1. Chạm vào menu rời PlayFrame (+0.1 / -0.1)
    if (self.hudPlayFrame && !self.hudPlayFrame.hidden && self.hudPlayFrame.userInteractionEnabled) {
        CGPoint p = [self convertPoint:point toView:self.hudPlayFrame];
        if ([self.hudPlayFrame pointInside:p withEvent:event]) {
            UIView *hit = [self.hudPlayFrame hitTest:p withEvent:event];
            return hit ?: self.hudPlayFrame;
        }
    }
    // 2. Chạm vào bong bóng nổi
    if (self.bubble && !self.bubble.hidden && self.bubble.userInteractionEnabled) {
        CGPoint p = [self convertPoint:point toView:self.bubble];
        if ([self.bubble pointInside:p withEvent:event]) {
            UIView *hit = [self.bubble hitTest:p withEvent:event];
            return hit ?: self.bubble;
        }
    }
    // 3. Chạm vào menu chính
    if (self.menu && !self.menu.hidden && self.menu.userInteractionEnabled) {
        CGPoint p = [self convertPoint:point toView:self.menu];
        if ([self.menu pointInside:p withEvent:event]) {
            UIView *hit = [self.menu hitTest:p withEvent:event];
            return hit ?: self.menu;
        }
    }
    // 4. Xuyên thấu toàn bộ các vùng còn lại ra ngoài game
    return nil;
}
@end
@interface RCPanel ()
@property (nonatomic, strong) RCPassWindow *win;
@property (nonatomic, strong) UIButton *bubble;
@property (nonatomic, strong) UIView *menu;
// Menu rời PlayFrame hiện tại (+0.1 và -0.1)
@property (nonatomic, strong) UIView *hudPlayFrame;
@property (nonatomic, strong) UILabel *lblFrameInfo;
@property (nonatomic, strong) UIButton *btnMinusSpeed;
@property (nonatomic, strong) UIButton *btnPlusSpeed;
// Các nút điều khiển chính (Không icon / emoji)
@property (nonatomic, strong) UIButton *bDl;
@property (nonatomic, strong) UIButton *bNoRep;
@property (nonatomic, strong) UIButton *bAuto;
@property (nonatomic, strong) UIButton *bRecord;
@property (nonatomic, strong) UIButton *bFixMap;
@property (nonatomic, strong) UISlider *sliderSpeed;
@property (nonatomic, strong) UILabel *lblSpeed;
@property (nonatomic, strong) UILabel *status;
- (void)show;
- (void)refresh;
- (void)showPlayFrameHud:(BOOL)show;
- (void)updatePlayFrameHud:(uint32_t)cur count:(uint32_t)total time:(float)t;
@end
static UIViewController *rtTopVC(void) {
    if (gPanel && gPanel.win && gPanel.win.rootViewController) {
        UIViewController *vc = gPanel.win.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        return vc;
    }
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
static void rtAlert(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = rtTopVC();
        if (!top) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:a animated:YES completion:nil];
    });
}
@implementation RCPanel
- (UIButton *)mk:(NSString *)t sel:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithRed:0.08 green:0.22 blue:0.35 alpha:0.95];
    b.layer.cornerRadius = 7;
    b.layer.borderWidth = 0.8;
    b.layer.borderColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.9 alpha:0.4].CGColor;
    b.clipsToBounds = YES;
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.win) return;
        CGRect scr = [UIScreen mainScreen].bounds;
        RCPassWindow *win = [[RCPassWindow alloc] initWithFrame:scr];
        win.backgroundColor = [UIColor clearColor];
        win.windowLevel = UIWindowLevelStatusBar + 100.0;
        win.userInteractionEnabled = YES;
        win.rootViewController = [UIViewController new];
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    win.windowScene = scene;
                    break;
                }
            }
            if (!win.windowScene) {
                for (UIWindow *w in UIApplication.sharedApplication.windows) {
                    if ([w isKindOfClass:[RCPassWindow class]]) continue;
                    if (w.windowScene) { win.windowScene = w.windowScene; break; }
                }
            }
        }
        self.win = win;
        // BẢO MẬT CHỐNG QUAY MÀN HÌNH / CHỤP MÀN HÌNH (Secure Canvas Trick)
        // Khi thêm view con vào canvas của UITextField có secureTextEntry = YES,
        // hệ thống iOS sẽ tự động làm trống / tàng hình view đó trên ảnh chụp màn hình và video quay màn hình!
        UITextField *secField = [[UITextField alloc] initWithFrame:scr];
        secField.secureTextEntry = YES;
        secField.userInteractionEnabled = NO;
        [win.rootViewController.view addSubview:secField];
        win.secureTextField = secField;
        UIView *secCanvas = secField.subviews.firstObject;
        if (secCanvas) {
            secCanvas.userInteractionEnabled = YES;
            win.secureContainer = secCanvas;
        } else {
            win.secureContainer = win.rootViewController.view;
        }
        UIView *container = win.secureContainer;
        // 1. Bong bóng nổi (Floating Bubble 44x44, không có icon/emoji)
        UIButton *bubble = [UIButton buttonWithType:UIButtonTypeCustom];
        bubble.frame = CGRectMake(scr.size.width - 54, scr.size.height * 0.35, 44, 44);
        bubble.backgroundColor = [UIColor colorWithRed:0.06 green:0.12 blue:0.18 alpha:0.95];
        bubble.layer.cornerRadius = 22;
        bubble.layer.borderWidth = 1.5;
        bubble.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.95].CGColor;
        bubble.clipsToBounds = YES;
        [bubble setTitle:@"RK" forState:UIControlStateNormal];
        bubble.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [bubble setTitleColor:[UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
        [bubble addTarget:self action:@selector(onBubbleTap) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:bubble];
        self.bubble = bubble;
        win.bubble = bubble;
        UIPanGestureRecognizer *panBubble = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
        panBubble.cancelsTouchesInView = NO;
        [bubble addGestureRecognizer:panBubble];
        // 2. Menu chính (Gọn đẹp, 205x285, không tab, không icon)
        UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(scr.size.width - 215, scr.size.height * 0.16, 205, 255)];
        menu.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.96];
        menu.layer.cornerRadius = 12;
        menu.layer.borderWidth = 1.2;
        menu.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.75].CGColor;
        menu.clipsToBounds = YES;
        menu.hidden = YES;
        [container addSubview:menu];
        self.menu = menu;
        win.menu = menu;
        UIPanGestureRecognizer *panMenu = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanMenu:)];
        panMenu.delegate = self;
        [menu addGestureRecognizer:panMenu];
        // Tiêu đề & Nút đóng
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, 140, 20)];
        t.text = @"RaceKit Pro";
        t.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
        t.font = [UIFont boldSystemFontOfSize:13];
        [menu addSubview:t];
        UIButton *bClose = [UIButton buttonWithType:UIButtonTypeSystem];
        bClose.frame = CGRectMake(175, 4, 24, 24);
        [bClose setTitle:@"✕" forState:UIControlStateNormal];
        [bClose setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
        bClose.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [bClose addTarget:self action:@selector(onToggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:bClose];
        // Danh sách các nút chức năng chính (Không icon / emoji)
        CGFloat startY = 30.0f;
        CGFloat btnH = 26.0f;
        CGFloat gap = 5.0f;
        self.bDl = [self mk:@"Tải Replay" sel:@selector(tapDownload)];
        self.bDl.frame = CGRectMake(10, startY, 185, btnH);
        [menu addSubview:self.bDl];
        startY += btnH + gap;
        self.bNoRep = [self mk:@"Chặn Replay: Bật" sel:@selector(tapNoRep)];
        self.bNoRep.frame = CGRectMake(10, startY, 185, btnH);
        [menu addSubview:self.bNoRep];
        startY += btnH + gap;
        self.bAuto = [self mk:@"Tự Động: Bật" sel:@selector(tapAuto)];
        self.bAuto.frame = CGRectMake(10, startY, 185, btnH);
        [menu addSubview:self.bAuto];
        startY += btnH + gap;
        self.bRecord = [self mk:@"Ghi Lại: Tắt" sel:@selector(tapRecordSelf)];
        self.bRecord.frame = CGRectMake(10, startY, 185, btnH);
        [menu addSubview:self.bRecord];
        startY += btnH + gap;
        self.bFixMap = [self mk:@"Báo Lỗi Map" sel:@selector(tapFixMap)];
        self.bFixMap.frame = CGRectMake(10, startY, 185, btnH);
        self.bFixMap.backgroundColor = [UIColor colorWithRed:0.65 green:0.18 blue:0.16 alpha:0.92];
        [menu addSubview:self.bFixMap];
        startY += btnH + 6.0f;
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(10, startY, 185, 20)];
        sl.minimumValue = 1.0f;
        sl.maximumValue = 5.0f;
        sl.value = gSpeedMultiplier;
        sl.continuous = YES;
        [sl addTarget:self action:@selector(onSpeedChange:) forControlEvents:UIControlEventValueChanged];
        [menu addSubview:sl];
        self.sliderSpeed = sl;
        startY += 20.0f;
        UILabel *ls = [[UILabel alloc] initWithFrame:CGRectMake(10, startY, 185, 14)];
        ls.font = [UIFont boldSystemFontOfSize:10];
        ls.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.9];
        ls.textAlignment = NSTextAlignmentCenter;
        ls.text = [NSString stringWithFormat:@"Tốc độ: %.1fx", gSpeedMultiplier];
        [menu addSubview:ls];
        self.lblSpeed = ls;
        startY += 16.0f;
        self.status = [[UILabel alloc] initWithFrame:CGRectMake(10, startY, 185, 34)];
        self.status.numberOfLines = 2;
        self.status.font = [UIFont systemFontOfSize:9];
        self.status.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        [menu addSubview:self.status];
        // 3. Menu rời PlayFrame (+0.1 và -0.1) khi bật Auto Play
        UIView *hud = [[UIView alloc] initWithFrame:CGRectMake(scr.size.width * 0.5 - 90, 18, 180, 34)];
        hud.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
        hud.layer.cornerRadius = 17;
        hud.layer.borderWidth = 1.0;
        hud.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.85].CGColor;
        hud.clipsToBounds = YES;
        hud.hidden = NO; // Luôn luôn hiện theo yêu cầu
        [container addSubview:hud];
        self.hudPlayFrame = hud;
        win.hudPlayFrame = hud;
        UIPanGestureRecognizer *panHud = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanHud:)];
        [hud addGestureRecognizer:panHud];
        UIButton *bMinus = [UIButton buttonWithType:UIButtonTypeCustom];
        bMinus.frame = CGRectMake(4, 4, 38, 26);
        [bMinus setTitle:@"-0.1" forState:UIControlStateNormal];
        bMinus.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [bMinus setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        bMinus.backgroundColor = [UIColor colorWithRed:0.12 green:0.24 blue:0.36 alpha:0.95];
        bMinus.layer.cornerRadius = 6;
        [bMinus addTarget:self action:@selector(onMinusSpeedTap) forControlEvents:UIControlEventTouchUpInside];
        [hud addSubview:bMinus];
        self.btnMinusSpeed = bMinus;
        UILabel *lblF = [[UILabel alloc] initWithFrame:CGRectMake(46, 4, 88, 26)];
        lblF.font = [UIFont boldSystemFontOfSize:10];
        lblF.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
        lblF.textAlignment = NSTextAlignmentCenter;
        lblF.text = [NSString stringWithFormat:@"%.1fx | 0/0", gSpeedMultiplier];
        [hud addSubview:lblF];
        self.lblFrameInfo = lblF;
        UIButton *bPlus = [UIButton buttonWithType:UIButtonTypeCustom];
        bPlus.frame = CGRectMake(138, 4, 38, 26);
        [bPlus setTitle:@"+0.1" forState:UIControlStateNormal];
        bPlus.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [bPlus setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        bPlus.backgroundColor = [UIColor colorWithRed:0.12 green:0.24 blue:0.36 alpha:0.95];
        bPlus.layer.cornerRadius = 6;
        [bPlus addTarget:self action:@selector(onPlusSpeedTap) forControlEvents:UIControlEventTouchUpInside];
        [hud addSubview:bPlus];
        self.btnPlusSpeed = bPlus;
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
static uint32_t sCurrentPlayFrame = 0;
- (void)onMinusSpeedTap {
    gSpeedMultiplier = roundf((gSpeedMultiplier - 0.1f) * 10.0f) / 10.0f;
    if (gSpeedMultiplier < 0.2f) gSpeedMultiplier = 0.2f;
    [self refreshSpeedUI];
    rtSaveSettings();
}
- (void)onPlusSpeedTap {
    gSpeedMultiplier = roundf((gSpeedMultiplier + 0.1f) * 10.0f) / 10.0f;
    if (gSpeedMultiplier > 5.0f) gSpeedMultiplier = 5.0f;
    [self refreshSpeedUI];
    rtSaveSettings();
}
- (void)refreshSpeedUI {
    if (self.sliderSpeed) self.sliderSpeed.value = gSpeedMultiplier;
    if (self.lblSpeed) self.lblSpeed.text = [NSString stringWithFormat:@"Tốc độ: %.1fx", gSpeedMultiplier];
    if (self.lblFrameInfo) {
        self.lblFrameInfo.text = [NSString stringWithFormat:@"%.1fx | %u/%u", gSpeedMultiplier, sCurrentPlayFrame, gFrameCount];
    }
}
- (void)showPlayFrameHud:(BOOL)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hudPlayFrame) {
            self.hudPlayFrame.hidden = NO; // Luôn luôn hiện
            [self refreshSpeedUI];
        }
    });
}
- (void)updatePlayFrameHud:(uint32_t)cur count:(uint32_t)total time:(float)t {
    sCurrentPlayFrame = cur;
    if (self.lblFrameInfo) {
        self.lblFrameInfo.text = [NSString stringWithFormat:@"%.1fx | %u/%u", gSpeedMultiplier, cur, total];
    }
}
- (void)onPanHud:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.win];
    self.hudPlayFrame.center = CGPointMake(self.hudPlayFrame.center.x + trans.x,
                                           self.hudPlayFrame.center.y + trans.y);
    [p setTranslation:CGPointZero inView:self.win];
}
- (void)refresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gNoReplay) {
            self.bNoRep.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95];
            [self.bNoRep setTitle:@"Chặn Replay: Bật" forState:UIControlStateNormal];
        } else {
            self.bNoRep.backgroundColor = [UIColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:0.95];
            [self.bNoRep setTitle:@"Chặn Replay: Tắt" forState:UIControlStateNormal];
        }
        if (gAutoArmed) {
            self.bAuto.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95];
            [self.bAuto setTitle:@"Tự Động: Bật" forState:UIControlStateNormal];
        } else {
            self.bAuto.backgroundColor = [UIColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:0.95];
            [self.bAuto setTitle:@"Tự Động: Tắt" forState:UIControlStateNormal];
        }
        if (gRecordSelf) {
            self.bRecord.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95];
            [self.bRecord setTitle:@"Ghi Lại: Bật" forState:UIControlStateNormal];
        } else {
            self.bRecord.backgroundColor = [UIColor colorWithRed:0.35 green:0.35 blue:0.35 alpha:0.95];
            [self.bRecord setTitle:@"Ghi Lại: Tắt" forState:UIControlStateNormal];
        }
        self.sliderSpeed.value = gSpeedMultiplier;
        self.lblSpeed.text = [NSString stringWithFormat:@"Tốc độ: %.1fx", gSpeedMultiplier];
        NSString *recType = @"Chưa có";
        NSString *cPath = rtPathForTrack();
        if (cPath && [[NSFileManager defaultManager] fileExistsAtPath:cPath]) {
            recType = @"Record tự làm (Ưu tiên)";
        } else {
            NSString *rPath = rtFindRepFile(gMapId);
            if (rPath) recType = @"File .rep server";
        }
        self.status.text = [NSString stringWithFormat:@"Map %d | Slot %d\nNguồn: %@",
                            gMapId, gMapStartSlot, recType];
    });
}
- (void)onBubbleTap {
    [self onToggleMenu];
}
- (void)onToggleMenu {
    self.menu.hidden = !self.menu.hidden;
    if (!self.menu.hidden) [self refresh];
}
- (void)onPanBubble:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.win];
    self.bubble.center = CGPointMake(self.bubble.center.x + trans.x, self.bubble.center.y + trans.y);
    [p setTranslation:CGPointZero inView:self.win];
}
- (void)onPanMenu:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.win];
    self.menu.center = CGPointMake(self.menu.center.x + trans.x, self.menu.center.y + trans.y);
    [p setTranslation:CGPointZero inView:self.win];
}
- (void)tapNoRep {
    gNoReplay = !gNoReplay;
    rtSaveSettings();
    [self refresh];
}
- (void)tapAuto {
    gAutoArmed = !gAutoArmed;
    if (!gAutoArmed) {
        gPlaying = NO;
        rtWriteKeyFlags(0);
        [self showPlayFrameHud:NO];
    }
    rtSaveSettings();
    [self refresh];
}
- (void)tapRecordSelf {
    gRecordSelf = !gRecordSelf;
    if (!gRecordSelf) {
        rtStopAndSaveCustomRecord();
    }
    rtSaveSettings();
    [self refresh];
}
- (void)onSpeedChange:(UISlider *)sl {
    gSpeedMultiplier = roundf(sl.value * 10.0f) / 10.0f;
    [self refreshSpeedUI];
    rtSaveSettings();
}
- (void)tapDownload {
    self.status.text = @"Đang tải replay...";
    rtDownloadAllPeakSpeedReplays(^(int done, int total, NSString *sub) {
        self.status.text = [NSString stringWithFormat:@"Đang tải: %d/%d\n%@", done, total, sub ?: @""];
    }, ^(int totalDownloaded) {
        self.status.text = [NSString stringWithFormat:@"Đã tải xong %d rep!", totalDownloaded];
        [self refresh];
    });
}
- (void)tapFixMap {
    if (gMapId <= 0) {
        rtAlert(@"Báo lỗi Map", @"Chưa vào map! Vui lòng bấm khi đang ở trong trận.");
        return;
    }
    int mapId = gMapId;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Báo lỗi Map"
                                                                   message:[NSString stringWithFormat:@"Xóa file replay cũ của Map %d và tải lại bản chuẩn?", mapId]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tải Lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        self.status.text = @"Đang tải lại rep...";
        rtRedownloadRepForMap(mapId, ^(BOOL success, NSString *msg) {
            self.status.text = msg;
            rtAlert(@"Báo lỗi Map", msg);
            [self refresh];
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [rtTopVC() presentViewController:alert animated:YES completion:nil];
}
@end

#pragma mark - Game & Anti-Cheat Hooks

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

// Anti-AFK Hooks
static void   (*orig_SdcVehicleInput_Update)(void *, float, const void *);
static void   (*orig_SdcPlayerInput_Update)(void *, float, const void *);
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
    if (gPlaying) {
        // Luôn giả lập phím điều khiển đang được thao tác tích cực
        if (keyType == 1 || keyType == 2 || keyType == 5 || keyType == 8) {
            static int sFakeCounter = 0;
            if (((sFakeCounter++) % 8) < 5) return TRUE;
        }
        if (keyType > 0 && keyType < 18) {
            if ((gKeyMask >> keyType) & 1) return TRUE;
        }
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

    // Bắt đầu ghi lại hành trình người chơi lái nếu bật Record
    if (gRecordSelf && gMapId > 0 && !gPlaying) {
        if (!gRecordBuffer) {
            gRecordBuffer = (RCFrame *)malloc(sizeof(RCFrame) * RC_MAX_RECORD_FRAMES);
        }
        gRecordCount = 0;
        gIsRecordingActive = YES;
        gRecordStartTime = rtNow();
        rtLog("[Record] Bắt đầu ghi hành trình cho map %d", gMapId);
    }

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
    } else {
        gPlaying = NO;
    }
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
    rtLog("FINISH reached: Stopping Auto Play & Stopping Record");
    gPlaying = NO;
    rtWriteKeyFlags(0);
    if (gIsRecordingActive) {
        rtStopAndSaveCustomRecord();
    }
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
    if (gIsRecordingActive) {
        rtStopAndSaveCustomRecord();
    }
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, crc, reset, m);
    gMapId = rtPtrOk(self) ? *(int *)((char *)self + 0x40) : 0;
    if (gMapId <= 0 && rtPtrOk(config)) {
        gMapId = *(int *)((char *)config + 0x14); // MapId is at offset 0x14
    }
    gTrackLen = 0.f;

    gCheckPointMgr = self;
    gCheckPointConfig = config;
    gOffsetApplied = NO;
    memset(gOffsetDelta, 0, sizeof(gOffsetDelta));
    memset(gMapActualPos, 0, sizeof(gMapActualPos));

    rtLog("MAP resolved from CheckPointMgr self=%p config=%p mapId=%d", self, config, gMapId);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gAutoArmed) {
            rtLoadRecord();
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

// No Replay Hooks
static int hook_MatchVideoMdl_StartEnterGame(void *self, int type, void *v1, void *v2, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted StartEnterGame");
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động vào trận.");
        return 0;
    }
    return orig_MatchVideoMdl_StartEnterGame ? orig_MatchVideoMdl_StartEnterGame(self, type, v1, v2, m) : 0;
}

static int hook_MatchVideoMdl_ChallengeShadow_info(void *self, void *info, uint64_t uid, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ChallengeShadow(info)");
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động vào trận bóng.");
        return 0;
    }
    return orig_MatchVideoMdl_ChallengeShadow_info ? orig_MatchVideoMdl_ChallengeShadow_info(self, info, uid, m) : 0;
}

static int hook_MatchVideoMdl_ChallengeShadow_mark(void *self, int64_t mark, uint64_t uid, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ChallengeShadow(mark)");
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động vào trận bóng.");
        return 0;
    }
    return orig_MatchVideoMdl_ChallengeShadow_mark ? orig_MatchVideoMdl_ChallengeShadow_mark(self, mark, uid, m) : 0;
}

static int hook_MatchVideoMdl_ReplayVideo_bytes(void *self, void *videoBytes, uint64_t uid, void *name, void *icon, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ReplayVideo(bytes)");
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động mở Replay.");
        return 0;
    }
    return orig_MatchVideoMdl_ReplayVideo_bytes ? orig_MatchVideoMdl_ReplayVideo_bytes(self, videoBytes, uid, name, icon, m) : 0;
}

static int hook_MatchVideoMdl_ReplayVideo_mark(void *self, int64_t mark, uint64_t uid, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ReplayVideo(mark=%lld)", (long long)mark);
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động mở Replay.");
        return 0;
    }
    return orig_MatchVideoMdl_ReplayVideo_mark ? orig_MatchVideoMdl_ReplayVideo_mark(self, mark, uid, m) : 0;
}

static int hook_MatchVideoMdl_ReplayTeachingVideo(void *self, int videoId, void *url, bool uncomp, const void *m) {
    if (gNoReplay) {
        rtLog("NO REPLAY: Intercepted ReplayTeachingVideo(id=%d)", videoId);
        rtAlert(@"No Replay", @"Đã tải xong file .rep!\nĐã chặn tự động mở Replay.");
        return 0;
    }
    return orig_MatchVideoMdl_ReplayTeachingVideo ? orig_MatchVideoMdl_ReplayTeachingVideo(self, videoId, url, uncomp, m) : 0;
}

// Anti-AFK Hooks: Triệt tiêu bộ đếm thời gian không điều khiển & tăng số lần thao tác giả lập
static void hook_SdcVehicleInput_Update(void *self, float dt, const void *m) {
    if (gPlaying && rtPtrOk(self)) {
        *(float *)((char *)self + 0x9C) = 0.f;  // mNotControlTime = 0 (Triệt tiêu AFK)
        *(bool  *)((char *)self + 0xA0) = true; // mLastIsControl = true
        *(float *)((char *)self + 0xA4) = 0.f;  // mLastControlTime = 0

        void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcVehicleInputEndData)
        if (rtPtrOk(endData)) {
            *(int *)((char *)endData + 0x2C) = 0; // CarNonControlTimeMax = 0
            *(int *)((char *)endData + 0x30) = 0; // CarNonControlTimeTotal = 0
            (*(int *)((char *)endData + 0x10)) += 2; // CarLeftTurnCount++
            (*(int *)((char *)endData + 0x18)) += 2; // CarRightTurnCount++
            (*(int *)((char *)endData + 0x24)) += 1; // CarDriftingCount++
        }
        return; // KHÔNG CHO HÀM GỐC TÍNH TOÁN AFK KHI ĐANG ĐUA AUTO
    }
    if (orig_SdcVehicleInput_Update) orig_SdcVehicleInput_Update(self, dt, m);
}

static void hook_SdcPlayerInput_Update(void *self, float dt, const void *m) {
    if (gPlaying && rtPtrOk(self)) {
        void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcPlayerInputEndData)
        if (rtPtrOk(endData)) {
            (*(int *)((char *)endData + 0x14)) += 2; // UserLeftTurnCount++
            (*(int *)((char *)endData + 0x18)) += 2; // UserRightTurnCount++
            (*(int *)((char *)endData + 0x20)) += 1; // UserDriftingCount++
            (*(int *)((char *)endData + 0x24)) += 1; // UserMiniJetCount++
        }
        return; // KHÔNG CHO HÀM GỐC TÍNH TOÁN AFK KHI ĐANG ĐUA AUTO
    }
    if (orig_SdcPlayerInput_Update) orig_SdcPlayerInput_Update(self, dt, m);
}

static BOOL hook_MatchUIMgr_Trusteeship(void *self, int aiActionID, const void *m) {
    rtLog("ANTI-AFK: Blocked in-game Trusteeship (%d)", aiActionID);
    return FALSE; // Luôn luôn chặn, tuyệt đối không cho game bật xe AI lái thay
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
                void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
                void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
                void *drivingCtrl = *(void **)((char *)self + kOffMotionDriving);
                void *sim = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + kOffPhySimOutput) : NULL;

                if (!gPlaying && rtPtrOk(vehicle)) {
                    gMapStartSlot = *(int *)((char *)vehicle + 0xE8);
                }

                if (gPlaying) {
                    if (rtPtrOk(steerData) && rtPtrOk(sim)) {
                        double now = rtNow();
                        rtPlaybackTick(self, steerData, drivingCtrl, sim, now);
                    }
                } else if (gIsRecordingActive && rtPtrOk(sim) && gRecordCount < RC_MAX_RECORD_FRAMES) {
                    static double sLastRecordTick = 0.0;
                    double now = rtNow();
                    if (now - sLastRecordTick >= 0.015) {
                        sLastRecordTick = now;
                        RCFrame *f = &gRecordBuffer[gRecordCount++];
                        f->t = (float)(now - gRecordStartTime);
                        f->px = *(float *)((char *)sim + 0x64);
                        f->py = *(float *)((char *)sim + 0x68);
                        f->pz = *(float *)((char *)sim + 0x6C);
                        f->qx = *(float *)((char *)sim + 0x70);
                        f->qy = *(float *)((char *)sim + 0x74);
                        f->qz = *(float *)((char *)sim + 0x78);
                        f->qw = *(float *)((char *)sim + 0x7C);
                        f->vx = *(float *)((char *)sim + 0x38);
                        f->vy = *(float *)((char *)sim + 0x3C);
                        f->vz = *(float *)((char *)sim + 0x40);
                        f->kmph = *(float *)((char *)sim + 0x10);
                        f->steer = rtPtrOk(steerData) ? *(float *)((char *)steerData + 0x1C) : 0.f;
                        int *kp = rtKeyFlagsPtr();
                        f->keys = kp ? (uint32_t)*kp : 0;
                        f->flags = 0;
                    }
                }
            }
        }
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, m);
}

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

    // Anti-AFK Hooks
    orig_SdcVehicleInput_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcVehicleInput", "Update", 1, (void *)hook_SdcVehicleInput_Update);
    orig_SdcPlayerInput_Update = (void (*)(void *, float, const void *))
        rtHookMethod("", "SdcPlayerInput", "Update", 1, (void *)hook_SdcPlayerInput_Update);
    orig_MatchUIMgr_Trusteeship = (BOOL (*)(void *, int, const void *))
        rtHookMethod("", "MatchUIMgr", "Trusteeship", 1, (void *)hook_MatchUIMgr_Trusteeship);
}

__attribute__((constructor))
static void rcInit(void) {
    rtLogOpen();
    rtLog("=== RaceRec loaded ===");
    rtLoadSettings();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        rtInstallHooks();
        gPanel = [RCPanel new];
        [gPanel show];
    });
}
