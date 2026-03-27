// tweak.xm
// Self-hiding dylib tweak for Theos/Logos
// Hides THIS dylib from _dyld_image_* APIs so apps and other dylibs cannot see it via standard enumeration.
// Prevents easy detection and dumping by tools that rely on dyld image list (e.g. many jailbreak detectors, Frida, Cycript, class-dump, etc.).
// Also adds basic anti-debug (PT_DENY_ATTACH) to make attaching a debugger/dumper harder.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <substrate.h>
#include <sys/ptrace.h>
#include <string.h>

// Global state - the original index of THIS dylib (found once in ctor)
static int g_hiddenIndex = -1;

// Original function pointers (set by MSHookFunction)
static uint32_t (*orig_dyld_image_count)(void) = NULL;
static const char* (*orig_dyld_get_image_name)(uint32_t) = NULL;
static const struct mach_header* (*orig_dyld_get_image_header)(uint32_t) = NULL;
static intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t) = NULL;

// Helper: get full path of THIS dylib using dladdr on a function inside it
static const char* getSelfDylibPath(void) {
    Dl_info info;
    if (dladdr((void*)getSelfDylibPath, &info) == 0) {
        return NULL;
    }
    return info.dli_fname;
}

// Helper: map a "visible" index (what the app sees) to the real original index (skipping our hidden one)
static uint32_t mapVisibleToRealIndex(uint32_t visibleIdx) {
    if (g_hiddenIndex < 0) {
        return visibleIdx;
    }
    if (visibleIdx < (uint32_t)g_hiddenIndex) {
        return visibleIdx;
    }
    return visibleIdx + 1;  // shift everything after the hidden slot
}

// Hooked versions - these are what the rest of the system (app + other dylibs) will call
static uint32_t my_dyld_image_count(void) {
    uint32_t realCount = orig_dyld_image_count();
    if (g_hiddenIndex >= 0 && (uint32_t)g_hiddenIndex < realCount) {
        return realCount - 1;
    }
    return realCount;
}

static const char* my_dyld_get_image_name(uint32_t image_index) {
    uint32_t realIdx = mapVisibleToRealIndex(image_index);
    return orig_dyld_get_image_name(realIdx);
}

static const struct mach_header* my_dyld_get_image_header(uint32_t image_index) {
    uint32_t realIdx = mapVisibleToRealIndex(image_index);
    return orig_dyld_get_image_header(realIdx);
}

static intptr_t my_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    uint32_t realIdx = mapVisibleToRealIndex(image_index);
    return orig_dyld_get_image_vmaddr_slide(realIdx);
}

%ctor {
    // Basic anti-debug / anti-dump protection (makes debugger attachment fail in many cases)
    ptrace(PT_DENY_ATTACH, 0, 0, 0);

    // Find our own image index BEFORE we install the hooks
    const char* selfPath = getSelfDylibPath();
    if (selfPath != NULL) {
        uint32_t realCount = _dyld_image_count();  // unhooked version
        for (uint32_t i = 0; i < realCount; i++) {
            const char* name = _dyld_get_image_name(i);  // unhooked
            if (name && strcmp(name, selfPath) == 0) {
                g_hiddenIndex = (int)i;
                break;
            }
        }
    }

    // Install the hooks using Substrate (this is what makes the hiding global)
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

    NSLog(@"[SelfHideTweak] Successfully hidden! Hidden index = %d | Path = %s", g_hiddenIndex, selfPath ?: "unknown");
    NSLog(@"[SelfHideTweak] This dylib will no longer appear in dyld image lists for the app or any other dylib.");
}
