// Tweak.xm - Self-hiding dylib (updated - no ptrace)
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <substrate.h>
#include <string.h>

// Global state - the original index of THIS dylib
static int g_hiddenIndex = -1;

// Original function pointers
static uint32_t (*orig_dyld_image_count)(void) = NULL;
static const char* (*orig_dyld_get_image_name)(uint32_t) = NULL;
static const struct mach_header* (*orig_dyld_get_image_header)(uint32_t) = NULL;
static intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t) = NULL;

// Get full path of this dylib
static const char* getSelfDylibPath(void) {
    Dl_info info;
    if (dladdr((void*)getSelfDylibPath, &info) == 0) {
        return NULL;
    }
    return info.dli_fname;
}

// Map visible index (what the app sees) → real index (skipping our hidden slot)
static uint32_t mapVisibleToRealIndex(uint32_t visibleIdx) {
    if (g_hiddenIndex < 0) return visibleIdx;
    if (visibleIdx < (uint32_t)g_hiddenIndex) return visibleIdx;
    return visibleIdx + 1;
}

// Hooked functions - these hide our dylib from everyone
static uint32_t my_dyld_image_count(void) {
    uint32_t realCount = orig_dyld_image_count();
    if (g_hiddenIndex >= 0 && (uint32_t)g_hiddenIndex < realCount) {
        return realCount - 1;
    }
    return realCount;
}

static const char* my_dyld_get_image_name(uint32_t image_index) {
    return orig_dyld_get_image_name(mapVisibleToRealIndex(image_index));
}

static const struct mach_header* my_dyld_get_image_header(uint32_t image_index) {
    return orig_dyld_get_image_header(mapVisibleToRealIndex(image_index));
}

static intptr_t my_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    return orig_dyld_get_image_vmaddr_slide(mapVisibleToRealIndex(image_index));
}

%ctor {
    // Find our own image index BEFORE hooking
    const char* selfPath = getSelfDylibPath();
    if (selfPath) {
        uint32_t realCount = _dyld_image_count();
        for (uint32_t i = 0; i < realCount; i++) {
            const char* name = _dyld_get_image_name(i);
            if (name && strcmp(name, selfPath) == 0) {
                g_hiddenIndex = (int)i;
                break;
            }
        }
    }

    // Install hooks
    MSHookFunction((void*)_dyld_image_count,
                   (void*)my_dyld_image_count,
                   (void**)&orig_dyld_image_count);

    MSHookFunction((void*)_dyld_get_image_name,
                   (void*)my_dyld_get_image_name,
                   (void**)&orig_dyld_get_image_name);

    MSHookFunction((void*)_dyld_get_image_header,
                   (void*)my_dyld_get_image_header,
                   (void**)&orig_dyld_get_image_header);

    MSHookFunction((void*)_dyld_get_image_vmaddr_slide,
                   (void*)my_dyld_get_image_vmaddr_slide,
                   (void**)&orig_dyld_get_image_vmaddr_slide);

    NSLog(@"[SelfHideTweak] Hidden successfully! Index = %d | Path = %s", 
          g_hiddenIndex, selfPath ?: "unknown");
}
