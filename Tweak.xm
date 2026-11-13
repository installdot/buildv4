// NetSpy — log (and optionally block) every network packet of haitacdaichien.
// Target: Unity IL2CPP iOS arm64. Transport is UnityEngine.Networking -> libcurl,
// so there is no NSURLSession to hook; everything goes through il2cpp.
//
// EVERY il2cpp method takes a trailing `const MethodInfo*`. Instance methods are
// (this, ..., method); statics are (..., method). Hooks MUST forward that register
// untouched or the callee reads garbage. Arities below match that exactly.
//
// Output in the app sandbox, Documents/:
//   netspy.log     one line per event
//   netspy.block   optional CSV of serviceIds to drop, e.g. 361,321

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ---------------------------------------------------------------------------
// il2cpp objects
// ---------------------------------------------------------------------------
typedef struct Il2CppString {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[];
} Il2CppString;

typedef struct Il2CppArray {
    void *klass;
    void *monitor;
    void *bounds;
    uint64_t max_length;
    uint8_t data[];
} Il2CppArray;

// ---------------------------------------------------------------------------
// log
// ---------------------------------------------------------------------------
static NSString *gLogPath;
static FILE *gFile;
static NSLock *gLock;

static NSString *DocsPath(void) {
    static NSString *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *a = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        d = a.count ? a[0] : @"/tmp";
    });
    return d;
}

static void LogLine(NSString *fmt, ...) {
    if (!gLock) {
        gLock = [NSLock new];
        gLogPath = [DocsPath() stringByAppendingPathComponent:@"netspy.log"];
    }
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [df stringFromDate:[NSDate date]], body];

    [gLock lock];
    if (!gFile) gFile = fopen(gLogPath.UTF8String, "a");
    if (gFile) { fputs(line.UTF8String, gFile); fflush(gFile); }
    [gLock unlock];
}

static NSString *HexOf(const uint8_t *p, NSUInteger n) {
    if (!p || !n) return @"";
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

static NSString *DumpArray(Il2CppArray *a, NSString *label) {
    if (!a) return [NSString stringWithFormat:@"%@=(null)", label];
    uint64_t n = a->max_length;
    if (!n) return [NSString stringWithFormat:@"%@=(empty)", label];
    if (n <= 4096) return [NSString stringWithFormat:@"%@[%llu]=%@", label, n, HexOf(a->data, (NSUInteger)n)];
    return [NSString stringWithFormat:@"%@[%llu]=%@...", label, n, HexOf(a->data, 512)];
}

static NSString *DumpStr(Il2CppString *s) {
    if (!s) return @"(null)";
    int32_t n = s->length;
    if (n < 0 || n > 4096) return @"(bad)";
    return [[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)n];
}

static BOOL ServiceBlocked(int32_t svc) {
    static NSMutableSet *cache;
    static time_t at;
    time_t now = time(NULL);
    if (!cache || now - at > 2) {
        cache = [NSMutableSet new];
        at = now;
        NSString *p = [DocsPath() stringByAppendingPathComponent:@"netspy.block"];
        NSString *s = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
        for (NSString *t in [s componentsSeparatedByCharactersInSet:
                 [NSCharacterSet characterSetWithCharactersInString:@", \n\r\t"]]) {
            if (t.length) [cache addObject:@(t.integerValue)];
        }
    }
    return [cache containsObject:@(svc)];
}

// ---------------------------------------------------------------------------
// base address: mach_header + slide (__TEXT vmaddr == 0 in this build)
// ---------------------------------------------------------------------------
static uintptr_t UfBase(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) {
            const struct mach_header *mh = _dyld_get_image_header(i);
            return (uintptr_t)mh + (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// RVAs
// ---------------------------------------------------------------------------
// layer A — UnityEngine.Networking
#define RVA_UWR_SetUrl          0x379D770
#define RVA_UWR_Get             0x379EE10
#define RVA_UWR_Put             0x379EEF0
#define RVA_UWR_SendWebRequest  0x379CAD4
#define RVA_DH_get_data         0x379AEEC
// layer B — transport
#define RVA_SendProtoPackage    0x151C554
#define RVA_Selialize           0x151C764
#define RVA_SendPackage         0x151CE4C
#define RVA_SendHttpRequest     0x151C0AC
#define RVA_ParsePbObject       0x19B4BF8
// layer C — semantics
#define RVA_LoginByAccount      0x1505960
#define RVA_LoginGame           0x1507980
#define RVA_PetRequestList      0x14FD040
#define RVA_PetActivate         0x14FC68C
#define RVA_PetUpgradeLevel     0x1501A3C
#define RVA_PetEvolve           0x1501B50
#define RVA_PetUpgradeSkill     0x1500B18
#define RVA_PetRebirth          0x1503A5C
#define RVA_PetUpgradeRuin      0x1502AF4
#define RVA_LuckyRotate         0x150FDBC
#define RVA_LuckyBuyChip        0x150FCAC
#define RVA_ItemShardSummon     0x150D4B4

// ===========================================================================
// layer A
// ===========================================================================
static void  (*oSetUrl)(void *, void *, void *);
static void *(*oGet)(void *, void *);
static void *(*oPut)(void *, void *, void *);
static void *(*oSend)(void *, void *);
static void *(*oDHData)(void *, void *);

static void HkSetUrl(void *self, void *url, void *m) {
    LogLine(@"    url -> %@", DumpStr((Il2CppString *)url));
    if (oSetUrl) oSetUrl(self, url, m);
}

static void *HkGet(void *uri, void *m) {
    void *r = oGet ? oGet(uri, m) : 0;
    LogLine(@"REQ GET %@  req=%p", DumpStr((Il2CppString *)uri), r);
    return r;
}

static void *HkPut(void *uri, void *body, void *m) {
    void *r = oPut ? oPut(uri, body, m) : 0;
    LogLine(@"REQ PUT %@  req=%p  %@", DumpStr((Il2CppString *)uri), r,
            DumpArray((Il2CppArray *)body, @"upload"));
    return r;
}

static void *HkSend(void *self, void *m) {
    LogLine(@"REQ send req=%p", self);
    return oSend ? oSend(self, m) : 0;
}

static void *HkDHData(void *self, void *m) {
    void *d = oDHData ? oDHData(self, m) : 0;
    LogLine(@"RESP %@", DumpArray((Il2CppArray *)d, @"body"));
    return d;
}

// ===========================================================================
// layer B
// ===========================================================================
static void  (*oProto)(void *, int32_t, void *, void *);
static void *(*oSer)(void *, void *, void *);
static void  (*oPkg)(void *, void *, void *);
static void  (*oHttp)(void *, int32_t, void *, void *, void *);
static void *(*oParse)(void *, void *);

static void HkProto(void *self, int32_t svc, void *obj, void *m) {
    if (ServiceBlocked(svc)) { LogLine(@"C2S svc=%d  *** BLOCKED ***", svc); return; }
    LogLine(@"C2S svc=%d obj=%p", svc, obj);
    if (oProto) oProto(self, svc, obj, m);
}

static void *HkSer(void *self, void *obj, void *m) {
    void *b = oSer ? oSer(self, obj, m) : 0;
    LogLine(@"    %@", DumpArray((Il2CppArray *)b, @"payload"));
    return b;
}

static void HkPkg(void *self, void *req, void *m) {
    LogLine(@"SEND RequestData=%p", req);
    if (oPkg) oPkg(self, req, m);
}

static void HkHttp(void *self, int32_t svc, void *url, void *params, void *m) {
    if (ServiceBlocked(svc)) {
        LogLine(@"C2S HTTP svc=%d *** BLOCKED *** url=%@", svc, DumpStr((Il2CppString *)url));
        return;
    }
    LogLine(@"C2S HTTP svc=%d url=%@", svc, DumpStr((Il2CppString *)url));
    if (oHttp) oHttp(self, svc, url, params, m);
}

static void *HkParse(void *data, void *m) {
    void *out = oParse ? oParse(data, m) : 0;
    LogLine(@"S2C %@", DumpArray((Il2CppArray *)data, @"in"));
    return out;
}

// ===========================================================================
// layer C
// ===========================================================================
static void (*oLoginAcc)(void *, void *, void *, void *);
static void (*oLoginGame)(void *, int32_t, void *, void *);
static void (*oPetList)(void *, void *);
static void (*oPetAct)(void *, int32_t, void *);
static void (*oPetLvl)(void *, int32_t, void *);
static void (*oPetEvo)(void *, int32_t, void *);
static void (*oPetSkl)(void *, int32_t, int32_t, void *);
static void (*oPetReb)(void *, int32_t, void *);
static void (*oPetRuin)(void *, int32_t, int32_t, void *);
static void (*oLuckyRot)(void *, int32_t, void *);
static void (*oLuckyChip)(void *, int32_t, void *);
static void (*oShard)(void *, int32_t, int32_t, int32_t, void *);

static void HkLoginAcc(void *s, void *u, void *p, void *m) {
    LogLine(@"LOGIN user=%@ pass=%@", DumpStr((Il2CppString *)u), DumpStr((Il2CppString *)p));
    if (oLoginAcc) oLoginAcc(s, u, p, m);
}
static void HkLoginGame(void *s, int32_t sid, void *u, void *m) {
    LogLine(@"LOGIN_GAME serverId=%d user=%@", sid, DumpStr((Il2CppString *)u));
    if (oLoginGame) oLoginGame(s, sid, u, m);
}
static void HkPetList(void *s, void *m) { LogLine(@"PET 360 list"); if (oPetList) oPetList(s, m); }
static void HkPetAct(void *s, int32_t id, void *m) { LogLine(@"PET 361 activate id=%d", id); if (oPetAct) oPetAct(s, id, m); }
static void HkPetLvl(void *s, int32_t id, void *m) { LogLine(@"PET 362 level id=%d", id); if (oPetLvl) oPetLvl(s, id, m); }
static void HkPetEvo(void *s, int32_t id, void *m) { LogLine(@"PET 363 evolve id=%d", id); if (oPetEvo) oPetEvo(s, id, m); }
static void HkPetSkl(void *s, int32_t id, int32_t i, void *m) { LogLine(@"PET 364 skill id=%d idx=%d", id, i); if (oPetSkl) oPetSkl(s, id, i, m); }
static void HkPetReb(void *s, int32_t id, void *m) { LogLine(@"PET 365 rebirth id=%d", id); if (oPetReb) oPetReb(s, id, m); }
static void HkPetRuin(void *s, int32_t id, int32_t i, void *m) { LogLine(@"PET 366 ruin id=%d idx=%d", id, i); if (oPetRuin) oPetRuin(s, id, i, m); }
static void HkLuckyRot(void *s, int32_t t, void *m) { LogLine(@"LUCKY 321 spin type=%d", t); if (oLuckyRot) oLuckyRot(s, t, m); }
static void HkLuckyChip(void *s, int32_t n, void *m) { LogLine(@"LUCKY 323 buychip n=%d", n); if (oLuckyChip) oLuckyChip(s, n, m); }
static void HkShard(void *s, int32_t ty, int32_t ik, int32_t n, void *m) {
    LogLine(@"ITEM 254 shard type=%d item=%d n=%d", ty, ik, n);
    if (oShard) oShard(s, ty, ik, n, m);
}

// ===========================================================================
// install
// ===========================================================================
static void Install(void) {
    static BOOL done;
    if (done) return;
    uintptr_t b = UfBase();
    if (!b) return;
    done = YES;
    LogLine(@"=== hooks @ base=0x%lx ===", (unsigned long)b);

#define H(rva, fn, orig) MSHookFunction((void *)(b + (rva)), (void *)(fn), (void **)&(orig))
    H(RVA_UWR_SetUrl,          HkSetUrl,     oSetUrl);
    H(RVA_UWR_Get,             HkGet,        oGet);
    H(RVA_UWR_Put,             HkPut,        oPut);
    H(RVA_UWR_SendWebRequest,  HkSend,       oSend);
    H(RVA_DH_get_data,         HkDHData,     oDHData);
    H(RVA_SendProtoPackage,    HkProto,      oProto);
    H(RVA_Selialize,           HkSer,        oSer);
    H(RVA_SendPackage,         HkPkg,        oPkg);
    H(RVA_SendHttpRequest,     HkHttp,       oHttp);
    H(RVA_ParsePbObject,       HkParse,      oParse);
    H(RVA_LoginByAccount,      HkLoginAcc,   oLoginAcc);
    H(RVA_LoginGame,           HkLoginGame,  oLoginGame);
    H(RVA_PetRequestList,      HkPetList,    oPetList);
    H(RVA_PetActivate,         HkPetAct,     oPetAct);
    H(RVA_PetUpgradeLevel,     HkPetLvl,     oPetLvl);
    H(RVA_PetEvolve,           HkPetEvo,     oPetEvo);
    H(RVA_PetUpgradeSkill,     HkPetSkl,     oPetSkl);
    H(RVA_PetRebirth,          HkPetReb,     oPetReb);
    H(RVA_PetUpgradeRuin,      HkPetRuin,    oPetRuin);
    H(RVA_LuckyRotate,         HkLuckyRot,   oLuckyRot);
    H(RVA_LuckyBuyChip,        HkLuckyChip,  oLuckyChip);
    H(RVA_ItemShardSummon,     HkShard,      oShard);
#undef H
    LogLine(@"=== hooks installed ===");
}

static void OnImage(const struct mach_header *mh, intptr_t slide) { Install(); }

%ctor {
    @autoreleasepool {
        LogLine(@"===== NetSpy start, docs=%@ =====", DocsPath());
        Install();
        _dyld_register_func_for_add_image(OnImage);
    }
}
