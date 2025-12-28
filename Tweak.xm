#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// Anti-detection: Hide dylib from dyld_get_image_name
static const char* (*original_dyld_get_image_name)(uint32_t) = NULL;

static const char* hooked_dyld_get_image_name(uint32_t index) {
    const char* name = original_dyld_get_image_name(index);
    if (name && strstr(name, "APIBypass")) {
        return NULL;
    }
    return name;
}

// Anti-detection: Hide from dladdr
static int (*original_dladdr)(const void*, Dl_info*) = NULL;

static int hooked_dladdr(const void* addr, Dl_info* info) {
    int result = original_dladdr(addr, info);
    if (result && info->dli_fname && strstr(info->dli_fname, "APIBypass")) {
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
        if (![path containsString:@"APIBypass"]) {
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
            original_dyld_get_image_name = dlsym(handle, "dyld_get_image_name");
            if (original_dyld_get_image_name) {
                MSHookFunction(original_dyld_get_image_name, hooked_dyld_get_image_name, NULL);
            }
            
            original_dladdr = dlsym(handle, "dladdr");
            if (original_dladdr) {
                MSHookFunction(original_dladdr, hooked_dladdr, NULL);
            }
        }
    }
}
