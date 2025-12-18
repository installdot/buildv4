#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <substrate.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <spawn.h>
#import <stdarg.h>

static NSString *gLogPath = nil;

static void TraceLog(NSString *fmt, ...)
{
    @autoreleasepool {
        va_list ap;
        va_start(ap, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
        va_end(ap);

        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSLog(@"%@", line);

        if (!gLogPath) return;

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:gLogPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
            if (!fh) return;
        }

        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

/* ===================== C function hooks (no %hookf) ===================== */

typedef int     (*open_t)(const char *path, int oflag, ...);
typedef ssize_t (*write_t)(int fd, const void *buf, size_t count);
typedef int     (*unlink_t)(const char *path);
typedef int     (*system_t)(const char *command);
typedef void *  (*dlopen_t)(const char *path, int mode);

typedef int (*posix_spawn_t)(
    pid_t *pid,
    const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[],
    char *const envp[]
);

static open_t        orig_open = NULL;
static write_t       orig_write = NULL;
static unlink_t      orig_unlink = NULL;
static system_t      orig_system = NULL;
static dlopen_t      orig_dlopen = NULL;
static posix_spawn_t orig_posix_spawn = NULL;

static int my_open(const char *path, int flags, ...)
{
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);

        TraceLog(@"open(path=%s flags=0x%x mode=%o)", path, flags, mode);
        return orig_open ? orig_open(path, flags, mode) : -1;
    }

    TraceLog(@"open(path=%s flags=0x%x)", path, flags);
    return orig_open ? orig_open(path, flags) : -1;
}

static ssize_t my_write(int fd, const void *buf, size_t count)
{
    TraceLog(@"write(fd=%d size=%zu)", fd, count);
    return orig_write ? orig_write(fd, buf, count) : -1;
}

static int my_unlink(const char *path)
{
    TraceLog(@"unlink(%s)", path);
    return orig_unlink ? orig_unlink(path) : -1;
}

static int my_system(const char *command)
{
    TraceLog(@"system(%s)", command ? command : "(null)");
    return orig_system ? orig_system(command) : -1;
}

static void *my_dlopen(const char *path, int mode)
{
    TraceLog(@"dlopen(%s)", path ? path : "(null)");
    return orig_dlopen ? orig_dlopen(path, mode) : NULL;
}

static int my_posix_spawn(
    pid_t *pid,
    const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[],
    char *const envp[]
) {
    TraceLog(@"posix_spawn(%s)", path ? path : "(null)");
    if (argv) {
        for (int i = 0; argv[i]; i++) {
            TraceLog(@"  argv[%d]=%s", i, argv[i]);
        }
    }
    return orig_posix_spawn ? orig_posix_spawn(pid, path, file_actions, attrp, argv, envp) : -1;
}

/* ===================== Objective-C hooks ===================== */

%hook NSFileManager

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err
{
    TraceLog(@"NSFileManager copy %@ -> %@", src, dst);
    return %orig(src, dst, err);
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
    TraceLog(@"NSFileManager remove %@", path);
    return %orig(path, err);
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr
{
    TraceLog(@"NSFileManager create %@ size=%lu", path, (unsigned long)data.length);
    return %orig(path, data, attr);
}

%end

/* ===================== ctor ===================== */

%ctor
{
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        gLogPath = [docs stringByAppendingPathComponent:@"patch_trace.log"];

        TraceLog(@"===== PatchTrace injected =====");
        TraceLog(@"Log file: %@", gLogPath);

        // Hook C functions safely (avoids Logos %hookf macro issues)
        MSHookFunction((void *)open,        (void *)my_open,        (void **)&orig_open);
        MSHookFunction((void *)write,       (void *)my_write,       (void **)&orig_write);
        MSHookFunction((void *)unlink,      (void *)my_unlink,      (void **)&orig_unlink);
        MSHookFunction((void *)system,      (void *)my_system,      (void **)&orig_system);
        MSHookFunction((void *)dlopen,      (void *)my_dlopen,      (void **)&orig_dlopen);
        MSHookFunction((void *)posix_spawn, (void *)my_posix_spawn, (void **)&orig_posix_spawn);
    }
}
