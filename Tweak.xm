#import <substrate.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>

// Self-reference structures
static const struct mach_header *self_header = NULL;
static vm_address_t self_slide = 0;
static char *self_path = NULL;
static mach_port_t self_task = MACH_PORT_NULL;

// DYLD INTERPOSITION (from previous - kept minimal)
static uint32_t (*orig__dyld_image_count)(void);
static const char* (*orig__dyld_get_image_name)(uint32_t image_index);

uint32_t hook__dyld_image_count(void) {
    uint32_t count = orig__dyld_image_count();
    return MAX(1, count - 1); // Always hide at least 1 (ourselves)
}

const char* hook__dyld_get_image_name(uint32_t image_index) {
    if (image_index >= orig__dyld_image_count()) return NULL;
    
    const char *name = orig__dyld_get_image_name(image_index);
    if (strstr(name ?: "", "tweak") || strstr(name ?: "", "substrate")) {
        return "/usr/lib/libSystem.B.dylib"; // Fake system lib
    }
    return name;
}

// ============================================================================
// CORE: FIND AND ERASE SELF FROM MEMORY
// ============================================================================

kern_return_t erase_self_from_memory() {
    if (!self_header || !self_task) return KERN_FAILURE;
    
    // Get all segments of our dylib
    struct segment_command_64 *seg_cmd = NULL;
    struct section_64 *sect = NULL;
    
    // Walk load commands
    const uint8_t *cmd = (uint8_t *)(self_header + 1);
    for (uint32_t i = 0; i < self_header->ncmds; i++) {
        if (((struct load_command*)cmd)->cmd == LC_SEGMENT_64) {
            seg_cmd = (struct segment_command_64*)cmd;
            if (strcmp(seg_cmd->segname, "__TEXT") == 0 || 
                strcmp(seg_cmd->segname, "__DATA") == 0 ||
                strcmp(seg_cmd->segname, "__LINKEDIT") == 0) {
                
                // Zero out the entire segment
                vm_address_t start = seg_cmd->vmaddr + self_slide;
                vm_size_t size = seg_cmd->vmsize;
                
                vm_protect(self_task, start, size, FALSE, VM_PROT_NO_CHANGE);
                memset((void*)start, 0x00, size); // Wipe with zeros
                vm_protect(self_task, start, size, FALSE, VM_PROT_READ | VM_PROT_EXEC);
            }
        }
        cmd = (uint8_t*)cmd + ((struct load_command*)cmd)->cmdsize;
    }
    
    // Deallocate our own memory pages
    vm_deallocate(self_task, (vm_address_t)self_header, 0x1000);
    
    return KERN_SUCCESS;
}

// Unmap entire dylib from memory
kern_return_t unmap_self_dylib() {
    if (!self_task) self_task = mach_task_self();
    
    // Find our vm regions and deallocate
    vm_address_t addr = 0;
    vm_size_t size = 0;
    mach_msg_type_number_t count;
    
    while (TRUE) {
        count = VM_REGION_SUBMAP_COUNT;
        natural_t depth = 0;
        
        kern_return_t kr = vm_region_64(self_task, &addr, &size, 
                                       &depth, NULL, NULL, NULL);
        if (kr != KERN_SUCCESS) break;
        
        // Check if this region contains our dylib
        Dl_info info;
        if (dladdr((void*)addr, &info) && info.dli_fbase == self_header) {
            vm_deallocate(self_task, addr, size);
            NSLog(@"[SELF-ERASE] Unmapped %p-%p", (void*)addr, (void*)(addr+size));
        }
        
        addr += size;
    }
    return KERN_SUCCESS;
}

// ============================================================================
// SELF DISCOVERY
// ============================================================================

void discover_self() {
    uint32_t img_count = _dyld_image_count();
    
    for (uint32_t i = 0; i < img_count; i++) {
        const char *img_name = _dyld_get_image_name(i);
        if (strstr(img_name, "tweak") || strstr(img_name, "substrate")) {
            self_header = _dyld_get_image_header(i);
            self_path = strdup(img_name);
            self_slide = _dyld_get_image_vmaddr_slide(i);
            self_task = mach_task_self();
            break;
        }
    }
}

// ============================================================================
// DYLD INTERPOSITION + SELF ERASE
// ============================================================================

__attribute__((used)) static struct {
    const char *name;
    void *replacement;
} dyld_table[] = {
    { "_dyld_image_count", (void*)hook__dyld_image_count },
    { "_dyld_get_image_name", (void*)hook__dyld_get_image_name },
};

void apply_dyld_interpose() {
    extern void dyld_interpose(const void *table, size_t count);
    dyld_interpose(dyld_table, sizeof(dyld_table)/sizeof(dyld_table[0]));
}

// ============================================================================
// EXECUTABLE CODE WIPE (Advanced)
// ============================================================================

void wipe_executable_code() {
    // Get __TEXT,__text section and zero it
    unsigned long size = 0;
    char *text_data = getsectiondata(self_header, "__TEXT", "__text", &size);
    
    if (text_data && size > 0) {
        mprotect((void*)text_data, size, PROT_READ | PROT_WRITE | PROT_EXEC);
        memset(text_data, 0x90, size); // NOP sled
        mprotect((void*)text_data, size, PROT_READ | PROT_EXEC);
    }
}

// ============================================================================
// MAIN HOOKS + SELF-DESTRUCT SEQUENCE
// ============================================================================

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // 1. Discover ourselves
    discover_self();
    
    // 2. Apply DYLD hiding
    apply_dyld_interpose();
    
    // 3. WIPE OURSELVES FROM MEMORY (delayed)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), 
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSLog(@"[SELF-ERASE] Initiating self-destruction...");
        
        wipe_executable_code();
        erase_self_from_memory();
        unmap_self_dylib();
        
        NSLog(@"[SELF-ERASE] Dylib completely erased from memory");
    });
}

%end

// ============================================================================
// EARLY CONSTRUCTOR - IMMEDIATE HIDING
// ============================================================================

static void early_hide() {
    discover_self();
    apply_dyld_interpose();
}

%ctor {
    early_hide();
    
    // Final self-erase after 2 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), 
                   dispatch_get_main_queue(), ^{
        unmap_self_dylib();
    });
}
