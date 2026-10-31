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
    if (m < 0) return;
    size_t total = (size_t)n + (size_t)m;
    if (total + 1 < sizeof buf) buf[total++] = '\n';
    ssize_t w = write(gLogFd, buf, total); (void)w;
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

static BOOL rtInitIl2Cpp(void) {
    if (il2cpp_domain_get) return YES;
    void *h = dlopen("Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW);
    if (!h) h = RTLD_DEFAULT;
    *(void **)&il2cpp_domain_get                 = dlsym(h, "il2cpp_domain_get");
    *(void **)&il2cpp_domain_get_assemblies      = dlsym(h, "il2cpp_domain_get_assemblies");
    *(void **)&il2cpp_assembly_get_image         = dlsym(h, "il2cpp_assembly_get_image");
    *(void **)&il2cpp_class_from_name            = dlsym(h, "il2cpp_class_from_name");
    *(void **)&il2cpp_class_get_method_from_name = dlsym(h, "il2cpp_class_get_method_from_name");
    BOOL ok = il2cpp_domain_get && il2cpp_domain_get_assemblies && il2cpp_assembly_get_image
           && il2cpp_class_from_name && il2cpp_class_get_method_from_name;
    rtLog("il2cpp api: %s", ok ? "OK" : "MISSING");
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
    if (orig == rep) return orig;

    const uint16_t slot = *(const uint16_t *)((const char *)m + 0x58);
    *(void **)((char *)m + 0) = rep;

    BOOL vt = NO;
    if (slot < 512) {
        VirtualInvokeData *e = (VirtualInvokeData *)((char *)k + 328) + slot;
        if (e->methodPtr == orig) { e->methodPtr = rep; vt = YES; }
    }
    rtLog("il2cpp: HOOK %s::%s slot=%u vtable=%s", cls, mth, (unsigned)slot, vt ? "OK" : "none");
    return orig;
}

#pragma mark - Offsets (đã kiểm chứng)

enum {
    kOffVehicleActorType = 0x14,   // NssVehicle.mActorType
    kOffVehicleDyn       = 0x20,   // NssVehicle.mDynamicVehicle

    kOffDynACC           = 0x28,   // DynamicVehicle.mACC

    kOffMotionSteerData  = 0x10,   // NssPhyVehicleMotionCtrlHelper.mSteeringData
    kOffMotionVehicle    = 0x18,   // .mVehicle
    kOffMotionPhyCtrl    = 0x20,   // .mVehiclePhyCtrl
    kOffMotionDynVehicle = 0x28,   // .mDynamicVehicle
    kOffMotionDriving    = 0x38,   // .mDrivingCtrl

    kOffPhySimOutput     = 0x28,   // NssPhyVehicleCtrl.mSimulateOutput

    kOffSimChassisPos    = 0x64,   // NssVehicleSimOutput.mChassisPosition
    kOffSimChassisRot    = 0x70,   // NssVehicleSimOutput.mChassisRotation

    kOffSteerForward     = 0x10,   // NssSteeringData.mForward
    kOffSteerBraking     = 0x14,   // .mBrakingState
    kOffSteerHandbrake   = 0x18,   // .mIsHandbrake
    kOffSteerLeft        = 0x1C,   // .mSteeringLeft

    kOffDrvThrottle      = 0x3C,   // NssPhyVehicleDrivingCtrl.mThrottle
    kOffDrvSteering      = 0x40,   // .mSteering

    kOffCpMapId          = 0x14,   // CheckPointConfig.MapId
    kOffCpCurveLength    = 0x2C,   // CheckPointConfig.MainCurveLength

    kOffInputKeyData     = 0xA8,   // InputModule.mInputKeyData
    kOffKeyDataFlags     = 0x10,   // InputKeyData.KeyFlags
};

#pragma mark - Frame format

#define RC_MAGIC "RKR1"
#define RC_MAX_FRAMES 21600
#define RC_SAMPLE_DT  0.008f

typedef struct {
    float t;
    float px, py, pz;
    float qx, qy, qz, qw;
    float steer;
    uint8_t keys;
    uint8_t flags;
    uint16_t pad;
} RCFrame;                            // 40 byte

typedef struct {
    char     magic[4];
    uint32_t ver;
    uint32_t count;
    float    trackLen;
    int32_t  mapId;
    uint32_t frameSize;
} RCHeader;                           // 24 byte

static RCFrame *gFrames;
static uint32_t gFrameCount;
static int      gMapId;
static float    gTrackLen;
static double   gGoTime;

static BOOL gRecArmed, gAutoArmed, gRecording, gPlaying;
static void *gPlayerVehicle;
static void *gInputModule;
static int   gKeyMask;

#pragma mark - Storage

static NSString *rtDir(void) {
    NSArray *p = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *d = [(p.firstObject ?: NSTemporaryDirectory()) stringByAppendingPathComponent:@"RaceKit"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}

static NSString *rtPathForTrack(void) {
    if (gMapId <= 0) return nil;
    return [rtDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"rec_map%d.rk", gMapId]];
}

static BOOL rtSaveRecord(void) {
    if (!gFrameCount || gMapId <= 0) return NO;
    NSString *path = rtPathForTrack();
    if (!path) return NO;
    FILE *f = fopen(path.fileSystemRepresentation, "wb");
    if (!f) { rtLog("save: fopen fail"); return NO; }

    RCHeader h;
    memcpy(h.magic, RC_MAGIC, 4);
    h.ver = 1; h.count = gFrameCount;
    h.trackLen = gTrackLen; h.mapId = gMapId; h.frameSize = sizeof(RCFrame);
    fwrite(&h, sizeof h, 1, f);
    fwrite(gFrames, sizeof(RCFrame), gFrameCount, f);
    fclose(f);
    rtLog("save: %u frames (%.2fs) map=%d -> %s", gFrameCount,
          gFrames[gFrameCount - 1].t, gMapId, path.UTF8String);
    return YES;
}

static BOOL rtLoadRecord(void) {
    gFrameCount = 0;
    if (gFrames) { free(gFrames); gFrames = NULL; }
    NSString *path = rtPathForTrack();
    if (!path) return NO;
    FILE *f = fopen(path.fileSystemRepresentation, "rb");
    if (!f) return NO;

    RCHeader h;
    if (fread(&h, sizeof h, 1, f) != 1 || memcmp(h.magic, RC_MAGIC, 4)
        || h.frameSize != sizeof(RCFrame) || !h.count) {
        fclose(f); return NO;
    }
    if (h.count > RC_MAX_FRAMES) h.count = RC_MAX_FRAMES;

    gFrames = (RCFrame *)malloc(sizeof(RCFrame) * h.count);
    if (!gFrames) { fclose(f); return NO; }
    gFrameCount = (uint32_t)fread(gFrames, sizeof(RCFrame), h.count, f);
    fclose(f);
    if (!gFrameCount) { free(gFrames); gFrames = NULL; return NO; }
    rtLog("load: %u frames (%.2fs) map=%d len=%.1f", gFrameCount,
          gFrames[gFrameCount - 1].t, h.mapId, h.trackLen);
    return YES;
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

static void rtRecordTick(void *steerData, void *sim, double now) {
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
    fr.steer = *(float *)((char *)steerData + kOffSteerLeft);

    int braking = *(int *)((char *)steerData + kOffSteerBraking);
    BOOL hb = *(bool *)((char *)steerData + kOffSteerHandbrake);
    fr.flags = (uint8_t)((braking ? 1 : 0) | (hb ? 2 : 0));
    fr.keys  = (uint8_t)(rtReadKeyFlags() & 0xff);

    gFrames[gFrameCount++] = fr;
}

static void rtPlaybackTick(void *steerData, void *drivingCtrl, void *sim, double now) {
    if (!gFrames || !gFrameCount) return;

    float t = (float)(now - gGoTime);
    if (t < 0.f) return;
    if (t >= gFrames[gFrameCount - 1].t) { rtWriteKeyFlags(0); return; }

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

    float steer = a->steer + (b->steer - a->steer) * al;

    // Bù sai lệch quỹ đạo: cross(forward, toTarget)
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
    float tx = a->px + (b->px - a->px) * al;
    float tz = a->pz + (b->pz - a->pz) * al;

    float dx = tx - cx, dz = tz - cz;
    float dl = sqrtf(dx * dx + dz * dz);
    if (dl > 1e-3f) { dx /= dl; dz /= dl; }

    float corr = ((dx * fz) - (dz * fx)) * 0.55f;
    if (corr >  0.40f) corr =  0.40f;
    if (corr < -0.40f) corr = -0.40f;

    steer += corr;
    if (steer >  1.f) steer =  1.f;
    if (steer < -1.f) steer = -1.f;

    *(float *)((char *)steerData + kOffSteerLeft) = steer;
    if (rtPtrOk(drivingCtrl)) {
        *(float *)((char *)drivingCtrl + kOffDrvSteering) = steer;
        *(float *)((char *)drivingCtrl + kOffDrvThrottle) = 1.0f;
    }
    *(float *)((char *)steerData + kOffSteerForward) = 1.0f;

    rtWriteKeyFlags(a->keys);
}

#pragma mark - Hooks

static void   (*orig_MotionCtrl_Update)(void *, float, const void *);
static void   (*orig_Input_Update)(void *, float, const void *);
static BOOL   (*orig_GetSteeringValue)(void *, void *, float, float *, float *, const void *);
static void   (*orig_GoImpEnter)(void *, const void *);
static void   (*orig_CheckPointMgr_Init)(void *, void *, bool, bool, const void *);

static void hook_Input_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) gInputModule = self;
    if (orig_Input_Update) orig_Input_Update(self, dt, m);
}

static BOOL hook_GetSteeringValue(void *self, void *carParams, float dt,
                                  float *steerValue, float *steeringTime, const void *m) {
    BOOL r = orig_GetSteeringValue ? orig_GetSteeringValue(self, carParams, dt, steerValue, steeringTime, m) : FALSE;
    if (gPlaying && rtPtrOk(steerValue) && rtPtrOk(self)) {
        void *dyn = *(void **)((char *)self + 0x10);
        void *vhc = rtPtrOk(dyn) ? *(void **)((char *)dyn + 0x10) : NULL;
        if (vhc && vhc == gPlayerVehicle) {
            *steerValue = *(float *)((char *)self + kOffDrvSteering);
            r = TRUE;
        }
    }
    return r;
}

static void hook_GoImpEnter(void *self, const void *m) {
    if (orig_GoImpEnter) orig_GoImpEnter(self, m);
    gGoTime = rtNow();

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
            int mid = gMapId;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *a = [UIAlertController
                    alertControllerWithTitle:@"Đua lập trình"
                    message:[NSString stringWithFormat:@"Chưa có record cho map %d.\nBấm REC rồi chạy 1 vòng để tạo.", mid]
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
                while (vc.presentedViewController) vc = vc.presentedViewController;
                [vc presentViewController:a animated:YES completion:nil];
            });
        }
    } else gPlaying = NO;
}

static void hook_CheckPointMgr_Init(void *self, void *config, bool crc, bool reset, const void *m) {
    if (orig_CheckPointMgr_Init) orig_CheckPointMgr_Init(self, config, crc, reset, m);
    if (rtPtrOk(config)) {
        int mapId = *(int *)((char *)config + kOffCpMapId);
        float len = *(float *)((char *)config + kOffCpCurveLength);
        if (mapId > 0) gMapId = mapId;
        if (len > 1.f) gTrackLen = len;
    }
    rtLog("map init map=%d len=%.2f", gMapId, gTrackLen);
}

static void hook_MotionCtrl_Update(void *self, float dt, const void *m) {
    if (rtPtrOk(self)) {
        void *vehicle = *(void **)((char *)self + kOffMotionVehicle);
        if (rtPtrOk(vehicle) && *(int *)((char *)vehicle + kOffVehicleActorType) == 0) {
            gPlayerVehicle = vehicle;
            void *steerData   = *(void **)((char *)self + kOffMotionSteerData);
            void *phyCtrl     = *(void **)((char *)self + kOffMotionPhyCtrl);
            void *drivingCtrl = *(void **)((char *)self + kOffMotionDriving);
            void *sim = rtPtrOk(phyCtrl) ? *(void **)((char *)phyCtrl + kOffPhySimOutput) : NULL;

            if (rtPtrOk(steerData) && rtPtrOk(sim)) {
                double now = rtNow();
                if (gPlaying)        rtPlaybackTick(steerData, drivingCtrl, sim, now);
                else if (gRecording) rtRecordTick(steerData, sim, now);
            }
        }
    }
    if (orig_MotionCtrl_Update) orig_MotionCtrl_Update(self, dt, m);
}

#pragma mark - UI

@interface RCPanel : NSObject
@property (nonatomic, strong) UIWindow *win;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *bRec;
@property (nonatomic, strong) UIButton *bAuto;
- (void)show;
- (void)refresh;
@end

static RCPanel *gPanel;

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
        self.win = [[UIWindow alloc] initWithFrame:scr];
        self.win.windowLevel = UIWindowLevelAlert + 2;
        self.win.backgroundColor = UIColor.clearColor;
        self.win.rootViewController = [UIViewController new];
        self.win.rootViewController.view.backgroundColor = UIColor.clearColor;

        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(14, scr.size.height * 0.30, 132, 150)];
        host.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.86];
        host.layer.cornerRadius = 12;
        host.layer.borderWidth = 1;
        host.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        [self.win.rootViewController.view addSubview:host];

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
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *a = [UIAlertController
                alertControllerWithTitle:@"REC"
                message:ok ? [NSString stringWithFormat:@"Đã lưu %u frame (map %d)", n, gMapId]
                           : @"Không có frame nào để lưu"
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
            while (vc.presentedViewController) vc = vc.presentedViewController;
            [vc presentViewController:a animated:YES completion:nil];
        });
    } else if (gRecArmed) {
        gAutoArmed = NO;
        rtLog("REC armed");
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
    orig_GetSteeringValue = (BOOL (*)(void *, void *, float, float *, float *, const void *))
        rtHookMethod("", "NssPlayerVehicleDrivingCtrl", "GetSteeringValue", 4, (void *)hook_GetSteeringValue);
    orig_GoImpEnter = (void (*)(void *, const void *))
        rtHookMethod("", "GameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    rtHookMethod("", "RaceKingGameGoState", "ImpEnter", 0, (void *)hook_GoImpEnter);
    orig_CheckPointMgr_Init = (void (*)(void *, void *, bool, bool, const void *))
        rtHookMethod("", "CheckPointMgr", "Init", 3, (void *)hook_CheckPointMgr_Init);
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
