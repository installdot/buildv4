// Tweak.xm — ArenaCapture (Crash-proof edition)
// Log: <App Sandbox>/Documents/ArenaCapture.log
//
// 1. il2cpp (UnityFramework):
//    - NetworkController.SendPackage(RequestData) @ 0x10BBC74
//    - NetworkController.Selialize(object)        @ 0x10BB67C
//    - NetworkController.UpdateProcessReceivedPackage() @ 0x10BCA3C
//    - HttpRequestData..ctor(int, string)         @ 0x105BB6C
// 2. NSURLSession:
//    - dataTaskWithRequest: / dataTaskWithRequest:completionHandler:
//    - uploadTaskWithRequest:fromData: / uploadTaskWithRequest:fromFile:
//    - UnityNSURLSession delegate (nếu có)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <stdarg.h>
#import <limits.h>
#import <unistd.h>
#import <os/lock.h>

#pragma mark - RVAs in UnityFramework (arm64, imagebase 0)

#define OFF_SEND_PACKAGE   0x10BBC74
#define OFF_SELIALIZE      0x10BB67C
#define OFF_UPDATE_RECV    0x10BCA3C
#define OFF_HTTPREQ_CTOR   0x105BB6C

#define LOG_NAME           "ArenaCapture.log"
#define MAX_HEX            8192
#define MAX_LOG_BYTES      (8u * 1024u * 1024u)

static os_unfair_lock gFileLock = OS_UNFAIR_LOCK_INIT;
static char gLogPath[PATH_MAX] = {0};
static BOOL gLogReady = NO;

#pragma mark - il2cpp ABI (arm64)

typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; } Il2CppArrayHdr;
typedef struct { void *klass; void *monitor; int32_t length; uint16_t chars[]; } Il2CppStringHdr;
typedef struct { void *klass; void *monitor; void *items; int32_t size; int32_t version; } Il2CppListHdr;

static inline BOOL IsValidPtr(const void *p) {
    return p != NULL && ((uintptr_t)p >= 0x100000000ULL);
}

#pragma mark - Safe Log path (app sandbox Documents)

static void ResolveLogPath(void) {
    @autoreleasepool {
        NSString *dir = nil;
        NSArray<NSString *> *docs =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count) dir = docs.firstObject;
        if (!dir.length) dir = NSTemporaryDirectory();

        NSString *p = [dir stringByAppendingPathComponent:@LOG_NAME];
        const char *fs = [p fileSystemRepresentation];
        if (!fs) fs = "/tmp/ArenaCapture.log";
        strlcpy(gLogPath, fs, sizeof(gLogPath));
        gLogReady = YES;
    }
}

static void RotateIfNeeded(void) {
    if (!gLogReady || gLogPath[0] == '\0') return;
    FILE *f = fopen(gLogPath, "rb");
    if (!f) return;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fclose(f);
    if (sz <= (long)MAX_LOG_BYTES) return;

    char bak[PATH_MAX];
    snprintf(bak, sizeof(bak), "%s.1", gLogPath);
    remove(bak);
    rename(gLogPath, bak);
}

static void AFLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSLog(@"[ArenaCap] %@", msg);

    static NSDateFormatter *df; static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"%@  %@\n",
                      [df stringFromDate:[NSDate date]], msg];

    os_unfair_lock_lock(&gFileLock);
    if (!gLogReady) ResolveLogPath();
    RotateIfNeeded();
    FILE *f = fopen(gLogPath, "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
    os_unfair_lock_unlock(&gFileLock);
}

static NSString *HexStr(const void *p, NSUInteger len, NSUInteger cap) {
    const uint8_t *b = (const uint8_t *)p;
    if (!b || !len) return @"";
    NSUInteger n = MIN(len, cap);
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2 + 40];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", b[i]];
    if (n < len) [s appendFormat:@"... (total %lu)", (unsigned long)len];
    return s;
}

#pragma mark - il2cpp helpers

static inline int32_t ILListSize(void *list) {
    if (!IsValidPtr(list)) return 0;
    Il2CppListHdr *l = (Il2CppListHdr *)list;
    int32_t sz = l->size;
    if (sz <= 0 || sz > 5000) return 0;
    return sz;
}

static inline void *ILListAt(void *list, int32_t i) {
    if (!IsValidPtr(list) || i < 0) return NULL;
    Il2CppListHdr *l = (Il2CppListHdr *)list;
    if (!IsValidPtr(l->items) || i >= l->size) return NULL;
    return *(void **)((uint8_t *)l->items + 0x20 + (size_t)8 * (size_t)i);
}

static NSString *ILStr(void *s) {
    if (!IsValidPtr(s)) return nil;
    Il2CppStringHdr *h = (Il2CppStringHdr *)s;
    int32_t len = h->length;
    if (len <= 0 || len > 200000) return nil;
    return [[NSString alloc] initWithCharacters:h->chars length:(NSUInteger)len];
}

static NSData *ILBytes(void *arr) {
    if (!IsValidPtr(arr)) return nil;
    Il2CppArrayHdr *h = (Il2CppArrayHdr *)arr;
    uintptr_t len = h->max_length;
    if (len == 0 || len > (32u << 20)) return nil;
    return [NSData dataWithBytes:(const uint8_t *)arr + 0x20 length:(NSUInteger)len];
}

static const char *ILClassName(void *obj) {
    if (!IsValidPtr(obj)) return "null";
    void *klass = *(void **)obj;
    if (!IsValidPtr(klass)) return "?";
    const char *n = *(const char **)((uint8_t *)klass + 0x10);
    return n ? n : "?";
}

#pragma mark - Action names

static const char *ActionName(int32_t id) {
    switch (id) {
        case 97:  return "BATTLE_REPLAY";
        case 327: return "ARENA_STATUS";
        case 328: return "CRYSTAL_STATUS";
        case 329: return "CRYSTAL_BATTLE_RECORD";
        case 330: return "CRYSTAL_REVENGE";
        case 331: return "CRYSTAL_SET_DEFENSE";
        case 332: return "CRYSTAL_BUY_TICKET";
        case 333: return "CRYSTAL_SEARCH_RIVAL";
        case 334: return "CRYSTAL_BATTLE";
        case 336: return "TRIAL_STATUS";
        case 337: return "TRIAL_BATTLE_RECORD";
        case 338: return "TRIAL_REVENGE";
        case 339: return "TRIAL_SET_DEFENSE";
        case 340: return "CRYSTAL_TOP_PLAYER";
        case 341: return "TRIAL_SEARCH_RIVAL";
        case 342: return "TRIAL_BATTLE";
        case 343: return "TRIAL_TOP_PLAYER";
        case 345: return "CRYSTAL_NOTIFY_LOG";
        case 346: return "TRIAL_NOTIFY_LOG";
        case 347: return "CRYSTAL_TOP_LAST_SEASON";
        case 348: return "TRIAL_TOP_LAST_SEASON";
        case 550: return "ALLSTARS_STATUS";
        case 551: return "ALLSTARS_BATTLE_RECORD";
        case 552: return "ALLSTARS_SET_DEFENSE";
        case 553: return "ALLSTARS_SEARCH_RIVAL";
        case 554: return "ALLSTARS_BATTLE";
        case 555: return "ALLSTARS_TOP_RANK";
        case 556: return "ALLSTARS_NOTIFY_LOG";
        case 558: return "ALLSTARS_PLAYOFF_PREPARE";
        case 559: return "ALLSTARS_PLAYOFF_RESULT";
        case 560: return "ALLSTARS_BUY_TURN";
        case 561: return "ALLSTARS_TOP_POINT";
        case 562: return "ALLSTARS_BET";
        case 563: return "ALLSTARS_BET_HISTORY";
        case 564: return "ALLSTARS_VOSONG";
        default:  return "-";
    }
}

static void DumpActionList(const char *tag, void *list) {
    int32_t n = ILListSize(list);
    AFLog(@"[%s] actions=%d", tag, n);
    for (int32_t i = 0; i < n; i++) {
        void *act = ILListAt(list, i);
        if (!IsValidPtr(act)) {
            AFLog(@"[%s][%d] <null>", tag, i);
            continue;
        }

        int32_t aid  = *(int32_t *)((uint8_t *)act + 0x10);
        void   *data = *(void **)((uint8_t *)act + 0x18);
        NSData *d    = ILBytes(data);

        AFLog(@"[%s][%d] id=%d (%s) len=%lu", tag, i, aid, ActionName(aid),
              (unsigned long)(d ? d.length : 0));
        if (d && d.length > 0) {
            AFLog(@"[%s][%d] %d.hex=%@", tag, i, aid, HexStr(d.bytes, d.length, MAX_HEX));
        }
    }
}

#pragma mark - il2cpp hooks

static void  (*orig_SendPackage)(void *, void *, void *) = NULL;
static void *(*orig_Selialize)(void *, void *, void *) = NULL;
static void  (*orig_UpdateRecv)(void *, void *) = NULL;
static void  (*orig_HttpReqCtor)(void *, int32_t, void *, void *) = NULL;

static void Hook_SendPackage(void *self, void *request, void *method) {
    @autoreleasepool {
        if (IsValidPtr(request)) {
            NSString *sess = ILStr(*(void **)((uint8_t *)request + 0x10));
            void *actions  = *(void **)((uint8_t *)request + 0x18);
            AFLog(@"========== [REQ] SendPackage class=%s session=%@ ==========",
                  ILClassName(request), sess ?: @"(nil)");
            DumpActionList("REQ", actions);
        }
    }
    if (orig_SendPackage) orig_SendPackage(self, request, method);
}

static void *Hook_Selialize(void *self, void *data, void *method) {
    void *ret = orig_Selialize ? orig_Selialize(self, data, method) : NULL;
    @autoreleasepool {
        if (IsValidPtr(data)) {
            NSData *d = ILBytes(ret);
            AFLog(@"[SER] class=%s retlen=%lu", ILClassName(data), (unsigned long)(d ? d.length : 0));
            if (d && d.length > 0) AFLog(@"[SER] hex=%@", HexStr(d.bytes, d.length, MAX_HEX));
        }
    }
    return ret;
}

static void Hook_UpdateRecv(void *self, void *method) {
    @autoreleasepool {
        if (IsValidPtr(self)) {
            void *recv = *(void **)((uint8_t *)self + 0x38);
            int32_t n = ILListSize(recv);
            if (n > 0) {
                AFLog(@"========== [RESP] %d action(s) ==========", n);
                DumpActionList("RESP", recv);
            }
        }
    }
    if (orig_UpdateRecv) orig_UpdateRecv(self, method);
}

static void Hook_HttpReqCtor(void *self, int32_t serviceId, void *url, void *method) {
    @autoreleasepool {
        AFLog(@"[REQ-LINE] serviceId=%d (%s) url=%@",
              serviceId, ActionName(serviceId), ILStr(url) ?: @"(nil)");
    }
    if (orig_HttpReqCtor) orig_HttpReqCtor(self, serviceId, url, method);
}

#pragma mark - Safe NSURLSession Hooks (No recursion, static orig)

static void DumpURLRequest(NSString *tag, NSURLRequest *r) {
    if (!r) return;
    AFLog(@"[%@] %@ %@", tag, r.HTTPMethod ?: @"?", r.URL.absoluteString ?: @"?");
    AFLog(@"[%@] headers=%@", tag, r.allHTTPHeaderFields ?: @{});
    NSData *body = r.HTTPBody;
    if (body.length) {
        AFLog(@"[%@] body=%lu bytes", tag, (unsigned long)body.length);
        AFLog(@"[%@] body.hex=%@", tag, HexStr(body.bytes, body.length, MAX_HEX));
    } else if (r.HTTPBodyStream) {
        AFLog(@"[%@] body=<stream>", tag);
    } else {
        AFLog(@"[%@] body=(none)", tag);
    }
}

// 1. dataTaskWithRequest:
static NSURLSessionDataTask *(*orig_dtReq)(id, SEL, NSURLRequest *) = NULL;
static NSURLSessionDataTask *hook_dtReq(id self, SEL _cmd, NSURLRequest *req) {
    @autoreleasepool { DumpURLRequest(@"HTTP-REQ", req); }
    return orig_dtReq ? orig_dtReq(self, _cmd, req) : nil;
}

// 2. dataTaskWithRequest:completionHandler:
static NSURLSessionDataTask *(*orig_dtReqCb)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)) = NULL;
static NSURLSessionDataTask *hook_dtReqCb(id self, SEL _cmd, NSURLRequest *req,
                                          void (^h)(NSData *, NSURLResponse *, NSError *)) {
    @autoreleasepool { DumpURLRequest(@"HTTP-REQ", req); }
    if (!h) {
        return orig_dtReqCb ? orig_dtReqCb(self, _cmd, req, nil) : nil;
    }
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        @autoreleasepool {
            long status = 0;
            if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
                status = (long)hr.statusCode;
                AFLog(@"[HTTP-RESP] status=%ld url=%@ headers=%@", status, hr.URL.absoluteString, hr.allHeaderFields);
            }
            AFLog(@"[HTTP-RESP] len=%lu err=%@", (unsigned long)(data ? data.length : 0), err ?: @"nil");
            if (data.length) {
                AFLog(@"[HTTP-RESP] body.hex=%@", HexStr(data.bytes, data.length, MAX_HEX));
            }
        }
        h(data, resp, err);
    };
    return orig_dtReqCb ? orig_dtReqCb(self, _cmd, req, wrapped) : nil;
}

// 3. uploadTaskWithRequest:fromData:
static NSURLSessionUploadTask *(*orig_upData)(id, SEL, NSURLRequest *, NSData *) = NULL;
static NSURLSessionUploadTask *hook_upData(id self, SEL _cmd, NSURLRequest *req, NSData *body) {
    @autoreleasepool {
        DumpURLRequest(@"HTTP-REQ", req);
        AFLog(@"[HTTP-REQ] uploadFromData=%lu bytes", (unsigned long)body.length);
        if (body.length) AFLog(@"[HTTP-REQ] upload.hex=%@", HexStr(body.bytes, body.length, MAX_HEX));
    }
    return orig_upData ? orig_upData(self, _cmd, req, body) : nil;
}

// 4. uploadTaskWithRequest:fromFile:
static NSURLSessionUploadTask *(*orig_upFile)(id, SEL, NSURLRequest *, NSURL *) = NULL;
static NSURLSessionUploadTask *hook_upFile(id self, SEL _cmd, NSURLRequest *req, NSURL *file) {
    @autoreleasepool {
        DumpURLRequest(@"HTTP-REQ", req);
        AFLog(@"[HTTP-REQ] uploadFromFile=%@", file.path);
        if (file) {
            NSData *d = [NSData dataWithContentsOfURL:file];
            if (d.length) AFLog(@"[HTTP-REQ] upload.hex=%@", HexStr(d.bytes, d.length, MAX_HEX));
        }
    }
    return orig_upFile ? orig_upFile(self, _cmd, req, file) : nil;
}

// 5. UnityNSURLSession delegate (nếu Unity có delegate riêng)
static void (*orig_unity_didRecvData)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *) = NULL;
static void hook_unity_didRecvData(id self, SEL _cmd, NSURLSession *s, NSURLSessionDataTask *t, NSData *d) {
    if (d.length) AFLog(@"[UNITY-NET] recv len=%lu", (unsigned long)d.length);
    if (orig_unity_didRecvData) orig_unity_didRecvData(self, _cmd, s, t, d);
}

static void (*orig_unity_didRecvResp)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSURLResponse *, void (^)(NSInteger)) = NULL;
static void hook_unity_didRecvResp(id self, SEL _cmd, NSURLSession *s, NSURLSessionDataTask *t, NSURLResponse *resp, void (^h)(NSInteger)) {
    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
        AFLog(@"[UNITY-NET] resp status=%ld url=%@", (long)hr.statusCode, hr.URL.absoluteString);
    }
    if (orig_unity_didRecvResp) orig_unity_didRecvResp(self, _cmd, s, t, resp, h);
}

static void (*orig_unity_didComplete)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *) = NULL;
static void hook_unity_didComplete(id self, SEL _cmd, NSURLSession *s, NSURLSessionTask *t, NSError *err) {
    if (err) AFLog(@"[UNITY-NET] complete err=%@", err.localizedDescription);
    if (orig_unity_didComplete) orig_unity_didComplete(self, _cmd, s, t, err);
}

static void InstallNSURLSessionHooks(void) {
    // Hook NSURLSession methods
    Class cSession = objc_getClass("NSURLSession");
    if (cSession) {
        MSHookMessageEx(cSession, @selector(dataTaskWithRequest:),
                        (IMP)hook_dtReq, (IMP *)&orig_dtReq);
        MSHookMessageEx(cSession, @selector(dataTaskWithRequest:completionHandler:),
                        (IMP)hook_dtReqCb, (IMP *)&orig_dtReqCb);
        MSHookMessageEx(cSession, @selector(uploadTaskWithRequest:fromData:),
                        (IMP)hook_upData, (IMP *)&orig_upData);
        MSHookMessageEx(cSession, @selector(uploadTaskWithRequest:fromFile:),
                        (IMP)hook_upFile, (IMP *)&orig_upFile);
        AFLog(@"[INIT] NSURLSession hooks installed");
    }

    // Hook UnityNSURLSession nếu có
    Class cUnity = objc_getClass("UnityNSURLSession");
    if (cUnity) {
        MSHookMessageEx(cUnity, @selector(URLSession:dataTask:didReceiveData:),
                        (IMP)hook_unity_didRecvData, (IMP *)&orig_unity_didRecvData);
        MSHookMessageEx(cUnity, @selector(URLSession:dataTask:didReceiveResponse:completionHandler:),
                        (IMP)hook_unity_didRecvResp, (IMP *)&orig_unity_didRecvResp);
        MSHookMessageEx(cUnity, @selector(URLSession:task:didCompleteWithError:),
                        (IMP)hook_unity_didComplete, (IMP *)&orig_unity_didComplete);
        AFLog(@"[INIT] UnityNSURLSession hooks installed");
    }
}

#pragma mark - Dynamic UnityFramework loader detection

static BOOL gHookedUnity = NO;

static void InstallIl2CppHooks(uintptr_t base) {
    if (gHookedUnity || !base) return;
    gHookedUnity = YES;

    AFLog(@"[INIT] Hooking UnityFramework base=0x%lx", (unsigned long)base);

    MSHookFunction((void *)(base + OFF_SEND_PACKAGE), (void *)&Hook_SendPackage, (void **)&orig_SendPackage);
    MSHookFunction((void *)(base + OFF_SELIALIZE),    (void *)&Hook_Selialize,    (void **)&orig_Selialize);
    MSHookFunction((void *)(base + OFF_UPDATE_RECV),   (void *)&Hook_UpdateRecv,   (void **)&orig_UpdateRecv);
    MSHookFunction((void *)(base + OFF_HTTPREQ_CTOR),  (void *)&Hook_HttpReqCtor,  (void **)&orig_HttpReqCtor);

    AFLog(@"[INIT] il2cpp hooks OK");
}

static void OnImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    if (gHookedUnity) return;
    Dl_info info;
    if (dladdr(mh, &info) && info.dli_fname) {
        if (strstr(info.dli_fname, "UnityFramework")) {
            InstallIl2CppHooks((uintptr_t)mh);
        }
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void ArenaCaptureInit(void) {
    @autoreleasepool {
        ResolveLogPath();
        AFLog(@"[INIT] pid=%d log=%s", getpid(), gLogPath);

        // Hook NSURLSession an toàn (không quét class, không đệ quy)
        InstallNSURLSessionHooks();

        // Đăng ký listener: hook UnityFramework dù được load trước hay sau
        _dyld_register_func_for_add_image(OnImageAdded);

        AFLog(@"[INIT] ready");
    }
}
