/*
 * tweak.xm — UDID Call Observer
 * Target UDID : 00008020-000640860179002E
 * Purpose     : Log EVERY place the UDID is accessed, read,
 *               compared, passed, or returned — with full
 *               stack trace, class name, method, and caller.
 * NO spoofing. Observe only.
 *
 * Build : Theos + CydiaSubstrate / libhooker (arm64)
 */

#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach/mach_vm.h>
#include <execinfo.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>

// ─────────────────────────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────────────────────────
#define TARGET_UDID  "00008020-000640860179002E"
#define TARGET_UDID_NS @"00008020-000640860179002E"
#define LOG_TAG      "[UDIDObserver]"

// How many stack frames to capture per hit
#define STACK_DEPTH  20

// ─────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────

// Print a symbolicated stack trace to NSLog
static void logStackTrace(const char *label) {
    void *frames[STACK_DEPTH];
    int count = backtrace(frames, STACK_DEPTH);
    char **symbols = backtrace_symbols(frames, count);

    NSMutableString *trace = [NSMutableString stringWithFormat:
        @"\n%s 📍 %s\n", LOG_TAG, label];

    for (int i = 2; i < count; i++) {   // skip frame 0 (this fn) + frame 1 (hook)
        // Attempt dladdr for better symbol names
        Dl_info info;
        if (dladdr(frames[i], &info) && info.dli_sname) {
            [trace appendFormat:@"  #%02d  %s  +%td  [%s]\n",
                i - 2,
                info.dli_sname,
                (char *)frames[i] - (char *)info.dli_saddr,
                info.dli_fname ? info.dli_fname : "?"];
        } else {
            [trace appendFormat:@"  #%02d  %s\n", i - 2,
                symbols ? symbols[i] : "??"];
        }
    }

    NSLog(@"%@", trace);
    if (symbols) free(symbols);
}

// Convenience: log a hit with context string
static void logHit(NSString *context, id value) {
    NSLog(@"%s ─────────────────────────────────", LOG_TAG);
    NSLog(@"%s 🎯 HIT  context : %@", LOG_TAG, context);
    NSLog(@"%s         value   : %@", LOG_TAG, value);
    NSLog(@"%s         thread  : %@", LOG_TAG, [NSThread currentThread]);
    logStackTrace(context.UTF8String);
}

// ─────────────────────────────────────────────────────────────
//  HOOK 1 — UIDevice (identifierForVendor is the closest
//            modern public API; legacy -uniqueIdentifier removed
//            in iOS 7 but still present in some SDKs via private)
// ─────────────────────────────────────────────────────────────
%hook UIDevice

- (NSUUID *)identifierForVendor {
    NSUUID *result = %orig;
    NSLog(@"%s Hook: [UIDevice identifierForVendor] → %@",
          LOG_TAG, result);
    logStackTrace("UIDevice -identifierForVendor");
    return result;
}

// Private legacy selector still linked by old SDKs
- (NSString *)uniqueIdentifier {
    NSString *result = %orig;
    if ([result isEqualToString:TARGET_UDID_NS]) {
        logHit(@"UIDevice -uniqueIdentifier", result);
    } else {
        NSLog(@"%s Hook: [UIDevice uniqueIdentifier] → %@",
              LOG_TAG, result);
    }
    return result;
}

%end

// ─────────────────────────────────────────────────────────────
//  HOOK 2 — NSString equality checks for the target UDID
// ─────────────────────────────────────────────────────────────
%hook NSString

- (BOOL)isEqualToString:(NSString *)other {
    BOOL result = %orig;
    // Catch either side being the target
    if ([self isKindOfClass:[NSString class]] &&
        ([self isEqual:TARGET_UDID_NS] || [other isEqual:TARGET_UDID_NS])) {
        logHit([NSString stringWithFormat:
            @"NSString -isEqualToString: (self=%@ other=%@)", self, other],
               @(result));
    }
    return result;
}

- (NSComparisonResult)compare:(NSString *)other {
    NSComparisonResult result = %orig;
    if ([self isEqual:TARGET_UDID_NS] || [other isEqual:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSString -compare: (self=%@ other=%@)", self, other],
               @(result));
    }
    return result;
}

- (NSRange)rangeOfString:(NSString *)searchStr {
    NSRange result = %orig;
    if ([searchStr isEqual:TARGET_UDID_NS] ||
        [self isEqual:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSString -rangeOfString: (self=%@ search=%@)", self, searchStr],
               NSStringFromRange(result));
    }
    return result;
}

- (BOOL)containsString:(NSString *)other {
    BOOL result = %orig;
    if ([other isEqual:TARGET_UDID_NS] || [self isEqual:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSString -containsString: (self=%@ other=%@)", self, other],
               @(result));
    }
    return result;
}

%end

// ─────────────────────────────────────────────────────────────
//  HOOK 3 — NSUserDefaults (many apps cache UDID here)
// ─────────────────────────────────────────────────────────────
%hook NSUserDefaults

- (id)objectForKey:(NSString *)key {
    id result = %orig;
    if ([result isKindOfClass:[NSString class]] &&
        [result isEqual:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSUserDefaults -objectForKey: key=%@", key], result);
    }
    return result;
}

- (NSString *)stringForKey:(NSString *)key {
    NSString *result = %orig;
    if ([result isEqual:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSUserDefaults -stringForKey: key=%@", key], result);
    }
    return result;
}

- (void)setObject:(id)value forKey:(NSString *)key {
    if ([value isKindOfClass:[NSString class]] &&
        [value isEqual:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSUserDefaults -setObject:forKey: key=%@", key], value);
    }
    %orig;
}

%end

// ─────────────────────────────────────────────────────────────
//  HOOK 4 — Keychain (SecItem* C functions via MSHookFunction)
//  Apps store UDID in keychain between installs.
// ─────────────────────────────────────────────────────────────
#include <Security/Security.h>

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query,
                                          CFTypeRef *result) {
    OSStatus status = orig_SecItemCopyMatching(query, result);
    if (status == errSecSuccess && result && *result) {
        NSString *str = nil;
        if (CFGetTypeID(*result) == CFStringGetTypeID()) {
            str = (__bridge NSString *)*result;
        } else if (CFGetTypeID(*result) == CFDataGetTypeID()) {
            str = [[NSString alloc]
                initWithData:(__bridge NSData *)*result
                    encoding:NSUTF8StringEncoding];
        }
        if ([str isEqual:TARGET_UDID_NS]) {
            logHit(@"SecItemCopyMatching → returned target UDID", str);
        }
    }
    return status;
}

static OSStatus hook_SecItemAdd(CFDictionaryRef attrs, CFTypeRef *result) {
    // Walk attrs for the target UDID string/data
    NSDictionary *d = (__bridge NSDictionary *)attrs;
    [d enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        NSString *str = nil;
        if ([v isKindOfClass:[NSString class]]) str = v;
        else if ([v isKindOfClass:[NSData class]])
            str = [[NSString alloc] initWithData:v
                                        encoding:NSUTF8StringEncoding];
        if ([str isEqual:TARGET_UDID_NS]) {
            logHit([NSString stringWithFormat:
                @"SecItemAdd storing UDID under key=%@", k], str);
            *stop = YES;
        }
    }];
    return orig_SecItemAdd(attrs, result);
}

// ─────────────────────────────────────────────────────────────
//  HOOK 5 — NSURLRequest / NSURLSession
//  Catch UDID being sent in HTTP headers or body
// ─────────────────────────────────────────────────────────────
%hook NSURLRequest

- (NSDictionary *)allHTTPHeaderFields {
    NSDictionary *headers = %orig;
    [headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        if ([v isKindOfClass:[NSString class]] &&
            [v containsString:TARGET_UDID_NS]) {
            logHit([NSString stringWithFormat:
                @"NSURLRequest header key=%@ contains UDID", k], v);
        }
    }];
    return headers;
}

%end

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([value containsString:TARGET_UDID_NS]) {
        logHit([NSString stringWithFormat:
            @"NSMutableURLRequest -setValue:forHTTPHeaderField: field=%@",
            field], value);
    }
    %orig;
}

- (void)setHTTPBody:(NSData *)data {
    if (data) {
        NSString *body = [[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding];
        if ([body containsString:TARGET_UDID_NS]) {
            logHit(@"NSMutableURLRequest -setHTTPBody: contains UDID", body);
        }
    }
    %orig;
}

%end

// ─────────────────────────────────────────────────────────────
//  HOOK 6 — NSFileManager (reading plist/files containing UDID)
// ─────────────────────────────────────────────────────────────
%hook NSFileManager

- (NSData *)contentsAtPath:(NSString *)path {
    NSData *data = %orig;
    if (data) {
        NSString *str = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
        if ([str containsString:TARGET_UDID_NS]) {
            logHit([NSString stringWithFormat:
                @"NSFileManager -contentsAtPath: path=%@", path], path);
        }
    }
    return data;
}

%end

// ─────────────────────────────────────────────────────────────
//  DYNAMIC METHOD OBSERVER
//  Scans all loaded classes for selectors that commonly return
//  a UDID string and wraps them with a logging IMP at runtime.
// ─────────────────────────────────────────────────────────────
static SEL observedSelectors[] = {
    // clang-format off
    @selector(udid),
    @selector(UDID),
    @selector(getUDID),
    @selector(deviceUDID),
    @selector(uniqueDeviceIdentifier),
    @selector(uniqueIdentifier),
    @selector(deviceIdentifier),
    @selector(hardwareIdentifier),
    @selector(serialNumber),
    @selector(deviceId),
    @selector(getDeviceId),
    @selector(platformUDID),
    @selector(advertisingIdentifier),   // IDFA — log if it returns target
    // clang-format on
};
static const int kObservedSelectorCount =
    sizeof(observedSelectors) / sizeof(observedSelectors[0]);

static void installDynamicObservers(void) {
    unsigned int classCount = 0;
    Class *classList = objc_copyClassList(&classCount);

    int hookedCount = 0;

    for (unsigned int c = 0; c < classCount; c++) {
        Class cls = classList[c];

        for (int s = 0; s < kObservedSelectorCount; s++) {
            SEL sel = observedSelectors[s];

            // Check instance and class methods
            for (int isClassMethod = 0; isClassMethod <= 1; isClassMethod++) {
                Method m = isClassMethod
                    ? class_getClassMethod(cls, sel)
                    : class_getInstanceMethod(cls, sel);
                if (!m) continue;

                const char *retType = method_getTypeEncoding(m);
                if (!retType || retType[0] != '@') continue;  // must return object

                IMP orig = method_getImplementation(m);
                SEL capturedSel = sel;
                Class capturedCls = cls;
                BOOL capturedIsClass = isClassMethod;

                IMP observer = imp_implementationWithBlock(^id(id self) {
                    id result = ((id (*)(id, SEL))orig)(self, capturedSel);
                    NSString *str = nil;
                    if ([result isKindOfClass:[NSString class]])
                        str = result;
                    else if ([result isKindOfClass:[NSUUID class]])
                        str = [(NSUUID *)result UUIDString];

                    // Log ALL calls to these selectors (not just matching)
                    NSLog(@"%s Dynamic hook: %@%@[%@ %@] → %@",
                          LOG_TAG,
                          capturedIsClass ? @"+" : @"-",
                          capturedIsClass ? @"" : @"",
                          NSStringFromClass(capturedCls),
                          NSStringFromSelector(capturedSel),
                          str ?: result);

                    if ([str isEqual:TARGET_UDID_NS]) {
                        logHit([NSString stringWithFormat:
                            @"Dynamic: %@[%@ %@] returned target UDID",
                            capturedIsClass ? @"+" : @"-",
                            NSStringFromClass(capturedCls),
                            NSStringFromSelector(capturedSel)], str);
                    }
                    return result;
                });

                method_setImplementation(m, observer);
                hookedCount++;
            }
        }
    }

    free(classList);
    NSLog(@"%s 🪝 Dynamic observers installed on %d method(s).",
          LOG_TAG, hookedCount);
}

// ─────────────────────────────────────────────────────────────
//  MEMORY SCANNER (read-only — scan & log, no patching)
// ─────────────────────────────────────────────────────────────
static void scanMemoryForUDID(void) {
    task_t task = mach_task_self();
    mach_vm_address_t addr = 0;
    mach_vm_size_t    size = 0;
    natural_t         depth = 0;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
    uint64_t hitCount = 0;

    while (1) {
        kern_return_t kr = mach_vm_region_recurse(
            task, &addr, &size, &depth,
            (vm_region_recurse_info_t)&info, &infoCount);
        if (kr != KERN_SUCCESS) break;

        if (info.is_submap) { depth++; continue; }

        if (info.protection & VM_PROT_READ) {
            const uint8_t *base = (const uint8_t *)(uintptr_t)addr;
            for (vm_size_t i = 0; i + 25 <= (vm_size_t)size; i++) {
                if (memcmp(base + i, TARGET_UDID, 25) == 0) {
                    hitCount++;
                    Dl_info dli;
                    const char *owner = "unknown";
                    if (dladdr(base + i, &dli) && dli.dli_fname)
                        owner = dli.dli_fname;
                    NSLog(@"%s 🔍 Memory hit #%llu at %p | region [%p-%p] "
                          @"prot=%d | owner: %s",
                          LOG_TAG, hitCount,
                          (void *)(base + i),
                          (void *)(uintptr_t)addr,
                          (void *)((uintptr_t)addr + size),
                          info.protection, owner);
                }
            }
        }

        addr += size;
        infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
    }

    NSLog(@"%s 🔍 Memory scan done — %llu occurrence(s) found.", LOG_TAG, hitCount);
}

// ─────────────────────────────────────────────────────────────
//  CONSTRUCTOR
// ─────────────────────────────────────────────────────────────
%ctor {
    NSLog(@"%s ──────────────────────────────────────", LOG_TAG);
    NSLog(@"%s 🚀 Observer loaded. Watching for UDID:", LOG_TAG);
    NSLog(@"%s    %s", LOG_TAG, TARGET_UDID);
    NSLog(@"%s ──────────────────────────────────────", LOG_TAG);

    @autoreleasepool {

        // Hook Keychain C functions
        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)hook_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        MSHookFunction((void *)SecItemAdd,
                       (void *)hook_SecItemAdd,
                       (void **)&orig_SecItemAdd);
        NSLog(@"%s 🔐 Keychain hooks installed.", LOG_TAG);

        // Install dynamic ObjC method observers
        installDynamicObservers();

        // Initial memory scan
        scanMemoryForUDID();

        // Re-scan after frameworks finish loading
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
            ^{ scanMemoryForUDID(); });

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
            ^{ scanMemoryForUDID(); });
    }
}
