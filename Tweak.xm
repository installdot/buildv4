#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// Anti-detection: Hide dylib from dyld_get_image_name
typedef const char* (*dyld_get_image_name_t)(uint32_t);
static dyld_get_image_name_t original_dyld_get_image_name = NULL;

static const char* hooked_dyld_get_image_name(uint32_t index) {
    const char* name = original_dyld_get_image_name(index);
    if (name && (strstr(name, "APIBypass") || strstr(name, "SystemFramework"))) {
        return NULL;
    }
    return name;
}

// Anti-detection: Hide from dladdr
typedef int (*dladdr_t)(const void*, Dl_info*);
static dladdr_t original_dladdr = NULL;

static int hooked_dladdr(const void* addr, Dl_info* info) {
    int result = original_dladdr(addr, info);
    if (result && info->dli_fname && (strstr(info->dli_fname, "APIBypass") || strstr(info->dli_fname, "SystemFramework"))) {
        return 0;
    }
    return result;
}

%hook APIClient

- (void)paid:(void (^)(void))execute {
    if (execute) {
        execute();
    }
}

%end

// Hide from image list
%hook NSBundle

- (NSArray *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath {
    NSArray *original = %orig;
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *path in original) {
        if (![path containsString:@"APIBypass"] && ![path containsString:@"SystemFramework"]) {
            [filtered addObject:path];
        }
    }
    return filtered;
}

%end

// Anti-detection constructor
%ctor {
    @autoreleasepool {
        // Hook dyld functions to hide our presence
        void *handle = dlopen(NULL, RTLD_NOW);
        if (handle) {
            void *sym1 = dlsym(handle, "dyld_get_image_name");
            if (sym1) {
                original_dyld_get_image_name = (dyld_get_image_name_t)sym1;
                MSHookFunction((void *)sym1, (void *)hooked_dyld_get_image_name, (void **)NULL);
            }
            
            void *sym2 = dlsym(handle, "dladdr");
            if (sym2) {
                original_dladdr = (dladdr_t)sym2;
                MSHookFunction((void *)sym2, (void *)hooked_dladdr, (void **)NULL);
            }
        }
    }
}
