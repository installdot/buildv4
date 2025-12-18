#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <fcntl.h>
#import <dlfcn.h>
#import <spawn.h>
#import <stdarg.h>

static NSString *LogFile = nil;

static void Log(NSString *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSString *line = [NSString stringWithFormat:@"%@\n", msg];
    NSLog(@"%@", line);

    if (!LogFile) return;

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LogFile];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:LogFile contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:LogFile];
    }

    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

/* ================= libc ================= */

%hookf(int, open, const char *path, int flags, ...)
{
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = va_arg(ap, int);
        va_end(ap);

        Log(@"open %s flags=0x%x mode=%o", path, flags, mode);
        return %orig(path, flags, mode);
    }

    Log(@"open %s flags=0x%x", path, flags);
    return %orig(path, flags);
}

%hookf(ssize_t, write, int fd, const void *buf, size_t sz)
{
    Log(@"write fd=%d size=%zu", fd, sz);
    return %orig(fd, buf, sz);
}

%hookf(int, unlink, const char *path)
{
    Log(@"unlink %s", path);
    return %orig(path);
}

/* ================= NSFileManager ================= */

%hook NSFileManager

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err
{
    Log(@"copy %@ -> %@", src, dst);
    return %orig(src, dst, err);
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
    Log(@"remove %@", path);
    return %orig(path, err);
}

%end

/* ================= process ================= */

%hookf(int, system, const char *cmd)
{
    Log(@"system %s", cmd);
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
    Log(@"spawn %s", path);
    return %orig(pid, path, fa, attr, argv, envp);
}

/* ================= dylib ================= */

%hookf(void *, dlopen, const char *path, int mode)
{
    Log(@"dlopen %s", path);
    return %orig(path, mode);
}

/* ================= ctor ================= */

%ctor
{
    @autoreleasepool {
        NSString *docs =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                NSUserDomainMask,
                                                YES)[0];

        LogFile = [docs stringByAppendingPathComponent:@"patch_trace.log"];
        Log(@"PatchTrace injected");
    }
}
