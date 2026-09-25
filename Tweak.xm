// Tweak.xm
// Safer version – minimal work inside the hook

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <sys/time.h>
#import <stdio.h>
#import <string.h>

static NSTimeInterval g_startTime = 0;
static volatile int g_callCount = 0;
static volatile int g_reentrant = 0;
static char g_logPath[1024] = {0};

static NSTimeInterval Now(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (NSTimeInterval)tv.tv_sec + tv.tv_usec / 1e6;
}

static void SafeLog(const char *msg) {
    // Extremely lightweight logging – no Objective-C inside the hot path
    if (g_logPath[0] == 0) return;

    FILE *f = fopen(g_logPath, "a");
    if (!f) return;

    struct timeval tv;
    gettimeofday(&tv, NULL);
    fprintf(f, "[%ld.%06d] %s\n", (long)tv.tv_sec, (int)tv.tv_usec, msg);
    fclose(f);
}

%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    // Prevent re-entrancy crash
    if (g_reentrant) {
        return %orig;
    }
    g_reentrant = 1;

    int count = ++g_callCount;

    NSTimeInterval start = Now();
    const char *result = %orig;
    NSTimeInterval durationMs = (Now() - start) * 1000.0;
    NSTimeInterval sinceLoadMs = (Now() - g_startTime) * 1000.0;

    // Only log the first 30 calls + every 50th after that (to avoid spam + performance issues)
    if (count <= 30 || (count % 50 == 0)) {
        char buf[1024];
        snprintf(buf, sizeof(buf),
                 "#%d  _dyld_get_image_name(%u) → \"%s\" | %.4f ms | %.1f ms after load",
                 count,
                 image_index,
                 result ? result : "(null)",
                 durationMs,
                 sinceLoadMs);
        SafeLog(buf);
    }

    g_reentrant = 0;
    return result;
}

%ctor {
    g_startTime = Now();

    // Try to write log into the app's Documents folder
    // Fallback to /var/mobile/Documents if sandbox is not ready yet
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject;

    if (doc) {
        snprintf(g_logPath, sizeof(g_logPath), "%s/dyld_get_image_name_log.txt", doc.UTF8String);
    } else {
        strcpy(g_logPath, "/var/mobile/Documents/dyld_get_image_name_log.txt");
    }

    // Clear old log
    FILE *f = fopen(g_logPath, "w");
    if (f) {
        fprintf(f, "=== Dyld hook started ===\n");
        fclose(f);
    }

    char msg[256];
    snprintf(msg, sizeof(msg), "Tweak loaded | log path: %s", g_logPath);
    SafeLog(msg);

    // Also log current image count
    uint32_t count = _dyld_image_count();
    snprintf(msg, sizeof(msg), "_dyld_image_count() = %u at load time", count);
    SafeLog(msg);
}
