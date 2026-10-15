// ==============================================================================
// TempMailTrace & Auto-Decrypt Tweak
// 1. Patches startup integrity checks & catches 0xdead crashes
// 2. Automatically triggers key decryption without manual button clicks
// 3. Captures decrypted CURLOPT_URL, CURLOPT_POSTFIELDS, and responses
// 4. Saves full audit log to: Documents/TempMail_Audit.log
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
#include <signal.h>
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

    // Console / os_log
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "%{public}s", entry.UTF8String);

    // File write
    pthread_mutex_lock(&logMutex);
    if (auditFD >= 0) {
        const char *buf = entry.UTF8String;
        size_t len = strlen(buf);
        write(auditFD, buf, len);
    }
    pthread_mutex_unlock(&logMutex);
}

// ------------------------------------------------------------------------------
// Base Address & Memory Patching
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

static BOOL PatchMemory(void *target, const void *bytes, size_t size) {
    vm_prot_t prot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY;
    mach_port_t task = mach_task_self();
    vm_address_t page = ((vm_address_t)target) & ~((vm_address_t)PAGE_SIZE - 1);
    size_t pageSize = ((size + ((vm_address_t)target - page) + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1));
    
    if (vm_protect(task, page, pageSize, FALSE, prot) == KERN_SUCCESS) {
        memcpy(target, bytes, size);
        vm_protect(task, page, pageSize, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        sys_dcache_flush(target, size);
        sys_icache_invalidate(target, size);
        return YES;
    }
    return NO;
}

// ------------------------------------------------------------------------------
// Crash Prevention: Catch SIGBUS / SIGSEGV at 0xdead
// ------------------------------------------------------------------------------
static void CrashSignalHandler(int sig, siginfo_t *info, void *ucontext) {
    ucontext_t *ctx = (ucontext_t *)ucontext;
    uintptr_t fault_pc = 0;
#if defined(__arm64__) || defined(__aarch64__)
    fault_pc = (uintptr_t)ctx->uc_mcontext->__ss.__pc;
#endif
    WriteAuditLog(@"CRASH_GUARD", @"⚡ Intercepted Signal %d (fault_addr=%p, pc=0x%lx)", sig, info->si_addr, (unsigned long)fault_pc);

    if (fault_pc == 0xdead || (uintptr_t)info->si_addr == 0xdead) {
        WriteAuditLog(@"CRASH_GUARD", @"🛡️ Successfully caught 0xdead integrity check trap! Thread terminating gracefully.");
        if (NSThread.isMainThread) {
            WriteAuditLog(@"CRASH_GUARD", @"Main thread triggered 0xdead - returning safely.");
            return;
        } else {
            pthread_exit(NULL);
        }
    }
    
    // For other crashes, exit cleanly with log
    WriteAuditLog(@"CRASH_GUARD", @"Exiting process cleanly to preserve logs.");
    exit(0);
}

static void InstallCrashGuards(uintptr_t base) {
    // 1. Register signal handlers
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = CrashSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);
    WriteAuditLog(@"PATCH", @"✅ Registered SIGBUS / SIGSEGV crash guards");

    // 2. Patch Startup Integrity Gate: 0x100053c4c (offset 0x53c4c)
    // Original: B.EQ #0x100053c7c (80 01 00 54)
    // Patched:  B    #0x100053c7c (0c 00 00 14)
    void *gate_addr = (void *)(base + 0x53c4c);
    uint32_t patch_b = 0x1400000c; // B #0x30 (12 instructions)
    if (PatchMemory(gate_addr, &patch_b, 4)) {
        WriteAuditLog(@"PATCH", @"✅ Patched integrity check gate at 0x%lx -> Unconditional Jump (B #0x53c7c)", (unsigned long)gate_addr);
    } else {
        WriteAuditLog(@"PATCH", @"⚠️ Failed to patch memory at 0x%lx", (unsigned long)gate_addr);
    }

    // 3. Bypass secondary integrity check: sub_100607F44 (offset 0x1538918)
    void *guard_byte = (void *)(base + 0x1538918);
    uint8_t one = 1;
    PatchMemory(guard_byte, &one, 1);
}

// ------------------------------------------------------------------------------
// Dynamic Hooking Engine
// ------------------------------------------------------------------------------
typedef void (*MSHookFunction_t)(void *symbol, void *hook, void **old);
typedef int (*DobbyHook_t)(void *function_address, void *replace_call_address, void **origin_call_address);

static BOOL HookFunction(void *target, void *replacement, void **orig) {
    if (!target) return NO;

    MSHookFunction_t msHook = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (msHook) {
        msHook(target, replacement, orig);
        return YES;
    }

    DobbyHook_t dobbyHook = (DobbyHook_t)dlsym(RTLD_DEFAULT, "DobbyHook");
    if (dobbyHook) {
        return (dobbyHook(target, replacement, orig) == 0);
    }

    // Direct branch trampoline fallback
    uint32_t trampoline[4];
    trampoline[0] = 0x58000050; // LDR X16, #8
    trampoline[1] = 0xd61f0200; // BR X16
    memcpy(&trampoline[2], &replacement, 8);
    return PatchMemory(target, trampoline, 16);
}

// ------------------------------------------------------------------------------
// Anti-Debug Hook (Block PT_DENY_ATTACH)
// ------------------------------------------------------------------------------
typedef int (*ptrace_t)(int request, pid_t pid, caddr_t addr, int data);
static ptrace_t orig_ptrace = NULL;

static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 31) { // PT_DENY_ATTACH = 31
        WriteAuditLog(@"ANTI_DEBUG", @"🛡️ Blocked ptrace(PT_DENY_ATTACH)");
        return 0;
    }
    return orig_ptrace ? orig_ptrace(request, pid, addr, data) : 0;
}

// ------------------------------------------------------------------------------
// CURL Hooks
// ------------------------------------------------------------------------------
#define CURLOPT_URL             10002
#define CURLOPT_POSTFIELDS      10015
#define CURLOPT_USERPWD         10018
#define CURLOPT_PINNEDPUBLICKEY 10230

static NSString *capturedEndpoint = nil;

typedef uintptr_t (*curl_easy_setopt_t)(uintptr_t handle, int option, ...);
static curl_easy_setopt_t orig_curl_easy_setopt = NULL;

static uintptr_t my_curl_easy_setopt(uintptr_t handle, int option, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7, uintptr_t a8, uintptr_t val) {
    @autoreleasepool {
        switch (option) {
            case CURLOPT_URL: {
                const char *url = (const char *)val;
                if (url) {
                    capturedEndpoint = [NSString stringWithUTF8String:url];
                    WriteAuditLog(@"CURL", @"🎯🎯🎯 [DECRYPTED ENDPOINT URL]: %s", url);
                    
                    // Show on-screen notification alert if on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIWindow *keyWindow = nil;
                        for (UIWindow *w in UIApplication.sharedApplication.windows) {
                            if (w.isKeyWindow) { keyWindow = w; break; }
                        }
                        UIViewController *root = keyWindow.rootViewController;
                        if (root) {
                            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 Endpoint Captured!"
                                                                                           message:[NSString stringWithFormat:@"URL: %s", url]
                                                                                    preferredStyle:UIAlertControllerStyleAlert];
                            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                            [root presentViewController:alert animated:YES completion:nil];
                        }
                    });
                }
                break;
            }
            case CURLOPT_POSTFIELDS: {
                const char *body = (const char *)val;
                WriteAuditLog(@"CURL", @"📦 [CURLOPT_POSTFIELDS]: %s", body ? body : "(null)");
                break;
            }
            case CURLOPT_USERPWD: {
                const char *userpwd = (const char *)val;
                WriteAuditLog(@"CURL", @"🔑 [CURLOPT_USERPWD]: %s", userpwd ? userpwd : "(null)");
                break;
            }
            case CURLOPT_PINNEDPUBLICKEY: {
                const char *pin = (const char *)val;
                WriteAuditLog(@"CURL", @"🔒 [CURLOPT_PINNEDPUBLICKEY]: %s", pin ? pin : "(null)");
                break;
            }
            default:
                break;
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
// dlopen Hook
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
__attribute__((unused)) static void SwizzleInstanceMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

__attribute__((unused)) static void SwizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

// Hook: UIAlertController
typedef id (*AlertImp_t)(id, SEL, NSString*, NSString*, UIAlertControllerStyle);
static AlertImp_t orig_alert = NULL;

static id my_alert(id self, SEL _cmd, NSString *title, NSString *message, UIAlertControllerStyle style) {
    WriteAuditLog(@"ALERT_POPUP", @"⚠️ Popup triggered! Title: '%@', Message: '%@'", title, message);
    return orig_alert(self, _cmd, title, message, style);
}

// ------------------------------------------------------------------------------
// Auto-Trigger Decryption (Calls login action automatically after UI loads)
// ------------------------------------------------------------------------------
static void ScheduleAutoDecrypt(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (capturedEndpoint) {
            WriteAuditLog(@"AUTO_DECRYPT", @"Endpoint already captured: %@", capturedEndpoint);
            return;
        }

        WriteAuditLog(@"AUTO_DECRYPT", @"⚡ Executing Auto-Trigger to extract Endpoint URL...");

        UIWindow *keyWindow = nil;
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        UIViewController *root = keyWindow ? keyWindow.rootViewController : nil;
        if (!root) {
            root = UIApplication.sharedApplication.windows.firstObject.rootViewController;
        }

        if (root && [NSStringFromClass(root.class) isEqualToString:@"VNTISFHTNSFJ"]) {
            WriteAuditLog(@"AUTO_DECRYPT", @"Found VNTISFHTNSFJ controller at %p", root);

            // Set textField to trigger valid length check
            Ivar ivar = class_getInstanceVariable(root.class, "textField");
            if (ivar) {
                UITextField *tf = object_getIvar(root, ivar);
                if (tf && [tf isKindOfClass:UITextField.class]) {
                    tf.text = @"AutoAuditKey12345678901234567890";
                    WriteAuditLog(@"AUTO_DECRYPT", @"Filled textField with test key");
                }
            }

            // Call -[VNTISFHTNSFJ POWMFHANGHT:] directly
            SEL loginSel = NSSelectorFromString(@"POWMFHANGHT:");
            if ([root respondsToSelector:loginSel]) {
                WriteAuditLog(@"AUTO_DECRYPT", @"Calling -[VNTISFHTNSFJ POWMFHANGHT:] to trigger verifier and URL decryption!");
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [root performSelector:loginSel withObject:nil];
                #pragma clang diagnostic pop
            }
        } else {
            WriteAuditLog(@"AUTO_DECRYPT", @"Root controller is not VNTISFHTNSFJ (found: %@)", root ? NSStringFromClass(root.class) : @"nil");
        }
    });
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

        // 3. Patch Integrity Check & Install Crash Guards (Fixes crash on inject)
        InstallCrashGuards(base);

        // 4. Hook Anti-Debug ptrace
        void *ptrace_ptr = dlsym(RTLD_DEFAULT, "ptrace");
        if (ptrace_ptr) {
            HookFunction(ptrace_ptr, (void *)my_ptrace, (void **)&orig_ptrace);
        }

        // 5. Hook libcurl Functions
        void *target_setopt = (void *)(base + 0x00bd0dd4);
        if (HookFunction(target_setopt, (void *)my_curl_easy_setopt, (void **)&orig_curl_easy_setopt)) {
            WriteAuditLog(@"INIT", @"✅ Hooked curl_easy_setopt at 0x%lx", (unsigned long)target_setopt);
        }

        void *target_perform = (void *)(base + 0x00ba7c90);
        if (HookFunction(target_perform, (void *)my_curl_easy_perform, (void **)&orig_curl_easy_perform)) {
            WriteAuditLog(@"INIT", @"✅ Hooked curl_easy_perform at 0x%lx", (unsigned long)target_perform);
        }

        // 6. Hook dlopen
        void *dlopen_ptr = dlsym(RTLD_DEFAULT, "dlopen");
        if (dlopen_ptr) {
            HookFunction(dlopen_ptr, (void *)my_dlopen, (void **)&orig_dlopen);
        }

        // 7. Hook Popups
        Class alertClass = objc_getClass("UIAlertController");
        if (alertClass) {
            SwizzleClassMethod(alertClass, @selector(alertControllerWithTitle:message:preferredStyle:), (IMP)my_alert, (IMP *)&orig_alert);
        }

        // 8. Auto-Trigger Decryption (Auto calls login to decrypt URL without waiting for user)
        if (!isOverlayProcess) {
            ScheduleAutoDecrypt();
        }

        WriteAuditLog(@"INIT", @"🎉 All guards and auto-decrypt triggers installed successfully!");
    }
}
