#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <pthread.h>
#import <time.h>
#import <math.h>

#pragma mark - Logging

static void rtLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void rtLog(const char *fmt, ...) {
    char buf[1024];
    va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);

    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm; localtime_r(&ts.tv_sec, &tm);
    char line[1200];
    int len = snprintf(line, sizeof line, "[%02d:%02d:%02d.%03ld][RaceRec] %s\n",
                       tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1000000, buf);

    static int sFd = -1;
    if (sFd < 0) {
        NSArray *p = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *dir = p.firstObject ?: NSTemporaryDirectory();
        NSString *path = [dir stringByAppendingPathComponent:@"racekit_rp.log"];
        sFd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    if (sFd >= 0) write(sFd, line, len);
    NSLog(@"[RaceRec] %s", buf);
}

static void rtLogOpen(void) {
    NSArray *p = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = p.firstObject ?: NSTemporaryDirectory();
    NSString *path = [dir stringByAppendingPathComponent:@"racekit_rp.log"];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        const char *h = "=== RaceRec log opened ===\n";
        write(fd, h, strlen(h));
        close(fd);
    }
}

#pragma mark - IL2CPP Native API

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;

typedef struct VirtualInvokeData {
    void *methodPtr;
    const MethodInfo *method;
} VirtualInvokeData;

static Il2CppDomain *(*il2cpp_domain_get)(void);
static const Il2CppAssembly **(*il2cpp_domain_get_assemblies)(const Il2CppDomain *, size_t *);
static const Il2CppImage *(*il2cpp_assembly_get_image)(const Il2CppAssembly *);
static Il2CppClass *(*il2cpp_class_from_name)(const Il2CppImage *, const char *, const char *);
static const MethodInfo *(*il2cpp_class_get_method_from_name)(Il2CppClass *, const char *, int);
static void *(*il2cpp_array_new)(Il2CppClass *, size_t);
static void *(*il2cpp_object_new)(Il2CppClass *);

static uintptr_t rtGetUnityBase(void) {
    static uintptr_t sBase = 0;
    if (sBase) return sBase;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "UnityFramework") || strstr(name, "UnityPlayer"))) {
            sBase = (uintptr_t)_dyld_get_image_header(i);
            rtLog("Found Framework base: 0x%lx (%s)", (unsigned long)sBase, name);
            return sBase;
        }
    }
    sBase = (uintptr_t)_dyld_get_image_header(0);
    rtLog("Using main executable header as base: 0x%lx", (unsigned long)sBase);
    return sBase;
}

static BOOL rtInitIl2Cpp(void) {
    static BOOL sInit = NO;
    if (sInit) return YES;
    sInit = YES;
    void *h = dlopen(NULL, RTLD_NOW);
    #define RESOLVE(fn) fn = (typeof(fn))dlsym(h, #fn)
    RESOLVE(il2cpp_domain_get);
    RESOLVE(il2cpp_domain_get_assemblies);
    RESOLVE(il2cpp_assembly_get_image);
    RESOLVE(il2cpp_class_from_name);
    RESOLVE(il2cpp_class_get_method_from_name);
    RESOLVE(il2cpp_array_new);
    RESOLVE(il2cpp_object_new);
    #undef RESOLVE
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
    kOffMotionDriving         = 0x28,   // .mVehicleDrivingCtrl
    kOffMotionForcePos        = 0x64,   // .mForcePosition (Vector3)
    kOffMotionForceRot        = 0x70,   // .mForceRotation (Quaternion)
    kOffMotionIsSetTransform  = 0x80,   // .mIsSetTransform (bool)

    kOffPhySimOutput          = 0x38,   // NssPhyVehicleCtrl.mSimOutput
    kOffSimChassisPos         = 0x08,   // DynamicVehicleSimOutput.mChassisPosition
    kOffSimChassisRot         = 0x14,   // .mChassisRotation
    kOffSimLinVel             = 0x24,   // .mLinearVelocity
    kOffSimAngVel             = 0x30,   // .mAngularVelocity
    kOffSimKmph               = 0x3C,   // .mKmph
    kOffSimGroundSteer        = 0x48,   // .mGroundSteerAngle

    kOffSteerTargetVal        = 0x24,   // NssPhyVehicleSteeringData.mTargetSteerValue
    kOffSteerDirectVal        = 0x28,   // .mDirectSteerValue
    kOffSteerOutVal           = 0x2C,   // .mOutSteerValue
    kOffSteerCurvature        = 0x34,   // .mCurvatureDistance

    kOffDrvThrottle           = 0x3C,   // NssPhyVehicleDrivingCtrl.mThrottle
    kOffDrvSteering           = 0x40,   // .mSteering

    kOffCpMapId               = 0x14,   // CheckPointConfig.MapId
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

static RCFrame *gFrames = NULL;
static uint32_t gFrameCount = 0;
static int      gMapId = 0;
static float    gTrackLen = 0.f;
static double   gGoTime = 0.0;
static BOOL     gAutoArmed = YES;
static BOOL     gPlaying = NO;
static void    *gPlayerVehicle = NULL;
static void    *gInputModule = NULL;
static int      gKeyMask = 0;
static float    gCurPlaybackSteer = 0.f;

static void *gMapDataComponent = NULL;
static BOOL  sHasStartPos = NO;
static float sStartPos[3] = {0.f, 0.f, 0.f};

#pragma mark - Helper Functions & Background BXH Downloader

static NSString *rtReadIl2CppString(void *strObj) {
    if (!rtPtrOk(strObj)) return nil;
    int32_t len = *(int32_t *)((char *)strObj + 0x10);
    if (len <= 0 || len > 4096) return nil;
    const unichar *chars = (const unichar *)((char *)strObj + 0x14);
    return [NSString stringWithCharacters:chars length:len];
}

static void rtDownloadAllPeakSpeedReplays(void (^onProgress)(int done, int total, NSString *info),
                                         void (^onComplete)(int totalDownloaded, int totalMaps)) {
    static BOOL gDownloading = NO;
    if (gDownloading) {
        if (onProgress) onProgress(0, 0, @"Đang trong tiến trình tải...");
        return;
    }
    gDownloading = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
        NSString *tempDir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:NULL];

        if (!gMapDataComponent) {
            gDownloading = NO;
            if (onComplete) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    onComplete(-1, 0);
                });
            }
            return;
        }

        void *list = *(void **)((char *)gMapDataComponent + 0x98); // VideoDetailCfgs (ListView<VideoDetailCfg>)
        if (!rtPtrOk(list)) {
            gDownloading = NO;
            if (onComplete) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    onComplete(-2, 0);
                });
            }
            return;
        }

        int count = *(int *)((char *)list + 0x18);
        void *arr = *(void **)((char *)list + 0x10);
        if (!rtPtrOk(arr) || count <= 0) {
            gDownloading = NO;
            if (onComplete) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    onComplete(0, 0);
                });
            }
            return;
        }

        void **items = (void **)((char *)arr + 0x20);

        // Lọc replay có thời gian nhanh nhất (Grade cao nhất, ưu tiên bGradeID == 3) cho mỗi MapID
        NSMutableDictionary<NSNumber *, NSString *> *bestUrlPerMap = [NSMutableDictionary new];
        NSMutableDictionary<NSNumber *, NSNumber *> *bestGradePerMap = [NSMutableDictionary new];

        for (int i = 0; i < count; i++) {
            void *cfg = items[i];
            if (!rtPtrOk(cfg)) continue;

            int mapId = *(int *)((char *)cfg + 0x14);
            if (mapId <= 0) continue;

            uint8_t grade = *(uint8_t *)((char *)cfg + 0x18);
            void *urlObj = *(void **)((char *)cfg + 0x30); // szRecordFileUrl
            if (!rtPtrOk(urlObj)) continue;

            NSString *urlStr = rtReadIl2CppString(urlObj);
            if (!urlStr || !urlStr.length) continue;

            NSNumber *k = @(mapId);
            NSNumber *curGrade = bestGradePerMap[k];
            if (!curGrade || grade >= curGrade.unsignedCharValue) {
                bestGradePerMap[k] = @(grade);
                bestUrlPerMap[k] = urlStr;
            }
        }

        int totalMaps = (int)bestUrlPerMap.count;
        int done = 0;
        int downloaded = 0;

        for (NSNumber *kMapId in bestUrlPerMap) {
            int mapId = kMapId.intValue;
            NSString *urlStr = bestUrlPerMap[kMapId];
            NSString *destPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d_3.rep", mapId]];

            NSDictionary *attr = [fm attributesOfItemAtPath:destPath error:NULL];
            if (!attr || attr.fileSize < 100) {
                if (onProgress) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        onProgress(done + 1, totalMaps, [NSString stringWithFormat:@"Đang tải Map %d...", mapId]);
                    });
                }
                NSData *repBytes = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr]];
                if (repBytes && repBytes.length > 100) {
                    [repBytes writeToFile:destPath atomically:YES];
                    downloaded++;
                }
            }
            done++;
        }

        gDownloading = NO;
        if (onComplete) {
            dispatch_async(dispatch_get_main_queue(), ^{
                onComplete(downloaded, totalMaps);
            });
        }
    });
}

#pragma mark - Storage & Parser .rep

static NSString *rtDir(void) {
    NSArray *p = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *d = [p.firstObject stringByAppendingPathComponent:@"RaceRec"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}

static NSString *rtPathForTrack(void) {
    if (!gMapId) return nil;
    return [rtDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"map_%d.rk", gMapId]];
}

static BOOL rtSaveRecord(void) {
    if (!gFrames || !gFrameCount) return NO;
    NSString *path = rtPathForTrack();
    if (!path) return NO;
    FILE *f = fopen(path.fileSystemRepresentation, "wb");
    if (!f) return NO;

    RCHeader h;
    memset(&h, 0, sizeof h);
    memcpy(h.magic, RC_MAGIC, 4);
    h.ver = 3;
    h.count = gFrameCount;
    h.trackLen = gTrackLen;
    h.mapId = gMapId;
    h.frameSize = sizeof(RCFrame);
    fwrite(&h, sizeof h, 1, f);
    fwrite(gFrames, sizeof(RCFrame), gFrameCount, f);
    fclose(f);
    rtLog("SAVED %u frames to %s", gFrameCount, path.UTF8String);
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

    // KIỂM TRA ĐÚNG MAP: Tuyệt đối không cho phép chạy nhầm file .rep của map khác!
    if (gMapId > 0 && mapId != (uint32_t)gMapId) {
        rtLog("[Rep] LỖI MAP: File .rep là của Map %u, trong khi trận hiện tại là Map %d!", mapId, gMapId);
        return NO;
    }

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

        // Flags
        uint8_t flags = 0;
        if (inputKeys & (1 << 6)) flags |= (1 << 0);
        if (inputKeys & (1 << 8)) flags |= (1 << 2);
        if (inputKeys & (1 << 3)) flags |= (1 << 3);
        if (inputKeys & (1 << 5)) flags |= (1 << 4);
        fr.flags = flags;

        // Ghi nhận góc lái steer
        if (inputKeys & (1 << 1)) fr.steer = -1.0f;
        else if (inputKeys & (1 << 2)) fr.steer = 1.0f;
        else fr.steer = 0.f;

        gFrames[i] = fr;
    }
    gFrameCount = count;
    rtLog("[Rep] Successfully extracted %u frames from game parser!", gFrameCount);

    // CHUẨN HÓA MỐC THỜI GIAN XUẤT PHÁT t = 0.0s (loại bỏ thời gian đếm ngược trong Replay)
    if (count > 0) {
        float t0 = gFrames[0].t;
        if (t0 > 0.001f) {
            for (int i = 0; i < count; i++) {
                gFrames[i].t -= t0;
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

    void *byteClass = rtFindClass("System", "Byte");
    void *desClass  = rtFindClass("", "MatchVideoDesHelper");
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
    if (targetMapId <= 0) return nil;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [doc stringByAppendingPathComponent:@"TempMatchVideos"];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
    if (!files || !files.count) return nil;

    // 1. ƯU TIÊN 1: File chuẩn kỷ lục Top 3 (nhanh nhất): <mapId>_3.rep
    NSString *top3Path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d_3.rep", targetMapId]];
    if ([fm fileExistsAtPath:top3Path]) {
        return top3Path;
    }

    // 2. ƯU TIÊN 2: File có tên bắt đầu bằng <mapId>_ (ví dụ: <mapId>_0.rep, <mapId>_timestamp.rep) hoặc <mapId>.rep
    NSString *targetPrefix = [NSString stringWithFormat:@"%d_", targetMapId];
    NSString *exactName = [NSString stringWithFormat:@"%d.rep", targetMapId];
    NSString *bestMatch = nil;
    NSDate *newestDate = [NSDate distantPast];

    for (NSString *name in files) {
        if ([name.pathExtension.lowercaseString isEqualToString:@"rep"]) {
            NSString *full = [dir stringByAppendingPathComponent:name];
            if ([name isEqualToString:exactName] || [name hasPrefix:targetPrefix]) {
                NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
                NSDate *mod = attr.fileModificationDate ?: [NSDate date];
                if ([mod compare:newestDate] == NSOrderedDescending) {
                    newestDate = mod;
                    bestMatch = full;
                }
            }
        }
    }

    // TUYỆT ĐỐI KHÔNG fallback sang file của map khác! Tránh lỗi văng xe ra ngoài hư không.
    return bestMatch;
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
                if (!memcmp(h.magic, RC_MAGIC, 4) && h.frameSize == sizeof(RCFrame)) {
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
                if (gFrameCount > 0) {
                    rtLog("LOADED %u frames from .rk file!", gFrameCount);
                    return YES;
                }
            } else {
                fclose(f);
            }
        }
    }

    rtLog("No valid record found for map %d", gMapId);
    return NO;
}

static void rtWriteKeyFlags(int mask) {
    if (gInputModule) {
        void *keyData = *(void **)((char *)gInputModule + kOffInputKeyData);
        if (keyData) *(int *)((char *)keyData + kOffKeyDataFlags) = mask;
    }
    gKeyMask = mask;
}

#pragma mark - Playback

static double rtNow(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void rtPlaybackTick(void *motionCtrl, void *steerData, void *drivingCtrl, void *sim, double now) {
    if (!gFrames || !gFrameCount) return;

    float t = (float)(now - gGoTime);
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

    // Ghi nhận vị trí xuất phát thực tế trên làn của xe trong trận Rank/PVP
    if (!sHasStartPos && rtPtrOk(sim)) {
        sStartPos[0] = *(float *)((char *)sim + kOffSimChassisPos + 0);
        sStartPos[1] = *(float *)((char *)sim + kOffSimChassisPos + 4);
        sStartPos[2] = *(float *)((char *)sim + kOffSimChassisPos + 8);
        sHasStartPos = YES;
    }

    // --- 1. TỌA ĐỘ VÀ VẬN TỐC NỘI SUY ---
    float tx = a->px + (b->px - a->px) * al;
    float ty = a->py + (b->py - a->py) * al;
    float tz = a->pz + (b->pz - a->pz) * al;

    // Chuyển làn mượt mà trong 0.6s đầu từ vị trí xuất phát vào đường đua (chống kẹt / lệch làn xe)
    if (sHasStartPos && t < 0.6f) {
        float blend = t / 0.6f;
        blend = blend * blend * (3.0f - 2.0f * blend); // smoothstep
        tx = sStartPos[0] + (tx - sStartPos[0]) * blend;
        ty = sStartPos[1] + (ty - sStartPos[1]) * blend;
        tz = sStartPos[2] + (tz - sStartPos[2]) * blend;
    }

    // --- 2. NỘI SUY GÓC XOAY QUATERNION CHUẨN XÁC (Shortest-path NLerp chống lật góc 180 độ) ---
    float dot = a->qx * b->qx + a->qy * b->qy + a->qz * b->qz + a->qw * b->qw;
    float bx = b->qx, by = b->qy, bz = b->qz, bw = b->qw;
    if (dot < 0.0f) {
        bx = -bx; by = -by; bz = -bz; bw = -bw;
    }
    float qx = a->qx + (bx - a->qx) * al;
    float qy = a->qy + (by - a->qy) * al;
    float qz = a->qz + (bz - a->qz) * al;
    float qw = a->qw + (bw - a->qw) * al;
    float ql = sqrtf(qx * qx + qy * qy + qz * qz + qw * qw);
    if (ql > 1e-4f) { qx /= ql; qy /= ql; qz /= ql; qw /= ql; }

    float vx = a->vx + (b->vx - a->vx) * al;
    float vy = a->vy + (b->vy - a->vy) * al;
    float vz = a->vz + (b->vz - a->vz) * al;
    float kmph = a->kmph + (b->kmph - a->kmph) * al;

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

        *(float *)((char *)sim + kOffSimLinVel + 0) = vx;
        *(float *)((char *)sim + kOffSimLinVel + 4) = vy;
        *(float *)((char *)sim + kOffSimLinVel + 8) = vz;

        *(float *)((char *)sim + kOffSimAngVel + 0) = 0.f;
        *(float *)((char *)sim + kOffSimAngVel + 4) = 0.f;
        *(float *)((char *)sim + kOffSimAngVel + 8) = 0.f;

        *(float *)((char *)sim + kOffSimKmph) = kmph;
        *(float *)((char *)sim + kOffSimGroundSteer) = a->steer;
    }

    // --- 4. GÓC ĐÁNH LÁI & ĐIỀU KHIỂN ---
    float steer = a->steer;
    gCurPlaybackSteer = steer;

    if (rtPtrOk(steerData)) {
        *(float *)((char *)steerData + kOffSteerTargetVal) = steer;
        *(float *)((char *)steerData + kOffSteerDirectVal) = steer;
        *(float *)((char *)steerData + kOffSteerOutVal)    = steer;
        *(float *)((char *)steerData + kOffSteerCurvature) = 0.5f;
    }

    if (rtPtrOk(drivingCtrl)) {
        *(float *)((char *)drivingCtrl + kOffDrvThrottle) = 1.0f;
        *(float *)((char *)drivingCtrl + kOffDrvSteering) = steer;
    }

    // --- 5. BƠM PHÍM BẤM INPUT TỰ ĐỘNG ---
    uint32_t keys = a->keys;

    // Giữ phím ga khởi động (Super Start Jet)
    if (t >= 0.06f && t <= 0.45f) {
        keys |= (1 << 5);  // MiniBoost
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

#pragma mark - UI Interface & Declarations

@interface RCPanel : NSObject
@property (nonatomic, strong) UIWindow *win;
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *bDlRep;
@property (nonatomic, strong) UIButton *bAuto;
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
        if ([self.panel pointInside:p withEvent:event]) {
            return [super hitTest:point withEvent:event];
        }
    }
    return nil;
}
@end

static RCPanel *gPanel = nil;

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
            best = w; break;
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

// Component Capturing Hooks
static void   (*orig_MapDataComponent_InitComponent)(void *, const void *);
static void   (*orig_NationalKingTrackChallengeSystem_InitModule)(void *, const void *);

// Anti-AFK Hooks (4 tầng bảo vệ chống AFK / Treo máy)
static void   (*orig_SdcVehicleInput_UpdateVehicleNotControlMaxTime)(void *, float, const void *);
static void   (*orig_SdcVehicleInput_Update)(void *, float, const void *);
static void   (*orig_SdcPlayerInput_Update)(void *, float, const void *);
static void   (*orig_CPR_FillVehicleInputData)(void *, void **, const void *);
static void   (*orig_CPR_FillPVPButtonUseData)(void *, void **, const void *);
static BOOL   (*orig_MatchUIMgr_Trusteeship)(void *, int, const void *);

static void hook_Input_Update(void *self, float dt, const void *m) {
    gInputModule = self;
    if (orig_Input_Update) orig_Input_Update(self, dt, m);
    if (gPlaying) {
        rtWriteKeyFlags(gKeyMask);
    }
}

static BOOL hook_Input_GetKey(void *self, int keyType, const void *m) {
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
    gCurPlaybackSteer = 0.f;
    sHasStartPos = NO;

    if (gAutoArmed) {
        BOOL ok = (gFrames && gFrameCount > 0) ? YES : rtLoadRecord();
        gPlaying = ok;
        rtLog("AUTO map=%d -> %s (%u frames)", gMapId, ok ? "playing" : "no record", gFrameCount);
        if (!ok) {
            rtAlert(@"Đua lập trình",
                    [NSString stringWithFormat:@"Không tìm thấy file .rep cho map %d trong TempMatchVideos!\nHãy nhấn nút TẢI .REP trên menu.", gMapId]);
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
    gPlaying = NO;
    gCurPlaybackSteer = 0.f;
    sHasStartPos = NO;
    rtWriteKeyFlags(0);
}

static BOOL hook_MatchVideoDesHelper_InitByVideoBytes(void *self, void *bytes, const void *m) {
    BOOL ret = orig_MatchVideoDesHelper_InitByVideoBytes ? orig_MatchVideoDesHelper_InitByVideoBytes(self, bytes, m) : NO;
    if (ret) {
        rtExtractFramesFromDesHelper(self);
    }
    return ret;
}

static void hook_CheckPointMgr_Init(void *self, void *config, bool crc, bool reset, const void *m) {
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, crc, reset, m);
    if (config) {
        gMapId = *(int *)((char *)config + kOffCpMapId);
        gTrackLen = *(float *)((char *)config + kOffCpCurveLength);
        rtLog("MAP LOAD: mapId=%d trackLen=%.1fm", gMapId, gTrackLen);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gAutoArmed) {
            rtLoadRecord();
        }
        if (gPanel) [gPanel refresh];
    });
}

static void hook_MapDataComponent_InitComponent(void *self, const void *m) {
    gMapDataComponent = self;
    rtLog("[MapDataComponent] Captured instance: %p", self);
    if (orig_MapDataComponent_InitComponent) orig_MapDataComponent_InitComponent(self, m);
}

static void hook_NationalKingTrackChallengeSystem_InitModule(void *self, const void *m) {
    if (orig_NationalKingTrackChallengeSystem_InitModule) orig_NationalKingTrackChallengeSystem_InitModule(self, m);
    if (rtPtrOk(self)) {
        void *comp = *(void **)((char *)self + 0xD0); // mMapDataComponent
        if (rtPtrOk(comp)) {
            gMapDataComponent = comp;
            rtLog("[NationalKing] Captured gMapDataComponent from System: %p", comp);
        }
    }
}

// ==================== ANTI-AFK 4 TẦNG (CHỐNG TREO MÁY TRONG TRẬN) ====================
// Tầng 1: Khóa vĩnh viễn bộ đếm thời gian không điều khiển của xe
static void hook_SdcVehicleInput_UpdateVehicleNotControlMaxTime(void *self, float dt, const void *m) {
    if (!rtPtrOk(self)) return;
    *(float *)((char *)self + 0x9C) = 0.f;  // mNotControlTime = 0
    *(bool  *)((char *)self + 0xA0) = true; // mLastIsControl = true
    *(float *)((char *)self + 0xA4) = 0.f;  // mFloatNotControlTime = 0

    void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcVehicleInputEndData)
    if (rtPtrOk(endData)) {
        *(int *)((char *)endData + 0x2C) = 0; // CarNonControlTimeMax = 0
        *(int *)((char *)endData + 0x30) = 0; // CarNonControlTimeTotal = 0
    }
    // Không gọi hàm gốc: Vô hiệu hóa hoàn toàn việc cộng dồn thời gian không điều khiển!
}

static void hook_SdcVehicleInput_Update(void *self, float dt, const void *m) {
    if (orig_SdcVehicleInput_Update) orig_SdcVehicleInput_Update(self, dt, m);
    if (rtPtrOk(self)) {
        *(float *)((char *)self + 0x9C) = 0.f;  // mNotControlTime = 0
        *(bool  *)((char *)self + 0xA0) = true; // mLastIsControl = true
        *(float *)((char *)self + 0xA4) = 0.f;  // mFloatNotControlTime = 0

        void *endData = *(void **)((char *)self + 0x58);
        if (rtPtrOk(endData)) {
            *(int *)((char *)endData + 0x2C) = 0; // CarNonControlTimeMax = 0
            *(int *)((char *)endData + 0x30) = 0; // CarNonControlTimeTotal = 0
            (*(int *)((char *)endData + 0x10))++; // CarLeftTurnCount++
            (*(int *)((char *)endData + 0x18))++; // CarRightTurnCount++
            (*(int *)((char *)endData + 0x24))++; // CarDriftingCount++
        }
    }
}

static void hook_SdcPlayerInput_Update(void *self, float dt, const void *m) {
    if (orig_SdcPlayerInput_Update) orig_SdcPlayerInput_Update(self, dt, m);
    if (rtPtrOk(self)) {
        void *endData = *(void **)((char *)self + 0x58); // mEndData (SdcPlayerInputEndData)
        if (rtPtrOk(endData)) {
            (*(int *)((char *)endData + 0x10))++; // UserLeftTurnCount++ (0x10)
            (*(int *)((char *)endData + 0x14))++; // UserRightTurnCount++ (0x14)
            (*(int *)((char *)endData + 0x18))++; // UserDriftingCount++ (0x18)
            (*(int *)((char *)endData + 0x1C))++; // UserMiniJetCount++ (0x1C)
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
        if (*(uint16_t *)(d + 0x12) < 15) *(uint16_t *)(d + 0x12) = 15 + (rand() % 10); // wUserLeftTurnCount
        if (*(uint16_t *)(d + 0x14) < 15) *(uint16_t *)(d + 0x14) = 15 + (rand() % 10); // wUserRightTurnCount
        if (*(uint16_t *)(d + 0x18) < 8)  *(uint16_t *)(d + 0x18) = 8 + (rand() % 5);   // wUserDriftingCount
        if (*(uint16_t *)(d + 0x1A) < 10) *(uint16_t *)(d + 0x1A) = 10 + (rand() % 6);  // wUserMiniJetCount
    }
}

// Tầng 4: Chặn Game chuyển sang trạng thái AFK / Trusteeship (xe AI tự lái)
static BOOL hook_MatchUIMgr_Trusteeship(void *self, int aiActionID, const void *m) {
    rtLog("ANTI-AFK: Blocked in-game Trusteeship (%d)", aiActionID);
    return FALSE; // Luôn từ chối chế độ lái hộ AFK
}

static void hook_MotionCtrl_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) {
        void *vehicle = *(void **)((char *)self + kOffMotionVehicle);
        if (rtPtrOk(vehicle)) {
            // SỬA LỖI VỊ TRÍ XE: Trong phòng Rank / Map thường có 6 xe, tất cả đều có actorType == 0!
            // CHỈ điều khiển xe của chính người chơi (mIsMainPlayer == true tại offset 0xF8)!
            // TUYỆT ĐỐI không can thiệp vào 5 xe của người chơi khác!
            bool isMain = *(bool *)((char *)vehicle + kOffVehicleIsMainPlayer);
            if (!isMain) return;

            gPlayerVehicle = vehicle;

            if (gPlaying) {
                void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
                void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
                void *drivingCtrl = *(void **)((char *)self + kOffMotionDriving);
                void *sim = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + kOffPhySimOutput) : NULL;

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

                // Thực hiện nội suy và khóa quỹ đạo chính xác cho xe người chơi
                rtPlaybackTick(self, steerData, drivingCtrl, sim, rtNow());
            }
        }
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, m);
}

#pragma mark - UI Implementation (Kéo thả di chuyển, Tải .rep toàn diện & Auto)

@implementation RCPanel

- (void)show {
    if (self.win) return;

    CGRect scr = [UIScreen mainScreen].bounds;
    CGFloat w = 210, h = 90;
    CGFloat x = scr.size.width - w - 20;
    CGFloat y = 60;

    RCPassWindow *win = [[RCPassWindow alloc] initWithFrame:scr];
    win.windowLevel = UIWindowLevelStatusBar + 100;
    win.backgroundColor = [UIColor clearColor];
    win.hidden = NO;
    self.win = win;

    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    host.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.90];
    host.layer.cornerRadius = 12.0;
    host.layer.borderWidth = 1.5;
    host.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.8].CGColor;
    host.clipsToBounds = YES;
    [win addSubview:host];
    self.host = host;
    win.panel = host;

    // Gesture kéo thả di chuyển menu
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [host addGestureRecognizer:pan];

    UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, w - 16, 36)];
    st.font = [UIFont boldSystemFontOfSize:11];
    st.textColor = [UIColor whiteColor];
    st.numberOfLines = 2;
    st.textAlignment = NSTextAlignmentCenter;
    [host addSubview:st];
    self.status = st;

    // Nút 1: TẢI .REP (Quét toàn bộ BXH tất cả map & tải replay nhanh nhất)
    UIButton *bDl = [UIButton buttonWithType:UIButtonTypeCustom];
    bDl.frame = CGRectMake(8, 48, 92, 34);
    bDl.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.85 alpha:0.9];
    bDl.layer.cornerRadius = 8;
    [bDl setTitle:@"TẢI .REP" forState:UIControlStateNormal];
    bDl.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [bDl setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [bDl addTarget:self action:@selector(onDlRep) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:bDl];
    self.bDlRep = bDl;

    // Nút 2: AUTO
    UIButton *bA = [UIButton buttonWithType:UIButtonTypeCustom];
    bA.frame = CGRectMake(110, 48, 92, 34);
    bA.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:0.85];
    bA.layer.cornerRadius = 8;
    [bA setTitle:@"▶ AUTO" forState:UIControlStateNormal];
    bA.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [bA setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [bA addTarget:self action:@selector(onAuto) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:bA];
    self.bAuto = bA;

    [self refresh];
}

- (void)onPan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint trans = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + trans.x, v.center.y + trans.y);
    [p setTranslation:CGPointZero inView:v.superview];
}

- (void)refresh {
    NSString *stateStr = gAutoArmed ? @"BẬT" : @"TẮT";
    self.status.text = [NSString stringWithFormat:@"Map: %d | Frames: %u\nAUTO: %@ | Đua: %d",
                        gMapId, gFrameCount, stateStr, (int)gPlaying];

    if (gAutoArmed) {
        self.bAuto.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:0.9];
        [self.bAuto setTitle:@"AUTO: BẬT" forState:UIControlStateNormal];
    } else {
        self.bAuto.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.9];
        [self.bAuto setTitle:@"AUTO: TẮT" forState:UIControlStateNormal];
    }
}

- (void)onDlRep {
    self.status.text = @"Đang quét BXH & tải .rep...";
    rtDownloadAllPeakSpeedReplays(^(int done, int total, NSString *info) {
        self.status.text = [NSString stringWithFormat:@"%@ (%d/%d)", info, done, total];
    }, ^(int totalDownloaded, int totalMaps) {
        if (totalDownloaded == -1) {
            self.status.text = @"Vào Chọn Map / BXH trước!";
            rtAlert(@"Chưa có dữ liệu", @"Vui lòng vào màn hình Chọn Map hoặc BXH Đua Cực Tốc 1 lần để nạp dữ liệu bản đồ!");
        } else if (totalDownloaded == -2 || totalMaps == 0) {
            self.status.text = @"Không tìm thấy video!";
        } else {
            self.status.text = [NSString stringWithFormat:@"Tải xong %d map mới (Tổng %d)!", totalDownloaded, totalMaps];
            rtAlert(@"Tải .rep thành công", [NSString stringWithFormat:@"Đã quét xong toàn bộ BXH!\nĐã tải replay nhanh nhất của %d map vào TempMatchVideos.", totalMaps]);
            if (gAutoArmed) rtLoadRecord();
        }
        [self refresh];
    });
}

- (void)onAuto {
    gAutoArmed = __omp_shell("gAutoArmed;")
    if (!gAutoArmed) { gPlaying = NO; rtWriteKeyFlags(0); }
    [self refresh];
}

@end

#pragma mark - Entry Point

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

    // Component Capturing Hooks
    orig_MapDataComponent_InitComponent = (void (*)(void *, const void *))
        rtHookMethod("", "MapDataComponent", "InitComponent", 0, (void *)hook_MapDataComponent_InitComponent);
    orig_NationalKingTrackChallengeSystem_InitModule = (void (*)(void *, const void *))
        rtHookMethod("", "NationalKingTrackChallengeSystem", "InitModule", 0, (void *)hook_NationalKingTrackChallengeSystem_InitModule);

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
