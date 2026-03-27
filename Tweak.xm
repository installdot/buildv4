#import <substrate.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>
#import <sys/mman.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>

// Self-reference structures
static const struct mach_header *self_header = NULL;
static vm_address_t self_slide = 0;
static char *self_path = NULL;
static mach_port_t self_task = MACH_PORT_NULL;

// Constants fixed for modern SDK
#define VM_PROT_EXEC  0x4
#define VM_PROT_READ  0x1
#define VM_PROT_WRITE 0x2

// DYLD INTERPOSITION
static uint32_t (*orig__dyld_image_count)(void);
static const char* (*orig__dyld_get_image_name)(uint32_t image_index);

uint32_t hook__dyld_image_count(void) {
    uint32_t count = orig__dyld_image_count();
    return MAX(1, count - 1);
}

const char* hook__dyld_get_image_name(uint32_t image_index) {
    if (image_index >= orig__dyld_image_count()) return NULL;
    
    const char *name = orig__dyld_get_image_name(image_index);
    if (strstr(name ?: "", "tweak") || strstr(name ?: "", "substrate")) {
        return "/usr/lib/libSystem.B.dylib";
    }
    return name;
}

// ============================================================================
// FIXED: ERASE SELF FROM MEMORY
// ============================================================================

kern_return_t erase_self_from_memory() {
    if (!self_header || !self_task) return KERN_FAILURE;
    
    // Walk load commands
    const uint8_t *cmd = (uint8_t *)(self_header + 1);
    for (uint32_t i = 0; i < self_header->ncmds; i++) {
        struct load_command *lc = (struct load_command*)cmd;
        
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64*)cmd;
            
            if (strcmp(seg->segname, "__TEXT") == 0 || 
                strcmp(seg->segname, "__DATA") == 0 ||
                strcmp(seg->segname, "__LINKEDIT") == 0) {
                
                vm_address_t start = seg->vmaddr + self_slide;
                vm_size_t size = seg->vmsize;
                
                // Change protection and zero
                vm_protect(self_task, start, size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
                memset((void*)start, 0x00, size);
                vm_protect(self_task, start, size, FALSE, VM_PROT_READ | VM_PROT_EXEC);
            }
        }
        cmd += lc->cmdsize;
    }
    
    return KERN_SUCCESS;
}

// FIXED: UNMAP SELF DYLIB
kern_return_t unmap_self_dylib() {
    self_task = mach_task_self();
    
    vm_address_t addr = 0;
    vm_size_t size = 0;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO_64;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    
    while (vm_region_64(self_task, &addr, &size, &flavor, (vm_region_info_t)&info, &count, NULL) == KERN_SUCCESS) {
        // Check if this region belongs to our dylib
        Dl_info dlinfo;
        if (dladdr((void*)addr, &dlinfo) && dlinfo.dli_fbase == self_header) {
            vm_deallocate(self_task, addr, size);
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
        if (strstr(img_name ?: "", "tweak") || strstr(img_name ?: "", "substrate")) {
            self_header = _dyld_get_image_header(i);
            self_path = strdup(img_name ?: "");
            self_slide = _dyld_get_image_vmaddr_slide(i);
            self_task = mach_task_self();
            break;
        }
    }
}

// DYLD INTERPOSITION TABLE
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

// ============================================================================
// FIXED: WIPE EXECUTABLE CODE (64-bit compatible)
// ============================================================================

void wipe_executable_code() {
    if (!self_header) return;
    
    // Use 64-bit getsectiondata
    unsigned long size = 0;
    const struct mach_header_64 *mh64 = (const struct mach_header_64*)self_header;
    uint8_t *text_data = getsectiondata(mh64, "__TEXT", "__text", &size);
    
    if (text_data && size > 0) {
        mprotect((void*)text_data, size, PROT_READ | PROT_WRITE | PROT_EXEC);
        memset(text_data, 0x90, size); // NOP sled
        mprotect((void*)text_data, size, PROT_READ | PROT_EXEC);
    }
}

// ============================================================================
// MAIN HOOKS
// ============================================================================

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    discover_self();
    apply_dyld_interpose();
    
    // Self-destruct sequence
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), 
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSLog(@"[SELF-ERASE] Starting self-destruction...");
        wipe_executable_code();
        erase_self_from_memory();
        unmap_self_dylib();
        NSLog(@"[SELF-ERASE] Dylib erased from memory!");
    });
}

%end

// EARLY CONSTRUCTOR
%ctor {
    discover_self();
    apply_dyld_interpose();
}
