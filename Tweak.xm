// Plain Objective-C++: no Logos/Substrate dependency; build with build.sh.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#include <atomic>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>

static int logFD = -1;
static pthread_mutex_t logLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned logLines = 0;
static NSString *logPath;

static void Trace(NSString *event) {
    int saved = errno;
    pthread_mutex_lock(&logLock);
    // ponytail: bounded diagnostic session; restart app for a fresh 20000-line log.
    if (logLines++ < 20000) {
        NSString *line = [NSString stringWithFormat:@"%.6f pid=%d uid=%d main=%d %@\n",
            NSDate.date.timeIntervalSince1970, getpid(), getuid(), NSThread.isMainThread, event];
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "%{public}s", line.UTF8String);
        if (logFD >= 0) {
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            const char *p = (const char *)data.bytes;
            size_t remaining = data.length;
            while (remaining) {
                ssize_t n = write(logFD, p, remaining);
                if (n < 0 && errno == EINTR) continue;
                if (n <= 0) break;
                p += n;
                remaining -= (size_t)n;
            }
        }
    }
    pthread_mutex_unlock(&logLock);
    errno = saved;
}

static void ViewState(id object, NSString *stage) {
    if (!NSThread.isMainThread) {
        Trace([stage stringByAppendingString:@" ui-snapshot-skipped=non-main-thread"]);
        return;
    }
    UIView *view = nil;
    if ([object isKindOfClass:UIViewController.class]) {
        UIViewController *vc = object;
        if (vc.isViewLoaded) view = vc.view; // Never trigger loadView while observing.
    } else if ([object isKindOfClass:UIView.class]) view = object;
    Trace([NSString stringWithFormat:@"%@ object=%p view=%p window=%p hidden=%d alpha=%.3f frame=%@ subviews=%lu",
        stage, (__bridge void *)object, (__bridge void *)view, (__bridge void *)view.window,
        view.hidden, view.alpha, NSStringFromCGRect(view.frame), (unsigned long)view.subviews.count]);
    if ([NSStringFromClass([object class]) isEqualToString:@"PSNVHRBF"]) {
        Ivar iv = class_getInstanceVariable([object class], "_floatingIcon");
        id icon = iv ? object_getIvar(object, iv) : nil;
        if ([icon isKindOfClass:UIView.class]) {
            UIView *v = icon;
            Trace([NSString stringWithFormat:@"%@ icon=%p parent=%p window=%p hidden=%d alpha=%.3f frame=%@ gestures=%lu",
                stage, (__bridge void *)v, (__bridge void *)v.superview, (__bridge void *)v.window,
                v.hidden, v.alpha, NSStringFromCGRect(v.frame), (unsigned long)v.gestureRecognizers.count]);
        } else Trace([stage stringByAppendingString:@" icon=nil-or-unavailable"]);
    }
}

static bool TypeIs(Method m, unsigned index, const char *expected) {
    char *type = method_copyArgumentType(m, index);
    bool same = type && strcmp(type, expected) == 0;
    free(type);
    return same;
}

static Method Checked(Class cls, SEL sel, unsigned argc, const char *ret) {
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    char *actual = m ? method_copyReturnType(m) : NULL;
    bool good = m && method_getNumberOfArguments(m) == argc && actual && strcmp(actual, ret) == 0;
    free(actual);
    if (!good) Trace([NSString stringWithFormat:@"SKIP %@ %@ absent-or-signature-mismatch",
        cls ? NSStringFromClass(cls) : @"missing-class", NSStringFromSelector(sel)]);
    return good ? m : NULL;
}

static void Install(Class cls, SEL sel, Method method, id block) {
    IMP replacement = imp_implementationWithBlock(block);
    // Add an override for inherited methods; never modify the superclass method.
    class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(method));
    Trace([NSString stringWithFormat:@"HOOK %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel)]);
}

static void HookVoid0(NSString *name, NSString *selector, bool meta = false) {
    Class cls = NSClassFromString(name);
    if (meta && cls) cls = object_getClass(cls);
    SEL sel = NSSelectorFromString(selector);
    Method m = Checked(cls, sel, 2, "v");
    if (!m) return;
    IMP original = method_getImplementation(m);
    NSString *label = [NSString stringWithFormat:@"%@ %@", name, selector];
    Install(cls, sel, m, ^(id self) {
        Trace([@"ENTER " stringByAppendingString:label]);
        @try { ((void (*)(id, SEL))original)(self, sel); }
        @catch (NSException *ex) { Trace([NSString stringWithFormat:@"EXCEPTION %@ name=%@", label, ex.name]); @throw; }
        Trace([@"EXIT " stringByAppendingString:label]);
        if (!meta) ViewState(self, label);
    });
}

static void HookVoid1(NSString *name, NSString *selector, bool firstOnly = false) {
    Class cls = NSClassFromString(name);
    SEL sel = NSSelectorFromString(selector);
    Method m = Checked(cls, sel, 3, "v");
    if (!m || !TypeIs(m, 2, "@")) return;
    IMP original = method_getImplementation(m);
    NSString *label = [NSString stringWithFormat:@"%@ %@", name, selector];
    // Shared state survives the installed block; first-frame logging avoids frame-rate overhead.
    auto *seen = new std::atomic<bool>(false);
    Install(cls, sel, m, ^(id self, id argument) {
        bool record = !firstOnly || !seen->exchange(true);
        if (record) Trace([@"ENTER " stringByAppendingString:label]);
        @try { ((void (*)(id, SEL, id))original)(self, sel, argument); }
        @catch (NSException *ex) { Trace([NSString stringWithFormat:@"EXCEPTION %@ name=%@", label, ex.name]); @throw; }
        if (record) {
            Trace([@"EXIT " stringByAppendingString:label]);
            ViewState(self, label);
        }
    });
}

static void HookRendererInit(void) {
    Class cls = NSClassFromString(@"LAFHTNFJTS");
    SEL sel = @selector(initWithNibName:bundle:);
    Method m = Checked(cls, sel, 4, "@");
    if (!m || !TypeIs(m, 2, "@") || !TypeIs(m, 3, "@")) return;
    IMP original = method_getImplementation(m);
    Install(cls, sel, m, ^id(id self, id nib, id bundle) {
        Trace(@"ENTER renderer.initWithNibName:bundle:");
        id result;
        @try { result = ((id (*)(id, SEL, id, id))original)(self, sel, nib, bundle); }
        @catch (NSException *ex) { Trace([@"EXCEPTION renderer.init " stringByAppendingString:ex.name]); @throw; }
        Trace([NSString stringWithFormat:@"EXIT renderer.init result=%p", (__bridge void *)result]);
        return result;
    });
}

static void HookDelegate(void) {
    Class cls = NSClassFromString(@"GWGCBAHTNSFR");
    SEL sel = @selector(application:didFinishLaunchingWithOptions:);
    Method m = Checked(cls, sel, 4, @encode(BOOL));
    if (!m || !TypeIs(m, 2, "@") || !TypeIs(m, 3, "@")) return;
    IMP original = method_getImplementation(m);
    Install(cls, sel, m, ^BOOL(id self, id app, id options) {
        Trace(@"ENTER overlay.didFinishLaunching");
        BOOL result;
        @try { result = ((BOOL (*)(id, SEL, id, id))original)(self, sel, app, options); }
        @catch (NSException *ex) { Trace([@"EXCEPTION overlay.didFinishLaunching " stringByAppendingString:ex.name]); @throw; }
        Trace([NSString stringWithFormat:@"EXIT overlay.didFinishLaunching result=%d", result]);
        return result;
    });
}

static void HookHosting(void) {
    Class cls = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    SEL sel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    Method m = Checked(cls, sel, 4, "v");
    if (!m || !TypeIs(m, 2, @encode(unsigned int)) || !TypeIs(m, 3, @encode(double))) return;
    IMP original = method_getImplementation(m);
    Install(cls, sel, m, ^(id self, unsigned int context, double level) {
        Trace([NSString stringWithFormat:@"ENTER hosting context=%u level=%.1f", context, level]);
        ((void (*)(id, SEL, unsigned int, double))original)(self, sel, context, level);
        Trace(@"EXIT hosting (return does not prove system accepted registration)");
    });
}

static bool RelevantView(UIView *view) {
    if ([view isKindOfClass:UIWindow.class]) return true;
    for (UIResponder *r = view; r; r = r.nextResponder)
        if ([NSStringFromClass(r.class) isEqualToString:@"PSNVHRBF"] ||
            [NSStringFromClass(r.class) isEqualToString:@"LAFHTNFJTS"]) return true;
    return false;
}

static void HookVisibility(void) {
    Class cls = UIView.class;
    SEL sel = @selector(setHidden:);
    Method m = Checked(cls, sel, 3, "v");
    if (!m || !TypeIs(m, 2, @encode(BOOL))) return;
    IMP original = method_getImplementation(m);
    Install(cls, sel, m, ^(UIView *self, BOOL hidden) {
        ((void (*)(id, SEL, BOOL))original)(self, sel, hidden);
        if (NSThread.isMainThread && RelevantView(self))
            ViewState(self, [NSString stringWithFormat:@"setHidden:%d %@", hidden, NSStringFromClass(self.class)]);
    });
}

__attribute__((constructor)) static void StartTrace(void) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"TempMail"]) return;
        NSString *filename = [NSString stringWithFormat:@"TempMailTrace-%d-%d-%.0f.log", getuid(), getpid(), NSDate.date.timeIntervalSince1970];
        NSURL *documents = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory
            inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
        logPath = documents ? [[documents URLByAppendingPathComponent:filename] path] : nil;
        if (logPath)
            logFD = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
        BOOL child = [NSProcessInfo.processInfo.arguments containsObject:@"-a"];
        Trace([NSString stringWithFormat:@"TRACE_START mode=%@ ppid=%d path=%@ file-open=%d",
            child ? @"overlay(-a)" : @"main", getppid(), logPath, logFD >= 0]);
        HookVoid1(@"VNTISFHTNSFJ", @"POWMFHANGHT:");
        HookVoid1(@"VNTISFHTNSFJ", @"GAJKGNRXCHR:");
        HookVoid0(@"GIAFNTHFSBTR", @"__completeAndRunAsPlugin");
        HookDelegate();
        HookRendererInit();
        for (NSString *name in @[@"PSNVHRBF", @"LAFHTNFJTS"]) {
            HookVoid0(name, @"loadView");
            HookVoid0(name, @"viewDidLoad");
        }
        HookVoid0(@"PSNVHRBF", @"toggleImGuiView");
        HookVoid0(@"PSNVHRBF", @"_clampFloatingIconToScreen");
        HookVoid0(@"LAFHTNFJTS", @"HSFGTGV", true);
        HookVoid1(@"LAFHTNFJTS", @"drawInMTKView:", true);
        HookVoid0(@"UIWindow", @"makeKeyAndVisible");
        HookHosting();
        HookVisibility();
        // Main-queue heartbeat: absence after ENTER can indicate main-thread blocking, not its cause.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            Trace(@"HEARTBEAT main-queue-after-5s");
        });
        Trace(@"HOOKS_READY; no key/token/body logging; no return-value modifications");
    }
}
