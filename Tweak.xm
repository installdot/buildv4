// Tweak.xm
// Hooks _dyld_get_image_name, measures call time, saves log to Documents/

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/time.h>

static NSTimeInterval g_startTime = 0;
static dispatch_queue_t g_logQueue = nil;

static NSString *DocumentsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject ?: @"/var/mobile/Documents";
}

static void WriteLog(NSString *message) {
    if (!g_logQueue) return;

    dispatch_async(g_logQueue, ^{
        @autoreleasepool {
            NSString *logPath = [DocumentsPath() stringByAppendingPathComponent:@"dyld_get_image_name_log.txt"];
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"HH:mm:ss.SSS";
            NSString *timestamp = [fmt stringFromDate:[NSDate date]];
            NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (!handle) {
                [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            } else {
                [handle seekToEndOfFile];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        }
    });
}

static NSTimeInterval Now(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (NSTimeInterval)tv.tv_sec + tv.tv_usec / 1e6;
}

%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    NSTimeInterval callStart = Now();

    const char *result = %orig;

    NSTimeInterval durationMs = (Now() - callStart) * 1000.0;
    NSTimeInterval sinceLoadMs = (Now() - g_startTime) * 1000.0;

    NSString *imageName = result ? @(result) : @"(null)";

    NSString *logMsg = [NSString stringWithFormat:
        @"_dyld_get_image_name(%u) → \"%@\" | took %.4f ms | %.2f ms after tweak load",
        image_index, imageName, durationMs, sinceLoadMs];

    NSLog(@"[dyld-hook] %@", logMsg);
    WriteLog(logMsg);

    return result;
}

%ctor {
    @autoreleasepool {
        g_startTime = Now();
        g_logQueue = dispatch_queue_create("com.dyldhook.logger", DISPATCH_QUEUE_SERIAL);

        NSString *msg = [NSString stringWithFormat:
            @"Tweak loaded (priority=app) | _dyld_get_image_name hooked | start=%.6f", g_startTime];
        NSLog(@"[dyld-hook] %@", msg);
        WriteLog(msg);

        uint32_t count = _dyld_image_count();
        NSString *countMsg = [NSString stringWithFormat:@"_dyld_image_count() = %u at load time", count];
        NSLog(@"[dyld-hook] %@", countMsg);
        WriteLog(countMsg);
    }
}
