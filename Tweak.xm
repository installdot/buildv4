/*
 * tweak.xm — UDID Memory Spoof Tweak
 * Target UDID : 00008020-000640860179002E
 * Spoof Value : UDID-GOT-SPOOF-KID
 *
 * Build deps  : Theos + CydiaSubstrate / libhooker
 * Arch target : arm64
 */

#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach/mach_vm.h>
#include <sys/mman.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>
#include <stdint.h>

// ─────────────────────────────────────────────
//  CONSTANTS
// ─────────────────────────────────────────────
#define TARGET_UDID   "00008020-000640860179002E"
#define SPOOF_UDID    "UDID-GOT-SPOOF-KID"

// Pad spoof value to same length as target so we
// never touch allocation boundaries.
#define TARGET_LEN    (sizeof(TARGET_UDID) - 1)   // 25 chars
#define SPOOF_LEN     (sizeof(SPOOF_UDID)  - 1)   // 18 chars

// ─────────────────────────────────────────────
//  MEMORY SCANNER
//  Walks every readable/writable vm region of
//  the current task and patches every occurrence
//  of TARGET_UDID in-place.
// ─────────────────────────────────────────────
static uint64_t patchCount = 0;

static void scanAndPatchMemory(void) {
    task_t task = mach_task_self();
    mach_vm_address_t addr = 0;
    mach_vm_size_t    size = 0;
    natural_t         depth = 0;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;

    while (1) {
        kern_return_t kr = mach_vm_region_recurse(
            task, &addr, &size, &depth,
            (vm_region_recurse_info_t)&info, &infoCount);

        if (kr != KERN_SUCCESS) break;

        // Only look at regions we can actually read
        if (info.is_submap) {
            depth++;
            continue;
        }

        vm_prot_t prot = info.protection;
        BOOL readable = (prot & VM_PROT_READ) != 0;
        BOOL writable = (prot & VM_PROT_WRITE) != 0;

        if (readable) {
            uint8_t *base = (uint8_t *)(uintptr_t)addr;
            vm_size_t remaining = (vm_size_t)size;

            // Scan for needle
            for (vm_size_t i = 0; i + TARGET_LEN <= remaining; i++) {
                if (memcmp(base + i, TARGET_UDID, TARGET_LEN) == 0) {

                    // Make page writable if needed
                    mach_vm_address_t pageAddr = (mach_vm_address_t)(
                        ((uintptr_t)(base + i)) & ~(PAGE_SIZE - 1));
                    mach_vm_size_t pageSize = PAGE_SIZE;

                    if (!writable) {
                        mach_vm_protect(task, pageAddr, pageSize,
                                        FALSE,
                                        VM_PROT_READ | VM_PROT_WRITE);
                    }

                    // Patch: overwrite with spoof, then null-fill remainder
                    memcpy(base + i, SPOOF_UDID, SPOOF_LEN);
                    if (SPOOF_LEN < TARGET_LEN)
                        memset(base + i + SPOOF_LEN, 0,
                               TARGET_LEN - SPOOF_LEN);

                    // Restore original protection
                    if (!writable) {
                        mach_vm_protect(task, pageAddr, pageSize,
                                        FALSE, prot);
                    }

                    patchCount++;
                    NSLog(@"[UDIDSpoof] ✅ Patched occurrence #%llu "
                          @"at %p", patchCount, (void *)(base + i));
                }
            }
        }

        addr += size;
        infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;   // reset for next call
    }

    NSLog(@"[UDIDSpoof] 🔍 Scan complete — %llu patch(es) applied.", patchCount);
}

// ─────────────────────────────────────────────
//  HOOKS — high-priority ObjC intercepts
// ─────────────────────────────────────────────

// 1) UIDevice -identifierForVendor  (not UDID but apps sometimes confuse them)
%hook UIDevice
- (NSUUID *)identifierForVendor {
    NSLog(@"[UDIDSpoof] Hook: -identifierForVendor called");
    return [[NSUUID alloc] initWithUUIDString:@"UDID-GOT-0000-SPOO-FKID00000000"];
}
%end

// 2) Any NSString that equals the target UDID
%hook NSString
- (BOOL)isEqualToString:(NSString *)aString {
    if ([aString isEqualToString:@TARGET_UDID]) {
        NSLog(@"[UDIDSpoof] Hook: isEqualToString matched target UDID");
    }
    return %orig;
}
%end

// 3) Hook common UDID retrieval selectors via forwardedClass
// Covers third-party analytics SDKs that call [SomeClass udid] / [SomeClass getUDID]
static void hookUDIDSelectors(void) {
    SEL selectors[] = {
        @selector(udid),
        @selector(UDID),
        @selector(getUDID),
        @selector(uniqueDeviceIdentifier),
        @selector(deviceUDID),
    };

    unsigned int classCount = 0;
    Class *classList = objc_copyClassList(&classCount);

    for (unsigned int c = 0; c < classCount; c++) {
        Class cls = classList[c];
        for (int s = 0; s < 5; s++) {
            Method m = class_getInstanceMethod(cls, selectors[s]);
            if (!m) m = class_getClassMethod(cls, selectors[s]);
            if (!m) continue;

            // Only patch methods that return id/NSString
            const char *retType = method_getTypeEncoding(m);
            if (retType && retType[0] == '@') {
                IMP orig = method_getImplementation(m);
                IMP patch = imp_implementationWithBlock(^id(id self) {
                    id result = ((id(*)(id,SEL))orig)(self, selectors[s]);
                    if ([result isKindOfClass:[NSString class]] &&
                        [result isEqualToString:@TARGET_UDID]) {
                        NSLog(@"[UDIDSpoof] Hook: %@ -[%@ %@] → spoofed",
                              NSStringFromClass([self class]),
                              NSStringFromClass(cls),
                              NSStringFromSelector(selectors[s]));
                        return @SPOOF_UDID;
                    }
                    return result;
                });
                method_setImplementation(m, patch);
            }
        }
    }
    free(classList);
    NSLog(@"[UDIDSpoof] 🪝 Dynamic selector hooks installed.");
}

// ─────────────────────────────────────────────
//  CONSTRUCTOR — runs before main(), +load, etc.
//  __attribute__((constructor)) fires at dylib
//  injection time, before any app code.
// ─────────────────────────────────────────────
%ctor {
    // Highest-priority dispatch — before app delegate
    NSLog(@"[UDIDSpoof] 🚀 Constructor fired — target: %s → spoof: %s",
          TARGET_UDID, SPOOF_UDID);

    @autoreleasepool {
        // Step 1: immediate memory scan + patch
        scanAndPatchMemory();

        // Step 2: install dynamic ObjC hooks
        hookUDIDSelectors();

        // Step 3: schedule a re-scan shortly after launch
        // (some frameworks load lazily and populate UDID after main)
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
            ^{
                NSLog(@"[UDIDSpoof] 🔄 Post-launch re-scan…");
                scanAndPatchMemory();
            }
        );

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
            ^{
                NSLog(@"[UDIDSpoof] 🔄 Late re-scan (SDK init window)…");
                scanAndPatchMemory();
            }
        );
    }
}
