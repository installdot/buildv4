// Tweak.xm
// Force _g_PTIsFullyAuthorized = 1
// Force _g_PTMatchedDay     = valid day (0-6)
// Target: OxideMenu.dylib

#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <stdint.h>

// ---------- Offsets inside OxideMenu.dylib ----------
static const uint64_t kOffset_PTIsFullyAuthorized = 0x621a48;
static const uint64_t kOffset_PTMatchedDay        = 0x62185c;

static const char *kTargetImageName = "OxideMenu.dylib";

// ---------------------------------------------------------

static uint8_t  *g_PTIsFullyAuthorized = NULL;
static uint32_t *g_PTMatchedDay        = NULL;

static uint64_t getImageSlide(const char *imageName) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, imageName)) {
            return (uint64_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

static void forceAuthorize(void) {
    if (!g_PTIsFullyAuthorized || !g_PTMatchedDay) return;

    // Always fully authorized
    *g_PTIsFullyAuthorized = 1;

    // Keep a valid day (0-6)
    if (*g_PTMatchedDay > 6) {
        *g_PTMatchedDay = 0;          // force valid day
    }
}

%ctor {
    @autoreleasepool {
        // Wait a bit so OxideMenu.dylib is loaded
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            uint64_t slide = getImageSlide(kTargetImageName);
            if (slide == 0) {
                NSLog(@"[PTAuth] OxideMenu.dylib not found");
                return;
            }

            g_PTIsFullyAuthorized = (uint8_t  *)(slide + kOffset_PTIsFullyAuthorized);
            g_PTMatchedDay        = (uint32_t *)(slide + kOffset_PTMatchedDay);

            NSLog(@"[PTAuth] OxideMenu slide=0x%llx", slide);
            NSLog(@"[PTAuth] auth @ %p   day @ %p", g_PTIsFullyAuthorized, g_PTMatchedDay);

            // Immediate force
            forceAuthorize();

            // Keep forcing (server / integrity checks may overwrite)
            while (true) {
                forceAuthorize();
                [NSThread sleepForTimeInterval:0.4];
            }
        });
    }
}
