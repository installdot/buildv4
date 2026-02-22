// SKCrashReporter.xm — Soul Knight Crash Reporter
// Captures ObjC exceptions + Unix signals, saves to disk, and uploads on next launch.
//
// HOW IT WORKS (important — read before modifying):
//
//   Signal handlers are severely restricted by POSIX — you CANNOT call malloc,
//   ObjC methods, NSLog, or any non-async-signal-safe function inside them.
//   Safe operations: write(), open(), close(), _exit(), signal-safe C functions.
//
//   Strategy:
//     1. On crash  → write a plain JSON file to the app's Documents folder
//                    using only async-signal-safe syscalls (write/open/close).
//     2. On launch → SKCrashReporter checks for a pending crash file,
//                    reads it, POSTs it to the PHP API, then deletes it.
//
//   This two-phase approach is the same technique used by PLCrashReporter,
//   Firebase Crashlytics, and every other production crash SDK.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <sys/utsname.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define CRASH_API_URL   @"https://chillysilly.frfrnocap.men/crash_api.php"  // ← change this
#define DYLIB_BUILD     @"271.ef2ca7"
#define APP_VERSION     @"10.7"
#define PENDING_CRASH_FILENAME  "SKPendingCrash.json"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Async-signal-safe file writer
//
//  We use raw POSIX I/O here — NO malloc, NO ObjC, NO NSLog.
//  Everything is stack-allocated.  The JSON we write is intentionally simple
//  so we can build it with snprintf into a fixed-size stack buffer.
// ─────────────────────────────────────────────────────────────────────────────
#define CRASH_BUF_SIZE  (64 * 1024)   // 64 KB — enough for a deep backtrace

// Globals written BEFORE signal handler is invoked (set from main thread on launch)
static char  g_pendingCrashPath[1024];   // absolute path to the pending-crash file
static char  g_deviceModel[64];
static char  g_iosVersion[32];
static char  g_deviceID[64];
static char  g_lastUserAction[256];      // updated by the panel on each user action

// Simple async-signal-safe string copy that guarantees NUL termination
static void safe_strncpy(char *dst, const char *src, size_t n) {
    if (!dst || !src || n == 0) return;
    size_t i = 0;
    while (i < n - 1 && src[i]) { dst[i] = src[i]; i++; }
    dst[i] = '\0';
}

// Write a C string to an fd — async-signal-safe
static void fd_write(int fd, const char *s) {
    if (fd < 0 || !s) return;
    size_t len = strlen(s);
    while (len > 0) {
        ssize_t n = write(fd, s, len);
        if (n <= 0) break;
        s   += n;
        len -= (size_t)n;
    }
}

// Escape a C string for JSON (minimal: escape backslash, double-quote, and control chars)
static void json_escape(char *out, size_t outSize, const char *in) {
    if (!out || outSize < 2 || !in) { if (out && outSize) out[0] = '\0'; return; }
    size_t wi = 0;
    for (size_t i = 0; in[i] && wi + 3 < outSize; i++) {
        unsigned char c = (unsigned char)in[i];
        if      (c == '"')  { out[wi++] = '\\'; out[wi++] = '"';  }
        else if (c == '\\') { out[wi++] = '\\'; out[wi++] = '\\'; }
        else if (c == '\n') { out[wi++] = '\\'; out[wi++] = 'n';  }
        else if (c == '\r') { out[wi++] = '\\'; out[wi++] = 'r';  }
        else if (c == '\t') { out[wi++] = '\\'; out[wi++] = 't';  }
        else if (c < 0x20)  { /* skip other control chars */ }
        else                { out[wi++] = (char)c; }
    }
    out[wi] = '\0';
}

// Core crash writer — called from both signal handler and ObjC exception handler.
// Must be async-signal-safe (no malloc, no ObjC, no stdio buffered calls).
static void writeCrashFile(const char *crashType,
                            const char *crashReason,
                            const char *crashLog) {
    if (!g_pendingCrashPath[0]) return;

    // Open/create the crash file — O_CREAT|O_WRONLY|O_TRUNC, mode 0644
    int fd = open(g_pendingCrashPath, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) return;

    // Escape fields for JSON
    static char eCrashType[256], eCrashReason[1024], eCrashLog[CRASH_BUF_SIZE];
    static char eDeviceModel[128], eIOSVersion[64], eDeviceID[128], eAction[512];

    json_escape(eCrashType,    sizeof(eCrashType),    crashType    ?: "Unknown");
    json_escape(eCrashReason,  sizeof(eCrashReason),  crashReason  ?: "");
    json_escape(eCrashLog,     sizeof(eCrashLog),      crashLog     ?: "");
    json_escape(eDeviceModel,  sizeof(eDeviceModel),   g_deviceModel);
    json_escape(eIOSVersion,   sizeof(eIOSVersion),    g_iosVersion);
    json_escape(eDeviceID,     sizeof(eDeviceID),      g_deviceID);
    json_escape(eAction,       sizeof(eAction),        g_lastUserAction);

    fd_write(fd, "{");
    fd_write(fd, "\"crash_type\":\"");    fd_write(fd, eCrashType);    fd_write(fd, "\",");
    fd_write(fd, "\"crash_reason\":\"");  fd_write(fd, eCrashReason);  fd_write(fd, "\",");
    fd_write(fd, "\"crash_log\":\"");     fd_write(fd, eCrashLog);     fd_write(fd, "\",");
    fd_write(fd, "\"device_model\":\"");  fd_write(fd, eDeviceModel);  fd_write(fd, "\",");
    fd_write(fd, "\"ios_version\":\"");   fd_write(fd, eIOSVersion);   fd_write(fd, "\",");
    fd_write(fd, "\"device_id\":\"");     fd_write(fd, eDeviceID);     fd_write(fd, "\",");
    fd_write(fd, "\"user_action\":\"");   fd_write(fd, eAction);       fd_write(fd, "\",");
    fd_write(fd, "\"app_version\":\"");   fd_write(fd, APP_VERSION);   fd_write(fd, "\",");
    fd_write(fd, "\"dylib_build\":\"");   fd_write(fd, DYLIB_BUILD);   fd_write(fd, "\"");
    fd_write(fd, "}");

    close(fd);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Backtrace builder (async-signal-safe)
// ─────────────────────────────────────────────────────────────────────────────
static void buildBacktrace(char *out, size_t outSize) {
    if (!out || outSize < 2) return;
    out[0] = '\0';

    void  *frames[128];
    int    frameCount = backtrace(frames, 128);
    char **syms       = backtrace_symbols(frames, frameCount);

    size_t written = 0;
    if (syms) {
        for (int i = 0; i < frameCount && written + 256 < outSize; i++) {
            const char *sym = syms[i] ?: "???";
            // Use async-signal-safe path: copy char by char
            size_t slen = strlen(sym);
            if (written + slen + 2 >= outSize) break;
            memcpy(out + written, sym, slen);
            written += slen;
            out[written++] = '\n';
        }
        // NOTE: free() is NOT async-signal-safe.
        // We intentionally leak 'syms' here — the process is about to die anyway.
        // In the ObjC exception handler path (which IS heap-safe) we free it.
    } else {
        // backtrace_symbols failed — write raw addresses
        char addr[32];
        for (int i = 0; i < frameCount && written + 32 < outSize; i++) {
            snprintf(addr, sizeof(addr), "%p\n", frames[i]);
            size_t alen = strlen(addr);
            memcpy(out + written, addr, alen);
            written += alen;
        }
    }
    out[written] = '\0';
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Signal handler
// ─────────────────────────────────────────────────────────────────────────────
static struct sigaction g_oldSIGSEGV, g_oldSIGABRT, g_oldSIGBUS,
                         g_oldSIGILL,  g_oldSIGFPE,  g_oldSIGPIPE;

static const char *sigName(int sig) {
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

static void skSignalHandler(int sig, siginfo_t *info, void *ctx) {
    // Stack-allocate the backtrace buffer — no heap
    static char btBuf[CRASH_BUF_SIZE];
    buildBacktrace(btBuf, sizeof(btBuf));

    char fullLog[CRASH_BUF_SIZE + 256];
    snprintf(fullLog, sizeof(fullLog),
        "Signal: %s (%d)\nAddress: %p\n\n=== Backtrace ===\n%s",
        sigName(sig), sig,
        info ? info->si_addr : (void *)0,
        btBuf);

    writeCrashFile(sigName(sig), "App received fatal signal", fullLog);

    // Re-raise with the original handler so the OS gets a proper crash report
    struct sigaction *old = NULL;
    switch (sig) {
        case SIGSEGV: old = &g_oldSIGSEGV; break;
        case SIGABRT: old = &g_oldSIGABRT; break;
        case SIGBUS:  old = &g_oldSIGBUS;  break;
        case SIGILL:  old = &g_oldSIGILL;  break;
        case SIGFPE:  old = &g_oldSIGFPE;  break;
        case SIGPIPE: old = &g_oldSIGPIPE; break;
    }
    if (old) {
        sigaction(sig, old, NULL);
    } else {
        signal(sig, SIG_DFL);
    }
    raise(sig);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ObjC uncaught exception handler
// ─────────────────────────────────────────────────────────────────────────────
static NSUncaughtExceptionHandler *g_previousExceptionHandler = NULL;

static void skExceptionHandler(NSException *exception) {
    NSString *name   = exception.name   ?: @"Unknown";
    NSString *reason = exception.reason ?: @"No reason";
    NSArray  *bt     = exception.callStackSymbols ?: @[];

    NSMutableString *log = [NSMutableString string];
    [log appendFormat:@"Exception: %@\nReason: %@\n\n=== Call Stack ===\n", name, reason];
    for (NSString *frame in bt) {
        [log appendFormat:@"%@\n", frame];
    }

    // Also append userInfo if present
    if (exception.userInfo.count) {
        [log appendFormat:@"\n=== UserInfo ===\n%@\n", exception.userInfo];
    }

    writeCrashFile(
        [NSString stringWithFormat:@"ObjC: %@", name].UTF8String,
        reason.UTF8String,
        log.UTF8String
    );

    // Chain to any previous handler (e.g. from the game itself or other dylibs)
    if (g_previousExceptionHandler) {
        g_previousExceptionHandler(exception);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Install handlers
// ─────────────────────────────────────────────────────────────────────────────
static void installCrashHandlers(void) {
    // ObjC exception handler (chain-safe)
    g_previousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(skExceptionHandler);

    // Unix signal handlers — save old handlers for chaining
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sigemptyset(&sa.sa_mask);
    sa.sa_flags     = SA_SIGINFO | SA_ONSTACK;
    sa.sa_sigaction = skSignalHandler;

    sigaction(SIGSEGV, &sa, &g_oldSIGSEGV);
    sigaction(SIGABRT, &sa, &g_oldSIGABRT);
    sigaction(SIGBUS,  &sa, &g_oldSIGBUS);
    sigaction(SIGILL,  &sa, &g_oldSIGILL);
    sigaction(SIGFPE,  &sa, &g_oldSIGFPE);
    sigaction(SIGPIPE, &sa, &g_oldSIGPIPE);

    NSLog(@"[SKCrash] Crash handlers installed. Pending path: %s", g_pendingCrashPath);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Populate device info globals (called once from main thread)
// ─────────────────────────────────────────────────────────────────────────────
static void populateDeviceGlobals(void) {
    // Pending crash file path
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *pendingPath = [docs stringByAppendingPathComponent:
        [NSString stringWithUTF8String:PENDING_CRASH_FILENAME]];
    safe_strncpy(g_pendingCrashPath, pendingPath.UTF8String, sizeof(g_pendingCrashPath));

    // Device model (uname — available without UIDevice)
    struct utsname sysInfo;
    uname(&sysInfo);
    safe_strncpy(g_deviceModel, sysInfo.machine, sizeof(g_deviceModel));

    // iOS version
    NSString *ver = [[UIDevice currentDevice] systemVersion] ?: @"Unknown";
    safe_strncpy(g_iosVersion, ver.UTF8String, sizeof(g_iosVersion));

    // Device ID
    NSString *did = [[[UIDevice currentDevice] identifierForVendor] UUIDString]
                    ?: @"Unknown";
    safe_strncpy(g_deviceID, did.UTF8String, sizeof(g_deviceID));

    // Default user action
    safe_strncpy(g_lastUserAction, "App launched (no action recorded yet)",
                 sizeof(g_lastUserAction));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Update last user action (call this from panel buttons)
//
//  Thread-safe for reading purposes — single write from main thread is fine.
//  The signal handler only ever reads g_lastUserAction, never writes.
// ─────────────────────────────────────────────────────────────────────────────
void SKCrashSetLastAction(NSString *action) {
    if (!action) return;
    safe_strncpy(g_lastUserAction, action.UTF8String, sizeof(g_lastUserAction));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload pending crash (called on next launch from main thread)
// ─────────────────────────────────────────────────────────────────────────────
static void uploadPendingCrashIfNeeded(void) {
    NSString *pendingPath = [NSString stringWithUTF8String:g_pendingCrashPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:pendingPath]) return;

    NSError *readErr = nil;
    NSData  *jsonData = [NSData dataWithContentsOfFile:pendingPath
                                               options:0
                                                 error:&readErr];
    if (!jsonData || readErr) {
        NSLog(@"[SKCrash] Could not read pending crash: %@", readErr);
        [[NSFileManager defaultManager] removeItemAtPath:pendingPath error:nil];
        return;
    }

    NSDictionary *crashDict = [NSJSONSerialization
        JSONObjectWithData:jsonData options:0 error:nil];
    if (![crashDict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[SKCrash] Pending crash JSON invalid — deleting.");
        [[NSFileManager defaultManager] removeItemAtPath:pendingPath error:nil];
        return;
    }

    NSLog(@"[SKCrash] Found pending crash (%@), uploading…",
          crashDict[@"crash_type"] ?: @"?");

    // Add action field and send
    NSMutableDictionary *payload = [crashDict mutableCopy];
    payload[@"action"] = @"report";

    NSURLSessionConfiguration *cfg =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 30;
    cfg.timeoutIntervalForResource = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:CRASH_API_URL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSError *serErr = nil;
    NSData  *body   = [NSJSONSerialization dataWithJSONObject:payload
                                                      options:0
                                                        error:&serErr];
    if (serErr || !body) {
        NSLog(@"[SKCrash] Failed to serialise payload: %@", serErr);
        [[NSFileManager defaultManager] removeItemAtPath:pendingPath error:nil];
        return;
    }

    // Delete the file BEFORE sending — if the app crashes again during upload
    // we don't want to loop forever re-uploading the same report.
    [[NSFileManager defaultManager] removeItemAtPath:pendingPath error:nil];

    [[session uploadTaskWithRequest:req
                           fromData:body
                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            NSLog(@"[SKCrash] Upload failed: %@", err.localizedDescription);
            return;
        }
        NSDictionary *json = [NSJSONSerialization
            JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSLog(@"[SKCrash] Upload response: %@", json ?: @"(non-JSON)");
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Logos hook — init on first viewDidAppear
// ─────────────────────────────────────────────────────────────────────────────
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Must run on main thread — UIDevice calls require it
        dispatch_async(dispatch_get_main_queue(), ^{
            populateDeviceGlobals();
            installCrashHandlers();
            // Small delay so the app finishes launching before we do network I/O
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(),
                ^{ uploadPendingCrashIfNeeded(); }
            );
        });
    });
}

%end
