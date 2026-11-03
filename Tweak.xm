// Tweak.xm — ArenaCapture
// Log: <App Sandbox>/Documents/ArenaCapture.log

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <stdarg.h>
#import <limits.h>
#import <unistd.h>
#import <os/lock.h>

#pragma mark - Config

#define OFF_SEND_PACKAGE   0x10BBC74
#define OFF_SELIALIZE      0x10BB67C
#define OFF_UPDATE_RECV    0x10BCA3C
#define OFF_HTTPREQ_CTOR   0x105BB6C

#define LOG_NAME           "ArenaCapture.log"
#define MAX_HEX            8192
#define MAX_LOG_BYTES      (8u * 1024u * 1024u)

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static char  gLogPath[PATH_MAX];
static BOOL  gLogReady = NO;

#pragma mark - il2cpp ABI (arm64)

typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; } Il2CppArrayHdr;
typedef struct { void *klass; void *monitor; int32_t length; uint16_t chars[]; } Il2CppStringHdr;
typedef struct { void *klass; void *monitor; void *items; int32_t size; int32_t version; } Il2CppListHdr;

#pragma mark - Log path (app sandbox Documents)

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

#pragma mark - Logging

static void AFLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSLog(@"[ArenaCap] %@", msg);

    static NSDateFormatter *df; static dispatch_once_t once;
    dispatch_once(&once, ^{ df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss.SSS"; });
    NSString *line = [NSString stringWithFormat:@"%@  %@\n",
                      [df stringFromDate:[NSDate date]], msg];

    os_unfair_lock_lock(&gLock);
    if (!gLogReady) ResolveLogPath();
    RotateIfNeeded();
    FILE *f = fopen(gLogPath, "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
    os_unfair_lock_unlock(&gLock);
}

static NSString *HexStr(const void *p, NSUInteger len, NSUInteger cap) {
    const uint8_t *b = (const uint8_t *)p;
    if (!b || !len) return @"";
    NSUInteger n = MIN(len, cap);
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2 + 40];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", b[i]];
    if (n < len) [s appendFormat:@"... (truncated, total %lu)", (unsigned long)len];
    return s;
}

#pragma mark - il2cpp helpers

static inline int32_t ILListSize(void *list) {
    return list ? ((Il2CppListHdr *)list)->size : 0;
}

static inline void *ILListAt(void *list, int32_t i) {
    if (!list || i < 0) return NULL;
    Il2CppListHdr *l = (Il2CppListHdr *)list;
    if (!l->items || i >= l->size) return NULL;
    return *(void **)((uint8_t *)l->items + 0x20 + (size_t)8 * (size_t)i);
}

static NSString *ILStr(void *s) {
    if (!s) return nil;
    Il2CppStringHdr *h = (Il2CppStringHdr *)s;
    if (h->length < 0 || h->length > 200000) return nil;
    return [[NSString alloc] initWithCharacters:h->chars length:(NSUInteger)h->length];
}

static NSData *ILBytes(void *arr) {
    if (!arr) return nil;
    Il2CppArrayHdr *h = (Il2CppArrayHdr *)arr;
    uintptr_t len = h->max_length;
    if (len > (64u << 20)) return nil;
    return [NSData dataWithBytes:(uint8_t *)arr + 0x20 length:(NSUInteger)len];
}

static const char *ILClassName(void *obj) {
    if (!obj) return "null";
    void *klass = *(void **)obj;
    if (!klass) return "?";
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
        if (!act) { AFLog(@"[%s][%d] <null>", tag, i); continue; }

        int32_t aid  = *(int32_t *)((uint8_t *)act + 0x10);   // PbAction.actionId
        void   *data = *(void **)((uint8_t *)act + 0x18);     // PbAction.data
        NSData *d    = ILBytes(data);

        AFLog(@"[%s][%d] id=%d (%s) len=%lu", tag, i, aid, ActionName(aid),
              (unsigned long)d.length);
        if (d.length) AFLog(@"[%s][%d] %d.hex=%@", tag, i, aid, HexStr(d.bytes, d.length, MAX_HEX));
    }
}

#pragma mark - Unity il2cpp hooks

static void (*orig_SendPackage)(void *, void *, void *);
static void *(*orig_Selialize)(void *, void *, void *);
static void (*orig_UpdateRecv)(void *, void *);
static void (*orig_HttpReqCtor)(void *, int32_t, void *, void *);

static void Hook_SendPackage(void *self, void *request, void *method) {
    @autoreleasepool {
        if (request) {
            NSString *sess = ILStr(*(void **)((uint8_t *)request + 0x10));
            void *actions  = *(void **)((uint8_t *)request + 0x18);
            AFLog(@"========== [REQ] SendPackage class=%s session=%@ ==========",
                  ILClassName(request), sess ?: @"(nil)");
            DumpActionList("REQ", actions);
        }
    }
    orig_SendPackage(self, request, method);
}

static void *Hook_Selialize(void *self, void *data, void *method) {
    void *ret = orig_Selialize(self, data, method);
    @autoreleasepool {
        NSData *d = ILBytes(ret);
        AFLog(@"[SER] class=%s retlen=%lu", ILClassName(data), (unsigned long)d.length);
        if (d.length) AFLog(@"[SER] hex=%@", HexStr(d.bytes, d.length, MAX_HEX));
    }
    return ret;
}

static void Hook_UpdateRecv(void *self, void *method) {
    @autoreleasepool {
        void *recv = self ? *(void **)((uint8_t *)self + 0x38) : NULL;
        int32_t n = ILListSize(recv);
        if (n > 0) {
            AFLog(@"========== [RESP] %d action(s) ==========", n);
            DumpActionList("RESP", recv);
        }
    }
    orig_UpdateRecv(self, method);
}

static void Hook_HttpReqCtor(void *self, int32_t serviceId, void *url, void *method) {
    @autoreleasepool {
        AFLog(@"[REQ-LINE] serviceId=%d (%s) url=%@",
              serviceId, ActionName(serviceId), ILStr(url) ?: @"(nil)");
    }
    orig_HttpReqCtor(self, serviceId, url, method);
}

#pragma mark - ObjC per-class orig IMP map (chống đệ quy khi hook kế thừa)

static NSMutableDictionary<NSString *, NSValue *> *gOrigIMPs;
static os_unfair_lock gImpLock = OS_UNFAIR_LOCK_INIT;

static NSString *ImpKey(Class c, SEL s) {
    return [NSString stringWithFormat:@"%s|%s", class_getName(c), sel_getName(s)];
}

static void StoreOrig(Class c, SEL s, IMP imp) {
    if (!c || !s || !imp) return;
    NSValue *v = [NSValue valueWithPointer:(const void *)imp];
    os_unfair_lock_lock(&gImpLock);
    gOrigIMPs[ImpKey(c, s)] = v;
    os_unfair_lock_unlock(&gImpLock);
}

static IMP LookupOrig(id self, SEL s) {
    os_unfair_lock_lock(&gImpLock);
    IMP found = NULL;
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSValue *v = gOrigIMPs[ImpKey(c, s)];
        if (v) { found = (IMP)v.pointerValue; break; }
    }
    os_unfair_lock_unlock(&gImpLock);
    return found;
}

static BOOL ImplementsDirectly(Class c, SEL s) {
    unsigned int n = 0;
    Method *ms = class_copyMethodList(c, &n);
    BOOL found = NO;
    for (unsigned int i = 0; i < n; i++) {
        if (sel_isEqual(method_getName(ms[i]), s)) { found = YES; break; }
    }
    if (ms) free(ms);
    return found;
}

// Gọi IMP gốc an toàn: nếu chưa hook class này thì dùng class_getMethodImplementation
#define CALL_ORIG(self, cmd, ...) ({                                      \
    IMP _i = LookupOrig((self), (cmd));                                   \
    if (!_i) _i = class_getMethodImplementation(object_getClass(self), (cmd)); \
    _i; })

#pragma mark - NSURLSession send side

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

static NSURLSessionDataTask *hook_dtReq(id self, SEL _cmd, NSURLRequest *req) {
    @autoreleasepool { DumpURLRequest(@"HTTP-REQ", req); }
    typedef NSURLSessionDataTask *(*Fn)(id, SEL, NSURLRequest *);
    return ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, req);
}

static NSURLSessionDataTask *hook_dtReqCb(id self, SEL _cmd, NSURLRequest *req,
                                          void (^h)(NSData *, NSURLResponse *, NSError *)) {
    @autoreleasepool { DumpURLRequest(@"HTTP-REQ", req); }
    typedef NSURLSessionDataTask *(*Fn)(id, SEL, NSURLRequest *,
                                        void (^)(NSData *, NSURLResponse *, NSError *));
    return ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, req, h);
}

static NSURLSessionUploadTask *hook_upData(id self, SEL _cmd, NSURLRequest *req, NSData *body) {
    @autoreleasepool {
        DumpURLRequest(@"HTTP-REQ", req);
        AFLog(@"[HTTP-REQ] uploadFromData=%lu bytes", (unsigned long)body.length);
        if (body.length) AFLog(@"[HTTP-REQ] upload.hex=%@", HexStr(body.bytes, body.length, MAX_HEX));
    }
    typedef NSURLSessionUploadTask *(*Fn)(id, SEL, NSURLRequest *, NSData *);
    return ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, req, body);
}

static NSURLSessionUploadTask *hook_upFile(id self, SEL _cmd, NSURLRequest *req, NSURL *file) {
    @autoreleasepool {
        DumpURLRequest(@"HTTP-REQ", req);
        AFLog(@"[HTTP-REQ] uploadFromFile=%@", file.path);
        NSData *d = [NSData dataWithContentsOfURL:file];
        if (d.length) AFLog(@"[HTTP-REQ] upload.hex=%@", HexStr(d.bytes, d.length, MAX_HEX));
    }
    typedef NSURLSessionUploadTask *(*Fn)(id, SEL, NSURLRequest *, NSURL *);
    return ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, req, file);
}

static void HookOneClass(Class c, SEL s, IMP hook) {
    if (!c || !s) return;
    if (!ImplementsDirectly(c, s)) return;
    IMP old = NULL;
    if (MSHookMessageEx(c, s, hook, &old) == 0 && old) StoreOrig(c, s, old);
}

static void HookNSURLSessionSend(void) {
    SEL sels[4] = {
        @selector(dataTaskWithRequest:),
        @selector(dataTaskWithRequest:completionHandler:),
        @selector(uploadTaskWithRequest:fromData:),
        @selector(uploadTaskWithRequest:fromFile:),
    };
    IMP hooks[4] = { (IMP)hook_dtReq, (IMP)hook_dtReqCb, (IMP)hook_upData, (IMP)hook_upFile };

    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"NSURLSession"];
    if (objc_getClass("UnityNSURLSession")) [names addObject:@"UnityNSURLSession"];

    for (NSString *n in names) {
        Class c = objc_getClass(n.UTF8String);
        if (!c) continue;
        for (int i = 0; i < 4; i++) HookOneClass(c, sels[i], hooks[i]);
    }
}

#pragma mark - NSURLSession delegate (chỉ class tự implement)

static NSMutableDictionary<NSNumber *, NSMutableData *> *gBodies;

static void hook_didRecvData(id self, SEL _cmd, NSURLSession *s,
                             NSURLSessionDataTask *task, NSData *data) {
    if (data.length) {
        @synchronized (gBodies) {
            NSMutableData *buf = gBodies[@(task.taskIdentifier)];
            if (!buf) { buf = [NSMutableData data]; gBodies[@(task.taskIdentifier)] = buf; }
            [buf appendData:data];
        }
    }
    typedef void (*Fn)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *);
    ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, s, task, data);
}

static void hook_didRecvResp(id self, SEL _cmd, NSURLSession *s,
                             NSURLSessionDataTask *task, NSURLResponse *resp,
                             void (^completion)(NSInteger)) {
    @autoreleasepool {
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
            AFLog(@"[HTTP-RESP] status=%ld url=%@", (long)hr.statusCode,
                  hr.URL.absoluteString ?: @"?");
            AFLog(@"[HTTP-RESP] headers=%@", hr.allHeaderFields ?: @{});
        }
    }
    typedef void (*Fn)(id, SEL, NSURLSession *, NSURLSessionDataTask *,
                       NSURLResponse *, void (^)(NSInteger));
    ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, s, task, resp, completion);
}

static void hook_didComplete(id self, SEL _cmd, NSURLSession *s,
                             NSURLSessionTask *task, NSError *err) {
    NSMutableData *buf = nil;
    @synchronized (gBodies) {
        buf = gBodies[@(task.taskIdentifier)];
        [gBodies removeObjectForKey:@(task.taskIdentifier)];
    }
    @autoreleasepool {
        long status = 0;
        if ([task.response isKindOfClass:[NSHTTPURLResponse class]])
            status = (long)((NSHTTPURLResponse *)task.response).statusCode;

        AFLog(@"[HTTP-RESP] id=%lu status=%ld len=%lu err=%@",
              (unsigned long)task.taskIdentifier, status,
              (unsigned long)buf.length, err ?: @"nil");
        if (buf.length) AFLog(@"[HTTP-RESP] body.hex=%@", HexStr(buf.bytes, buf.length, MAX_HEX));
    }
    typedef void (*Fn)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *);
    ((Fn)CALL_ORIG(self, _cmd))(self, _cmd, s, task, err);
}

static void HookSessionDelegates(void) {
    SEL sels[3] = {
        @selector(URLSession:dataTask:didReceiveData:),
        @selector(URLSession:dataTask:didReceiveResponse:completionHandler:),
        @selector(URLSession:task:didCompleteWithError:),
    };
    IMP hooks[3] = { (IMP)hook_didRecvData, (IMP)hook_didRecvResp, (IMP)hook_didComplete };

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return;
    count = objc_getClassList(classes, count);

    int hooked = 0;
    for (int i = 0; i < count; i++) {
        Class c = classes[i];
        for (int k = 0; k < 3; k++) {
            if (ImplementsDirectly(c, sels[k])) {
                HookOneClass(c, sels[k], hooks[k]);
                hooked++;
            }
        }
    }
    free(classes);
    AFLog(@"[INIT] NSURLSession delegate hooks=%d", hooked);
}

#pragma mark - Init

static uintptr_t FindUnityFramework(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework"))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

__attribute__((constructor))
static void ArenaCaptureInit(void) {
    @autoreleasepool {
        gBodies   = [NSMutableDictionary new];
        gOrigIMPs = [NSMutableDictionary new];
        ResolveLogPath();

        uintptr_t base = FindUnityFramework();
        AFLog(@"[INIT] pid=%d log=%s base=0x%lx", getpid(), gLogPath, (unsigned long)base);

        if (base) {
            MSHookFunction((void *)(base + OFF_SEND_PACKAGE), (void *)&Hook_SendPackage,
                           (void **)&orig_SendPackage);
            MSHookFunction((void *)(base + OFF_SELIALIZE), (void *)&Hook_Selialize,
                           (void **)&orig_Selialize);
            MSHookFunction((void *)(base + OFF_UPDATE_RECV), (void *)&Hook_UpdateRecv,
                           (void **)&orig_UpdateRecv);
            MSHookFunction((void *)(base + OFF_HTTPREQ_CTOR), (void *)&Hook_HttpReqCtor,
                           (void **)&orig_HttpReqCtor);
            AFLog(@"[INIT] il2cpp hooks installed");
        } else {
            AFLog(@"[INIT] UnityFramework NOT FOUND");
        }

        HookNSURLSessionSend();
        HookSessionDelegates();
        AFLog(@"[INIT] ready");
    }
}
