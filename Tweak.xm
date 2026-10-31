// RaceRec — Ghi / Phát lại đường đua (record & playback)
//
// Nút REC  : bật → vào map → tự ghi từng frame. Tắt → lưu Documents/RaceKit/rec_map<MapId>.rk
// Nút AUTO : bật → vào map → có record thì đua lập trình, không có thì báo lỗi.
//
// Mọi offset dưới đây đã được kiểm chứng bằng decompile trên UnityFramework.i64:
//   NssVehicle.GetActorType            0x7C60B70 -> *(u32*)(a1+20)          => 0x14
//   NssVehicle.get_DynamicVehicleImpl  0x7C5F6E0 -> *(qword*)(a1+32)        => 0x20
//   NssVehicleSimOutput.get_Position   0x7C94C90 -> *(float*)(a1+100)       => 0x64
//   NssVehicleSimOutput.get_Rotation   0x7C94C9C -> *(float*)(a1+112)       => 0x70
//   NssPhyVehicleDrivingCtrl.get_Throttle       0x7AF6DE0 -> a1+60          => 0x3C
//   NssPhyVehicleDrivingCtrl.set_Throttle       0x7AF6DE8 -> a1+60          => 0x3C
//   NssPhyVehicleDrivingCtrl.get_Steering       0x7AF6DF0 -> a1+64          => 0x40
//   NssPhyVehicleDrivingCtrl.set_Steering       0x7AF6DF8 -> a1+64          => 0x40
//   NssSteeringData.IsBraking                   0x7BCE598 -> *(u32*)(a1+20) => 0x14
//   InputModule.GetKey                          0x5AD62AC -> (*(u32*)(*(a1+168)+16) >> keyType) & 1
//   InputModule.SetKeyFlags                     0x5AD61B8 -> *(u32*)(*(a1+168)+16) = flags
//   CheckPointConfig.MapId               (dump.cs)                          => 0x14
//   CheckPointConfig.MainCurveLength     (dump.cs)                          => 0x2C

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
        Il2CppImage *img = il2cpp_assembly_get_image(asms[i]);
        if (!img) continue;
        Il2CppClass *k = il2cpp_class_from_name(img, ns, name);
        if (k) return k;
    }
    return NULL;
}

static BOOL rtPtrOk(const void *p) { return p && (uintptr_t)p > 0x1000 && (uintptr_t)p < 0x00007fffffffffffULL; }

// MethodInfo.slot ở +0x58 (kiểm chứng: il2cpp_method_get_param_count đọc +90 => layout runtime
// rộng hơn header dumper; slot 0x58 là giá trị khớp khi hook thành công trên thiết bị)
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
    kOffSimLinearVel          = 0x38,   // .mLinearVelocity (Vector3)
    kOffSimChassisPos         = 0x64,   // .mChassisPosition (Vector3)
    kOffSimChassisRot         = 0x70,   // .mChassisRotation (Quaternion)

    kOffSteerForward          = 0x10,   // NssSteeringData.mForward
    kOffSteerBraking          = 0x14,   // .mBrakingState
    kOffSteerHandbrake        = 0x18,   // .mIsHandbrake
    kOffSteerLeft             = 0x1C,   // .mSteeringLeft

    kOffDrvThrottle           = 0x3C,   // NssPhyVehicleDrivingCtrl.mThrottle
    kOffDrvSteering           = 0x40,   // .mSteering

    kOffInputKeyData          = 0xA8,   // InputModule.mInputKeyData
    kOffKeyDataFlags          = 0x10,   // InputKeyData.KeyFlags
};

#pragma mark - Frame format

// Forward: UI helpers dùng trước khi định nghĩa
@class RCPassWindow;
static void rtAlert(NSString *title, NSString *msg);
static UIViewController *rtTopVC(void);

#define RC_MAGIC "RKR3"
#define RC_MAX_FRAMES 21600
#define RC_SAMPLE_DT  0.008f

typedef struct {
    float    t;               // Thời gian tương đối (s)
    float    px, py, pz;      // Vị trí khung gầm (mChassisPosition)
    float    qx, qy, qz, qw;  // Hướng xoay Quaternion (mChassisRotation)
    float    vx, vy, vz;      // Vận tốc tuyến tính (mLinearVelocity)
    float    kmph;            // Tốc độ hiển thị km/h
    float    steer;           // Góc đánh lái (-1.0 đến 1.0)
    uint32_t keys;            // Bitmask phím (Drift, SmallBoost, Nitro, v.v.)
    uint8_t  flags;           // b0: phanh, b1: phanh tay, b2: drift, b3: nitro, b4: miniboost
    uint8_t  pad[3];          // Đệm căn byte
} RCFrame;                    // 60 byte

typedef struct {
    float    t;
    float    px, py, pz;
    float    qx, qy, qz, qw;
    float    steer;
    uint32_t keys;
    uint8_t  flags;
    uint8_t  pad[3];
} RCFrameV2;                   // 44 byte (tương thích các file tự record trước đó)

typedef struct {
    char     magic[4];        // "RKR3"
    uint32_t ver;            // 3
    uint32_t count;          // Số lượng frame
    float    trackLen;       // Chiều dài đường đua
    int32_t  mapId;          // ID bản đồ
    uint32_t frameSize;      // 60
} RCHeader;                   // 24 byte

static RCFrame *gFrames;
static uint32_t gFrameCount;
static int      gMapId;
static float    gTrackLen;
static double   gGoTime;
static BOOL gRecArmed, gAutoArmed, gRecording, gPlaying;
static void *gPlayerVehicle;
static void *gInputModule;
static int   gKeyMask;
static float gCurPlaybackSteer;

#pragma mark - Storage

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
    if (!f) { rtLog("save: fopen fail"); return NO; }

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
        uint32_t repKeys = *(uint32_t *)((char *)m + 0x20); // mKeyFlag (MatchInputKeyType)
        uint32_t inputKeys = 0;
        // Chuyển đổi mã phím Replay sang InputKeyType chuẩn:
        if (repKeys & ((1 << 1) | (1 << 13))) inputKeys |= (1 << 1); // Left (1)
        if (repKeys & ((1 << 2) | (1 << 14))) inputKeys |= (1 << 2); // Right (2)
        if (repKeys & ((1 << 3) | (1 << 4)))  inputKeys |= (1 << 3); // Nitro (3)
        if (repKeys & ((1 << 7) | (1 << 8)))  inputKeys |= (1 << 5); // MiniBoost (5)
        if (repKeys & ((1 << 9) | (1 << 10))) inputKeys |= (1 << 6); // Brake (6)
        if (repKeys & ((1 << 13) | (1 << 14))) inputKeys |= (1 << 8); // Drift (8)

        fr.keys = inputKeys;
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
        fr.kmph = *(float *)((char *)m + 0x5C); // mKMPH

        if (inputKeys & (1 << 1)) fr.steer = -0.85f;
        else if (inputKeys & (1 << 2)) fr.steer = 0.85f;
        else fr.steer = 0.f;

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

    rtSaveRecord();
    return YES;
}

static BOOL rtLoadRepFromDisk(NSString *repPath) {
    if (!repPath || ![[NSFileManager defaultManager] fileExistsAtPath:repPath]) return NO;
    NSData *data = [NSData dataWithContentsOfFile:repPath];
    if (!data || !data.length) return NO;

    rtLog("[Rep] Reading file: %s (%lu bytes)", repPath.UTF8String, (unsigned long)data.length);

    void *byteClass = rtFindClass("System", "Byte");
    void *desClass  = rtFindClass("", "MatchVideoDesHelper");
    if (!byteClass || !desClass || !il2cpp_array_new || !il2cpp_object_new) {
        rtLog("[Rep] il2cpp functions missing: byteClass=%p desClass=%p arrNew=%p objNew=%p",
              byteClass, desClass, il2cpp_array_new, il2cpp_object_new);
        return NO;
    }

    uintptr_t base = rtGetUnityBase();
    if (!base) return NO;

    // 1. Tạo Il2CppArray chứa dữ liệu file
    void *arr = il2cpp_array_new(byteClass, data.length);
    if (!arr) return NO;
    memcpy((char *)arr + 0x20, data.bytes, data.length);

    // 2. Giải nén nếu file bị nén qua MatchVideoStaticHelper.GetUnZipData (0x71E28EC)
    typedef void *(*fn_unzip_t)(void *, ...);
    fn_unzip_t fn_unzip = (fn_unzip_t)(base + 0x71E28EC);
    void *unzipArr = fn_unzip ? fn_unzip(arr) : arr;
    if (!unzipArr) unzipArr = arr;

    // 3. Khởi tạo đối tượng MatchVideoDesHelper
    void *helper = il2cpp_object_new(desClass);
    if (!helper) return NO;
    typedef void (*fn_ctor_t)(void *);
    fn_ctor_t fn_ctor = (fn_ctor_t)(base + 0x71B6A88);
    if (fn_ctor) fn_ctor(helper);

    // 4. Giải mã dữ liệu qua InitByVideoBytes (0x71B3E20)
    typedef BOOL (*fn_init_t)(void *, void *, ...);
    fn_init_t fn_init = (fn_init_t)(base + 0x71B3E20);
    BOOL ok = fn_init ? fn_init(helper, unzipArr) : NO;
    rtLog("[Rep] InitByVideoBytes result=%d", (int)ok);
    if (ok) {
        return rtExtractFramesFromDesHelper(helper);
    }
    return NO;
}

static NSString *rtFindRepFile(int targetMapId) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
    NSArray *dirs = @[@"TempMatchVideos", @"MatchVideos", @"RaceKit"];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *bestMatch = nil;
    NSString *newestFile = nil;
    NSDate *newestDate = [NSDate distantPast];

    NSString *mapStr = targetMapId > 0 ? [NSString stringWithFormat:@"%d", targetMapId] : nil;

    for (NSString *sub in dirs) {
        NSString *dir = [doc stringByAppendingPathComponent:sub];
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
        for (NSString *name in files) {
            if ([name.pathExtension.lowercaseString isEqualToString:@"rep"]) {
                NSString *full = [dir stringByAppendingPathComponent:name];
                if (mapStr && [name containsString:mapStr]) {
                    bestMatch = full;
                    break;
                }
                NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
                NSDate *mod = attr.fileModificationDate ?: [NSDate date];
                if ([mod compare:newestDate] == NSOrderedDescending) {
                    newestDate = mod;
                    newestFile = full;
                }
            }
        }
        if (bestMatch) break;
    }
    return bestMatch ?: newestFile;
}

static BOOL rtScanAndLoadRepFiles(int targetMapId) {
    NSString *rep = rtFindRepFile(targetMapId);
    if (!rep) {
        rtLog("[Rep] No .rep file found in TempMatchVideos/MatchVideos");
        return NO;
    }
    rtLog("[Rep] Selected .rep file: %s", rep.UTF8String);
    return rtLoadRepFromDisk(rep);
}

static BOOL rtLoadRecord(void) {
    gFrameCount = 0;
    if (gFrames) { free(gFrames); gFrames = NULL; }

    // 1. Thử load record .rk đã lưu sẵn
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
                if (gFrameCount) {
                    rtLog("load: %u frames (%.2fs) map=%d len=%.1f", gFrameCount,
                          gFrames[gFrameCount - 1].t, h.mapId, h.trackLen);
                    return YES;
                }
            } else {
                fclose(f);
            }
        }
    }

    // 2. Nếu chưa có .rk, tự động quét TempMatchVideos đọc file .rep!
    rtLog("No .rk record found, checking TempMatchVideos for .rep...");
    if (rtScanAndLoadRepFiles(gMapId)) {
        return (gFrameCount > 0);
    }

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

static int rtReadKeyFlags(void) {
    int *p = rtKeyFlagsPtr();
    return p ? *p : gKeyMask;
}

static void rtWriteKeyFlags(int mask) {
    int *p = rtKeyFlagsPtr();
    if (p) *p = mask;
    gKeyMask = mask;
}

#pragma mark - Record / playback

static double rtNow(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void rtRecordTick(void *motionCtrl, void *steerData, void *sim, double now) {
    if (!gRecording) return;
    if (!gFrames) {
        gFrames = (RCFrame *)malloc(sizeof(RCFrame) * RC_MAX_FRAMES);
        if (!gFrames) { gRecording = NO; return; }
        gFrameCount = 0;
    }
    if (gFrameCount >= RC_MAX_FRAMES) { gRecording = NO; rtSaveRecord(); return; }

    float t = (float)(now - gGoTime);
    if (t < 0.f) return;
    if (gFrameCount && (t - gFrames[gFrameCount - 1].t) < RC_SAMPLE_DT) return;

    RCFrame fr;
    memset(&fr, 0, sizeof fr);
    fr.t  = t;
    fr.px = *(float *)((char *)sim + kOffSimChassisPos + 0);
    fr.py = *(float *)((char *)sim + kOffSimChassisPos + 4);
    fr.pz = *(float *)((char *)sim + kOffSimChassisPos + 8);
    fr.qx = *(float *)((char *)sim + kOffSimChassisRot + 0);
    fr.qy = *(float *)((char *)sim + kOffSimChassisRot + 4);
    fr.qz = *(float *)((char *)sim + kOffSimChassisRot + 8);
    fr.qw = *(float *)((char *)sim + kOffSimChassisRot + 12);
    fr.vx = *(float *)((char *)sim + kOffSimLinearVel + 0);
    fr.vy = *(float *)((char *)sim + kOffSimLinearVel + 4);
    fr.vz = *(float *)((char *)sim + kOffSimLinearVel + 8);
    fr.kmph = *(float *)((char *)sim + kOffSimKmph);
    fr.steer = *(float *)((char *)steerData + kOffSteerLeft);
    fr.keys = (uint32_t)rtReadKeyFlags();

    int braking = *(int *)((char *)steerData + kOffSteerBraking);
    BOOL hb = *(bool *)((char *)steerData + kOffSteerHandbrake);

    void *driftCtrl = *(void **)((char *)motionCtrl + kOffMotionDrift);
    BOOL isDrift = (driftCtrl && *(bool *)((char *)driftCtrl + 0x76)) ||
                   ((fr.keys & ((1 << 8) | (1 << 9))) != 0);
    BOOL isNitro = (fr.keys & (1 << 3)) || (fr.kmph > 275.f);
    BOOL isBoost = (fr.keys & (1 << 5)) != 0;

    uint8_t flags = 0;
    if (braking) flags |= 0x01;
    if (hb)      flags |= 0x02;
    if (isDrift) flags |= 0x04;
    if (isNitro) flags |= 0x08;
    if (isBoost) flags |= 0x10;
    fr.flags = flags;

    gFrames[gFrameCount++] = fr;
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

    // --- 1. Tọa độ mục tiêu nội suy theo thời gian ---
    float tx = a->px + (b->px - a->px) * al;
    float ty = a->py + (b->py - a->py) * al;
    float tz = a->pz + (b->pz - a->pz) * al;

    // --- 2. Tính góc hướng hiện tại và độ lệch quỹ đạo (Cua chuẩn xác như bản trước) ---
    float qx = *(float *)((char *)sim + kOffSimChassisRot + 0);
    float qy = *(float *)((char *)sim + kOffSimChassisRot + 4);
    float qz = *(float *)((char *)sim + kOffSimChassisRot + 8);
    float qw = *(float *)((char *)sim + kOffSimChassisRot + 12);
    float fx = 2.0f * (qx * qz + qw * qy);
    float fz = 1.0f - 2.0f * (qx * qx + qy * qy);
    float fl = sqrtf(fx * fx + fz * fz);
    if (fl > 1e-4f) { fx /= fl; fz /= fl; }

    float cx = *(float *)((char *)sim + kOffSimChassisPos + 0);
    float cz = *(float *)((char *)sim + kOffSimChassisPos + 8);

    float dx = tx - cx;
    float dz = tz - cz;

    // Sai lệch ngang (mét): khoảng cách vuông góc từ xe tới đường đua mục tiêu
    float latDist = (dx * fz) - (dz * fx);
    float corr = latDist * 0.22f;
    if (corr >  0.45f) corr =  0.45f;
    if (corr < -0.45f) corr = -0.45f;

    // Góc đánh lái tổng hợp: góc ghi + góc sửa sai lệch quỹ đạo
    float steer = a->steer + (b->steer - a->steer) * al + corr;
    if (steer >  1.0f) steer =  1.0f;
    if (steer < -1.0f) steer = -1.0f;
    gCurPlaybackSteer = steer;

    // Gán góc lái xuống PhysX DrivingCtrl và SteeringData
    *(float *)((char *)steerData + kOffSteerLeft) = steer;
    if (rtPtrOk(drivingCtrl)) {
        *(float *)((char *)drivingCtrl + 0x40) = steer; // mSteering
        *(float *)((char *)drivingCtrl + 0x68) = steer; // mInputXPosition
        *(float *)((char *)drivingCtrl + 0x34) = steer; // mVehicleCtrlParams.steering
        *(float *)((char *)drivingCtrl + 0x3C) = 1.0f;  // mThrottle
        *(float *)((char *)drivingCtrl + 0x38) = 1.0f;  // mVehicleCtrlParams.throttle
    }
    *(float *)((char *)steerData + kOffSteerForward) = 1.0f;

    // --- 3. PHÍM BẤM: MINIBOOST, NITRO, DRIFT & TRÁI/PHẢI ---
    uint32_t keys = a->keys;
    if (a->flags & 0x04) keys |= (1 << 8); // Cờ Drift
    if (a->flags & 0x08) keys |= (1 << 3); // Cờ Nitro
    if (a->flags & 0x10) keys |= (1 << 5); // Cờ MiniBoost

    // Kích hoạt tiểu phóng xuất phát (Start MiniBoost)
    if (t >= 0.06f && t <= 0.42f) {
        keys |= (1 << 5);
    }

    // Bơm phím rẽ Trái/Phải theo góc lái thực tế để hiển thị animation quay vô-lăng và bẻ bánh
    if (steer < -0.10f) {
        keys |= (1 << 1);  // Phím Left
        keys &= ~(1 << 2); // Thả Right
    } else if (steer > 0.10f) {
        keys |= (1 << 2);  // Phím Right
        keys &= ~(1 << 1); // Thả Left
    }

    gKeyMask = (int)keys;
    rtWriteKeyFlags((int)keys);

    // --- 4. GIỮ TỐC ĐỘ XE & CHỐNG LỆCH MAP (Soft-sync, không đóng băng vật lý) ---
    float distSq = dx * dx + dz * dz;
    if (distSq > 16.0f) {
        // Chỉ kéo nhẹ vị trí nếu bị chệch quá 4 mét do va chạm mạng
        *(float *)((char *)sim + kOffSimChassisPos + 0) = tx;
        *(float *)((char *)sim + kOffSimChassisPos + 8) = tz;
    }
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

    gCurPlaybackSteer = 0.f;
    if (gRecArmed) {
        gRecording = YES; gPlaying = NO;
        gFrameCount = 0;
        if (gFrames) { free(gFrames); gFrames = NULL; }
        rtLog("REC start map=%d len=%.1f", gMapId, gTrackLen);
    } else gRecording = NO;

    if (gAutoArmed) {
        BOOL ok = rtLoadRecord();
        gPlaying = ok;
        rtLog("AUTO map=%d -> %s", gMapId, ok ? "playing" : "no record");
        if (!ok) {
            rtAlert(@"Đua lập trình",
                    [NSString stringWithFormat:@"Chưa có record cho map %d.\nBấm REC rồi chạy 1 vòng để tạo.", gMapId]);
        }
    } else gPlaying = NO;
}

static void hook_GoImpEnter(void *self, const void *m) {
    if (orig_GoImpEnter) orig_GoImpEnter(self, m);
    rtBeginRace();
}
static void hook_RaceKingGoImpEnter(void *self, const void *m) {
    // Different classes have different originals; never call GameGoState on this instance.
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
    rtLog("FINISH reached -> auto save record");
    if (gRecording && gFrameCount) {
        rtSaveRecord();
        gRecording = NO;
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
    if (gRecording && gFrameCount) rtSaveRecord();
    gRecording = NO;
    gPlaying = NO;
    gPlayerVehicle = NULL;
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, crc, reset, m);
    gMapId = rtPtrOk(self) ? *(int *)((char *)self + 0x40) : 0;
    gTrackLen = 0.f;
    rtLog("MAP resolved from CheckPointMgr self=%p config=%p", self, config);
    rtLog("map init map=%d len=%.2f", gMapId, gTrackLen);
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

                if (gRecording || gPlaying) {
                    void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
                    void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
                    void *drivingCtrl = *(void **)((char *)self + kOffMotionDriving);
                    void *sim = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + kOffPhySimOutput) : NULL;

                    // Hook vtable slot 33 (GetSteeringValue) trực tiếp trên instance của drivingCtrl
                    if (gPlaying && rtPtrOk(drivingCtrl)) {
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
                        if (gPlaying)        rtPlaybackTick(self, steerData, drivingCtrl, sim, now);
                        else if (gRecording) rtRecordTick(self, steerData, sim, now);
                    }
                }
            }
        }
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, m);
}

#pragma mark - UI

@interface RCPanel : NSObject
@property (nonatomic, strong) UIWindow *win;
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *bRec;
@property (nonatomic, strong) UIButton *bAuto;
- (void)show;
- (void)refresh;
@end

// Window chỉ nhận touch bên trong panel; ngoài ra trả nil để game nhận.
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

static RCPanel *gPanel;

// Tìm UIViewController của game (bỏ qua window overlay của tweak)
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
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

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

        // iOS 13+: phải gắn windowScene thì window mới thực sự nổi lên
        if (@available(iOS 13.0, *)) {
            if (!self.win.windowScene) {
                for (UIWindow *w in UIApplication.sharedApplication.windows) {
                    if ([w isKindOfClass:[RCPassWindow class]]) continue;
                    if (w.windowScene) { self.win.windowScene = w.windowScene; break; }
                }
            }
        }

        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(14, scr.size.height * 0.30, 132, 150)];
        host.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.86];
        host.layer.cornerRadius = 12;
        host.layer.borderWidth = 1;
        host.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        host.userInteractionEnabled = YES;
        [self.win.rootViewController.view addSubview:host];
        self.host = host;
        ((RCPassWindow *)self.win).panel = host;

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 112, 18)];
        t.text = @"RaceKit R/P";
        t.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        t.font = [UIFont boldSystemFontOfSize:12];
        [host addSubview:t];

        self.bRec = [self mk:@"● REC" sel:@selector(tapRec)];
        self.bRec.frame = CGRectMake(10, 30, 112, 36);
        [host addSubview:self.bRec];

        self.bAuto = [self mk:@"▶ AUTO" sel:@selector(tapAuto)];
        self.bAuto.frame = CGRectMake(10, 72, 112, 36);
        [host addSubview:self.bAuto];

        self.status = [[UILabel alloc] initWithFrame:CGRectMake(10, 114, 112, 28)];
        self.status.numberOfLines = 2;
        self.status.font = [UIFont systemFontOfSize:9];
        self.status.textColor = [UIColor colorWithWhite:1 alpha:0.7];
        [host addSubview:self.status];

        self.win.hidden = NO;
        [self.win makeKeyAndVisible];

        // Không được để overlay giữ key window — game cần key window để nhận touch.
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
        self.bRec.backgroundColor  = gRecArmed  ? [UIColor colorWithRed:0.75 green:0.15 blue:0.15 alpha:0.95]
                                               : [UIColor colorWithWhite:0.12 alpha:0.92];
        self.bAuto.backgroundColor = gAutoArmed ? [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:0.95]
                                                : [UIColor colorWithWhite:0.12 alpha:0.92];
        self.status.text = [NSString stringWithFormat:@"map %d / %.0fm\nrec %u  play %d",
                            gMapId, gTrackLen, gFrameCount, (int)gPlaying];
    });
}

- (void)tapRec {
    gRecArmed = !gRecArmed;
    if (!gRecArmed && gRecording) {
        gRecording = NO;
        BOOL ok = rtSaveRecord();
        uint32_t n = gFrameCount;
        int mid = gMapId > 0 ? gMapId : 1;
        if (ok) rtAlert(@"REC", [NSString stringWithFormat:@"Đã lưu %u frame (map %d)", n, mid]);
        else    rtAlert(@"REC", @"Không có frame nào để lưu");
    } else if (gRecArmed) {
        gAutoArmed = NO;
        gPlaying = NO;
        if (gPlayerVehicle) {
            gRecording = YES;
            gGoTime = rtNow();
            gFrameCount = 0;
            if (gFrames) { free(gFrames); gFrames = NULL; }
            rtLog("REC manual start mid-race/replay map=%d", gMapId);
        } else {
            rtLog("REC armed");
        }
    }
    [self refresh];
}

- (void)tapAuto {
    gAutoArmed = !gAutoArmed;
    if (gAutoArmed) { gRecArmed = NO; gRecording = NO; }
    else { gPlaying = NO; rtWriteKeyFlags(0); }
    rtLog("AUTO armed=%d", (int)gAutoArmed);
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
