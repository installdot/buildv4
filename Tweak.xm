// Tweak.xm
// OxideMenu.dylib – force authorization globals

#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <stdint.h>

// Offsets inside OxideMenu.dylib (VA == file offset)
static const uint64_t kOff_PTIsFullyAuthorized = 0x621A48;  // uint8_t
static const uint64_t kOff_PTMatchedDay        = 0x62185C;  // uint32_t

static uint8_t  *g_auth = NULL;
static uint32_t *g_day  = NULL;

static uint64_t slideForImage(const char *name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *img = _dyld_get_image_name(i);
        if (img && strstr(img, name))
            return (uint64_t)_dyld_get_image_vmaddr_slide(i);
    }
    return 0;
}

static void force(void) {
    if (!g_auth || !g_day) return;

    // Fully authorized
    *g_auth = 1;

    // Valid day (0-6). Keep existing value if already valid, otherwise force 0.
    if (*g_day > 6)
        *g_day = 0;
}

%ctor {
    @autoreleasepool {
        // Give OxideMenu.dylib time to load
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{

            uint64_t slide = slideForImage("OxideMenu.dylib");
            if (!slide) {
                NSLog(@"[PTAuth] OxideMenu.dylib not found");
                return;
            }

            g_auth = (uint8_t  *)(slide + kOff_PTIsFullyAuthorized);
            g_day  = (uint32_t *)(slide + kOff_PTMatchedDay);

            NSLog(@"[PTAuth] slide = 0x%llx", slide);
            NSLog(@"[PTAuth] auth  @ %p", g_auth);
            NSLog(@"[PTAuth] day   @ %p", g_day);

            // Initial force
            force();

            // Keep them forced (anti-tamper / server response may overwrite)
            while (1) {
                force();
                [NSThread sleepForTimeInterval:0.35];
            }
        });
    }
}
