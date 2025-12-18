#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <fcntl.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/stat.h>

static NSString *logPath = nil;

static void writeLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *final = [NSString stringWithFormat:@"[%@] %@\n",
        [[NSDate date] description], msg];

    NSLog(@"%@", final);

    if (!logPath) return;

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }

    [fh seekToEndOfFile];
    [fh writeData:[final dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

#pragma mark - libc hooks

%hookf(int, open, const char *path, int flags, ...)
{
    writeLog(@"open() path=%s flags=0x%x", path, flags);
    return %orig;
}

%hookf(ssize_t, write, int fd, const void *buf, size_t count)
{
    writeLog(@"write() fd=%d size=%zu", fd, count);
    return %orig;
}

%hookf(int, rename, const char *oldp, const char *newp)
{
    writeLog(@"rename() %s -> %s", oldp, newp);
    return %orig;
}

%hookf(int, unlink, const char *path)
{
    writeLog(@"unlink() %s", path);
    return %orig;
}

#pragma mark - NSFileManager hooks

%hook NSFileManager

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err
{
    writeLog(@"NSFileManager copy %@ -> %@", src, dst);
    return %orig;
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
    writeLog(@"NSFileManager remove %@", path);
    return %orig;
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr
{
    writeLog(@"NSFileManager create %@ size=%lu", path, (unsigned long)data.length);
    return %orig;
}

%end

#pragma mark - Process execution

%hookf(int, system, const char *cmd)
{
    writeLog(@"system(): %s", cmd);
    return %orig;
}

%hookf(int, posix_spawn,
    pid_t *pid,
    const char *path,
    const posix_spawn_file_actions_t *fa,
    const posix_spawnattr_t *attr,
    char *const argv[],
    char *const envp[])
{
    writeLog(@"posix_spawn(): %s", path);
    if (argv) {
        for (int i = 0; argv[i]; i++) {
            writeLog(@" argv[%d] = %s", i, argv[i]);
        }
    }
    return %orig;
}

#pragma mark - dylib loading

%hookf(void *, dlopen, const char *path, int mode)
{
    writeLog(@"dlopen(): %s", path);
    return %orig;
}

#pragma mark - ctor

%ctor
{
    @autoreleasepool {
        NSString *doc =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        logPath = [doc stringByAppendingPathComponent:@"patch_trace.log"];

        writeLog(@"==== PatchTrace dylib injected ====");
        writeLog(@"Log file: %@", logPath);
    }
}
