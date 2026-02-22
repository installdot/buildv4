// SKCrashReporter.xm — Soul Knight Crash Reporter  v2
// Logos fix: all C/ObjC helper code is wrapped in %{ %} so the Logos
// preprocessor never tries to count braces inside plain C functions.

// ─────────────────────────────────────────────────────────────────────────────
// %{ ... %} = "pass through verbatim — do NOT parse as Logos"
// ─────────────────────────────────────────────────────────────────────────────
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
#define CRASH_API_URL          @"https://YOUR_SERVER/crash_api.php"
#define DYLIB_BUILD            @"271.ef2ca7"
#define APP_VERSION            @"10.7"
#define PENDING_CRASH_FILENAME "SKPendingCrash.json"
#define CRASH_BUF_SIZE         (64 * 1024)

// ── Globals ───────────────────────────────────────────────────────────────────
static char g_pendingCrashPath[1024];
static char g_deviceModel[64];
static char g_iosVersion[32];
static char g_deviceID[64];
static char g_lastUserAction[256];

// ── Async-signal-safe helpers ─────────────────────────────────────────────────
static void safe_strncpy(char *dst, const char *src, size_t n) {
    if (!dst || !src || n == 0) return;
    size_t i = 0;
    while (i < n - 1 && src[i]) { dst[i] = src[i]; i++; }
    dst[i] = '\0';
}

static void fd_write(int fd, const char *s) {
    if (fd < 0 || !s) return;
    size_t len = strlen(s);
    while (len > 0) {
        ssize_t n = write(fd, s, len);
        if (n <= 0) break;
        s += n; len -= (size_t)n;
    }
}

static void json_escape(char *out, size_t outSize, const char *in) {
    if (!out || outSize < 2) return;
    if (!in) { out[0] = '\0'; return; }
    size_t wi = 0;
    for (size_t i = 0; in[i] && wi + 6 < outSize; i++) {
        unsigned char c = (unsigned char)in[i];
        if      (c == '"')  { out[wi++] = '\\'; out[wi++] = '"';  }
        else if (c == '\\') { out[wi++] = '\\'; out[wi++] = '\\'; }
        else if (c == '\n') { out[wi++] = '\\'; out[wi++] = 'n';  }
        else if (c == '\r') { out[wi++] = '\\'; out[wi++] = 'r';  }
        else if (c == '\t') { out[wi++] = '\\'; out[wi++] = 't';  }
        else if (c < 0x20)  { /* skip control chars */ }
        else                { out[wi++] = (char)c; }
    }
    out[wi] = '\0';
}

// ── Crash file writer (async-signal-safe) ─────────────────────────────────────
static void writeCrashFile(const char *crashType,
                            const char *crashReason,
                            const char *crashLog) {
    if (!g_pendingCrashPath[0]) return;
    int fd = open(g_pendingCrashPath, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) return;

    static char eCrashType[256], eCrashReason[1024], eCrashLog[CRASH_BUF_SIZE];
    static char eDeviceModel[128], eIOSVersion[64], eDeviceID[128], eAction[512];

    json_escape(eCrashType,   sizeof(eCrashType),   crashType   ? crashType   : "Unknown");
    json_escape(eCrashReason, sizeof(eCrashReason), crashReason ? crashReason : "");
    json_escape(eCrashLog,    sizeof(eCrashLog),    crashLog    ? crashLog    : "");
    json_escape(eDeviceModel, sizeof(eDeviceModel), g_deviceModel[0] ? g_deviceModel : "Unknown-early");
    json_escape(eIOSVersion,  sizeof(eIOSVersion),  g_iosVersion[0]  ? g_iosVersion  : "Unknown-early");
    json_escape(eDeviceID,    sizeof(eDeviceID),    g_deviceID[0]    ? g_deviceID    : "Unknown-early");
    json_escape(eAction,      sizeof(eAction),      g_lastUserAction[0] ? g_lastUserAction : "Crash before app launched");

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

// ── Backtrace builder (async-signal-safe) ─────────────────────────────────────
static void buildBacktrace(char *out, size_t outSize) {
    if (!out || outSize < 2) { if (out) out[0] = '\0'; return; }
    out[0] = '\0';
    void  *frames[128];
    int    count = backtrace(frames, 128);
    char **syms  = backtrace_symbols(frames, count);
    size_t written = 0;
    if (syms) {
        for (int i = 0; i < count && written + 256 < outSize; i++) {
            const char *sym = syms[i] ? syms[i] : "???";
            size_t slen = strlen(sym);
            if (written + slen + 2 >= outSize) break;
            memcpy(out + written, sym, slen);
            written += slen;
            out[written++] = '\n';
        }
        // Not freeing syms — process is dying
    } else {
        char addr[32];
        for (int i = 0; i < count && written + 32 < outSize; i++) {
            snprintf(addr, sizeof(addr), "%p\n", frames[i]);
            size_t alen = strlen(addr);
            memcpy(out + written, addr, alen);
            written += alen;
        }
    }
    out[written] = '\0';
}

// ── Signal handler ────────────────────────────────────────────────────────────
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
    static char btBuf[CRASH_BUF_SIZE];
    static char fullLog[CRASH_BUF_SIZE + 512];

    buildBacktrace(btBuf, sizeof(btBuf));

    char faultAddr[32];
    snprintf(faultAddr, sizeof(faultAddr), "%p", info ? info->si_addr : (void *)0);

    snprintf(fullLog, sizeof(fullLog),
        "Signal: %s (%d)\n"
        "Fault Address: %s\n"
        "Device info populated: %s\n"
        "\n=== Backtrace ===\n%s",
        sigName(sig), sig,
        faultAddr,
        g_deviceModel[0] ? "yes" : "no — crash before UIDevice init",
        btBuf);

    writeCrashFile(sigName(sig), "App received fatal signal", fullLog);

    struct sigaction *old = NULL;
    switch (sig) {
        case SIGSEGV: old = &g_oldSIGSEGV; break;
        case SIGABRT: old = &g_oldSIGABRT; break;
        case SIGBUS:  old = &g_oldSIGBUS;  break;
        case SIGILL:  old = &g_oldSIGILL;  break;
        case SIGFPE:  old = &g_oldSIGFPE;  break;
        case SIGPIPE: old = &g_oldSIGPIPE; break;
    }
    if (old) sigaction(sig, old, NULL);
    else     signal(sig, SIG_DFL);
    raise(sig);
}

// ── ObjC uncaught exception handler ──────────────────────────────────────────
static NSUncaughtExceptionHandler *g_previousExceptionHandler = NULL;

static void skExceptionHandler(NSException *exception) {
    NSString *name   = exception.name   ?: @"Unknown";
    NSString *reason = exception.reason ?: @"No reason";
    NSArray  *bt     = exception.callStackSymbols ?: @[];

    NSMutableString *log = [NSMutableString string];
    [log appendFormat:@"Exception: %@\nReason: %@\n", name, reason];
    if (!g_deviceModel[0])
        [log appendString:@"Note: crash before UIDevice init\n"];
    [log appendString:@"\n=== Call Stack ===\n"];
    for (NSString *frame in bt)
        [log appendFormat:@"%@\n", frame];
    if (exception.userInfo.count)
        [log appendFormat:@"\n=== UserInfo ===\n%@\n", exception.userInfo];

    writeCrashFile(
        [NSString stringWithFormat:@"ObjC: %@", name].UTF8String,
        reason.UTF8String,
        log.UTF8String
    );

    if (g_previousExceptionHandler) g_previousExceptionHandler(exception);
}

// ── CONSTRUCTOR — runs before main(), before any ObjC ────────────────────────
//
//  This is what fixes "instant crash on launch".
//  Installs signal + exception handlers at dylib-load time via dyld,
//  before any app code runs at all.
//  Uses only getenv() and sigaction() — no heap, no ObjC needed.
//
__attribute__((constructor))
static void SKCrashReporterEarlyInit(void) {
    const char *home = getenv("HOME");
    if (home) {
        snprintf(g_pendingCrashPath, sizeof(g_pendingCrashPath),
                 "%s/Documents/%s", home, PENDING_CRASH_FILENAME);
    } else {
        snprintf(g_pendingCrashPath, sizeof(g_pendingCrashPath),
                 "/tmp/%s", PENDING_CRASH_FILENAME);
    }

    safe_strncpy(g_deviceModel,    "Unknown-early",             sizeof(g_deviceModel));
    safe_strncpy(g_iosVersion,     "Unknown-early",             sizeof(g_iosVersion));
    safe_strncpy(g_deviceID,       "Unknown-early",             sizeof(g_deviceID));
    safe_strncpy(g_lastUserAction, "Crash before app launched", sizeof(g_lastUserAction));

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

    g_previousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(skExceptionHandler);
}

// ── Populate real UIDevice info (needs run loop) ──────────────────────────────
static void populateDeviceInfo(void) {
    struct utsname s;
    uname(&s);
    safe_strncpy(g_deviceModel, s.machine, sizeof(g_deviceModel));

    NSString *ver = [[UIDevice currentDevice] systemVersion] ?: @"Unknown";
    safe_strncpy(g_iosVersion, ver.UTF8String, sizeof(g_iosVersion));

    NSString *did = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"Unknown";
    safe_strncpy(g_deviceID, did.UTF8String, sizeof(g_deviceID));
}

// ── Upload pending crash from previous run ────────────────────────────────────
static void uploadPendingCrashIfNeeded(void) {
    NSString *path = [NSString stringWithUTF8String:g_pendingCrashPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    NSData *jsonData = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!jsonData.length) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    NSLog(@"[SKCrash] Uploading pending crash: %@", dict[@"crash_type"] ?: @"?");

    NSMutableDictionary *payload = [dict mutableCopy];
    payload[@"action"] = @"report";

    // Delete BEFORE uploading — prevents infinite loop if upload crashes
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 30;
    cfg.timeoutIntervalForResource = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:CRASH_API_URL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!body) return;

    [[session uploadTaskWithRequest:req fromData:body completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
        if (err) { NSLog(@"[SKCrash] Upload error: %@", err.localizedDescription); return; }
        NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSLog(@"[SKCrash] Upload OK: %@", res ?: @"(non-JSON)");
    }] resume];
}

// ── Public API — call from Tweak.xm panel buttons ─────────────────────────────
void SKCrashSetLastAction(NSString *action) {
    if (!action) return;
    safe_strncpy(g_lastUserAction, action.UTF8String, sizeof(g_lastUserAction));
}

%}  // end of %{ ... %} verbatim block

// ─────────────────────────────────────────────────────────────────────────────
// Logos hooks — these are parsed by Logos normally
// ─────────────────────────────────────────────────────────────────────────────

%hook UIApplication

- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {

    BOOL result = %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        populateDeviceInfo();
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{ uploadPendingCrashIfNeeded(); }
        );
    });

    return result;
}

%end
