// Tweak.xm
// Hooks _dyld_get_image_name to detect usage + measure timing
// Loads at app priority and saves logs to Documents/

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <os/log.h>
#import <sys/time.h>

static NSMutableArray *g_logs = nil;
static NSTimeInterval g_startTime = 0;
static dispatch_queue_t g_logQueue = nil;
static BOOL g_initialized = NO;

static NSString *DocumentsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject ?: @"/tmp";
}

static void WriteLogToFile(NSString *message) {
    if (!g_logQueue) return;
    
    dispatch_async(g_logQueue, ^{
        @autoreleasepool {
            NSString *logPath = [DocumentsPath() stringByAppendingPathComponent:@"dyld_get_image_name_log.txt"];
            NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                               dateStyle:NSDateFormatterNoStyle
                                                               timeStyle:NSDateFormatterMediumStyle];
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

static NSTimeInterval CurrentTime(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (NSTimeInterval)tv.tv_sec + (NSTimeInterval)tv.tv_usec / 1000000.0;
}

// Original function pointer
static const char *(*orig_dyld_get_image_name)(uint32_t image_index) = NULL;

static const char *hooked_dyld_get_image_name(uint32_t image_index) {
    NSTimeInterval callStart = CurrentTime();
    
    const char *result = orig_dyld_get_image_name ? orig_dyld_get_image_name(image_index) : NULL;
    
    NSTimeInterval duration = (CurrentTime() - callStart) * 1000.0; // ms
    NSTimeInterval sinceLoad = (CurrentTime() - g_startTime) * 1000.0; // ms since tweak loaded
    
    NSString *imageName = result ? [NSString stringWithUTF8String:result] : @"(null)";
    
    NSString *logMsg = [NSString stringWithFormat:
        @"_dyld_get_image_name(%u) → \"%@\" | took %.4f ms | %.2f ms after tweak load",
        image_index, imageName, duration, sinceLoad];
    
    // Also log to console (visible in Console.app / idevicesyslog)
    NSLog(@"[dyld-hook] %@", logMsg);
    WriteLogToFile(logMsg);
    
    return result;
}

%ctor {
    // High priority so we load early in the app process
    @autoreleasepool {
        g_startTime = CurrentTime();
        g_logs = [NSMutableArray new];
        g_logQueue = dispatch_queue_create("com.dyldhook.logger", DISPATCH_QUEUE_SERIAL);
        
        // Resolve the real symbol
        void *handle = dlopen(NULL, RTLD_NOW);
        orig_dyld_get_image_name = (const char *(*)(uint32_t))dlsym(handle, "_dyld_get_image_name");
        
        if (orig_dyld_get_image_name) {
            // Use MSHookFunction if available (MobileSubstrate / Substitute / ElleKit)
            // For pure Logos + Theos we can also use %hookf
            MSHookFunction((void *)orig_dyld_get_image_name,
                           (void *)hooked_dyld_get_image_name,
                           (void **)&orig_dyld_get_image_name);
            
            NSString *msg = [NSString stringWithFormat:
                @"Tweak loaded at priority=app | _dyld_get_image_name hooked successfully | start=%.6f",
                g_startTime];
            NSLog(@"[dyld-hook] %@", msg);
            WriteLogToFile(msg);
            g_initialized = YES;
        } else {
            NSString *msg = @"Failed to resolve _dyld_get_image_name";
            NSLog(@"[dyld-hook] %@", msg);
            WriteLogToFile(msg);
        }
        
        // Also log total number of images at load time for reference
        uint32_t count = _dyld_image_count();
        NSString *countMsg = [NSString stringWithFormat:@"_dyld_image_count() = %u at tweak load", count];
        NSLog(@"[dyld-hook] %@", countMsg);
        WriteLogToFile(countMsg);
    }
}
