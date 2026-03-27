#import <substrate.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>

// Self-reference
static const struct mach_header *self_header = NULL;
static vm_address_t self_slide = 0;
static char *self_path = NULL;

// DYLD INTERPOSITION - HIDE FROM DYLD
static uint32_t (*orig__dyld_image_count)(void);
static const char* (*orig__dyld_get_image_name)(uint32_t image_index);

uint32_t hook__dyld_image_count(void) {
    uint32_t count = orig__dyld_image_count();
    return MAX(1, count - 1); // Hide ourselves
}

const char* hook__dyld_get_image_name(uint32_t image_index) {
    if (image_index >= orig__dyld_image_count()) return NULL;
    
    const char *name = orig__dyld_get_image_name(image_index);
    if (strstr(name ?: "", "tweak") || strstr(name ?: "", "substrate") || strstr(name ?: "", "iSK")) {
        return "/usr/lib/libSystem.B.dylib"; // Fake system lib
    }
    return name;
}

// ============================================================================
// SIMPLIFIED SELF-HIDING - NO VM COMMANDS
// ============================================================================

// Wipe our own code section with NOPs
void wipe_self_code() {
    if (!self_header) return;
    
    // Get __TEXT,__text section (64-bit safe)
    const struct mach_header_64 *mh64 = (const struct mach_header_64*)self_header;
    unsigned long size = 0;
    uint8_t *text_data = getsectiondata(mh64, "__TEXT", "__text", &size);
    
    if (text_data && size > 0) {
        // Make writable, fill with NOPs, restore protection
        mprotect((void*)text_data, size, PROT_READ | PROT_WRITE | PROT_EXEC);
        memset(text_data, 0x90, size); // NOP sled (0x90)
        mprotect((void*)text_data, size, PROT_READ | PROT_EXEC);
        NSLog(@"[HIDE] Code wiped with NOPs (%lu bytes)", size);
    }
}

// Hide from dlopen/dlclose traces
void hide_dl_traces() {
    // Overwrite our own dlopen entry
    void *handle = dlopen(self_path ?: "", RTLD_NOLOAD);
    if (handle) {
        dlclose(handle);
    }
}

// ============================================================================
// SELF DISCOVERY
// ============================================================================

void discover_self() {
    uint32_t img_count = _dyld_image_count();
    
    for (uint32_t i = 0; i < img_count; i++) {
        const char *img_name = _dyld_get_image_name(i);
        if (strstr(img_name ?: "", "tweak") || strstr(img_name ?: "", "substrate") || strstr(img_name ?: "", "iSK")) {
            self_header = _dyld_get_image_header(i);
            self_path = strdup(img_name ?: "");
            self_slide = _dyld_get_image_vmaddr_slide(i);
            NSLog(@"[HIDE] Found self: %s", self_path);
            return;
        }
    }
}

// DYLD INTERPOSITION
__attribute__((used)) static struct {
    const char *name;
    void *replacement;
    void **original;
} dyld_table[] = {
    { "_dyld_image_count", (void*)hook__dyld_image_count, (void**)&orig__dyld_image_count },
    { "_dyld_get_image_name", (void*)hook__dyld_get_image_name, (void**)&orig__dyld_get_image_name },
};

void apply_dyld_interpose() {
    extern void dyld_interpose(const void *table, size_t count);
    dyld_interpose(dyld_table, sizeof(dyld_table)/sizeof(dyld_table[0]));
}

// Anti-sysctl (simple)
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Block process listing
    if (namelen >= 2 && name[0] == CTL_KERN && name[1] == KERN_PROC) {
        return 0;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

// ============================================================================
// MAIN HOOKS
// ============================================================================

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // Initialize hiding
    discover_self();
    apply_dyld_interpose();
    MSHookFunction((void*)sysctl, (void*)hook_sysctl, (void**)&orig_sysctl);
    
    // Self-hide after short delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), 
                   dispatch_get_main_queue(), ^{
        wipe_self_code();
        hide_dl_traces();
        NSLog(@"[HIDE] Tweak completely hidden!");
    });
}

%end

// ============================================================================
// EARLY + LATE CONSTRUCTORS
// ============================================================================

%ctor {
    discover_self();
    apply_dyld_interpose();
}
