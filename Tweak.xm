// SKCrashReporter.xm
// Add to your Makefile: iSK_FILES = Tweak.xm SKCrashReporter.xm
// Or #import "SKCrashReporter.xm" at the top of Tweak.xm if you prefer 1 file.
//
// All C code lives inside %{ %} — Logos never parses those braces.
// Only the two %hook blocks at the bottom are touched by Logos.

%{

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/utsname.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define SK_CRASH_API    @"https://YOUR_SERVER/crash_api.php"
#define SK_APP_VER      "10.7"
#define SK_BUILD        "271.ef2ca7"
#define SK_CRASH_FILE   "SKPendingCrash.json"
#define SK_BUF          65536

// ── Globals (written before crash, read inside signal handler) ────────────────
static char sk_crashPath[1024];
static char sk_model[64];
static char sk_ios[32];
static char sk_devid[64];
static char sk_action[256];

// ── Signal handler old-action slots ──────────────────────────────────────────
static struct sigaction sk_old_segv, sk_old_abrt, sk_old_bus,
                         sk_old_ill,  sk_old_fpe,  sk_old_pipe;

// ── ObjC exception chain ──────────────────────────────────────────────────────
static NSUncaughtExceptionHandler *sk_prevHandler = NULL;

// ─────────────────────────────────────────────────────────────────────────────
// Async-signal-safe helpers — NO malloc, NO ObjC, NO buffered I/O
// ─────────────────────────────────────────────────────────────────────────────
static void sk_copy(char *d, const char *s, size_t n) {
    if (!d || !s || n == 0) return;
    size_t i = 0;
    while (i < n-1 && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static void sk_fdwrite(int fd, const char *s) {
    if (fd < 0 || !s) return;
    size_t len = strlen(s);
    while (len > 0) {
        ssize_t w = write(fd, s, len);
        if (w <= 0) break;
        s += w; len -= (size_t)w;
    }
}

static void sk_escape(char *out, size_t sz, const char *in) {
    if (!out || sz < 2) return;
    if (!in) { out[0] = '\0'; return; }
    size_t wi = 0;
    for (size_t i = 0; in[i] && wi+6 < sz; i++) {
        unsigned char c = (unsigned char)in[i];
        if      (c == '"')  { out[wi++]='\\'; out[wi++]='"';  }
        else if (c == '\\') { out[wi++]='\\'; out[wi++]='\\'; }
        else if (c == '\n') { out[wi++]='\\'; out[wi++]='n';  }
        else if (c == '\r') { out[wi++]='\\'; out[wi++]='r';  }
        else if (c == '\t') { out[wi++]='\\'; out[wi++]='t';  }
        else if (c < 0x20)  { }
        else                { out[wi++]=(char)c; }
    }
    out[wi] = '\0';
}

// ─────────────────────────────────────────────────────────────────────────────
// Write crash JSON to disk — async-signal-safe
// ─────────────────────────────────────────────────────────────────────────────
static void sk_writeCrash(const char *type, const char *reason, const char *log) {
    if (!sk_crashPath[0]) return;
    int fd = open(sk_crashPath, O_CREAT|O_WRONLY|O_TRUNC, 0644);
    if (fd < 0) return;

    // Static so signal-stack usage stays minimal
    static char eType[256], eReason[1024], eLog[SK_BUF];
    static char eModel[128], eOS[64], eID[128], eAct[512];

    sk_escape(eType,   sizeof(eType),   type   ? type   : "Unknown");
    sk_escape(eReason, sizeof(eReason), reason ? reason : "");
    sk_escape(eLog,    sizeof(eLog),    log    ? log    : "");
    sk_escape(eModel,  sizeof(eModel),  sk_model[0]  ? sk_model  : "Unknown-early");
    sk_escape(eOS,     sizeof(eOS),     sk_ios[0]    ? sk_ios    : "Unknown-early");
    sk_escape(eID,     sizeof(eID),     sk_devid[0]  ? sk_devid  : "Unknown-early");
    sk_escape(eAct,    sizeof(eAct),    sk_action[0] ? sk_action : "Crash at launch");

    sk_fdwrite(fd, "{");
    sk_fdwrite(fd, "\"crash_type\":\"");    sk_fdwrite(fd, eType);    sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"crash_reason\":\"");  sk_fdwrite(fd, eReason);  sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"crash_log\":\"");     sk_fdwrite(fd, eLog);     sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"device_model\":\"");  sk_fdwrite(fd, eModel);   sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"ios_version\":\"");   sk_fdwrite(fd, eOS);      sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"device_id\":\"");     sk_fdwrite(fd, eID);      sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"user_action\":\"");   sk_fdwrite(fd, eAct);     sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"app_version\":\"");   sk_fdwrite(fd, SK_APP_VER); sk_fdwrite(fd, "\",");
    sk_fdwrite(fd, "\"dylib_build\":\"");   sk_fdwrite(fd, SK_BUILD);   sk_fdwrite(fd, "\"");
    sk_fdwrite(fd, "}");
    close(fd);
}

// ─────────────────────────────────────────────────────────────────────────────
// Backtrace — async-signal-safe
// ─────────────────────────────────────────────────────────────────────────────
static void sk_backtrace(char *out, size_t sz) {
    if (!out || sz < 2) { if (out) out[0]='\0'; return; }
    out[0] = '\0';
    void  *frames[128];
    int    cnt  = backtrace(frames, 128);
    char **syms = backtrace_symbols(frames, cnt);
    size_t w = 0;
    if (syms) {
        for (int i = 0; i < cnt && w+256 < sz; i++) {
            const char *s = syms[i] ? syms[i] : "???";
            size_t l = strlen(s);
            if (w+l+2 >= sz) break;
            memcpy(out+w, s, l);
            w += l;
            out[w++] = '\n';
        }
        // intentionally not freeing — process is dying
    } else {
        char a[32];
        for (int i = 0; i < cnt && w+32 < sz; i++) {
            snprintf(a, sizeof(a), "%p\n", frames[i]);
            size_t l = strlen(a);
            memcpy(out+w, a, l);
            w += l;
        }
    }
    out[w] = '\0';
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal handler
// ─────────────────────────────────────────────────────────────────────────────
static const char *sk_signame(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV (Bad Memory Access)";
        case SIGABRT: return "SIGABRT (Abort)";
        case SIGBUS:  return "SIGBUS (Bus Error)";
        case SIGILL:  return "SIGILL (Illegal Instruction)";
        case SIGFPE:  return "SIGFPE (Floating Point Exception)";
        case SIGPIPE: return "SIGPIPE (Broken Pipe)";
        default:      return "SIGNAL (Unknown)";
    }
}

static void sk_sighandler(int sig, siginfo_t *info, void *ctx) {
    static char bt[SK_BUF];
    static char full[SK_BUF + 512];
    sk_backtrace(bt, sizeof(bt));
    char addr[32];
    snprintf(addr, sizeof(addr), "%p", info ? info->si_addr : (void *)0);
    snprintf(full, sizeof(full),
        "Signal: %s (%d)\nFault Address: %s\nDevice populated: %s\n\n=== Backtrace ===\n%s",
        sk_signame(sig), sig, addr,
        sk_model[0] ? "yes" : "no — crash before UIDevice init",
        bt);
    sk_writeCrash(sk_signame(sig), "Fatal signal", full);
    struct sigaction *old = NULL;
    switch (sig) {
        case SIGSEGV: old = &sk_old_segv; break;
        case SIGABRT: old = &sk_old_abrt; break;
        case SIGBUS:  old = &sk_old_bus;  break;
        case SIGILL:  old = &sk_old_ill;  break;
        case SIGFPE:  old = &sk_old_fpe;  break;
        case SIGPIPE: old = &sk_old_pipe; break;
    }
    if (old) sigaction(sig, old, NULL);
    else     signal(sig, SIG_DFL);
    raise(sig);
}

// ─────────────────────────────────────────────────────────────────────────────
// ObjC exception handler
// ─────────────────────────────────────────────────────────────────────────────
static void sk_exceptionHandler(NSException *ex) {
    NSString *name   = ex.name   ?: @"Unknown";
    NSString *reason = ex.reason ?: @"No reason";
    NSMutableString *log = [NSMutableString string];
    [log appendFormat:@"Exception: %@\nReason: %@\n", name, reason];
    if (!sk_model[0])
        [log appendString:@"Note: crash before UIDevice init\n"];
    [log appendString:@"\n=== Call Stack ===\n"];
    for (NSString *f in (ex.callStackSymbols ?: @[]))
        [log appendFormat:@"%@\n", f];
    if (ex.userInfo.count)
        [log appendFormat:@"\n=== UserInfo ===\n%@\n", ex.userInfo];
    sk_writeCrash(
        [NSString stringWithFormat:@"ObjC: %@", name].UTF8String,
        reason.UTF8String,
        log.UTF8String
    );
    if (sk_prevHandler) sk_prevHandler(ex);
}

// ─────────────────────────────────────────────────────────────────────────────
// CONSTRUCTOR — runs before main(), before any app code
// This is what catches instant-on-launch crashes.
// Only uses getenv() + sigaction() — no heap, no ObjC needed at this point.
// ─────────────────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void sk_earlyInit(void) {
    const char *home = getenv("HOME");
    snprintf(sk_crashPath, sizeof(sk_crashPath), "%s/Documents/%s",
             home ? home : "/tmp", SK_CRASH_FILE);

    sk_copy(sk_model,  "Unknown-early",          sizeof(sk_model));
    sk_copy(sk_ios,    "Unknown-early",           sizeof(sk_ios));
    sk_copy(sk_devid,  "Unknown-early",           sizeof(sk_devid));
    sk_copy(sk_action, "Crash before app launched", sizeof(sk_action));

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sigemptyset(&sa.sa_mask);
    sa.sa_flags     = SA_SIGINFO | SA_ONSTACK;
    sa.sa_sigaction = sk_sighandler;
    sigaction(SIGSEGV, &sa, &sk_old_segv);
    sigaction(SIGABRT, &sa, &sk_old_abrt);
    sigaction(SIGBUS,  &sa, &sk_old_bus);
    sigaction(SIGILL,  &sa, &sk_old_ill);
    sigaction(SIGFPE,  &sa, &sk_old_fpe);
    sigaction(SIGPIPE, &sa, &sk_old_pipe);

    sk_prevHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(sk_exceptionHandler);
}

// ─────────────────────────────────────────────────────────────────────────────
// Fill real device info — called after UIDevice is available
// ─────────────────────────────────────────────────────────────────────────────
static void sk_populateDevice(void) {
    struct utsname u;
    uname(&u);
    sk_copy(sk_model, u.machine, sizeof(sk_model));
    NSString *ver = [[UIDevice currentDevice] systemVersion] ?: @"Unknown";
    sk_copy(sk_ios, ver.UTF8String, sizeof(sk_ios));
    NSString *did = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"Unknown";
    sk_copy(sk_devid, did.UTF8String, sizeof(sk_devid));
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload any pending crash from the previous run
// ─────────────────────────────────────────────────────────────────────────────
static void sk_uploadIfNeeded(void) {
    NSString *path = [NSString stringWithUTF8String:sk_crashPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data.length) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }
    NSLog(@"[SKCrash] Uploading: %@", dict[@"crash_type"] ?: @"?");

    NSMutableDictionary *payload = [dict mutableCopy];
    payload[@"action"] = @"report";

    // Delete BEFORE upload so a crash during upload doesn't loop forever
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 30;
    cfg.timeoutIntervalForResource = 60;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:SK_CRASH_API]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!body) return;

    [[[NSURLSession sessionWithConfiguration:cfg]
        uploadTaskWithRequest:req fromData:body
            completionHandler:^(NSData *resp, NSURLResponse *r, NSError *err) {
        if (err) { NSLog(@"[SKCrash] Upload failed: %@", err.localizedDescription); return; }
        NSDictionary *res = [NSJSONSerialization
            JSONObjectWithData:resp ?: [NSData data] options:0 error:nil];
        NSLog(@"[SKCrash] Upload OK: %@", res ?: @"(non-JSON)");
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// Public — call from panel buttons so crash log shows which action crashed
// e.g.  SKCrashNote(@"Tapped Upload");
// ─────────────────────────────────────────────────────────────────────────────
static void SKCrashNote(NSString *action) {
    if (action) sk_copy(sk_action, action.UTF8String, sizeof(sk_action));
}

%}  // ── end of %{ %} verbatim block ──────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// Logos hooks — the ONLY thing Logos parses
// ─────────────────────────────────────────────────────────────────────────────

%hook UIApplication

- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL result = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        sk_populateDevice();
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{ sk_uploadIfNeeded(); }
        );
    });
    return result;
}

%end
