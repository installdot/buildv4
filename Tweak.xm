#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <fcntl.h>
#import <dlfcn.h>
#import <spawn.h>
#import <stdarg.h>

static NSString *gLogPath = nil;

static void WriteLog(NSString *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [NSDate date], msg];

    NSLog(@"%@", line);

    if (!gLogPath) return;

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:gLogPath
                                                contents:nil
                                              attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
    }

    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

#pragma mark - libc hooks

%hookf(int, open, const char *path, int flags, ...)
{
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = va_arg(ap, int);
        va_end(ap);

        WriteLog(@"open(path=%s flags=0x%x mode=%o)", path, flags, mode);
        return %orig(path, flags, mode);
    }

    WriteLog(@"open(path=%s flags=0x%x)", path, flags);
    return %orig(path, flags);
}

%hookf(ssize_t, write, int fd, const void *buf, size_t size)
{
    WriteLog(@"write(fd=%d size=%zu)", fd, size);
    return %orig(fd, buf, size);
}

%hookf(int, rename, const char *oldp, const char *newp)
{
    WriteLog(@"rename(%s -> %s)", oldp, newp);
    return %orig(oldp, newp);
}

%hookf(int, unlink, const char *path)
{
    WriteLog(@"unlink(%s)", path);
    return %orig(path);
}

#pragma mark - NSFileManager hooks

%hook NSFileManager

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err
{
    WriteLog(@"NSFileManager copy %@ -> %@", src, dst);
    return %orig(src, dst, err);
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
    WriteLog(@"NSFileManager remove %@", path);
    return %orig(path, err);
}

- (BOOL)createFileAtPath:(NSString *)path
                contents:(NSData *)data
              attributes:(NSDictionary *)attr
{
    WriteLog(@"NSFileManager create %@ size=%lu",
             path, (unsigned long)data.length);
    return %orig(path, data, attr);
}

%end

#pragma mark - process execution

%hookf(int, system, const char *cmd)
{
    WriteLog(@"system(%s)", cmd);
    return %orig(cmd);
}

%hookf(int, posix_spawn,
       pid_t *pid,
       const char *path,
       const posix_spawn_file_actions_t *fa,
       const posix_spawnattr_t *attr,
       char *const argv[],
       char *const envp[])
{
    WriteLog(@"posix_spawn(%s)", path);
    if (argv) {
        for (int i = 0; argv[i]; i++) {
            WriteLog(@" argv[%d]=%s", i, argv[i]);
        }
    }
    return %orig(pid, path, fa, attr, argv, envp);
}

#pragma mark - dylib loading

%hookf(void *, dlopen, const char *path, int mode)
{
    WriteLog(@"dlopen(%s)", path);
    return %orig(path, mode);
}

#pragma mark - ctor

%ctor
{
    @autoreleasepool {
        NSString *docs =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                NSUserDomainMask,
                                                YES).firstObject;

        gLogPath = [docs stringByAppendingPathComponent:@"patch_trace.log"];

        WriteLog(@"===== PatchTrace injected =====");
        WriteLog(@"Log file: %@", gLogPath);
    }
}
