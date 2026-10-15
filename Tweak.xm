// ==============================================================================
// TempMailTrace: Tweak & Audit Dylib
// Captures verify API endpoints, headers, payload, response, and UI/render states
// Saves full trace to: Documents/TempMail_Audit.log
// ==============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>
#include <libkern/OSCacheControl.h>

#ifdef __cplusplus
extern "C" {
#endif
void sys_icache_invalidate(void *start, size_t len);
void sys_dcache_flush(void *start, size_t len);
#ifdef __cplusplus
}
#endif

// ------------------------------------------------------------------------------
// Logging Infrastructure
// ------------------------------------------------------------------------------
static int auditFD = -1;
static pthread_mutex_t logMutex = PTHREAD_MUTEX_INITIALIZER;
static NSString *auditLogPath = nil;

static void WriteAuditLog(NSString *category, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    pid_t pid = getpid();
    uid_t uid = getuid();
    BOOL isMain = NSThread.isMainThread;
    
    NSString *entry = [NSString stringWithFormat:@"[%.3f][PID:%d][UID:%d][Main:%d][%@] %@\n",
                       now, pid, uid, isMain, category, message];

    // 1. Console / os_log
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "%{public}s", entry.UTF8String);

    // 2. File write (Documents/TempMail_Audit.log)
    pthread_mutex_lock(&logMutex);
    if (auditFD >= 0) {
        const char *buf = entry.UTF8String;
        size_t len = strlen(buf);
        write(auditFD, buf, len);
    }
    pthread_mutex_unlock(&logMutex);
}

// ------------------------------------------------------------------------------
// Base Address Resolution
// ------------------------------------------------------------------------------
static uintptr_t GetMainBinaryBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "TempMail.app/TempMail")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return (uintptr_t)_dyld_get_image_header(0);
}

// ------------------------------------------------------------------------------
// Dynamic Hooking Engine (MSHookFunction -> DobbyHook -> Inline ARM64 fallback)
// ------------------------------------------------------------------------------
typedef void (*MSHookFunction_t)(void *symbol, void *hook, void **old);
typedef int (*DobbyHook_t)(void *function_address, void *replace_call_address, void **origin_call_address);

static BOOL HookFunction(void *target, void *replacement, void **orig) {
    if (!target) return NO;

    // 1. Try CydiaSubstrate / ElleKit MSHookFunction
    MSHookFunction_t msHook = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (msHook) {
        msHook(target, replacement, orig);
        return YES;
    }

    // 2. Try DobbyHook
    DobbyHook_t dobbyHook = (DobbyHook_t)dlsym(RTLD_DEFAULT, "DobbyHook");
    if (dobbyHook) {
        return (dobbyHook(target, replacement, orig) == 0);
    }

    // 3. Fallback: ARM64 Direct Branch Trampoline (if memory is writable / patchable)
    vm_prot_t prot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY;
    mach_port_t task = mach_task_self();
    vm_address_t page = ((vm_address_t)target) & ~((vm_address_t)PAGE_SIZE - 1);
    
    if (vm_protect(task, page, PAGE_SIZE * 2, FALSE, prot) == KERN_SUCCESS) {
        // LDR X16, #8; BR X16; <target_ptr 8 bytes>
        uint32_t trampoline[4];
        trampoline[0] = 0x58000050; // LDR X16, #8
        trampoline[1] = 0xd61f0200; // BR X16
        memcpy(&trampoline[2], &replacement, 8);
        
        memcpy(target, trampoline, 16);
        vm_protect(task, page, PAGE_SIZE * 2, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        sys_icache_invalidate(target, 16);
        return YES;
    }
    return NO;
}

// ------------------------------------------------------------------------------
// CURL Hooks
// ------------------------------------------------------------------------------
#define CURLOPT_URL             10002
#define CURLOPT_POSTFIELDS      10015
#define CURLOPT_USERPWD         10018
#define CURLOPT_PINNEDPUBLICKEY 10230

typedef uintptr_t (*curl_easy_setopt_t)(uintptr_t handle, int option, ...);
static curl_easy_setopt_t orig_curl_easy_setopt = NULL;

static uintptr_t my_curl_easy_setopt(uintptr_t handle, int option, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7, uintptr_t a8, uintptr_t val) {
    @autoreleasepool {
        switch (option) {
            case CURLOPT_URL: {
                const char *url = (const char *)val;
                WriteAuditLog(@"CURL", @"🎯 [CURLOPT_URL] = %s", url ? url : "(null)");
                break;
            }
            case CURLOPT_POSTFIELDS: {
                const char *body = (const char *)val;
                WriteAuditLog(@"CURL", @"📦 [CURLOPT_POSTFIELDS] = %s", body ? body : "(null)");
                break;
            }
            case CURLOPT_USERPWD: {
                const char *userpwd = (const char *)val;
                WriteAuditLog(@"CURL", @"🔑 [CURLOPT_USERPWD] = %s", userpwd ? userpwd : "(null)");
                break;
            }
            case CURLOPT_PINNEDPUBLICKEY: {
                const char *pin = (const char *)val;
                WriteAuditLog(@"CURL", @"🔒 [CURLOPT_PINNEDPUBLICKEY] = %s", pin ? pin : "(null)");
                break;
            }
            default: {
                WriteAuditLog(@"CURL", @"[setopt] opt=%d, val=0x%lx", option, (unsigned long)val);
                break;
            }
        }
    }
    return orig_curl_easy_setopt(handle, option, a3, a4, a5, a6, a7, a8, val);
}

typedef uintptr_t (*curl_easy_perform_t)(uintptr_t handle);
static curl_easy_perform_t orig_curl_easy_perform = NULL;

static uintptr_t my_curl_easy_perform(uintptr_t handle) {
    WriteAuditLog(@"CURL", @">>> curl_easy_perform: START HTTP REQUEST >>>");
    uintptr_t ret = orig_curl_easy_perform(handle);
    WriteAuditLog(@"CURL", @"<<< curl_easy_perform: FINISHED HTTP REQUEST, Code = %ld <<<", (long)ret);
    return ret;
}

// ------------------------------------------------------------------------------
// dlopen Hook (Diagnose jailbreak backend loading)
// ------------------------------------------------------------------------------
static void* (*orig_dlopen)(const char *filename, int flag) = NULL;

static void* my_dlopen(const char *filename, int flag) {
    void *h = orig_dlopen(filename, flag);
    if (filename && (strstr(filename, "jailbreak") || strstr(filename, "jbroot") || strstr(filename, "basebin"))) {
        WriteAuditLog(@"DLOPEN", @"dlopen('%s', %d) -> %p (dlerror: %s)", filename, flag, h, h ? "None" : dlerror());
    }
    return h;
}

// ------------------------------------------------------------------------------
// Objective-C Method Swizzling
// ------------------------------------------------------------------------------
static void SwizzleInstanceMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        WriteAuditLog(@"OBJC_HOOK", @"Method not found: -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
    WriteAuditLog(@"OBJC_HOOK", @"Swizzled -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
}

static void SwizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        WriteAuditLog(@"OBJC_HOOK", @"Class method not found: +[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
    WriteAuditLog(@"OBJC_HOOK", @"Swizzled +[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
}

// Hook: UIAlertController alertControllerWithTitle:message:preferredStyle:
typedef id (*AlertImp_t)(id, SEL, NSString*, NSString*, UIAlertControllerStyle);
static AlertImp_t orig_alert = NULL;

static id my_alert(id self, SEL _cmd, NSString *title, NSString *message, UIAlertControllerStyle style) {
    WriteAuditLog(@"ALERT_POPUP", @"⚠️ Popup triggered! Title: '%@', Message: '%@'", title, message);
    return orig_alert(self, _cmd, title, message, style);
}

// Hook: -[VNTISFHTNSFJ GAJKGNRXCHR:] (Load Cheat trigger)
typedef void (*LoadCheatImp_t)(id, SEL, id);
static LoadCheatImp_t orig_loadCheat = NULL;

static void my_loadCheat(id self, SEL _cmd, id sender) {
    WriteAuditLog(@"ACTION", @"🚀 [User clicked LOAD CHEAT] (-[VNTISFHTNSFJ GAJKGNRXCHR:])");
    orig_loadCheat(self, _cmd, sender);
}

// Hook: -[GWGCBAHTNSFR application:didFinishLaunchingWithOptions:] (Overlay Window & Delegate Init)
typedef BOOL (*OverlayAppLaunch_t)(id, SEL, id, id);
static OverlayAppLaunch_t orig_overlayLaunch = NULL;

static BOOL my_overlayLaunch(id self, SEL _cmd, id app, id options) {
    WriteAuditLog(@"OVERLAY_LIFECYCLE", @"🎬 Overlay Application launched (-[GWGCBAHTNSFR didFinishLaunching])");
    BOOL res = orig_overlayLaunch(self, _cmd, app, options);
    WriteAuditLog(@"OVERLAY_LIFECYCLE", @"🎬 Overlay Application returned: %d", res);
    return res;
}

// Hook: -[PSNVHRBF viewDidLoad] (Floating Icon & Menu Root Controller)
typedef void (*PSNVHRBF_viewDidLoad_t)(id, SEL);
static PSNVHRBF_viewDidLoad_t orig_psnvhrbf_viewDidLoad = NULL;

static void my_psnvhrbf_viewDidLoad(id self, SEL _cmd) {
    WriteAuditLog(@"UI_VIEW", @"Entering -[PSNVHRBF viewDidLoad]");
    orig_psnvhrbf_viewDidLoad(self, _cmd);
    
    // Inspect floatingIcon state
    Ivar ivar = class_getInstanceVariable([self class], "_floatingIcon");
    if (ivar) {
        id icon = object_getIvar(self, ivar);
        if ([icon isKindOfClass:[UIView class]]) {
            UIView *iconView = (UIView *)icon;
            WriteAuditLog(@"UI_VIEW", @"📌 Floating Icon: ptr=%p, frame=%@, hidden=%d, alpha=%.2f, superview=%p, window=%p",
                          iconView, NSStringFromCGRect(iconView.frame), iconView.hidden, iconView.alpha, iconView.superview, iconView.window);
        } else {
            WriteAuditLog(@"UI_VIEW", @"⚠️ _floatingIcon is nil or not UIView!");
        }
    }
}

// Hook: -[LAFHTNFJTS initWithNibName:bundle:] (ImGui / Metal Renderer)
typedef id (*LAFHTNFJTS_init_t)(id, SEL, id, id);
static LAFHTNFJTS_init_t orig_lafhtnfjts_init = NULL;

static id my_lafhtnfjts_init(id self, SEL _cmd, id nib, id bundle) {
    WriteAuditLog(@"RENDERER", @"Entering -[LAFHTNFJTS initWithNibName:bundle:]");
    id res = orig_lafhtnfjts_init(self, _cmd, nib, bundle);
    WriteAuditLog(@"RENDERER", @"Exited -[LAFHTNFJTS initWithNibName:bundle:], result=%p", res);
    return res;
}

// Hook: Window Hosting registration
typedef void (*HostingReg_t)(id, SEL, unsigned int, double);
static HostingReg_t orig_hostingReg = NULL;

static void my_hostingReg(id self, SEL _cmd, unsigned int contextId, double level) {
    WriteAuditLog(@"WINDOW_HOSTING", @"🖥️ registerWindowWithContextID:%u atLevel:%.1f", contextId, level);
    orig_hostingReg(self, _cmd, contextId, level);
}

// ------------------------------------------------------------------------------
// Constructor Entry Point
// ------------------------------------------------------------------------------
__attribute__((constructor)) static void InitializeTraceTweak(void) {
    @autoreleasepool {
        // 1. Setup Audit Log File in Documents directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = paths.firstObject;
        if (!docDir) docDir = NSTemporaryDirectory();
        
        auditLogPath = [docDir stringByAppendingPathComponent:@"TempMail_Audit.log"];
        auditFD = open(auditLogPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0666);

        BOOL isOverlayProcess = [NSProcessInfo.processInfo.arguments containsObject:@"-a"];
        WriteAuditLog(@"INIT", @"=================================================================");
        WriteAuditLog(@"INIT", @"⚡ TempMailTrace Injected! Mode: %@", isOverlayProcess ? @"OVERLAY PROCESS (-a)" : @"MAIN APP PROCESS");
        WriteAuditLog(@"INIT", @"📂 Audit Log Path: %@", auditLogPath);
        WriteAuditLog(@"INIT", @"=================================================================");

        // 2. Resolve Binary Base Address
        uintptr_t base = GetMainBinaryBase();
        WriteAuditLog(@"INIT", @"Main Binary Mach-O Base = 0x%lx", (unsigned long)base);

        // 3. Hook Statically Linked libcurl Functions
        // curl_easy_setopt virtual 0x100bd0dd4 -> offset 0x00bd0dd4
        void *target_setopt = (void *)(base + 0x00bd0dd4);
        if (HookFunction(target_setopt, (void *)my_curl_easy_setopt, (void **)&orig_curl_easy_setopt)) {
            WriteAuditLog(@"INIT", @"✅ Hooked curl_easy_setopt at 0x%lx", (unsigned long)target_setopt);
        } else {
            WriteAuditLog(@"INIT", @"❌ Failed to hook curl_easy_setopt");
        }

        // curl_easy_perform virtual 0x100ba7c90 -> offset 0x00ba7c90
        void *target_perform = (void *)(base + 0x00ba7c90);
        if (HookFunction(target_perform, (void *)my_curl_easy_perform, (void **)&orig_curl_easy_perform)) {
            WriteAuditLog(@"INIT", @"✅ Hooked curl_easy_perform at 0x%lx", (unsigned long)target_perform);
        }

        // 4. Hook dlopen to track libjailbreak loading
        void *dlopen_ptr = dlsym(RTLD_DEFAULT, "dlopen");
        if (dlopen_ptr) {
            HookFunction(dlopen_ptr, (void *)my_dlopen, (void **)&orig_dlopen);
            WriteAuditLog(@"INIT", @"✅ Hooked dlopen");
        }

        // 5. Hook Objective-C Methods
        // Popups
        Class alertClass = objc_getClass("UIAlertController");
        if (alertClass) {
            SwizzleClassMethod(alertClass, @selector(alertControllerWithTitle:message:preferredStyle:), (IMP)my_alert, (IMP *)&orig_alert);
        }

        // Load cheat trigger
        Class vntisClass = objc_getClass("VNTISFHTNSFJ");
        if (vntisClass) {
            SwizzleInstanceMethod(vntisClass, NSSelectorFromString(@"GAJKGNRXCHR:"), (IMP)my_loadCheat, (IMP *)&orig_loadCheat);
        }

        // Overlay app delegate
        Class gwgcClass = objc_getClass("GWGCBAHTNSFR");
        if (gwgcClass) {
            SwizzleInstanceMethod(gwgcClass, @selector(application:didFinishLaunchingWithOptions:), (IMP)my_overlayLaunch, (IMP *)&orig_overlayLaunch);
        }

        // Floating icon view controller
        Class psnvClass = objc_getClass("PSNVHRBF");
        if (psnvClass) {
            SwizzleInstanceMethod(psnvClass, @selector(viewDidLoad), (IMP)my_psnvhrbf_viewDidLoad, (IMP *)&orig_psnvhrbf_viewDidLoad);
        }

        // Metal Renderer
        Class lafhClass = objc_getClass("LAFHTNFJTS");
        if (lafhClass) {
            SwizzleInstanceMethod(lafhClass, @selector(initWithNibName:bundle:), (IMP)my_lafhtnfjts_init, (IMP *)&orig_lafhtnfjts_init);
        }

        // Window Hosting
        Class hostingClass = objc_getClass("SBSAccessibilityWindowHostingController");
        if (hostingClass) {
            SwizzleInstanceMethod(hostingClass, NSSelectorFromString(@"registerWindowWithContextID:atLevel:"), (IMP)my_hostingReg, (IMP *)&orig_hostingReg);
        }
        
        WriteAuditLog(@"INIT", @"🎉 All hooks initialized successfully!");
    }
}
